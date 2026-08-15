<#
.SYNOPSIS
    Compares LiteDeploy driver packs to Dell/HP/Lenovo online catalogs and can download updates.

.DESCRIPTION
    Manager tool. Refreshes vendor driver-pack catalogs under Content\Temp\OemCatalogs\,
    compares them to Content\Drivers\catalog.json, and prints a shell status table.

    -CheckStatus     → compare only (show LocalVersion vs OnlineVersion).
    -Update All      → download newer packs, replace Extracted\, update catalog.json.
    -Update "Model"  → download/replace that model (name or modelId).
    -Update "sku"    → download/replace by SystemSKU / Machine Type.

.PARAMETER DeploymentRoot
    Deployment share root.

.PARAMETER CheckStatus
    Compare local catalog to vendor pack catalogs and print a table (no download).

.PARAMETER Update
    Download/replace packs and update catalog.json.
    Use All for every UpdateAvailable model, or a model name/id / SystemSKU string.

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
    .\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -CheckStatus

.EXAMPLE
    .\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Update All -Force

.EXAMPLE
    .\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Update "Latitude 7450" -Force

.EXAMPLE
    .\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Update "0C09" -Force
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "CheckStatus")]
param(
    [Parameter(Mandatory = $true)]
    [string]$DeploymentRoot,

    [Parameter(Mandatory = $true, ParameterSetName = "CheckStatus")]
    [switch]$CheckStatus,

    [Parameter(Mandatory = $true, ParameterSetName = "Update")]
    [string]$Update = "",

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

    [Parameter(Mandatory = $false, ParameterSetName = "Update")]
    [switch]$UseCurl,

    [Parameter(Mandatory = $false, ParameterSetName = "Update")]
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

function Write-OemPackLog {
    param(
        [string]$Message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Cyan
    )
    Write-SyncLog -Message $Message -ForegroundColor $ForegroundColor
}

$script:OemDriverPackCatalogLib = @(
    (Join-Path $PSScriptRoot "..\..\Shared\OemDriverPacks\LiteDeploy.OemDriverPackCatalog.ps1"),
    (Join-Path $PSScriptRoot "..\Shared\OemDriverPacks\LiteDeploy.OemDriverPackCatalog.ps1")
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $script:OemDriverPackCatalogLib) {
    throw "Shared OEM pack catalog library not found (LiteDeploy.OemDriverPackCatalog.ps1)."
}
. $script:OemDriverPackCatalogLib

# Compatibility wrappers for older SyncOEMDrivers call sites
function Save-RemoteFileNative { param([string]$Uri,[string]$Destination) Save-OemRemoteFile -Uri $Uri -Destination $Destination }
function Expand-CabFile { param([string]$CabPath,[string]$XmlPath) Expand-OemCatalogCab -CabPath $CabPath -XmlPath $XmlPath }
function Test-CatalogCacheFresh { param([string]$Path,[int]$MaxAgeDays) Test-OemCatalogCacheFresh -Path $Path -MaxAgeDays $MaxAgeDays }

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
        -VendorFamily $ManufacturerName `
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
        Write-SyncLog "Newer packs online (use -Update All / -Update `"Model`" / -Update `"sku`" to download):" -ForegroundColor Yellow
        $updates | Format-Table -AutoSize Manufacturer, Model, SystemSku, LocalVersion, OnlineVersion, OnlineDate, VendorUrl
    }

    return [pscustomobject]@{
        CatalogPath = $catalogPath
        OemCatalogs = $oemCatalogsRoot
        Rows        = $statusRows
        Summary     = @($summary)
    }
}

# -Update All | "Model" | "sku" → download + replace Extracted + update catalog.json
if (-not (Test-Path -LiteralPath $importScript -PathType Leaf)) {
    throw "ImportOEMDrivers script not found: $importScript"
}

$updateValue = $Update.Trim()
if ([string]::IsNullOrWhiteSpace($updateValue)) {
    throw "-Update requires All, a model name/id, or a SystemSKU."
}

$statusRows = @(New-StatusRows -LocalModels $localModels -VendorMap $vendorMap -AllowList @())
$statusByKey = @{}
foreach ($row in $statusRows) {
    $key = "{0}|{1}" -f $row.Manufacturer, $row.ModelId
    $statusByKey[$key] = $row
}

function Test-IsFullOsLocalModel {
    param($Local)
    if ($Local.Role -eq "winpe") { return $false }
    if ([string]::Equals([string]$Local.ModelId, "winpe", [StringComparison]::OrdinalIgnoreCase)) { return $false }
    return $true
}

$targets = @()
if ([string]::Equals($updateValue, "All", [StringComparison]::OrdinalIgnoreCase) -or
    [string]::Equals($updateValue, "*", [StringComparison]::OrdinalIgnoreCase)) {
    Write-SyncLog "Update mode      : All (UpdateAvailable)"
    $targets = foreach ($local in $localModels) {
        if (-not (Test-IsFullOsLocalModel -Local $local)) { continue }
        $key = "{0}|{1}" -f $local.ManufacturerName, $local.ModelId
        $row = $statusByKey[$key]
        if ($null -eq $row) { continue }
        if ($row.Status -eq "UpdateAvailable" -or (
                $row.Status -eq "MissingContent" -and -not [string]::IsNullOrWhiteSpace($row.VendorUrl))) {
            $local
        }
    }
    $targets = @($targets)
}
else {
    # Prefer model name / modelId match; fall back to SystemSKU.
    $modelHits = @($localModels | Where-Object {
            (Test-IsFullOsLocalModel -Local $_) -and (
                $_.ModelName -like "*$updateValue*" -or $_.ModelId -like "*$updateValue*"
            )
        })
    if ($modelHits.Count -gt 0) {
        Write-SyncLog "Update mode      : Model '$updateValue'"
        $targets = $modelHits
    }
    else {
        $want = $updateValue.ToUpperInvariant()
        $skuHits = @($localModels | Where-Object {
                (Test-IsFullOsLocalModel -Local $_) -and (
                    @($_.SystemSku | ForEach-Object { $_.ToUpperInvariant() }) -contains $want
                )
            })
        if ($skuHits.Count -eq 0) {
            throw "No FullOS model matched -Update '$updateValue' as model name/id or SystemSKU."
        }
        Write-SyncLog "Update mode      : SystemSku '$updateValue'"
        $targets = $skuHits
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
