# ImportOEMDrivers

LiteDeployManager tool that imports an OEM driver pack into the deployment share and upserts `Content/Drivers/catalog.json`.

**Script:** `LiteDeploy.ImportOEMDrivers.ps1`  
**Catalog contract:** [LITEDEPLOY_DRIVERS_CATALOG.md](../../../docs/architecture/LITEDEPLOY_DRIVERS_CATALOG.md)

## What it does

1. Creates `Content/Drivers/<ManufacturerName>/<Folder>/`
2. Optionally **downloads** the pack from `-DownloadLink` into **`Content\Temp\ImportOEMDrivers\...`**
3. Extracts CABs under **`Content\Temp\...`**, then promotes into **`Extracted\`**
4. Creates **`WinPE\`** (empty or from `-WinPESourcePath`)
5. Upserts the manufacturer / model entry in `catalog.json`

Vendor catalog discovery files (Dell/HP/Lenovo index CABs) should also download/extract under `Content\Temp\OemCatalogs\` when that sync is added.

## Staging vs published layout

```text
Content\Temp\ImportOEMDrivers\<Mfr>\<ModelId>\
  Download\pack.cab
  Extracted\...                    ← temporary expand

Content\Drivers\<Mfr>\<Model>\
  pack.cab                         ← kept original
  Extracted\...                    ← published FullOS injection
  WinPE\...                        ← published WinPE drivers
```

| Mode | When | Behavior |
| --- | --- | --- |
| **Native (default)** | `-DownloadLink` without `-UseCurl` | `Start-BitsTransfer`, then `Invoke-WebRequest` |
| **Curl (optional)** | `-DownloadLink -UseCurl` | `Engine\Tools\Curl\curl.exe` if present, else `Tools\Curl\curl.exe`, else OS `curl.exe` |

Default never calls curl. `-UseCurl` fails closed if no curl binary is found.

## Layout written

```text
Content/Drivers/Dell/Latitude 7450/
  Latitude_7450.cab          ← kept when SourcePath is a file
  Extracted/                 ← FullOS injection
  WinPE/                     ← WinPE storage/NIC
```

## Parameters

| Parameter | Required | Notes |
| --- | --- | --- |
| `-DeploymentRoot` | yes | Share root containing `Content\Drivers` |
| `-ManufacturerId` | yes | Exact WMI value (`Dell Inc.`) |
| `-ManufacturerName` | yes | Friendly / folder (`Dell`) |
| `-ModelId` | yes | Stable id (`latitude-7450`) |
| `-ModelName` | yes | Display name |
| `-SystemSku` | yes | One or more SKU / Type keys |
| `-Version` | yes | Pack version label |
| `-SourcePath` | for local import | `.cab`, `.exe`, or extracted folder |
| `-DownloadLink` | for remote import | Vendor URL (also stored in catalog) |
| `-Format` | if folder source / needed | `exe` \| `cab` (auto from file extension) |
| `-ReleaseDate` | no | `YYYY-MM-DD` (default today) |
| `-WinPESourcePath` | no | Folder copied into `WinPE\` |
| `-FolderName` | no | Defaults to `ModelName` |
| `-UseCurl` | no | Optional curl transfer (Tools curl, then OS curl) |
| `-Force` | no | Replace existing model content / catalog row |

## Examples

```powershell
# CAB → expand into Extracted\
.\LiteDeploy.ImportOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -ManufacturerId "Dell Inc." `
  -ManufacturerName "Dell" `
  -ModelId "latitude-7450" `
  -ModelName "Latitude 7450" `
  -SystemSku "0C09" `
  -Version "2026.01" `
  -ReleaseDate "2026-01-15" `
  -SourcePath "C:\Temp\Latitude_7450_Win11.cab" `
  -DownloadLink "https://downloads.dell.com/..."

# Already-extracted tree + WinPE drivers
.\LiteDeploy.ImportOEMDrivers.ps1 `
  -DeploymentRoot "\\Server\DeploymentShare$" `
  -ManufacturerId "LENOVO" `
  -ManufacturerName "Lenovo" `
  -ModelId "thinkpad-x1-carbon-gen11" `
  -ModelName "ThinkPad X1 Carbon Gen 11" `
  -SystemSku @("21KC","21KC004AUS") `
  -Version "2026.03" `
  -Format exe `
  -SourcePath "C:\Temp\x1_extracted" `
  -WinPESourcePath "C:\Temp\x1_winpe" `
  -FolderName "21KC" `
  -Force

# Download with native APIs (default), then import
.\LiteDeploy.ImportOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -ManufacturerId "Dell Inc." `
  -ManufacturerName "Dell" `
  -ModelId "latitude-7450" `
  -ModelName "Latitude 7450" `
  -SystemSku "0C09" `
  -Version "2026.01" `
  -Format cab `
  -DownloadLink "https://downloads.dell.com/.../Latitude_7450.cab"

# Optional: use Tools\Curl (or OS curl) instead of native APIs
.\LiteDeploy.ImportOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -ManufacturerId "Dell Inc." `
  -ManufacturerName "Dell" `
  -ModelId "latitude-7450" `
  -ModelName "Latitude 7450" `
  -SystemSku "0C09" `
  -Version "2026.01" `
  -Format cab `
  -DownloadLink "https://downloads.dell.com/.../Latitude_7450.cab" `
  -UseCurl
```

## Notes

- `.exe` packs are stored in the model folder; populate `Extracted\` by passing an extracted folder as `-SourcePath` (or extract the EXE offline first). Silent EXE unpack varies by OEM and is intentionally out of scope for v1.
- `.cab` packs are expanded with `expand.exe`.
- Runtime matches `manufacturerId` + `systemSku`, then uses `path\Extracted` or `path\WinPE`.
