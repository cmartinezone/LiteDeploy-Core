<#
.SYNOPSIS
    Compares LiteDeploy driver catalog entries to OEM vendor indexes and optionally updates packs.

.DESCRIPTION
    Manager tool. Refreshes vendor catalog indexes under Content\Temp\OemCatalogs\,
    compares them to Content\Drivers\catalog.json, and prints a shell status table.
    Update modes re-import packs that already have downloadLink via ImportOEMDrivers.

.PARAMETER DeploymentRoot
    Deployment share root.

.PARAMETER CheckStatus
    Compare local catalog to vendor indexes and print a table.

.PARAMETER UpdateAll
    Re-download every local catalog model that has a downloadLink (optional manufacturer filter).

.PARAMETER Model
    Update models whose name or modelId matches this string (case-insensitive substring).

.PARAMETER SystemSku
    Update models that list this SystemSKU / Machine Type.

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
    Pass -Force to ImportOEMDrivers on update.

.EXAMPLE
    .\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -CheckStatus

.EXAMPLE
    .\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -UpdateAll -ManufacturerName Dell

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

    # Dell CatalogIndexPC
    $dellDir = Join-Path $OemCatalogsRoot "Dell"
    $dellXml = Join-Path $dellDir "CatalogIndexPC.xml"
    $dellCab = Join-Path $dellDir "CatalogIndexPC.cab"
    if ($ForceRefresh -or -not (Test-CatalogCacheFresh -Path $dellXml -MaxAgeDays $MaxAgeDays)) {
        if (-not (Test-Path -LiteralPath $dellDir)) { $null = New-Item -Path $dellDir -ItemType Directory -Force }
        Save-RemoteFileNative -Uri "https://downloads.dell.com/catalog/CatalogIndexPC.cab" -Destination $dellCab
        Expand-CabFile -CabPath $dellCab -XmlPath $dellXml
        Remove-Item -LiteralPath $dellCab -Force -ErrorAction SilentlyContinue
        Write-SyncLog "Dell index refreshed: $dellXml" -ForegroundColor Green
    }
    else {
        Write-SyncLog "Dell index cache fresh: $dellXml"
    }
    $results["Dell"] = $dellXml

    # HP platformList
    $hpDir = Join-Path $OemCatalogsRoot "HP"
    $hpXml = Join-Path $hpDir "PlatformList.xml"
    $hpCab = Join-Path $hpDir "platformList.cab"
    if ($ForceRefresh -or -not (Test-CatalogCacheFresh -Path $hpXml -MaxAgeDays $MaxAgeDays)) {
        if (-not (Test-Path -LiteralPath $hpDir)) { $null = New-Item -Path $hpDir -ItemType Directory -Force }
        Save-RemoteFileNative -Uri "https://hpia.hpcloud.hp.com/ref/platformList.cab" -Destination $hpCab
        Expand-CabFile -CabPath $hpCab -XmlPath $hpXml
        Remove-Item -LiteralPath $hpCab -Force -ErrorAction SilentlyContinue
        Write-SyncLog "HP index refreshed: $hpXml" -ForegroundColor Green
    }
    else {
        Write-SyncLog "HP index cache fresh: $hpXml"
    }
    $results["HP"] = $hpXml

    # Lenovo catalogv2 (XML direct)
    $lenovoDir = Join-Path $OemCatalogsRoot "Lenovo"
    $lenovoXml = Join-Path $lenovoDir "catalogv2.xml"
    if ($ForceRefresh -or -not (Test-CatalogCacheFresh -Path $lenovoXml -MaxAgeDays $MaxAgeDays)) {
        if (-not (Test-Path -LiteralPath $lenovoDir)) { $null = New-Item -Path $lenovoDir -ItemType Directory -Force }
        Save-RemoteFileNative -Uri "https://download.lenovo.com/cdrt/td/catalogv2.xml" -Destination $lenovoXml
        Write-SyncLog "Lenovo index refreshed: $lenovoXml" -ForegroundColor Green
    }
    else {
        Write-SyncLog "Lenovo index cache fresh: $lenovoXml"
    }
    $results["Lenovo"] = $lenovoXml

    return $results
}

function Get-VendorIndexMaps {
    param($IndexPaths)

    # Keyed by normalized SKU -> list of hits
    $map = @{}

    function Add-VendorHit {
        param([string]$Vendor, [string]$Sku, [string]$Name, [string]$Url)
        if ([string]::IsNullOrWhiteSpace($Sku)) { return }
        $key = $Sku.Trim().ToUpperInvariant()
        if (-not $map.ContainsKey($key)) {
            $map[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $map[$key].Add([pscustomobject]@{
                Vendor = $Vendor
                Sku    = $key
                Name   = $Name
                Url    = $Url
            })
    }

    if ($IndexPaths.ContainsKey("Dell") -and (Test-Path -LiteralPath $IndexPaths["Dell"])) {
        Write-SyncLog "Parsing Dell CatalogIndexPC..."
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.IgnoreWhitespace = $true
        $settings.IgnoreComments = $true
        $reader = [System.Xml.XmlReader]::Create($IndexPaths["Dell"], $settings)
        try {
            while ($reader.Read()) {
                if ($reader.NodeType -ne [System.Xml.XmlNodeType]::Element -or $reader.Name -ne "GroupManifest") {
                    continue
                }
                $sub = $reader.ReadSubtree()
                $doc = New-Object System.Xml.XmlDocument
                $doc.Load($sub)
                $sub.Dispose()

                $brandNode = $doc.SelectSingleNode("//*[local-name()='SupportedSystems']/*[local-name()='Brand']")
                if (-not $brandNode) { continue }
                $brandDisplay = ""
                $brandDisplayNode = $brandNode.SelectSingleNode("*[local-name()='Display']")
                if ($brandDisplayNode) { $brandDisplay = $brandDisplayNode.InnerText.Trim() }

                $modelNode = $brandNode.SelectSingleNode("*[local-name()='Model']")
                if (-not $modelNode) { continue }
                $systemId = $modelNode.GetAttribute("systemID")
                $modelNumber = ""
                $modelDisplayNode = $modelNode.SelectSingleNode("*[local-name()='Display']")
                if ($modelDisplayNode) { $modelNumber = $modelDisplayNode.InnerText.Trim() }

                $manifestInfo = $doc.SelectSingleNode("//*[local-name()='ManifestInformation']")
                $pathAttr = if ($manifestInfo) { $manifestInfo.GetAttribute("path") } else { "" }
                $cabUrl = if ($pathAttr) { "https://downloads.dell.com/$pathAttr" } else { "" }

                $gmDisplayNode = $doc.SelectSingleNode("/*[local-name()='GroupManifest']/*[local-name()='Display']")
                $modelFull = $null
                if ($gmDisplayNode -and $gmDisplayNode.InnerText) {
                    $modelFull = ($gmDisplayNode.InnerText.Trim() -replace '^\s*PDK Catalog for\s+', '').Trim()
                }
                if ([string]::IsNullOrWhiteSpace($modelFull)) {
                    $modelFull = ("{0} {1}" -f $brandDisplay, $modelNumber).Trim()
                }

                Add-VendorHit -Vendor "Dell" -Sku $systemId -Name $modelFull -Url $cabUrl
            }
        }
        finally {
            $reader.Dispose()
        }
    }

    if ($IndexPaths.ContainsKey("HP") -and (Test-Path -LiteralPath $IndexPaths["HP"])) {
        Write-SyncLog "Parsing HP PlatformList..."
        try {
            [xml]$hp = Get-Content -LiteralPath $IndexPaths["HP"] -Raw -Encoding UTF8
            $platforms = @($hp.SelectNodes("//*[local-name()='Platform']"))
            foreach ($p in $platforms) {
                $sysIdNode = $p.SelectSingleNode("*[local-name()='SystemID']")
                $nameNode = $p.SelectSingleNode("*[local-name()='ProductName']")
                if (-not $sysIdNode) { continue }
                $sysId = $sysIdNode.InnerText.Trim()
                $name = if ($nameNode) { $nameNode.InnerText.Trim() } else { $sysId }
                $url = "https://hpia.hpcloud.hp.com/ref/$sysId/"
                Add-VendorHit -Vendor "HP" -Sku $sysId -Name $name -Url $url
            }
        }
        catch {
            Write-SyncLog "HP PlatformList parse warning: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    if ($IndexPaths.ContainsKey("Lenovo") -and (Test-Path -LiteralPath $IndexPaths["Lenovo"])) {
        Write-SyncLog "Parsing Lenovo catalogv2..."
        try {
            [xml]$lenovo = Get-Content -LiteralPath $IndexPaths["Lenovo"] -Raw -Encoding UTF8
            $models = @($lenovo.SelectNodes("//*[local-name()='model']"))
            foreach ($m in $models) {
                $name = $m.GetAttribute("name")
                if ([string]::IsNullOrWhiteSpace($name)) {
                    $n = $m.SelectSingleNode("*[local-name()='name']")
                    if ($n) { $name = $n.InnerText }
                }
                $types = @($m.SelectNodes(".//*[local-name()='type']"))
                if ($types.Count -eq 0) {
                    $mt = $m.GetAttribute("mt")
                    if ($mt) { $types = @([pscustomobject]@{ InnerText = $mt }) }
                }
                foreach ($t in $types) {
                    $raw = if ($t.InnerText) { $t.InnerText } else { [string]$t }
                    $sku = ($raw.ToString().Trim() -replace '\s+', '')
                    if ($sku.Length -gt 4) { $sku = $sku.Substring(0, 4) }
                    Add-VendorHit -Vendor "Lenovo" -Sku $sku -Name $name -Url ""
                }
            }
        }
        catch {
            Write-SyncLog "Lenovo catalogv2 parse warning: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    Write-SyncLog ("Vendor SKU index entries: {0}" -f $map.Count)
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
        $vendorName = if ($vendorHit) { ($vendorHits | Select-Object -ExpandProperty Name -Unique) -join " | " } else { "" }
        $vendorUrl = if ($vendorHit) { ($vendorHits | Select-Object -ExpandProperty Url -Unique | Where-Object { $_ } | Select-Object -First 1) } else { "" }

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
        elseif (-not [string]::IsNullOrWhiteSpace($local.DownloadLink)) {
            $status = "UpdateReady"
        }

        $rows.Add([pscustomobject]@{
                Manufacturer = $local.ManufacturerName
                Model        = $local.ModelName
                ModelId      = $local.ModelId
                SystemSku    = $skuText
                LocalVersion = $local.Version
                PathOk       = $local.PathOk
                VendorHit    = $vendorHit
                VendorName   = $vendorName
                VendorUrl    = $vendorUrl
                DownloadLink = $local.DownloadLink
                Status       = $status
            })
    }

    foreach ($allow in @($AllowList)) {
        if ($localSkuSet.Contains($allow.SystemSku)) { continue }
        if (-not $VendorMap.ContainsKey($allow.SystemSku)) { continue }
        $hits = @($VendorMap[$allow.SystemSku])
        $hit = $hits | Select-Object -First 1
        $rows.Add([pscustomobject]@{
                Manufacturer = $hit.Vendor
                Model        = $allow.ModelName
                ModelId      = ""
                SystemSku    = $allow.SystemSku
                LocalVersion = ""
                PathOk       = $false
                VendorHit    = $true
                VendorName   = $hit.Name
                VendorUrl    = $hit.Url
                DownloadLink = ""
                Status       = "NewInAllowList"
            })
    }

    return @($rows.ToArray())
}

function Invoke-ModelPackUpdate {
    param(
        [object]$LocalModel,
        [string]$DeploymentRoot,
        [string]$ImportScript,
        [switch]$UseCurl,
        [switch]$Force
    )

    if ([string]::IsNullOrWhiteSpace($LocalModel.DownloadLink)) {
        Write-SyncLog "Skip (no downloadLink): $($LocalModel.ManufacturerName) / $($LocalModel.ModelName)" -ForegroundColor DarkYellow
        return [pscustomobject]@{ Model = $LocalModel.ModelName; Updated = $false; Reason = "NoDownloadLink" }
    }

    $skuArgs = @($LocalModel.SystemSku)
    if ($skuArgs.Count -eq 0) {
        Write-SyncLog "Skip (no systemSku): $($LocalModel.ModelName)" -ForegroundColor DarkYellow
        return [pscustomobject]@{ Model = $LocalModel.ModelName; Updated = $false; Reason = "NoSystemSku" }
    }

    $format = $LocalModel.Format
    if ($format -notin @("exe", "cab")) {
        $ext = [IO.Path]::GetExtension(([Uri]$LocalModel.DownloadLink).LocalPath).TrimStart(".").ToLowerInvariant()
        if ($ext -in @("exe", "cab")) { $format = $ext } else { $format = "cab" }
    }

    $version = if ([string]::IsNullOrWhiteSpace($LocalModel.Version)) { (Get-Date).ToString("yyyy.MM.dd") } else { $LocalModel.Version }

    $argList = @{
        DeploymentRoot   = $DeploymentRoot
        ManufacturerId   = $LocalModel.ManufacturerId
        ManufacturerName = $LocalModel.ManufacturerName
        ModelId          = $LocalModel.ModelId
        ModelName        = $LocalModel.ModelName
        SystemSku        = $skuArgs
        Version          = $version
        Format           = $format
        DownloadLink     = $LocalModel.DownloadLink
        FolderName       = Split-Path -Leaf $LocalModel.FullPath
    }
    if ($UseCurl) { $argList["UseCurl"] = $true }
    if ($Force) { $argList["Force"] = $true }

    $target = "$($LocalModel.ManufacturerName)/$($LocalModel.ModelName)"
    if (-not $PSCmdlet.ShouldProcess($target, "Update OEM driver pack from downloadLink")) {
        return [pscustomobject]@{ Model = $LocalModel.ModelName; Updated = $false; Reason = "WhatIf" }
    }

    Write-SyncLog "Updating $target ..." -ForegroundColor Green
    & $ImportScript @argList
    return [pscustomobject]@{ Model = $LocalModel.ModelName; Updated = $true; Reason = "Imported" }
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
    $indexPaths = @{
        Dell   = (Join-Path $oemCatalogsRoot "Dell\CatalogIndexPC.xml")
        HP     = (Join-Path $oemCatalogsRoot "HP\PlatformList.xml")
        Lenovo = (Join-Path $oemCatalogsRoot "Lenovo\catalogv2.xml")
    }
}

$vendorMap = Get-VendorIndexMaps -IndexPaths $indexPaths
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
        Format-Table -AutoSize Manufacturer, Model, SystemSku, LocalVersion, PathOk, VendorHit, Status, VendorName

    $summary = $statusRows | Group-Object Status | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ Status = $_.Name; Count = $_.Count }
    }
    Write-Host ""
    Write-SyncLog "Summary:"
    $summary | Format-Table -AutoSize

    return [pscustomobject]@{
        CatalogPath = $catalogPath
        OemCatalogs = $oemCatalogsRoot
        Rows        = $statusRows
        Summary     = @($summary)
    }
}

# Update modes
if (-not (Test-Path -LiteralPath $importScript -PathType Leaf)) {
    throw "ImportOEMDrivers script not found: $importScript"
}

$targets = @($localModels)
switch ($PSCmdlet.ParameterSetName) {
    "UpdateModel" {
        $targets = @($localModels | Where-Object {
                $_.ModelName -like "*$Model*" -or $_.ModelId -like "*$Model*"
            })
    }
    "UpdateSku" {
        $want = $SystemSku.Trim().ToUpperInvariant()
        $targets = @($localModels | Where-Object {
                @($_.SystemSku | ForEach-Object { $_.ToUpperInvariant() }) -contains $want
            })
    }
    "UpdateAll" {
        $targets = @($localModels)
    }
}

if ($targets.Count -eq 0) {
    Write-SyncLog "No matching local catalog models to update." -ForegroundColor DarkYellow
    return
}

Write-SyncLog ("Update candidates: {0}" -f $targets.Count)
$results = foreach ($t in $targets) {
    Invoke-ModelPackUpdate `
        -LocalModel $t `
        -DeploymentRoot $DeploymentRoot `
        -ImportScript $importScript `
        -UseCurl:$UseCurl `
        -Force:$Force
}

$results | Format-Table -AutoSize
return [pscustomobject]@{
    Updated = @($results)
}
