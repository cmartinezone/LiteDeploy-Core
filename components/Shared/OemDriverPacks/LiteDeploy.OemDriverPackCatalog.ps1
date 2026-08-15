<#
.SYNOPSIS
    Shared Dell/HP/Lenovo driver-pack catalog helpers for Manager and Media runtime.

.DESCRIPTION
    Refresh OEM pack indexes, compare versions, resolve pack URLs by SystemSKU,
    and optionally download/extract a pack onto local media (same Content\Drivers layout).

    Dot-source from SyncOEMDrivers (Manager) or SelectWorkflow (Media).
    Override Write-OemPackLog before dot-sourcing to redirect logging.
#>

if (-not (Get-Command Write-OemPackLog -ErrorAction SilentlyContinue)) {
    function Write-OemPackLog {
        param(
            [string]$Message,
            [ConsoleColor]$ForegroundColor = [ConsoleColor]::Cyan
        )
        Write-Host " [OemDriverPack]  $Message" -ForegroundColor $ForegroundColor
    }
}

function Save-OemRemoteFile {
    param([string]$Uri, [string]$Destination)

    $destinationDir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destinationDir)) {
        $null = New-Item -Path $destinationDir -ItemType Directory -Force
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }

    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Write-OemPackLog "Downloading (BITS): $Uri"
        try {
            Start-BitsTransfer -Source $Uri -Destination $Destination -ErrorAction Stop
            if (Test-Path -LiteralPath $Destination -PathType Leaf) { return }
        }
        catch {
            Write-OemPackLog "BITS failed; falling back to Invoke-WebRequest. $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    Write-OemPackLog "Downloading (Invoke-WebRequest): $Uri"
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -ErrorAction Stop
}

function Expand-OemCatalogCab {
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

function Test-OemCatalogCacheFresh {
    param([string]$Path, [int]$MaxAgeDays)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $age = ((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalDays
    return ($age -lt $MaxAgeDays)
}

function Update-OemVendorIndexes {
    param(
        [string]$OemCatalogsRoot,
        [int]$MaxAgeDays = 7,
        [switch]$ForceRefresh
    )

    $results = [ordered]@{}

    function Sync-CabCatalog {
        param([string]$Dir, [string]$CabName, [string]$XmlName, [string]$Uri, [string]$Label)
        $xmlPath = Join-Path $Dir $XmlName
        $cabPath = Join-Path $Dir $CabName
        if ($ForceRefresh -or -not (Test-OemCatalogCacheFresh -Path $xmlPath -MaxAgeDays $MaxAgeDays)) {
            if (-not (Test-Path -LiteralPath $Dir)) { $null = New-Item -Path $Dir -ItemType Directory -Force }
            Save-OemRemoteFile -Uri $Uri -Destination $cabPath
            Expand-OemCatalogCab -CabPath $cabPath -XmlPath $xmlPath
            Remove-Item -LiteralPath $cabPath -Force -ErrorAction SilentlyContinue
            Write-OemPackLog "$Label refreshed: $xmlPath" -ForegroundColor Green
        }
        else {
            Write-OemPackLog "$Label cache fresh: $xmlPath"
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
    if ($ForceRefresh -or -not (Test-OemCatalogCacheFresh -Path $lenovoXml -MaxAgeDays $MaxAgeDays)) {
        if (-not (Test-Path -LiteralPath $lenovoDir)) { $null = New-Item -Path $lenovoDir -ItemType Directory -Force }
        Save-OemRemoteFile -Uri "https://download.lenovo.com/cdrt/td/catalogv2.xml" -Destination $lenovoXml
        Write-OemPackLog "Lenovo catalogv2 refreshed: $lenovoXml" -ForegroundColor Green
    }
    else {
        Write-OemPackLog "Lenovo catalogv2 cache fresh: $lenovoXml"
    }
    $results["Lenovo"] = $lenovoXml

    return $results
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

    $lm = [regex]::Match($lv, '^A(\d{2})$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $om = [regex]::Match($ov, '^A(\d{2})$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($lm.Success -and $om.Success) {
        return ([int]$lm.Groups[1].Value -lt [int]$om.Groups[1].Value)
    }

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

    return $true
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
    $existing = $Map[$key][0]
    if (Test-OnlinePackNewer -LocalVersion $existing.Version -LocalReleaseDate $existing.ReleaseDate -OnlineVersion $Version -OnlineReleaseDate $ReleaseDate) {
        $Map[$key].Clear()
        $Map[$key].Add($candidate)
    }
}

function Get-VendorPackMaps {
    param($IndexPaths)

    $map = @{}

    if ($IndexPaths["DellPack"] -and (Test-Path -LiteralPath $IndexPaths["DellPack"])) {
        Write-OemPackLog "Parsing Dell DriverPackCatalog (pack versions)..."
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
            Write-OemPackLog "Dell DriverPackCatalog parse warning: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    if ($IndexPaths["HPPack"] -and (Test-Path -LiteralPath $IndexPaths["HPPack"])) {
        Write-OemPackLog "Parsing HP Client DriverPackCatalog (pack versions)..."
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
            Write-OemPackLog "HP DriverPackCatalog parse warning: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    if ($IndexPaths["Lenovo"] -and (Test-Path -LiteralPath $IndexPaths["Lenovo"])) {
        Write-OemPackLog "Parsing Lenovo catalogv2 (SCCM pack versions)..."
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
            Write-OemPackLog "Lenovo catalogv2 parse warning: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    Write-OemPackLog ("Vendor pack version entries: {0}" -f $map.Count)
    return $map
}

function Resolve-VendorFamily {
    param([string]$ManufacturerName, [string]$ManufacturerId = "")
    $blob = ("{0} {1}" -f $ManufacturerName, $ManufacturerId).ToLowerInvariant()
    if ($blob -match 'dell') { return "Dell" }
    if ($blob -match 'lenovo') { return "Lenovo" }
    if ($blob -match '\bhp\b|hewlett') { return "HP" }
    return $ManufacturerName
}

function Test-OemOnlineCompareSupported {
    param([string]$ManufacturerName, [string]$ManufacturerId = "")
    $family = Resolve-VendorFamily -ManufacturerName $ManufacturerName -ManufacturerId $ManufacturerId
    return ($family -in @("Dell", "HP", "Lenovo"))
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

function Get-SystemHardwareIdentity {
    $rawManuf = ""
    $rawModel = ""
    $manufacturerId = ""
    $skus = [System.Collections.Generic.List[string]]::new()

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $rawManuf = [string]$cs.Manufacturer
        $rawModel = [string]$cs.Model
        $manufacturerId = $rawManuf.Trim()
    }
    catch {
        try {
            $wmiCs = Get-WmiObject Win32_ComputerSystem -ErrorAction Stop
            $rawManuf = [string]$wmiCs.Manufacturer
            $rawModel = [string]$wmiCs.Model
            $manufacturerId = $rawManuf.Trim()
        }
        catch {
            $rawManuf = "Unknown"
            $rawModel = "Unknown"
        }
    }

    $family = Resolve-VendorFamily -ManufacturerName $rawManuf -ManufacturerId $manufacturerId

    try {
        $msi = Get-CimInstance -Namespace root\wmi -ClassName MS_SystemInformation -ErrorAction Stop
        if ($msi.SystemSKU) { [void]$skus.Add(([string]$msi.SystemSKU).Trim().ToUpperInvariant()) }
        if ($msi.BaseBoardProduct) { [void]$skus.Add(([string]$msi.BaseBoardProduct).Trim().ToUpperInvariant()) }
        if ($msi.SystemProductName) {
            $prod = ([string]$msi.SystemProductName).Trim()
            if ($prod.Length -ge 4) { [void]$skus.Add($prod.Substring(0, 4).ToUpperInvariant()) }
        }
    }
    catch { }

    try {
        $bb = Get-CimInstance Win32_BaseBoard -ErrorAction Stop
        if ($bb.Product) { [void]$skus.Add(([string]$bb.Product).Trim().ToUpperInvariant()) }
    }
    catch { }

    try {
        $csp = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop
        if ($csp.Name) {
            $n = ([string]$csp.Name).Trim() -replace '\s+', ''
            if ($n.Length -ge 4) { [void]$skus.Add($n.Substring(0, 4).ToUpperInvariant()) }
            [void]$skus.Add($n.ToUpperInvariant())
        }
        if ($csp.Version) {
            $v = ([string]$csp.Version).Trim() -replace '\s+', ''
            if ($v.Length -ge 4) { [void]$skus.Add($v.Substring(0, 4).ToUpperInvariant()) }
        }
    }
    catch { }

    $uniqueSkus = @($skus | Where-Object { $_ } | Select-Object -Unique)

    return [pscustomobject]@{
        ManufacturerId   = $manufacturerId
        ManufacturerName = $family
        ModelName        = $rawModel.Trim()
        SystemSku        = $uniqueSkus
        CompareSupported = ($family -in @("Dell", "HP", "Lenovo"))
    }
}

function ConvertTo-ModelIdSlug {
    param([string]$Name)
    $slug = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = "model" }
    return $slug
}

function Find-LocalMediaDriverModel {
    param(
        [string]$DeploymentRoot,
        [object]$Hardware
    )

    $driversRoot = Join-Path $DeploymentRoot "Content\Drivers"
    $catalogPath = Join-Path $driversRoot "catalog.json"
    $skuSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($s in @($Hardware.SystemSku)) { [void]$skuSet.Add($s) }

    $catalogHit = $null
    if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
        try {
            $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($mfr in @($catalog.manufacturers)) {
                $mfrFamily = Resolve-VendorFamily -ManufacturerName $mfr.name -ManufacturerId $mfr.manufacturerId
                if ($mfrFamily -ne $Hardware.ManufacturerName -and
                    -not [string]::Equals([string]$mfr.manufacturerId, [string]$Hardware.ManufacturerId, [StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }
                foreach ($model in @($mfr.models)) {
                    $role = if ($model.PSObject.Properties["role"] -and $model.role) { [string]$model.role } else { "fullOs" }
                    if ($role -eq "winpe" -or [string]::Equals([string]$model.modelId, "winpe", [StringComparison]::OrdinalIgnoreCase)) {
                        continue
                    }
                    $modelSkus = @($model.systemSku | ForEach-Object { [string]$_ })
                    $skuMatch = $false
                    foreach ($ms in $modelSkus) {
                        if ($skuSet.Contains($ms)) { $skuMatch = $true; break }
                    }
                    $nameMatch = [string]::Equals([string]$model.name, [string]$Hardware.ModelName, [StringComparison]::OrdinalIgnoreCase)
                    if (-not $skuMatch -and -not $nameMatch) { continue }

                    $rel = [string]$model.path
                    $full = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $DeploymentRoot (($rel -replace '/', '\')) }
                    $extracted = Join-Path $full "Extracted"
                    $pathOk = $false
                    if (Test-Path -LiteralPath $extracted -PathType Container) {
                        $any = Get-ChildItem -LiteralPath $extracted -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                        $pathOk = $null -ne $any
                    }
                    $catalogHit = [pscustomobject]@{
                        ManufacturerId   = [string]$mfr.manufacturerId
                        ManufacturerName = [string]$mfr.name
                        ModelId          = [string]$model.modelId
                        ModelName        = [string]$model.name
                        SystemSku        = $modelSkus
                        Version          = [string]$model.version
                        ReleaseDate      = if ($model.PSObject.Properties["releaseDate"]) { [string]$model.releaseDate } else { "" }
                        Format           = [string]$model.format
                        DownloadLink     = if ($model.PSObject.Properties["downloadLink"]) { [string]$model.downloadLink } else { "" }
                        Path             = $rel
                        FullPath         = $full
                        PathOk           = $pathOk
                        MatchedBy        = $(if ($skuMatch) { "Sku" } else { "ModelName" })
                    }
                    if ($skuMatch) { break }
                }
                if ($catalogHit -and $catalogHit.MatchedBy -eq "Sku") { break }
            }
        }
        catch {
            Write-OemPackLog "catalog.json parse warning: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    if ($catalogHit) { return $catalogHit }

    # Folder fallback: Content\Drivers\<Family>\<Model>
    $folder = Join-Path $driversRoot (Join-Path $Hardware.ManufacturerName $Hardware.ModelName)
    $extractedFolder = Join-Path $folder "Extracted"
    $pathOk = $false
    if (Test-Path -LiteralPath $extractedFolder -PathType Container) {
        $any = Get-ChildItem -LiteralPath $extractedFolder -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $pathOk = $null -ne $any
    }
    elseif (Test-Path -LiteralPath $folder -PathType Container) {
        $pathOk = $true
    }

    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        return $null
    }

    return [pscustomobject]@{
        ManufacturerId   = $Hardware.ManufacturerId
        ManufacturerName = $Hardware.ManufacturerName
        ModelId          = ConvertTo-ModelIdSlug -Name $Hardware.ModelName
        ModelName        = $Hardware.ModelName
        SystemSku        = @($Hardware.SystemSku)
        Version          = ""
        ReleaseDate      = ""
        Format           = ""
        DownloadLink     = ""
        Path             = "Content\Drivers\$($Hardware.ManufacturerName)\$($Hardware.ModelName)"
        FullPath         = $folder
        PathOk           = $pathOk
        MatchedBy        = "Folder"
    }
}

function Expand-OemDriverCabToExtracted {
    param(
        [string]$CabPath,
        [string]$ExtractedFolder,
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $ExtractedFolder)) {
        $null = New-Item -Path $ExtractedFolder -ItemType Directory -Force
    }
    elseif ($Force) {
        Get-ChildItem -LiteralPath $ExtractedFolder -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    $expand = Get-Command expand.exe -ErrorAction SilentlyContinue
    if (-not $expand) {
        throw "expand.exe was not found. Cannot extract CAB: $CabPath"
    }
    $args = @("`"$CabPath`"", "-F:*", "`"$ExtractedFolder`"")
    $p = Start-Process -FilePath $expand.Source -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) {
        throw "expand.exe failed for '$CabPath' (exit $($p.ExitCode))."
    }
}

function Update-MediaDriversCatalogEntry {
    param(
        [string]$CatalogPath,
        [object]$Hardware,
        [string]$ModelFolderRelative,
        [string]$ModelId,
        [string]$ModelName,
        [string]$Version,
        [string]$ReleaseDate,
        [string]$Format,
        [string]$DownloadLink
    )

    $catalogDir = Split-Path -Parent $CatalogPath
    if (-not (Test-Path -LiteralPath $catalogDir)) {
        $null = New-Item -Path $catalogDir -ItemType Directory -Force
    }

    $catalog = $null
    if (Test-Path -LiteralPath $CatalogPath -PathType Leaf) {
        try {
            $catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch { }
    }
    if ($null -eq $catalog) {
        $catalog = [pscustomobject]@{
            '$schema'     = "./schemas/drivers-catalog.schema.json"
            schemaVersion = 1
            manufacturers = @()
        }
    }

    $mfrs = [System.Collections.Generic.List[object]]::new()
    foreach ($m in @($catalog.manufacturers)) { $mfrs.Add($m) }

    $mfr = $null
    foreach ($candidate in $mfrs) {
        if ([string]::Equals([string]$candidate.name, [string]$Hardware.ManufacturerName, [StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals([string]$candidate.manufacturerId, [string]$Hardware.ManufacturerId, [StringComparison]::OrdinalIgnoreCase)) {
            $mfr = $candidate
            break
        }
    }
    if ($null -eq $mfr) {
        $mfr = [pscustomobject]@{
            manufacturerId = $Hardware.ManufacturerId
            name           = $Hardware.ManufacturerName
            enabled        = $true
            models         = @()
        }
        $mfrs.Add($mfr)
    }

    $models = [System.Collections.Generic.List[object]]::new()
    foreach ($model in @($mfr.models)) { $models.Add($model) }

    $existing = $null
    foreach ($model in $models) {
        if ([string]::Equals([string]$model.modelId, $ModelId, [StringComparison]::OrdinalIgnoreCase)) {
            $existing = $model
            break
        }
    }

    $entry = [ordered]@{
        modelId      = $ModelId
        name         = $ModelName
        systemSku    = @($Hardware.SystemSku)
        role         = "fullOs"
        version      = $Version
        releaseDate  = $ReleaseDate
        importedDate = (Get-Date).ToString("yyyy-MM-dd")
        format       = $Format
        enabled      = $true
        path         = $ModelFolderRelative
    }
    if (-not [string]::IsNullOrWhiteSpace($DownloadLink)) {
        $entry["downloadLink"] = $DownloadLink
    }

    if ($null -ne $existing) {
        $idx = $models.IndexOf($existing)
        $models[$idx] = [pscustomobject]$entry
    }
    else {
        $models.Add([pscustomobject]$entry)
    }

    $mfr.models = @($models.ToArray())
    $catalog.manufacturers = @($mfrs.ToArray())
    ($catalog | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $CatalogPath -Encoding UTF8
}

function Invoke-MediaOemDriverPackAction {
    <#
    .SYNOPSIS
        Media-only: ensure pack on local media, or check for update when folder exists.
    .DESCRIPTION
        - Missing model folder → download + extract (CAB) onto media.
        - Folder exists + -CheckUpdate → compare Dell/HP/Lenovo only; return UpdateAvailable (no silent replace).
        - Folder exists without -CheckUpdate → use local (SkippedExisting).
        - -ForceDownload replaces even when present (after operator confirms in UI).
    #>
    param(
        [string]$DeploymentRoot,
        [object]$Hardware = $null,
        [switch]$CheckUpdate,
        [switch]$ForceDownload,
        [int]$MaxCatalogAgeDays = 7,
        [switch]$RefreshCatalog
    )

    if ($null -eq $Hardware) {
        $Hardware = Get-SystemHardwareIdentity
    }

    $local = Find-LocalMediaDriverModel -DeploymentRoot $DeploymentRoot -Hardware $Hardware
    $folderExists = $null -ne $local -and -not [string]::IsNullOrWhiteSpace($local.FullPath) -and (Test-Path -LiteralPath $local.FullPath -PathType Container)
    $contentOk = $folderExists -and $local.PathOk

    if ($folderExists -and $contentOk -and -not $ForceDownload -and -not $CheckUpdate) {
        return [pscustomobject]@{
            Action           = "SkippedExisting"
            DriverFolderPath = $local.FullPath
            LocalVersion     = $local.Version
            OnlineVersion    = ""
            Message          = "Local driver pack already exists on media."
            Hardware         = $Hardware
            Local            = $local
            Pack             = $null
        }
    }

    if (-not $Hardware.CompareSupported) {
        return [pscustomobject]@{
            Action           = "CompareNotSupported"
            DriverFolderPath = if ($local) { $local.FullPath } else { "" }
            LocalVersion     = if ($local) { $local.Version } else { "" }
            OnlineVersion    = ""
            Message          = "Online pack compare/download is only available for Dell, HP, and Lenovo."
            Hardware         = $Hardware
            Local            = $local
            Pack             = $null
        }
    }

    $oemRoot = Join-Path $DeploymentRoot "Content\Temp\OemCatalogs"
    $indexPaths = Update-OemVendorIndexes -OemCatalogsRoot $oemRoot -MaxAgeDays $MaxCatalogAgeDays -ForceRefresh:$RefreshCatalog
    $vendorMap = Get-VendorPackMaps -IndexPaths $indexPaths

    $lookupModel = if ($local) {
        $local
    }
    else {
        [pscustomobject]@{
            ManufacturerId   = $Hardware.ManufacturerId
            ManufacturerName = $Hardware.ManufacturerName
            SystemSku        = $Hardware.SystemSku
        }
    }
    $pack = Resolve-PackFromVendorMap -LocalModel $lookupModel -VendorMap $vendorMap
    if ($null -eq $pack -or [string]::IsNullOrWhiteSpace($pack.Url)) {
        return [pscustomobject]@{
            Action           = "PackNotFound"
            DriverFolderPath = if ($local) { $local.FullPath } else { "" }
            LocalVersion     = if ($local) { $local.Version } else { "" }
            OnlineVersion    = ""
            Message          = "No OEM driver pack found online for this model/SKU."
            Hardware         = $Hardware
            Local            = $local
            Pack             = $null
        }
    }

    if ($folderExists -and $contentOk -and $CheckUpdate -and -not $ForceDownload) {
        $localVer = if ($local) { $local.Version } else { "" }
        $localDate = if ($local) { $local.ReleaseDate } else { "" }
        $isNewer = Test-OnlinePackNewer -LocalVersion $localVer -LocalReleaseDate $localDate -OnlineVersion $pack.Version -OnlineReleaseDate $pack.ReleaseDate
        if ($isNewer) {
            return [pscustomobject]@{
                Action           = "UpdateAvailable"
                DriverFolderPath = $local.FullPath
                LocalVersion     = $localVer
                OnlineVersion    = [string]$pack.Version
                OnlineDate       = [string]$pack.ReleaseDate
                Message          = "A newer driver pack is available online (local '$localVer' → online '$($pack.Version)')."
                Hardware         = $Hardware
                Local            = $local
                Pack             = $pack
            }
        }
        return [pscustomobject]@{
            Action           = "Current"
            DriverFolderPath = $local.FullPath
            LocalVersion     = $localVer
            OnlineVersion    = [string]$pack.Version
            Message          = "Local driver pack is current."
            Hardware         = $Hardware
            Local            = $local
            Pack             = $pack
        }
    }

    # Download onto media (missing folder, empty Extracted, or ForceDownload).
    $modelName = if ($local -and $local.ModelName) { $local.ModelName } elseif ($pack.Name) { [string]$pack.Name } else { $Hardware.ModelName }
    $modelId = if ($local -and $local.ModelId) { $local.ModelId } else { ConvertTo-ModelIdSlug -Name $modelName }
    $mfrName = $Hardware.ManufacturerName
    $modelFolder = Join-Path (Join-Path (Join-Path $DeploymentRoot "Content\Drivers") $mfrName) $modelName
    $extracted = Join-Path $modelFolder "Extracted"
    $relPath = "Content\Drivers\$mfrName\$modelName"

    if (-not (Test-Path -LiteralPath $modelFolder)) {
        $null = New-Item -Path $modelFolder -ItemType Directory -Force
    }

    $ext = ""
    try {
        $ext = [IO.Path]::GetExtension(([Uri]$pack.Url).LocalPath).TrimStart(".").ToLowerInvariant()
    }
    catch { }
    if ($ext -notin @("cab", "exe")) { $ext = "cab" }

    $fileName = [IO.Path]::GetFileName(([Uri]$pack.Url).LocalPath)
    if ([string]::IsNullOrWhiteSpace($fileName)) { $fileName = "driverpack.$ext" }
    $downloadTarget = Join-Path $modelFolder $fileName

    Write-OemPackLog "Downloading pack for $mfrName / $modelName → $downloadTarget"
    Save-OemRemoteFile -Uri $pack.Url -Destination $downloadTarget

    if ($ext -eq "cab") {
        Expand-OemDriverCabToExtracted -CabPath $downloadTarget -ExtractedFolder $extracted -Force
    }
    else {
        if (-not (Test-Path -LiteralPath $extracted)) {
            $null = New-Item -Path $extracted -ItemType Directory -Force
        }
        Write-OemPackLog "EXE pack stored at model folder. Populate Extracted\ offline if Setup needs INF tree." -ForegroundColor DarkYellow
    }

    $catalogPath = Join-Path $DeploymentRoot "Content\Drivers\catalog.json"
    Update-MediaDriversCatalogEntry `
        -CatalogPath $catalogPath `
        -Hardware $Hardware `
        -ModelFolderRelative $relPath `
        -ModelId $modelId `
        -ModelName $modelName `
        -Version ([string]$pack.Version) `
        -ReleaseDate ([string]$pack.ReleaseDate) `
        -Format $ext `
        -DownloadLink ([string]$pack.Url)

    return [pscustomobject]@{
        Action           = $(if ($ForceDownload) { "Replaced" } else { "Downloaded" })
        DriverFolderPath = $modelFolder
        LocalVersion     = [string]$pack.Version
        OnlineVersion    = [string]$pack.Version
        Message          = "Driver pack downloaded to media: $relPath"
        Hardware         = $Hardware
        Local            = $null
        Pack             = $pack
    }
}
