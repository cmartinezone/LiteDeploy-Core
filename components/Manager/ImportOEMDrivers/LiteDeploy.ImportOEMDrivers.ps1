<#
.SYNOPSIS
    Imports an OEM driver pack into the LiteDeploy drivers catalog and share layout.

.DESCRIPTION
    LiteDeployManager tool. Places FullOS drivers under <Model>\Extracted\ and optional
    WinPE drivers under <ManufacturerName>\WinPE\ (manufacturer root), then upserts
    Content\Drivers\catalog.json using the v1 drivers catalog contract
    (manufacturerId from WMI, systemSku, format, dates).

    Local import: pass -SourcePath (.cab / .exe / extracted folder).
    Remote import: pass -DownloadLink without -SourcePath to download first.
    Downloads and CAB extracts stage under Content\Temp\ImportOEMDrivers\, then
    promote into Content\Drivers\...\Extracted. OEM vendor catalogs (future sync)
    also land under Content\Temp. Downloads default to native APIs (BITS, then
    Invoke-WebRequest). -UseCurl is optional and prefers Engine\Tools\Curl\curl.exe,
    then OS curl.exe.

.PARAMETER DeploymentRoot
    Deployment share root (contains Content\Drivers).

.PARAMETER ManufacturerId
    Exact Win32_ComputerSystem.Manufacturer value (e.g. "Dell Inc.").

.PARAMETER ManufacturerName
    Friendly manufacturer label / folder name (e.g. "Dell").

.PARAMETER ModelId
    Stable model id within the manufacturer (e.g. "latitude-7450").

.PARAMETER ModelName
    Friendly model display name.

.PARAMETER SystemSku
    One or more SystemSKU / Machine Type / BaseBoardProduct match keys.

.PARAMETER Version
    Driver pack version label.

.PARAMETER ReleaseDate
    Vendor release date (YYYY-MM-DD). Defaults to today when omitted.

.PARAMETER Format
    Original pack format: exe or cab. Auto-detected from SourcePath when possible.

.PARAMETER DownloadLink
    Vendor URL. Stored in the catalog. When -SourcePath is omitted, the pack is downloaded from this URL first.

.PARAMETER SourcePath
    Local .cab, .exe, or folder of extracted FullOS drivers. Optional when -DownloadLink is set for remote import.

.PARAMETER WinPESourcePath
    Optional folder of WinPE storage/NIC drivers to copy into
    Content\Drivers\<ManufacturerName>\WinPE\ (shared for the manufacturer).

.PARAMETER FolderName
    Model folder leaf under Content\Drivers\<ManufacturerName>\. Defaults to ModelName.

.PARAMETER Enabled
    Catalog enabled flag. Default $true.

.PARAMETER UseCurl
    Optional. Download with curl instead of native APIs. Prefers
    <DeploymentRoot>\Engine\Tools\Curl\curl.exe, then <DeploymentRoot>\Tools\Curl\curl.exe,
    then curl.exe on PATH. Default is native BITS / Invoke-WebRequest only.

.PARAMETER ModelsCsvPath
    Optional. Comma-separated CSV of supported models for this manufacturer.
    Required columns: Model (or ModelName), SystemSku (or SkuId / Sku).
    Multiple SKUs in one cell may be separated with ; or |.
    Optional columns: ModelId, FolderName, Version, Format, DownloadLink.

.PARAMETER CsvDelimiter
    CSV field delimiter. Default is comma (,).

.PARAMETER Force
    Overwrite existing model Extracted\ and/or manufacturer WinPE\ content and replace catalog model entry fields.

.EXAMPLE
    .\LiteDeploy.ImportOEMDrivers.ps1 `
      -DeploymentRoot "D:\DeploymentShare" `
      -ManufacturerId "Dell Inc." `
      -ManufacturerName "Dell" `
      -ModelId "latitude-7450" `
      -ModelName "Latitude 7450" `
      -SystemSku "0C09" `
      -Version "2026.01" `
      -SourcePath "C:\Temp\Latitude_7450.cab"

.EXAMPLE
    # Register supported models for a manufacturer from CSV (Model,SystemSku)
    .\LiteDeploy.ImportOEMDrivers.ps1 `
      -DeploymentRoot "D:\DeploymentShare" `
      -ManufacturerId "Dell Inc." `
      -ManufacturerName "Dell" `
      -ModelsCsvPath "D:\Lists\Dell-SupportedModels.csv" `
      -Version "2026.01" `
      -Format cab
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "LocalSource")]
param(
    [Parameter(Mandatory = $true)]
    [string]$DeploymentRoot,

    [Parameter(Mandatory = $true)]
    [string]$ManufacturerId,

    [Parameter(Mandatory = $true)]
    [string]$ManufacturerName,

    [Parameter(Mandatory = $true, ParameterSetName = "LocalSource")]
    [Parameter(Mandatory = $true, ParameterSetName = "Download")]
    [string]$ModelId = "",

    [Parameter(Mandatory = $true, ParameterSetName = "LocalSource")]
    [Parameter(Mandatory = $true, ParameterSetName = "Download")]
    [string]$ModelName = "",

    [Parameter(Mandatory = $true, ParameterSetName = "LocalSource")]
    [Parameter(Mandatory = $true, ParameterSetName = "Download")]
    [string[]]$SystemSku = @(),

    [Parameter(Mandatory = $false)]
    [string]$Version = "",

    [Parameter(Mandatory = $false)]
    [string]$ReleaseDate = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("exe", "cab")]
    [string]$Format = "",

    [Parameter(Mandatory = $false, ParameterSetName = "LocalSource")]
    [Parameter(Mandatory = $true, ParameterSetName = "Download")]
    [string]$DownloadLink = "",

    [Parameter(Mandatory = $true, ParameterSetName = "LocalSource")]
    [Parameter(Mandatory = $false, ParameterSetName = "Download")]
    [string]$SourcePath = "",

    [Parameter(Mandatory = $false, ParameterSetName = "LocalSource")]
    [Parameter(Mandatory = $false, ParameterSetName = "Download")]
    [string]$WinPESourcePath = "",

    [Parameter(Mandatory = $false, ParameterSetName = "LocalSource")]
    [Parameter(Mandatory = $false, ParameterSetName = "Download")]
    [string]$FolderName = "",

    [Parameter(Mandatory = $true, ParameterSetName = "ModelsCsv")]
    [string]$ModelsCsvPath = "",

    [Parameter(Mandatory = $false, ParameterSetName = "ModelsCsv")]
    [ValidateSet(",", ";", "`t")]
    [string]$CsvDelimiter = ",",

    [Parameter(Mandatory = $false)]
    [bool]$Enabled = $true,

    [Parameter(Mandatory = $false, ParameterSetName = "Download")]
    [switch]$UseCurl,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Write-ImportLog {
    param(
        [string]$Message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Cyan
    )
    Write-Host " [ImportOEMDrivers]  $Message" -ForegroundColor $ForegroundColor
}

function Resolve-LiteDeployCurlPath {
    param([string]$DeploymentRoot)

    $candidates = @(
        (Join-Path $DeploymentRoot "Engine\Tools\Curl\curl.exe"),
        (Join-Path $DeploymentRoot "Tools\Curl\curl.exe")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $osCurl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($osCurl -and $osCurl.Source) {
        return [string]$osCurl.Source
    }

    return $null
}

function Save-RemoteFileNative {
    param(
        [string]$Uri,
        [string]$Destination
    )

    $destinationDir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destinationDir)) {
        $null = New-Item -Path $destinationDir -ItemType Directory -Force
    }

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }

    # Prefer BITS when available (Windows admin workstation / share host).
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        Write-ImportLog "Downloading (BITS): $Uri"
        try {
            Start-BitsTransfer -Source $Uri -Destination $Destination -ErrorAction Stop
            if (Test-Path -LiteralPath $Destination -PathType Leaf) {
                return
            }
        }
        catch {
            Write-ImportLog "BITS failed; falling back to Invoke-WebRequest. $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    Write-ImportLog "Downloading (Invoke-WebRequest): $Uri"
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        throw "Native download produced no file: $Destination"
    }
}

function Save-RemoteFileCurl {
    param(
        [string]$Uri,
        [string]$Destination,
        [string]$DeploymentRoot
    )

    $curlPath = Resolve-LiteDeployCurlPath -DeploymentRoot $DeploymentRoot
    if (-not $curlPath) {
        throw "-UseCurl was set but curl was not found under Engine\Tools\Curl, Tools\Curl, or PATH."
    }

    $destinationDir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destinationDir)) {
        $null = New-Item -Path $destinationDir -ItemType Directory -Force
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }

    Write-ImportLog "Downloading (curl): $curlPath"
    $args = @(
        "--fail",
        "--location",
        "--silent",
        "--show-error",
        "--output", $Destination,
        $Uri
    )
    $p = Start-Process -FilePath $curlPath -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) {
        throw "curl failed (exit $($p.ExitCode)) for '$Uri'."
    }
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        throw "curl produced no file: $Destination"
    }
}

function Get-DownloadFileName {
    param(
        [string]$Uri,
        [string]$Format
    )

    try {
        $uriObj = [Uri]$Uri
        $leaf = [System.IO.Path]::GetFileName($uriObj.LocalPath)
        if (-not [string]::IsNullOrWhiteSpace($leaf) -and $leaf -notlike "*[*") {
            return $leaf
        }
    }
    catch {}

    $ext = if ($Format) { ".$Format" } else { ".bin" }
    return ("driver-pack-{0:yyyyMMdd-HHmmss}{1}" -f (Get-Date), $ext)
}

function Save-RemoteDriverPack {
    param(
        [string]$Uri,
        [string]$Destination,
        [string]$DeploymentRoot,
        [switch]$UseCurl
    )

    if ($UseCurl) {
        Save-RemoteFileCurl -Uri $Uri -Destination $Destination -DeploymentRoot $DeploymentRoot
    }
    else {
        Save-RemoteFileNative -Uri $Uri -Destination $Destination
    }
}

function Test-IsoDate {
    param([string]$Value)
    return [bool]($Value -match '^\d{4}-\d{2}-\d{2}$')
}

function Get-NormalizedSkuList {
    param([string[]]$Values)

    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($value in @($Values)) {
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $trimmed = $value.Trim()
        $exists = $false
        foreach ($existing in $list) {
            if ([string]::Equals($existing, $trimmed, [System.StringComparison]::OrdinalIgnoreCase)) {
                $exists = $true
                break
            }
        }
        if (-not $exists) { $list.Add($trimmed) }
    }
    if ($list.Count -eq 0) {
        throw "SystemSku must contain at least one non-empty value."
    }
    return @($list.ToArray())
}

function New-RelativeSharePath {
    param(
        [string]$Root,
        [string]$FullPath
    )

    $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    $full = (Resolve-Path -LiteralPath $FullPath).Path
    if (-not $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path '$FullPath' is outside deployment root '$Root'."
    }
    $relative = $full.Substring($rootFull.Length).TrimStart('\', '/')
    return ($relative -replace '\\', '/')
}

function Ensure-EmptyDirectory {
    param(
        [string]$Path,
        [switch]$Force
    )

    if (Test-Path -LiteralPath $Path) {
        $children = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
        if ($children.Count -gt 0 -and -not $Force) {
            throw "Directory already has content: $Path (use -Force to replace)."
        }
        if ($Force -and $children.Count -gt 0) {
            Remove-Item -LiteralPath $Path -Recurse -Force
        }
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -Path $Path -ItemType Directory -Force
    }
}

function Copy-DriverTree {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Source folder not found: $Source"
    }
    Ensure-EmptyDirectory -Path $Destination -Force:$Force
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

function Expand-CabToFolder {
    param(
        [string]$CabPath,
        [string]$Destination,
        [switch]$Force
    )

    Ensure-EmptyDirectory -Path $Destination -Force:$Force
    $expand = Get-Command expand.exe -ErrorAction SilentlyContinue
    if (-not $expand) {
        throw "expand.exe was not found. Cannot extract CAB: $CabPath"
    }

    # expand.exe extracts matching files into the destination directory.
    $args = @("`"$CabPath`"", "-F:*", "`"$Destination`"")
    $p = Start-Process -FilePath $expand.Source -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) {
        throw "expand.exe failed for '$CabPath' (exit $($p.ExitCode))."
    }
}

function Import-SourceIntoExtracted {
    param(
        [string]$SourcePath,
        [string]$ModelFolder,
        [string]$ExtractedFolder,
        [string]$ResolvedFormat,
        [switch]$Force
    )

    $resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path

    if (Test-Path -LiteralPath $resolvedSource -PathType Container) {
        Write-ImportLog "Copying extracted driver tree → Extracted\"
        Copy-DriverTree -Source $resolvedSource -Destination $ExtractedFolder -Force:$Force
        return
    }

    if (-not (Test-Path -LiteralPath $resolvedSource -PathType Leaf)) {
        throw "SourcePath not found: $SourcePath"
    }

    $leaf = Split-Path -Leaf $resolvedSource
    $archiveDest = Join-Path $ModelFolder $leaf
    Write-ImportLog "Keeping original pack: $archiveDest"
    if ((Test-Path -LiteralPath $archiveDest) -and -not $Force) {
        throw "Archive already exists: $archiveDest (use -Force to replace)."
    }
    Copy-Item -LiteralPath $resolvedSource -Destination $archiveDest -Force

    switch ($ResolvedFormat) {
        "cab" {
            Write-ImportLog "Expanding CAB → Extracted\"
            Expand-CabToFolder -CabPath $resolvedSource -Destination $ExtractedFolder -Force:$Force
        }
        "exe" {
            Ensure-EmptyDirectory -Path $ExtractedFolder -Force:$Force
            Write-ImportLog "EXE stored at model folder. Pass an already-extracted folder as -SourcePath to populate Extracted\, or extract the EXE offline first." -ForegroundColor Yellow
        }
        default {
            throw "Unsupported format '$ResolvedFormat'."
        }
    }
}

function Get-OrCreateDriversCatalog {
    param([string]$CatalogPath)

    if (Test-Path -LiteralPath $CatalogPath -PathType Leaf) {
        $raw = Get-Content -LiteralPath $CatalogPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Trim() -eq "{}") {
            return [ordered]@{
                '$schema'      = "./schemas/drivers-catalog.schema.json"
                schemaVersion  = 1
                manufacturers  = @()
            }
        }
        $obj = $raw | ConvertFrom-Json
        if (-not $obj.PSObject.Properties['schemaVersion']) {
            $obj | Add-Member -NotePropertyName schemaVersion -NotePropertyValue 1
        }
        if (-not $obj.PSObject.Properties['manufacturers'] -or $null -eq $obj.manufacturers) {
            $obj | Add-Member -NotePropertyName manufacturers -NotePropertyValue @() -Force
        }
        if (-not $obj.PSObject.Properties['$schema']) {
            $obj | Add-Member -NotePropertyName '$schema' -NotePropertyValue "./schemas/drivers-catalog.schema.json"
        }
        return $obj
    }

    $catalogDir = Split-Path -Parent $CatalogPath
    if (-not (Test-Path -LiteralPath $catalogDir)) {
        $null = New-Item -Path $catalogDir -ItemType Directory -Force
    }

    return [ordered]@{
        '$schema'     = "./schemas/drivers-catalog.schema.json"
        schemaVersion = 1
        manufacturers = @()
    }
}

function ConvertTo-OrderedCatalog {
    param($Catalog)

    $manufacturers = @()
    foreach ($mfr in @($Catalog.manufacturers)) {
        $models = @()
        foreach ($model in @($mfr.models)) {
            $sku = @($model.systemSku | ForEach-Object { [string]$_ })
            $modelOrdered = [ordered]@{
                modelId      = [string]$model.modelId
                name         = [string]$model.name
                systemSku    = $sku
                version      = [string]$model.version
                releaseDate  = [string]$model.releaseDate
                importedDate = [string]$model.importedDate
                format       = [string]$model.format
                enabled      = [bool]$model.enabled
                path         = [string]$model.path
            }
            if ($model.PSObject.Properties['downloadLink'] -and -not [string]::IsNullOrWhiteSpace([string]$model.downloadLink)) {
                $modelOrdered['downloadLink'] = [string]$model.downloadLink
            }
            $models += [pscustomobject]$modelOrdered
        }

        $manufacturers += [pscustomobject][ordered]@{
            manufacturerId = [string]$mfr.manufacturerId
            name           = [string]$mfr.name
            enabled        = [bool]$mfr.enabled
            models         = $models
        }
    }

    return [pscustomobject][ordered]@{
        '$schema'     = if ($Catalog.PSObject.Properties['$schema']) { [string]$Catalog.'$schema' } else { "./schemas/drivers-catalog.schema.json" }
        schemaVersion = 1
        manufacturers = $manufacturers
    }
}

function Update-DriversCatalogEntry {
    param(
        $Catalog,
        [string]$ManufacturerId,
        [string]$ManufacturerName,
        [bool]$ManufacturerEnabled,
        [hashtable]$ModelEntry,
        [switch]$Force
    )

    $manufacturers = [System.Collections.Generic.List[object]]::new()
    foreach ($existing in @($Catalog.manufacturers)) {
        $manufacturers.Add($existing)
    }

    $mfrIndex = -1
    for ($i = 0; $i -lt $manufacturers.Count; $i++) {
        if ([string]::Equals([string]$manufacturers[$i].manufacturerId, $ManufacturerId, [System.StringComparison]::OrdinalIgnoreCase)) {
            $mfrIndex = $i
            break
        }
    }

    if ($mfrIndex -lt 0) {
        $newMfr = [pscustomobject][ordered]@{
            manufacturerId = $ManufacturerId
            name           = $ManufacturerName
            enabled        = $ManufacturerEnabled
            models         = @([pscustomobject]$ModelEntry)
        }
        $manufacturers.Add($newMfr)
    }
    else {
        $mfr = $manufacturers[$mfrIndex]
        $mfr.name = $ManufacturerName
        $mfr.enabled = $ManufacturerEnabled

        $models = [System.Collections.Generic.List[object]]::new()
        foreach ($existingModel in @($mfr.models)) {
            $models.Add($existingModel)
        }

        $modelIndex = -1
        for ($i = 0; $i -lt $models.Count; $i++) {
            if ([string]::Equals([string]$models[$i].modelId, [string]$ModelEntry.modelId, [System.StringComparison]::OrdinalIgnoreCase)) {
                $modelIndex = $i
                break
            }
        }

        if ($modelIndex -ge 0 -and -not $Force) {
            throw "ModelId '$($ModelEntry.modelId)' already exists under '$ManufacturerId' (use -Force to replace)."
        }

        $modelObject = [pscustomobject]$ModelEntry
        if ($modelIndex -ge 0) {
            $models[$modelIndex] = $modelObject
        }
        else {
            $models.Add($modelObject)
        }

        $mfr.models = @($models.ToArray())
        $manufacturers[$mfrIndex] = $mfr
    }

    $Catalog.manufacturers = @($manufacturers.ToArray())
    return $Catalog
}

function ConvertTo-LiteDeployModelId {
    param([string]$Name)

    $slug = $Name.Trim().ToLowerInvariant()
    $slug = [regex]::Replace($slug, '[^a-z0-9]+', '-')
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "Cannot build ModelId from name '$Name'."
    }
    return $slug
}

function Get-CsvPropertyValue {
    param(
        $Row,
        [string[]]$CandidateNames
    )

    foreach ($name in $CandidateNames) {
        $prop = $Row.PSObject.Properties[$name]
        if ($prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            return [string]$prop.Value
        }
    }

    # Case-insensitive header match
    foreach ($prop in $Row.PSObject.Properties) {
        foreach ($name in $CandidateNames) {
            if ([string]::Equals($prop.Name, $name, [System.StringComparison]::OrdinalIgnoreCase) -and
                -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
                return [string]$prop.Value
            }
        }
    }
    return $null
}

function Import-SupportedModelsFromCsv {
    param(
        [string]$CsvPath,
        [string]$Delimiter,
        [string]$DeploymentRoot,
        [string]$ManufacturerId,
        [string]$ManufacturerName,
        [string]$DefaultVersion,
        [string]$DefaultFormat,
        [string]$ReleaseDate,
        [string]$ImportedDate,
        [bool]$Enabled,
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        throw "ModelsCsvPath not found: $CsvPath"
    }

    $rows = @(Import-Csv -LiteralPath $CsvPath -Delimiter $Delimiter -ErrorAction Stop)
    if ($rows.Count -eq 0) {
        throw "Models CSV has no data rows: $CsvPath"
    }

    $driversRoot = Join-Path $DeploymentRoot "Content\Drivers"
    $catalogPath = Join-Path $driversRoot "catalog.json"
    $catalog = Get-OrCreateDriversCatalog -CatalogPath $catalogPath

    $imported = [System.Collections.Generic.List[object]]::new()
    $rowNumber = 1
    foreach ($row in $rows) {
        $rowNumber++
        $modelName = Get-CsvPropertyValue -Row $row -CandidateNames @("Model", "ModelName", "Name", "FriendlyName")
        $skuRaw = Get-CsvPropertyValue -Row $row -CandidateNames @("SystemSku", "SkuId", "SKU", "Sku", "SystemSKU")
        if ([string]::IsNullOrWhiteSpace($modelName) -or [string]::IsNullOrWhiteSpace($skuRaw)) {
            throw "CSV row $rowNumber must include Model and SystemSku (or SkuId) columns."
        }

        $modelIdRaw = Get-CsvPropertyValue -Row $row -CandidateNames @("ModelId", "Id")
        $modelId = if (-not [string]::IsNullOrWhiteSpace($modelIdRaw)) {
            $modelIdRaw.Trim()
        } else {
            ConvertTo-LiteDeployModelId -Name $modelName
        }

        $folderNameRaw = Get-CsvPropertyValue -Row $row -CandidateNames @("FolderName", "Folder")
        $folderName = if (-not [string]::IsNullOrWhiteSpace($folderNameRaw)) {
            $folderNameRaw.Trim()
        } else {
            $modelName.Trim()
        }

        $versionRaw = Get-CsvPropertyValue -Row $row -CandidateNames @("Version")
        $rowVersion = if (-not [string]::IsNullOrWhiteSpace($versionRaw)) {
            $versionRaw.Trim()
        } elseif (-not [string]::IsNullOrWhiteSpace($DefaultVersion)) {
            $DefaultVersion
        } else {
            "unknown"
        }

        $formatRaw = Get-CsvPropertyValue -Row $row -CandidateNames @("Format")
        $rowFormat = if (-not [string]::IsNullOrWhiteSpace($formatRaw)) {
            $formatRaw.Trim().TrimStart('.').ToLowerInvariant()
        } elseif (-not [string]::IsNullOrWhiteSpace($DefaultFormat)) {
            $DefaultFormat
        } else {
            "cab"
        }
        if ($rowFormat -notin @("exe", "cab")) {
            throw "CSV row $rowNumber has invalid Format '$rowFormat' (use exe or cab)."
        }

        $downloadLinkRaw = Get-CsvPropertyValue -Row $row -CandidateNames @("DownloadLink", "Url", "URL")
        $skuParts = @($skuRaw -split '[,;|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $skuList = Get-NormalizedSkuList -Values $skuParts

        $manufacturerFolder = Join-Path $driversRoot $ManufacturerName
        $modelFolder = Join-Path $manufacturerFolder $folderName
        $extractedFolder = Join-Path $modelFolder "Extracted"
        $winPeFolder = Join-Path $manufacturerFolder "WinPE"

        if (-not $PSCmdlet.ShouldProcess($modelFolder, "Register CSV model '$modelName'")) {
            continue
        }

        if (-not (Test-Path -LiteralPath $modelFolder)) {
            $null = New-Item -Path $modelFolder -ItemType Directory -Force
        }
        if (-not (Test-Path -LiteralPath $extractedFolder)) {
            $null = New-Item -Path $extractedFolder -ItemType Directory -Force
        }
        if (-not (Test-Path -LiteralPath $winPeFolder)) {
            $null = New-Item -Path $winPeFolder -ItemType Directory -Force
        }

        $relativePath = New-RelativeSharePath -Root $DeploymentRoot -FullPath $modelFolder
        $modelEntry = [ordered]@{
            modelId      = $modelId
            name         = $modelName.Trim()
            systemSku    = @($skuList)
            version      = $rowVersion
            releaseDate  = $ReleaseDate
            importedDate = $ImportedDate
            format       = $rowFormat
            enabled      = [bool]$Enabled
            path         = $relativePath
        }
        if (-not [string]::IsNullOrWhiteSpace($downloadLinkRaw)) {
            $modelEntry["downloadLink"] = $downloadLinkRaw.Trim()
        }

        $catalog = Update-DriversCatalogEntry `
            -Catalog $catalog `
            -ManufacturerId $ManufacturerId `
            -ManufacturerName $ManufacturerName `
            -ManufacturerEnabled $true `
            -ModelEntry $modelEntry `
            -Force:$Force

        Write-ImportLog "CSV model registered: $ManufacturerName / $($modelEntry.name) [$modelId] sku=$($skuList -join ';')" -ForegroundColor Green
        $imported.Add([pscustomobject]@{
            ModelId      = $modelId
            ModelName    = $modelEntry.name
            SystemSku    = $skuList
            RelativePath = $relativePath
            Version      = $rowVersion
            Format       = $rowFormat
        })
    }

    $ordered = ConvertTo-OrderedCatalog -Catalog $catalog
    $json = $ordered | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $catalogPath -Value $json -Encoding UTF8 -Force

    return [pscustomobject]@{
        CatalogPath      = $catalogPath
        ModelsCsvPath    = $CsvPath
        ManufacturerId   = $ManufacturerId
        ManufacturerName = $ManufacturerName
        ModelCount       = $imported.Count
        Models           = @($imported.ToArray())
    }
}

# ------------------------------------------------------------------------------
# Validate inputs
# ------------------------------------------------------------------------------

$DeploymentRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DeploymentRoot)
if (-not (Test-Path -LiteralPath $DeploymentRoot -PathType Container)) {
    throw "DeploymentRoot not found: $DeploymentRoot"
}

$ManufacturerId = $ManufacturerId.Trim()
$ManufacturerName = $ManufacturerName.Trim()

if ([string]::IsNullOrWhiteSpace($ReleaseDate)) {
    $ReleaseDate = (Get-Date).ToString("yyyy-MM-dd")
}
if (-not (Test-IsoDate $ReleaseDate)) {
    throw "ReleaseDate must be YYYY-MM-DD. Got: $ReleaseDate"
}
$importedDate = (Get-Date).ToString("yyyy-MM-dd")

# CSV bulk registration of manufacturer-supported models.
if ($PSCmdlet.ParameterSetName -eq "ModelsCsv" -or -not [string]::IsNullOrWhiteSpace($ModelsCsvPath)) {
    $csvPathResolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModelsCsvPath)
    Write-ImportLog "CSV import      : $csvPathResolved"
    Write-ImportLog "Manufacturer    : $ManufacturerName ($ManufacturerId)"
    Write-ImportLog "Delimiter       : '$CsvDelimiter'"

    return (Import-SupportedModelsFromCsv `
        -CsvPath $csvPathResolved `
        -Delimiter $CsvDelimiter `
        -DeploymentRoot $DeploymentRoot `
        -ManufacturerId $ManufacturerId `
        -ManufacturerName $ManufacturerName `
        -DefaultVersion $Version `
        -DefaultFormat $Format `
        -ReleaseDate $ReleaseDate `
        -ImportedDate $importedDate `
        -Enabled:$Enabled `
        -Force:$Force)
}

$ModelId = $ModelId.Trim()
$ModelName = $ModelName.Trim()
if ([string]::IsNullOrWhiteSpace($Version)) {
    throw "Version is required for single-model import."
}
$Version = $Version.Trim()
$skuList = Get-NormalizedSkuList -Values $SystemSku

if ([string]::IsNullOrWhiteSpace($FolderName)) {
    $FolderName = $ModelName
}
$FolderName = $FolderName.Trim()

$downloadLinkValue = if ([string]::IsNullOrWhiteSpace($DownloadLink)) { "" } else { $DownloadLink.Trim() }
$effectiveSourcePath = $SourcePath

if ([string]::IsNullOrWhiteSpace($effectiveSourcePath) -and [string]::IsNullOrWhiteSpace($downloadLinkValue)) {
    throw "Provide -SourcePath for local import, or -DownloadLink to download the pack."
}

if ($UseCurl -and [string]::IsNullOrWhiteSpace($downloadLinkValue)) {
    throw "-UseCurl requires -DownloadLink."
}

if ($UseCurl -and -not [string]::IsNullOrWhiteSpace($effectiveSourcePath)) {
    throw "-UseCurl applies only when downloading (-DownloadLink without -SourcePath)."
}

if (-not [string]::IsNullOrWhiteSpace($WinPESourcePath) -and -not (Test-Path -LiteralPath $WinPESourcePath -PathType Container)) {
    throw "WinPESourcePath must be an existing folder: $WinPESourcePath"
}

$driversRoot = Join-Path $DeploymentRoot "Content\Drivers"
$tempRoot = Join-Path $DeploymentRoot "Content\Temp"
$catalogPath = Join-Path $driversRoot "catalog.json"
$manufacturerFolder = Join-Path $driversRoot $ManufacturerName
$modelFolder = Join-Path $manufacturerFolder $FolderName
$extractedFolder = Join-Path $modelFolder "Extracted"
$winPeFolder = Join-Path $manufacturerFolder "WinPE"
# Online packs and CAB expands stage under Content\Temp, then promote into Drivers\.
$tempWorkRoot = Join-Path $tempRoot (Join-Path "ImportOEMDrivers" (Join-Path $ManufacturerName $ModelId))
$downloadStaging = Join-Path $tempWorkRoot "Download"
$extractStaging = Join-Path $tempWorkRoot "Extracted"

Write-ImportLog "Deployment root : $DeploymentRoot"
Write-ImportLog "Temp staging    : $tempWorkRoot"
Write-ImportLog "Model folder    : $modelFolder"
Write-ImportLog "Manufacturer    : $ManufacturerName ($ManufacturerId)"
Write-ImportLog "Model           : $ModelName [$ModelId]"
Write-ImportLog "SystemSku       : $($skuList -join ', ')"
Write-ImportLog "Format/Version  : $(if ($Format) { $Format } else { '(auto)' }) / $Version"
if ($UseCurl) {
    Write-ImportLog "Transfer mode   : curl (-UseCurl)"
}
elseif ([string]::IsNullOrWhiteSpace($effectiveSourcePath) -and $downloadLinkValue) {
    Write-ImportLog "Transfer mode   : native APIs (BITS / Invoke-WebRequest)"
}

if (-not $PSCmdlet.ShouldProcess($modelFolder, "Import OEM drivers and update catalog.json")) {
    return
}

if (-not (Test-Path -LiteralPath $tempRoot)) {
    $null = New-Item -Path $tempRoot -ItemType Directory -Force
}
if (-not (Test-Path -LiteralPath $modelFolder)) {
    $null = New-Item -Path $modelFolder -ItemType Directory -Force
}

$sourceForImport = $effectiveSourcePath

if ([string]::IsNullOrWhiteSpace($sourceForImport)) {
    $fileName = Get-DownloadFileName -Uri $downloadLinkValue -Format $Format
    Ensure-EmptyDirectory -Path $downloadStaging -Force
    $downloadTarget = Join-Path $downloadStaging $fileName
    Save-RemoteDriverPack -Uri $downloadLinkValue -Destination $downloadTarget -DeploymentRoot $DeploymentRoot -UseCurl:$UseCurl
    $sourceForImport = $downloadTarget
    Write-ImportLog "Downloaded pack : $sourceForImport" -ForegroundColor Green
}

if (-not (Test-Path -LiteralPath $sourceForImport)) {
    throw "SourcePath not found: $sourceForImport"
}

if ([string]::IsNullOrWhiteSpace($Format)) {
    if (Test-Path -LiteralPath $sourceForImport -PathType Leaf) {
        $ext = [System.IO.Path]::GetExtension($sourceForImport).TrimStart('.').ToLowerInvariant()
        if ($ext -in @("exe", "cab")) {
            $Format = $ext
        }
        else {
            throw "Cannot detect Format from '$sourceForImport'. Pass -Format exe or -Format cab."
        }
    }
    else {
        throw "When -SourcePath is a folder, pass -Format exe or -Format cab for catalog metadata."
    }
}

# CAB/EXE files: expand or stage under Content\Temp, then promote into the model folder.
if (Test-Path -LiteralPath $sourceForImport -PathType Leaf) {
    $leaf = Split-Path -Leaf $sourceForImport
    $archiveDest = Join-Path $modelFolder $leaf
    Write-ImportLog "Keeping original pack in model folder: $archiveDest"
    if ((Test-Path -LiteralPath $archiveDest) -and -not $Force) {
        throw "Archive already exists: $archiveDest (use -Force to replace)."
    }
    Copy-Item -LiteralPath $sourceForImport -Destination $archiveDest -Force

    if ($Format -eq "cab") {
        Write-ImportLog "Extracting CAB under Content\Temp → $extractStaging"
        Expand-CabToFolder -CabPath $sourceForImport -Destination $extractStaging -Force:$Force
        Write-ImportLog "Promoting Temp extract → Extracted\"
        Copy-DriverTree -Source $extractStaging -Destination $extractedFolder -Force:$Force
    }
    else {
        Ensure-EmptyDirectory -Path $extractedFolder -Force:$Force
        Write-ImportLog "EXE stored at model folder. Pass an extracted folder as -SourcePath to populate Extracted\, or extract the EXE under Content\Temp first." -ForegroundColor Yellow
    }
}
else {
    Import-SourceIntoExtracted -SourcePath $sourceForImport -ModelFolder $modelFolder -ExtractedFolder $extractedFolder -ResolvedFormat $Format -Force:$Force
}

if (-not [string]::IsNullOrWhiteSpace($WinPESourcePath)) {
    Write-ImportLog "Copying WinPE drivers → $ManufacturerName\WinPE\"
    Copy-DriverTree -Source $WinPESourcePath -Destination $winPeFolder -Force:$Force
}
else {
    if (-not (Test-Path -LiteralPath $winPeFolder)) {
        $null = New-Item -Path $winPeFolder -ItemType Directory -Force
        Write-ImportLog "Created empty $ManufacturerName\WinPE\ (shared manufacturer WinPE; add storage/NIC drivers later)." -ForegroundColor DarkYellow
    }
}

$relativePath = New-RelativeSharePath -Root $DeploymentRoot -FullPath $modelFolder

$modelEntry = [ordered]@{
    modelId      = $ModelId
    name         = $ModelName
    systemSku    = @($skuList)
    version      = $Version
    releaseDate  = $ReleaseDate
    importedDate = $importedDate
    format       = $Format
    enabled      = [bool]$Enabled
    path         = $relativePath
}
if (-not [string]::IsNullOrWhiteSpace($downloadLinkValue)) {
    $modelEntry["downloadLink"] = $downloadLinkValue
}

$catalog = Get-OrCreateDriversCatalog -CatalogPath $catalogPath
$catalog = Update-DriversCatalogEntry `
    -Catalog $catalog `
    -ManufacturerId $ManufacturerId `
    -ManufacturerName $ManufacturerName `
    -ManufacturerEnabled $true `
    -ModelEntry $modelEntry `
    -Force:$Force

$ordered = ConvertTo-OrderedCatalog -Catalog $catalog
$json = $ordered | ConvertTo-Json -Depth 8
Set-Content -LiteralPath $catalogPath -Value $json -Encoding UTF8 -Force

Write-ImportLog "Catalog updated : $catalogPath" -ForegroundColor Green
Write-ImportLog "Extracted       : $extractedFolder" -ForegroundColor Green
Write-ImportLog "WinPE           : $winPeFolder" -ForegroundColor Green
Write-ImportLog "Temp staging    : $tempWorkRoot" -ForegroundColor DarkCyan

return [pscustomobject]@{
    CatalogPath      = $catalogPath
    ModelFolder      = $modelFolder
    ExtractedPath    = $extractedFolder
    WinPEPath        = $winPeFolder
    TempWorkRoot     = $tempWorkRoot
    RelativePath     = $relativePath
    ManufacturerId   = $ManufacturerId
    ManufacturerName = $ManufacturerName
    ModelId          = $ModelId
    ModelName        = $ModelName
    SystemSku        = $skuList
    Version          = $Version
    Format           = $Format
    DownloadLink     = $downloadLinkValue
    UsedCurl         = [bool]$UseCurl
}
