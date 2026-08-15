<#
.SYNOPSIS
    Compares LiteDeploy driver packs to Dell/HP/Lenovo online catalogs and can download updates.

.DESCRIPTION
    Manager tool. Refreshes vendor driver-pack catalogs under Content\Temp\OemCatalogs\,
    compares them to Content\Drivers\catalog.json, and prints a shell status table.

    -CheckStatus  → compare only (show LocalVersion vs OnlineVersion).
    -UpdateAll / -Model / -SystemSku → download pack (URL from OEM catalog when needed),
    replace Extracted content, and update catalog.json via ImportOEMDrivers.

.PARAMETER DeploymentRoot
    Deployment share root.

.PARAMETER CheckStatus
    Compare local catalog to vendor pack catalogs and print a table (no download).

.PARAMETER UpdateAll
    Download newer packs for FullOS models with UpdateAvailable (URL from OEM catalog),
    replace Extracted\, update catalog.json.

.PARAMETER Model
    Download/replace the matching model (name or modelId substring).

.PARAMETER SystemSku
    Download/replace models that list this SystemSKU / Machine Type.

.PARAMETER ManufacturerName
    Optional friendly manufacturer filter (e.g. Dell).

.PARAMETER ManufacturerId
    Optional WMI manufacturerId filter (e.g. "Dell Inc.").

.PARAMETER ModelsCsvPath
    Optional allow-list CSV (Model + SystemSku/SkuId). With -CheckStatus, surfaces NewInAllowList rows.

.PARAMETER CsvDelimiter
    CSV delimiter. Default comma.

.PARAMETER RefreshCatalog
    Force re-download of vendor indexes even if cache is fresh.

.PARAMETER MaxCatalogAgeDays
    Refresh vendor indexes when older than this many days. Default 7.

.PARAMETER UseCurl
    Pass through to ImportOEMDrivers on update.

.PARAMETER Force
    Pass -Force to ImportOEMDrivers (replace existing Extracted content).

.EXAMPLE
    # Compare only — show what is newer online
    .\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -CheckStatus

.EXAMPLE
    # Download/replace every model that has a newer pack online
    .\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -UpdateAll -Force

.EXAMPLE
    .\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Model "Latitude 7450" -Force

.EXAMPLE
    .\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -SystemSku "0C09" -Force
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "CheckStatus")]
param(
    [Parameter(Mandatory = $true)]
    [string]$DeploymentRoot,

    [Parameter(Mandatory = $true, ParameterSetName = "CheckStatus")]
    [switch]$CheckStatus,

    [Parameter(Mandatory = $true, ParameterSetName = "UpdateAll")]
    [switch]$UpdateAll,

    [Parameter(Mandatory = $true, ParameterSetName = "UpdateModel")]
    [string]$Model = "",

    [Parameter(Mandatory = $true, ParameterSetName = "UpdateSku")]
    [string]$SystemSku = "",

    [Parameter(Mandatory = $false)]
    [string]$ManufacturerName = "",

    [Parameter(Mandatory = $false)]
    [string]$ManufacturerId = "",

    [Parameter(Mandatory = $false, ParameterSetName = "CheckStatus")]
    [string]$ModelsCsvPath = "",

    [Parameter(Mandatory = $false, ParameterSetName = "CheckStatus")]
    [ValidateSet(",", ";", "`t")]
    [string]$CsvDelimiter = ",",

    [Parameter(Mandatory = $false)]
    [switch]$RefreshCatalog,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$MaxCatalogAgeDays = 7,

    [Parameter(Mandatory = $false, ParameterSetName = "UpdateAll")]
    [Parameter(Mandatory = $false, ParameterSetName = "UpdateModel")]
    [Parameter(Mandatory = $false, ParameterSetName = "UpdateSku")]
    [switch]$UseCurl,

    [Parameter(Mandatory = $false, ParameterSetName = "UpdateAll")]
    [Parameter(Mandatory = $false, ParameterSetName = "UpdateModel")]
    [Parameter(Mandatory = $false, ParameterSetName = "UpdateSku")]
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Write-SyncLog {
    param(
        [string]$Message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Cyan
    )
    Write-Host " [SyncOEMDrivers]  $Message" -ForegroundColor $ForegroundColor
}

function Save-RemoteFileNative {
    param([string]$Uri, [string]$Destination)

    $destinationDir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destinationDir)) {
        $null = New-Item -Path $destinationDir -ItemType Directory -Force
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }

    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Write-SyncLog "Downloading (BITS): $Uri"
        try {
            Start-BitsTransfer -Source $Uri -Destination $Destination -ErrorAction Stop
            if (Test-Path -LiteralPath $Destination -PathType Leaf) { return }
        }
        catch {
            Write-SyncLog "BITS failed; falling back to Invoke-WebRequest. $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    Write-SyncLog "Downloading (Invoke-WebRequest): $Uri"
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -ErrorAction Stop
}

function Test-CatalogCacheFresh {
    param([string]$Path, [int]$MaxAgeDays)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $age = ((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalDays
    return ($age -lt $MaxAgeDays)
}

function Expand-CabFile {
    param([string]$CabPath, [string]$XmlPath)
    if (Test-Path -LiteralPath $XmlPath) {
        Remove-Item -LiteralPath $XmlPath -Force
    }
    $expand = Get-Command expand.exe -ErrorAction SilentlyContinue
    if (-not $expand) {
        throw "expand.exe not found (required to extract OEM catalog CABs)."
    }
    $p = Start-Process -FilePath $expand.Source -ArgumentList @("`"$CabPath`"", "`"$XmlPath`"") -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $XmlPath -PathType Leaf)) {
        throw "Failed to expand catalog CAB: $CabPath"
    }
}

function Update-OemVendorIndexes {
    param(
        [string]$OemCatalogsRoot,
        [int]$MaxAgeDays,
        [switch]$ForceRefresh
    )

    $results = [ordered]@{}

    function Sync-CabCatalog {
        param([string]$Dir, [string]$CabName, [string]$XmlName, [string]$Uri, [string]$Label)
        $xmlPath = Join-Path $Dir $XmlName
        $cabPath = Join-Path $Dir $CabName
        if ($ForceRefresh -or -not (Test-CatalogCacheFresh -Path $xmlPath -MaxAgeDays $MaxAgeDays)) {
            if (-not (Test-Path -LiteralPath $Dir)) { $null = New-Item -Path $Dir -ItemType Directory -Force }
            Save-RemoteFileNative -Uri $Uri -Destination $cabPath
            Expand-CabFile -CabPath $cabPath -XmlPath $xmlPath
            Remove-Item -LiteralPath $cabPath -Force -ErrorAction SilentlyContinue
            Write-SyncLog "$Label refreshed: $xmlPath" -ForegroundColor Green
        }
        else {
            Write-SyncLog "$Label cache fresh: $xmlPath"
        }
        return $xmlPath
    }

    $dellDir = Join-Path $OemCatalogsRoot "Dell"
    $results["DellIndex"] = Sync-CabCatalog -Dir $dellDir -CabName "CatalogIndexPC.cab" -XmlName "CatalogIndexPC.xml" `
        -Uri "https://downloads.dell.com/catalog/CatalogIndexPC.cab" -Label "Dell CatalogIndexPC"
    $results["DellPack"] = Sync-CabCatalog -Dir $dellDir -CabName "DriverPackCatalog.cab" -XmlName "DriverPackCatalog.xml" `
        -Uri "https://downloads.dell.com/catalog/DriverPackCatalog.cab" -Label "Dell DriverPackCatalog"

    $hpDir = Join-Path $OemCatalogsRoot "HP"
    $results["HPIndex"] = Sync-CabCatalog -Dir $hpDir -CabName "platformList.cab" -XmlName "PlatformList.xml" `
        -Uri "https://hpia.hpcloud.hp.com/ref/platformList.cab" -Label "HP PlatformList"
    $results["HPPack"] = Sync-CabCatalog -Dir $hpDir -CabName "HPClientDriverPackCatalog.cab" -XmlName "HPClientDriverPackCatalog.xml" `
        -Uri "https://ftp.hp.com/pub/caps-softpaq/cmit/HPClientDriverPackCatalog.cab" -Label "HP DriverPackCatalog"

    $lenovoDir = Join-Path $OemCatalogsRoot "Lenovo"
    $lenovoXml = Join-Path $lenovoDir "catalogv2.xml"
    if ($ForceRefresh -or -not (Test-CatalogCacheFresh -Path $lenovoXml -MaxAgeDays $MaxAgeDays)) {
        if (-not (Test-Path -LiteralPath $lenovoDir)) { $null = New-Item -Path $lenovoDir -ItemType Directory -Force }
        Save-RemoteFileNative -Uri "https://download.lenovo.com/cdrt/td/catalogv2.xml" -Destination $lenovoXml
        Write-SyncLog "Lenovo catalogv2 refreshed: $lenovoXml" -ForegroundColor Green
    }
    else {
        Write-SyncLog "Lenovo catalogv2 cache fresh: $lenovoXml"
    }
    $results["Lenovo"] = $lenovoXml

    return $results
}

function Add-PackMapHit {
    param(
        $Map,
        [string]$Vendor,
        [string]$Sku,
        [string]$Name,
        [string]$Url,
        [string]$Version,
        [string]$ReleaseDate
    )
    if ([string]::IsNullOrWhiteSpace($Sku)) { return }
    $key = $Sku.Trim().ToUpperInvariant()
    $candidate = [pscustomobject]@{
        Vendor      = $Vendor
        Sku         = $key
        Name        = $Name
        Url         = $Url
        Version     = $Version
        ReleaseDate = $ReleaseDate
    }
    if (-not $Map.ContainsKey($key)) {
        $Map[$key] = [System.Collections.Generic.List[object]]::new()
        $Map[$key].Add($candidate)
        return
    }
    # Keep the newest by ReleaseDate, then Version string.
    $existing = $Map[$key][0]
    if (Test-OnlinePackNewer -LocalVersion $existing.Version -LocalReleaseDate $existing.ReleaseDate -OnlineVersion $Version -OnlineReleaseDate $ReleaseDate) {
        $Map[$key].Clear()
        $Map[$key].Add($candidate)
    }
}

function Test-OnlinePackNewer {
    param(
        [string]$LocalVersion,
        [string]$LocalReleaseDate,
        [string]$OnlineVersion,
        [string]$OnlineReleaseDate
    )

    $localDate = $null
    $onlineDate = $null
    if (-not [string]::IsNullOrWhiteSpace($LocalReleaseDate)) {
        [void][datetime]::TryParse($LocalReleaseDate, [ref]$localDate)
    }
    if (-not [string]::IsNullOrWhiteSpace($OnlineReleaseDate)) {
        [void][datetime]::TryParse($OnlineReleaseDate, [ref]$onlineDate)
    }
    if ($null -ne $localDate -and $null -ne $onlineDate) {
        if ($onlineDate.Date -gt $localDate.Date) { return $true }
        if ($onlineDate.Date -lt $localDate.Date) { return $false }
    }

    $lv = if ($LocalVersion) { $LocalVersion.Trim() } else { "" }
    $ov = if ($OnlineVersion) { $OnlineVersion.Trim() } else { "" }
    if ([string]::IsNullOrWhiteSpace($ov)) { return $false }
    if ([string]::IsNullOrWhiteSpace($lv)) { return $true }
    if ([string]::Equals($lv, $ov, [StringComparison]::OrdinalIgnoreCase)) { return $false }

    # Dell-style A00..A99
    $lm = [regex]::Match($lv, '^A(\d{2})$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $om = [regex]::Match($ov, '^A(\d{2})$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($lm.Success -and $om.Success) {
        return ([int]$lm.Groups[1].Value -lt [int]$om.Groups[1].Value)
    }
    # Dotted numeric versions (2026.01 / 1.2.3)
    $lParts = @($lv -split '[^\d]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    $oParts = @($ov -split '[^\d]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    if ($lParts.Count -gt 0 -and $oParts.Count -gt 0) {
        $n = [Math]::Max($lParts.Count, $oParts.Count)
        for ($i = 0; $i -lt $n; $i++) {
            $l = if ($i -lt $lParts.Count) { $lParts[$i] } else { 0 }
            $o = if ($i -lt $oParts.Count) { $oParts[$i] } else { 0 }
            if ($o -gt $l) { return $true }
            if ($o -lt $l) { return $false }
        }
        return $false
    }

    # Different opaque strings with no date signal → treat as update available so the table outlines OnlineVersion.
    return $true
}

function Get-VendorPackMaps {
    param($IndexPaths)

    $map = @{}

    if ($IndexPaths["DellPack"] -and (Test-Path -LiteralPath $IndexPaths["DellPack"])) {
        Write-SyncLog "Parsing Dell DriverPackCatalog (pack versions)..."
        try {
            $settings = New-Object System.Xml.XmlReaderSettings
            $settings.IgnoreWhitespace = $true
            $settings.IgnoreComments = $true
            $reader = [System.Xml.XmlReader]::Create($IndexPaths["DellPack"], $settings)
            $baseLocation = "downloads.dell.com"
            try {
                while ($reader.Read()) {
                    if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and $reader.LocalName -eq "DriverPackManifest") {
                        $bl = $reader.GetAttribute("baseLocation")
                        if ($bl) { $baseLocation = $bl.Trim().TrimEnd('/') }
                    }
                    if ($reader.NodeType -ne [System.Xml.XmlNodeType]::Element -or $reader.LocalName -ne "DriverPackage") {
                        continue
                    }
                    $type = $reader.GetAttribute("type")
                    if ($type -and $type -match '(?i)winpe') { continue }

                    $dellVersion = $reader.GetAttribute("dellVersion")
                    $vendorVersion = $reader.GetAttribute("vendorVersion")
                    $dateTime = $reader.GetAttribute("dateTime")
                    $path = $reader.GetAttribute("path")
                    $version = if ($dellVersion) { $dellVersion } elseif ($vendorVersion) { $vendorVersion } else { "" }
                    $releaseDate = ""
                    if ($dateTime) {
                        $dt = $null
                        if ([datetime]::TryParse($dateTime, [ref]$dt)) {
                            $releaseDate = $dt.ToString("yyyy-MM-dd")
                        }
                    }
                    $url = if ($path) { "https://$baseLocation/$path" } else { "" }

                    $sub = $reader.ReadSubtree()
                    $doc = New-Object System.Xml.XmlDocument
                    $doc.Load($sub)
                    $sub.Dispose()

                    $nameNode = $doc.SelectSingleNode("//*[local-name()='Name']/*[local-name()='Display']")
                    $name = if ($nameNode) { $nameNode.InnerText.Trim() } else { [IO.Path]::GetFileName($path) }
                    $modelNodes = @($doc.SelectNodes("//*[local-name()='SupportedSystems']//*[local-name()='Model']"))
                    foreach ($mn in $modelNodes) {
                        $systemId = $mn.GetAttribute("systemID")
                        $modelName = $mn.GetAttribute("name")
                        if ([string]::IsNullOrWhiteSpace($modelName) -and $name) { $modelName = $name }
                        Add-PackMapHit -Map $map -Vendor "Dell" -Sku $systemId -Name $modelName -Url $url -Version $version -ReleaseDate $releaseDate
                    }
                }
            }
            finally {
                $reader.Dispose()
            }
        }
        catch {
            Write-SyncLog "Dell DriverPackCatalog parse warning: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    if ($IndexPaths["HPPack"] -and (Test-Path -LiteralPath $IndexPaths["HPPack"])) {
        Write-SyncLog "Parsing HP Client DriverPackCatalog (pack versions)..."
        try {
            [xml]$hp = Get-Content -LiteralPath $IndexPaths["HPPack"] -Raw -Encoding UTF8
            $softById = @{}
            foreach ($sp in @($hp.SelectNodes("//*[local-name()='SoftPaq']"))) {
                $idNode = $sp.SelectSingleNode("*[local-name()='Id']")
                if (-not $idNode -or [string]::IsNullOrWhiteSpace($idNode.InnerText)) { continue }
                $id = $idNode.InnerText.Trim()
                $nameNode = $sp.SelectSingleNode("*[local-name()='Name']")
                $verNode = $sp.SelectSingleNode("*[local-name()='Version']")
                $urlNode = $sp.SelectSingleNode("*[local-name()='Url']")
                $dateNode = $sp.SelectSingleNode("*[local-name()='DateReleased']")
                $softById[$id] = [pscustomobject]@{
                    Id      = $id
                    Name    = if ($nameNode) { $nameNode.InnerText } else { $id }
                    Version = if ($verNode) { $verNode.InnerText } else { "" }
                    Url     = if ($urlNode) { $urlNode.InnerText } else { "" }
                    Date    = if ($dateNode) { $dateNode.InnerText } else { "" }
                }
            }
            foreach ($prod in @($hp.SelectNodes("//*[local-name()='ProductOSDriverPack']"))) {
                $sysNode = $prod.SelectSingleNode("*[local-name()='SystemId']")
                $nameNode = $prod.SelectSingleNode("*[local-name()='SystemName']")
                $softNode = $prod.SelectSingleNode("*[local-name()='SoftPaqId']")
                if (-not $sysNode -or -not $softNode) { continue }
                $sysRaw = $sysNode.InnerText
                $sysName = if ($nameNode) { $nameNode.InnerText } else { "" }
                $softId = $softNode.InnerText.Trim()
                if (-not $sysRaw -or -not $softById.ContainsKey($softId)) { continue }
                $sp = $softById[$softId]
                $releaseDate = ""
                $dt = $null
                if ($sp.Date -and [datetime]::TryParse($sp.Date, [ref]$dt)) {
                    $releaseDate = $dt.ToString("yyyy-MM-dd")
                }
                foreach ($sku in @($sysRaw -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                    Add-PackMapHit -Map $map -Vendor "HP" -Sku $sku -Name $sysName -Url $sp.Url -Version $sp.Version -ReleaseDate $releaseDate
                }
            }
        }
        catch {
            Write-SyncLog "HP DriverPackCatalog parse warning: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    if ($IndexPaths["Lenovo"] -and (Test-Path -LiteralPath $IndexPaths["Lenovo"])) {
        Write-SyncLog "Parsing Lenovo catalogv2 (SCCM pack versions)..."
        try {
            [xml]$lenovo = Get-Content -LiteralPath $IndexPaths["Lenovo"] -Raw -Encoding UTF8
            foreach ($m in @($lenovo.SelectNodes("//*[local-name()='Model']"))) {
                $name = $m.GetAttribute("name")
                $types = @($m.SelectNodes(".//*[local-name()='Type']") | ForEach-Object { $_.InnerText.Trim() } | Where-Object { $_ })
                $sccmNodes = @($m.SelectNodes(".//*[local-name()='SCCM']"))
                if ($sccmNodes.Count -eq 0 -or $types.Count -eq 0) { continue }

                $best = $null
                foreach ($s in $sccmNodes) {
                    $os = $s.GetAttribute("os")
                    $ver = $s.GetAttribute("version")
                    $date = $s.GetAttribute("date")
                    $url = ($s.InnerText).Trim()
                    $score = 0
                    if ($os -match '(?i)win11') { $score += 200 }
                    elseif ($os -match '(?i)win10') { $score += 100 }
                    $dt = $null
                    if ($date -and [datetime]::TryParse($date, [ref]$dt)) { $score += [int]$dt.ToString("yyyyMMdd") }
                    $cand = [pscustomobject]@{ Score = $score; Version = $ver; Date = $date; Url = $url; Os = $os }
                    if ($null -eq $best -or $cand.Score -gt $best.Score) { $best = $cand }
                }
                if ($null -eq $best) { continue }
                foreach ($t in $types) {
                    $sku = ($t -replace '\s+', '')
                    if ($sku.Length -gt 4) { $sku = $sku.Substring(0, 4) }
                    Add-PackMapHit -Map $map -Vendor "Lenovo" -Sku $sku -Name $name -Url $best.Url -Version $best.Version -ReleaseDate $best.Date
                }
            }
        }
        catch {
            Write-SyncLog "Lenovo catalogv2 parse warning: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    Write-SyncLog ("Vendor pack version entries: {0}" -f $map.Count)
    return $map
}

function Get-LocalDriverModels {
    param(
        [string]$CatalogPath,
        [string]$DeploymentRoot,
        [string]$ManufacturerNameFilter,
        [string]$ManufacturerIdFilter
    )

    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
        throw "Drivers catalog not found: $CatalogPath"
    }

    $catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($mfr in @($catalog.manufacturers)) {
        if ($ManufacturerNameFilter -and -not [string]::Equals([string]$mfr.name, $ManufacturerNameFilter, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if ($ManufacturerIdFilter -and -not [string]::Equals([string]$mfr.manufacturerId, $ManufacturerIdFilter, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        foreach ($model in @($mfr.models)) {
            $rel = [string]$model.path
            $full = if ([string]::IsNullOrWhiteSpace($rel)) {
                ""
            }
            elseif ([System.IO.Path]::IsPathRooted($rel)) {
                $rel
            }
            else {
                Join-Path $DeploymentRoot (($rel -replace '/', '\'))
            }
            $extracted = if ($full) { Join-Path $full "Extracted" } else { "" }
            $pathOk = $false
            if ($extracted -and (Test-Path -LiteralPath $extracted -PathType Container)) {
                $any = Get-ChildItem -LiteralPath $extracted -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                $pathOk = $null -ne $any
            }

            $skus = @()
            if ($model.systemSku) {
                $skus = @($model.systemSku | ForEach-Object { [string]$_ } | Where-Object { $_ })
            }

            $rows.Add([pscustomobject]@{
                    ManufacturerId   = [string]$mfr.manufacturerId
                    ManufacturerName = [string]$mfr.name
                    ModelId          = [string]$model.modelId
                    ModelName        = [string]$model.name
                    SystemSku        = $skus
                    Version          = [string]$model.version
                    ReleaseDate      = if ($model.PSObject.Properties["releaseDate"]) { [string]$model.releaseDate } else { "" }
                    Role             = if ($model.PSObject.Properties["role"] -and $model.role) { [string]$model.role } else { "fullOs" }
                    ImportedDate     = [string]$model.importedDate
                    Format           = [string]$model.format
                    DownloadLink     = if ($model.PSObject.Properties["downloadLink"]) { [string]$model.downloadLink } else { "" }
                    Path             = $rel
                    FullPath         = $full
                    PathOk           = $pathOk
                })
        }
    }

    return @($rows.ToArray())
}

function Get-CsvAllowList {
    param([string]$CsvPath, [string]$Delimiter)

    if ([string]::IsNullOrWhiteSpace($CsvPath)) { return @() }
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        throw "ModelsCsvPath not found: $CsvPath"
    }

    $rows = @(Import-Csv -LiteralPath $CsvPath -Delimiter $Delimiter -ErrorAction Stop)
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $modelName = $null
        $skuRaw = $null
        foreach ($prop in $row.PSObject.Properties) {
            if ($prop.Name -match '^(Model|ModelName|Name)$' -and $prop.Value) { $modelName = [string]$prop.Value }
            if ($prop.Name -match '^(SystemSku|SkuId|SKU|Sku|SystemSKU)$' -and $prop.Value) { $skuRaw = [string]$prop.Value }
        }
        if (-not $modelName -or -not $skuRaw) { continue }
        $skus = @($skuRaw -split '[,;|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        foreach ($sku in $skus) {
            $list.Add([pscustomobject]@{
                    ModelName = $modelName.Trim()
                    SystemSku = $sku.Trim().ToUpperInvariant()
                })
        }
    }
    return @($list.ToArray())
}

function Resolve-VendorFamily {
    param([string]$ManufacturerName, [string]$ManufacturerId)
    $blob = ("{0} {1}" -f $ManufacturerName, $ManufacturerId).ToLowerInvariant()
    if ($blob -match 'dell') { return "Dell" }
    if ($blob -match 'lenovo') { return "Lenovo" }
    if ($blob -match '\bhp\b|hewlett') { return "HP" }
    return $ManufacturerName
}

function New-StatusRows {
    param(
        [object[]]$LocalModels,
        [hashtable]$VendorMap,
        [object[]]$AllowList
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $localSkuSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($local in $LocalModels) {
        # WinPE model is not compared against FullOS pack catalogs.
        if ($local.Role -eq "winpe" -or [string]::Equals($local.ModelId, "winpe", [StringComparison]::OrdinalIgnoreCase)) {
            $rows.Add([pscustomobject]@{
                    Manufacturer  = $local.ManufacturerName
                    Model         = $local.ModelName
                    ModelId       = $local.ModelId
                    SystemSku     = ($local.SystemSku -join ";")
                    LocalVersion  = $local.Version
                    OnlineVersion = ""
                    OnlineDate    = ""
                    PathOk        = $local.PathOk
                    VendorHit     = $false
                    VendorName    = ""
                    VendorUrl     = ""
                    DownloadLink  = $local.DownloadLink
                    Status        = $(if ($local.PathOk) { "WinPeModel" } else { "MissingContent" })
                })
            continue
        }

        $family = Resolve-VendorFamily -ManufacturerName $local.ManufacturerName -ManufacturerId $local.ManufacturerId
        $skuText = ($local.SystemSku -join ";")
        $vendorHits = [System.Collections.Generic.List[object]]::new()
        foreach ($sku in @($local.SystemSku)) {
            $key = $sku.ToUpperInvariant()
            [void]$localSkuSet.Add($key)
            if ($VendorMap.ContainsKey($key)) {
                foreach ($hit in $VendorMap[$key]) {
                    if ($hit.Vendor -eq $family -or [string]::IsNullOrWhiteSpace($family)) {
                        $vendorHits.Add($hit)
                    }
                }
            }
        }

        $vendorHit = $vendorHits.Count -gt 0
        $bestHit = $null
        if ($vendorHit) {
            foreach ($h in $vendorHits) {
                if ($null -eq $bestHit -or (Test-OnlinePackNewer -LocalVersion $bestHit.Version -LocalReleaseDate $bestHit.ReleaseDate -OnlineVersion $h.Version -OnlineReleaseDate $h.ReleaseDate)) {
                    $bestHit = $h
                }
            }
        }
        $vendorName = if ($bestHit) { [string]$bestHit.Name } else { "" }
        $vendorUrl = if ($bestHit) { [string]$bestHit.Url } else { "" }
        $onlineVersion = if ($bestHit) { [string]$bestHit.Version } else { "" }
        $onlineDate = if ($bestHit) { [string]$bestHit.ReleaseDate } else { "" }

        $localDate = $local.ReleaseDate
        if ([string]::IsNullOrWhiteSpace($localDate)) { $localDate = $local.ImportedDate }

        $status = "Current"
        if (-not $local.PathOk) {
            $status = "MissingContent"
        }
        elseif ($family -in @("Dell", "HP", "Lenovo") -and $VendorMap.Count -eq 0) {
            $status = "NoVendorIndex"
        }
        elseif ($family -in @("Dell", "HP", "Lenovo") -and -not $vendorHit) {
            $status = "MissingFromVendor"
        }
        elseif ($vendorHit -and (Test-OnlinePackNewer -LocalVersion $local.Version -LocalReleaseDate $localDate -OnlineVersion $onlineVersion -OnlineReleaseDate $onlineDate)) {
            $status = "UpdateAvailable"
        }

        $rows.Add([pscustomobject]@{
                Manufacturer  = $local.ManufacturerName
                Model         = $local.ModelName
                ModelId       = $local.ModelId
                SystemSku     = $skuText
                LocalVersion  = $local.Version
                OnlineVersion = $onlineVersion
                OnlineDate    = $onlineDate
                PathOk        = $local.PathOk
                VendorHit     = $vendorHit
                VendorName    = $vendorName
                VendorUrl     = $vendorUrl
                DownloadLink  = $local.DownloadLink
                Status        = $status
            })
    }

    foreach ($allow in @($AllowList)) {
        if ($localSkuSet.Contains($allow.SystemSku)) { continue }
        if (-not $VendorMap.ContainsKey($allow.SystemSku)) { continue }
        $hits = @($VendorMap[$allow.SystemSku])
        $hit = $hits | Select-Object -First 1
        $rows.Add([pscustomobject]@{
                Manufacturer  = $hit.Vendor
                Model         = $allow.ModelName
                ModelId       = ""
                SystemSku     = $allow.SystemSku
                LocalVersion  = ""
                OnlineVersion = [string]$hit.Version
                OnlineDate    = [string]$hit.ReleaseDate
                PathOk        = $false
                VendorHit     = $true
                VendorName    = $hit.Name
                VendorUrl     = $hit.Url
                DownloadLink  = [string]$hit.Url
                Status        = "NewInAllowList"
            })
    }

    return @($rows.ToArray())
}

function Resolve-PackFromVendorMap {
    param(
        [object]$LocalModel,
        [hashtable]$VendorMap
    )

    $family = Resolve-VendorFamily -ManufacturerName $LocalModel.ManufacturerName -ManufacturerId $LocalModel.ManufacturerId
    $best = $null
    foreach ($sku in @($LocalModel.SystemSku)) {
        $key = ([string]$sku).ToUpperInvariant()
        if (-not $VendorMap.ContainsKey($key)) { continue }
        foreach ($hit in $VendorMap[$key]) {
            if ($hit.Vendor -ne $family -and -not [string]::IsNullOrWhiteSpace($family)) { continue }
            if ($null -eq $best -or (Test-OnlinePackNewer -LocalVersion $best.Version -LocalReleaseDate $best.ReleaseDate -OnlineVersion $hit.Version -OnlineReleaseDate $hit.ReleaseDate)) {
                $best = $hit
            }
        }
    }
    return $best
}

function Invoke-ModelPackUpdate {
    param(
        [object]$LocalModel,
        [string]$DeploymentRoot,
        [string]$ImportScript,
        [hashtable]$VendorMap = $null,
        [string]$ResolvedDownloadLink = "",
        [string]$ResolvedVersion = "",
        [switch]$UseCurl,
        [switch]$Force
    )

    if ($LocalModel.Role -eq "winpe" -or [string]::Equals([string]$LocalModel.ModelId, "winpe", [StringComparison]::OrdinalIgnoreCase)) {
        Write-SyncLog "Skip WinPE model (use -WinPESourcePath on ImportOEMDrivers): $($LocalModel.ManufacturerName)" -ForegroundColor DarkYellow
        return [pscustomobject]@{ Model = $LocalModel.ModelName; Updated = $false; Reason = "WinPeModel" }
    }

    $downloadLink = $ResolvedDownloadLink
    if ([string]::IsNullOrWhiteSpace($downloadLink)) {
        $downloadLink = [string]$LocalModel.DownloadLink
    }
    $onlineVersion = $ResolvedVersion
    if ([string]::IsNullOrWhiteSpace($downloadLink) -and $null -ne $VendorMap) {
        $pack = Resolve-PackFromVendorMap -LocalModel $LocalModel -VendorMap $VendorMap
        if ($pack -and -not [string]::IsNullOrWhiteSpace($pack.Url)) {
            $downloadLink = [string]$pack.Url
            if ([string]::IsNullOrWhiteSpace($onlineVersion)) {
                $onlineVersion = [string]$pack.Version
            }
            Write-SyncLog "Resolved pack URL from OEM catalog: $downloadLink"
        }
    }

    if ([string]::IsNullOrWhiteSpace($downloadLink)) {
        Write-SyncLog "Skip (no downloadLink / catalog URL): $($LocalModel.ManufacturerName) / $($LocalModel.ModelName)" -ForegroundColor DarkYellow
        return [pscustomobject]@{ Model = $LocalModel.ModelName; Updated = $false; Reason = "NoDownloadLink" }
    }

    $skuArgs = @($LocalModel.SystemSku)
    if ($skuArgs.Count -eq 0) {
        Write-SyncLog "Skip (no systemSku): $($LocalModel.ModelName)" -ForegroundColor DarkYellow
        return [pscustomobject]@{ Model = $LocalModel.ModelName; Updated = $false; Reason = "NoSystemSku" }
    }

    $format = $LocalModel.Format
    if ($format -notin @("exe", "cab")) {
        try {
            $ext = [IO.Path]::GetExtension(([Uri]$downloadLink).LocalPath).TrimStart(".").ToLowerInvariant()
            if ($ext -in @("exe", "cab")) { $format = $ext } else { $format = "cab" }
        }
        catch {
            $format = "cab"
        }
    }

    $version = if (-not [string]::IsNullOrWhiteSpace($onlineVersion)) {
        $onlineVersion
    }
    elseif (-not [string]::IsNullOrWhiteSpace($LocalModel.Version)) {
        $LocalModel.Version
    }
    else {
        (Get-Date).ToString("yyyy.MM.dd")
    }

    $folderName = if ($LocalModel.FullPath) { Split-Path -Leaf $LocalModel.FullPath } else { $LocalModel.ModelName }

    $argList = @{
        DeploymentRoot   = $DeploymentRoot
        ManufacturerId   = $LocalModel.ManufacturerId
        ManufacturerName = $LocalModel.ManufacturerName
        ModelId          = $LocalModel.ModelId
        ModelName        = $LocalModel.ModelName
        SystemSku        = $skuArgs
        Version          = $version
        Format           = $format
        DownloadLink     = $downloadLink
        FolderName       = $folderName
    }
    if ($UseCurl) { $argList["UseCurl"] = $true }
    if ($Force) { $argList["Force"] = $true }

    $target = "$($LocalModel.ManufacturerName)/$($LocalModel.ModelName)"
    if (-not $PSCmdlet.ShouldProcess($target, "Download OEM driver pack from catalog/URL")) {
        return [pscustomobject]@{ Model = $LocalModel.ModelName; Updated = $false; Reason = "WhatIf"; DownloadLink = $downloadLink }
    }

    Write-SyncLog "Updating $target ($version) ..." -ForegroundColor Green
    & $ImportScript @argList
    return [pscustomobject]@{
        Model         = $LocalModel.ModelName
        Updated       = $true
        Reason        = "Imported"
        DownloadLink  = $downloadLink
        OnlineVersion = $version
    }
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

$DeploymentRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DeploymentRoot)
if (-not (Test-Path -LiteralPath $DeploymentRoot -PathType Container)) {
    throw "DeploymentRoot not found: $DeploymentRoot"
}

$driversRoot = Join-Path $DeploymentRoot "Content\Drivers"
$catalogPath = Join-Path $driversRoot "catalog.json"
$tempRoot = Join-Path $DeploymentRoot "Content\Temp"
$oemCatalogsRoot = Join-Path $tempRoot "OemCatalogs"
$importScript = Join-Path $PSScriptRoot "..\ImportOEMDrivers\LiteDeploy.ImportOEMDrivers.ps1"
$importScript = [System.IO.Path]::GetFullPath($importScript)

if (-not (Test-Path -LiteralPath $tempRoot)) {
    $null = New-Item -Path $tempRoot -ItemType Directory -Force
}

Write-SyncLog "Deployment root : $DeploymentRoot"
Write-SyncLog "Drivers catalog : $catalogPath"
Write-SyncLog "OemCatalogs     : $oemCatalogsRoot"
Write-SyncLog "Mode            : $($PSCmdlet.ParameterSetName)"

$indexPaths = $null
try {
    $indexPaths = Update-OemVendorIndexes `
        -OemCatalogsRoot $oemCatalogsRoot `
        -MaxAgeDays $MaxCatalogAgeDays `
        -ForceRefresh:$RefreshCatalog
}
catch {
    Write-SyncLog "Vendor index refresh failed (status may be limited): $($_.Exception.Message)" -ForegroundColor DarkYellow
    $indexPaths = [ordered]@{
        DellIndex = (Join-Path $oemCatalogsRoot "Dell\CatalogIndexPC.xml")
        DellPack  = (Join-Path $oemCatalogsRoot "Dell\DriverPackCatalog.xml")
        HPIndex   = (Join-Path $oemCatalogsRoot "HP\PlatformList.xml")
        HPPack    = (Join-Path $oemCatalogsRoot "HP\HPClientDriverPackCatalog.xml")
        Lenovo    = (Join-Path $oemCatalogsRoot "Lenovo\catalogv2.xml")
    }
}

$vendorMap = Get-VendorPackMaps -IndexPaths $indexPaths
$localModels = @(Get-LocalDriverModels `
        -CatalogPath $catalogPath `
        -DeploymentRoot $DeploymentRoot `
        -ManufacturerNameFilter $ManufacturerName `
        -ManufacturerIdFilter $ManufacturerId)

if ($PSCmdlet.ParameterSetName -eq "CheckStatus") {
    $csvResolved = ""
    if (-not [string]::IsNullOrWhiteSpace($ModelsCsvPath)) {
        $csvResolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModelsCsvPath)
    }
    $allowList = @(Get-CsvAllowList -CsvPath $csvResolved -Delimiter $CsvDelimiter)
    $statusRows = @(New-StatusRows -LocalModels $localModels -VendorMap $vendorMap -AllowList $allowList)

    Write-SyncLog ("Status rows: {0}" -f $statusRows.Count) -ForegroundColor Green
    $statusRows |
        Sort-Object Status, Manufacturer, Model |
        Format-Table -AutoSize Manufacturer, Model, SystemSku, LocalVersion, OnlineVersion, OnlineDate, Status

    $summary = $statusRows | Group-Object Status | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ Status = $_.Name; Count = $_.Count }
    }
    Write-Host ""
    Write-SyncLog "Summary:"
    $summary | Format-Table -AutoSize

    $updates = @($statusRows | Where-Object { $_.Status -eq "UpdateAvailable" })
    if ($updates.Count -gt 0) {
        Write-Host ""
        Write-SyncLog "Newer packs online (use -UpdateAll / -Model / -SystemSku to download):" -ForegroundColor Yellow
        $updates | Format-Table -AutoSize Manufacturer, Model, SystemSku, LocalVersion, OnlineVersion, OnlineDate, VendorUrl
    }

    return [pscustomobject]@{
        CatalogPath = $catalogPath
        OemCatalogs = $oemCatalogsRoot
        Rows        = $statusRows
        Summary     = @($summary)
    }
}

# Update modes: download + replace Extracted + update catalog.json
if (-not (Test-Path -LiteralPath $importScript -PathType Leaf)) {
    throw "ImportOEMDrivers script not found: $importScript"
}

$statusRows = @(New-StatusRows -LocalModels $localModels -VendorMap $vendorMap -AllowList @())
$statusByKey = @{}
foreach ($row in $statusRows) {
    $key = "{0}|{1}" -f $row.Manufacturer, $row.ModelId
    $statusByKey[$key] = $row
}

$targets = @()
switch ($PSCmdlet.ParameterSetName) {
    "UpdateModel" {
        $targets = @($localModels | Where-Object {
                $_.Role -ne "winpe" -and
                -not [string]::Equals([string]$_.ModelId, "winpe", [StringComparison]::OrdinalIgnoreCase) -and
                ($_.ModelName -like "*$Model*" -or $_.ModelId -like "*$Model*")
            })
    }
    "UpdateSku" {
        $want = $SystemSku.Trim().ToUpperInvariant()
        $targets = @($localModels | Where-Object {
                $_.Role -ne "winpe" -and
                -not [string]::Equals([string]$_.ModelId, "winpe", [StringComparison]::OrdinalIgnoreCase) -and
                (@($_.SystemSku | ForEach-Object { $_.ToUpperInvariant() }) -contains $want)
            })
    }
    "UpdateAll" {
        # Only models that have a newer pack online (or missing content with a catalog URL).
        $targets = foreach ($local in $localModels) {
            if ($local.Role -eq "winpe" -or [string]::Equals([string]$local.ModelId, "winpe", [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $key = "{0}|{1}" -f $local.ManufacturerName, $local.ModelId
            $row = $statusByKey[$key]
            if ($null -eq $row) { continue }
            if ($row.Status -in @("UpdateAvailable", "MissingContent") -and -not [string]::IsNullOrWhiteSpace($row.VendorUrl)) {
                $local
            }
            elseif ($row.Status -eq "UpdateAvailable") {
                $local
            }
        }
        $targets = @($targets)
    }
}

if ($targets.Count -eq 0) {
    Write-SyncLog "No matching models to update (CheckStatus for UpdateAvailable rows)." -ForegroundColor DarkYellow
    return
}

Write-SyncLog ("Update candidates: {0} (download → replace Extracted → update catalog)" -f $targets.Count)
$results = foreach ($t in $targets) {
    $key = "{0}|{1}" -f $t.ManufacturerName, $t.ModelId
    $row = $statusByKey[$key]
    $resolvedUrl = if ($row) { [string]$row.VendorUrl } else { "" }
    $resolvedVer = if ($row) { [string]$row.OnlineVersion } else { "" }
    Invoke-ModelPackUpdate `
        -LocalModel $t `
        -DeploymentRoot $DeploymentRoot `
        -ImportScript $importScript `
        -VendorMap $vendorMap `
        -ResolvedDownloadLink $resolvedUrl `
        -ResolvedVersion $resolvedVer `
        -UseCurl:$UseCurl `
        -Force:$Force
}

$results | Format-Table -AutoSize
return [pscustomobject]@{
    Updated = @($results)
}
