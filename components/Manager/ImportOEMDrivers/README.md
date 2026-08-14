# ImportOEMDrivers

LiteDeployManager tool that imports an OEM driver pack into the deployment share and upserts `Content/Drivers/catalog.json`.

**Script:** `LiteDeploy.ImportOEMDrivers.ps1`  
**Catalog contract:** [LITEDEPLOY_DRIVERS_CATALOG.md](../../../docs/architecture/LITEDEPLOY_DRIVERS_CATALOG.md)

## What it does

1. Creates `Content/Drivers/<ManufacturerName>/<Folder>/` for the FullOS model
2. Ensures the manufacturer **WinPE model** at `Content/Drivers/<ManufacturerName>/WinPE/` (`modelId: winpe`)
3. Optionally **downloads** the pack from `-DownloadLink` into **`Content\Temp\ImportOEMDrivers\...`**
4. Extracts CABs under **`Content\Temp\...`**, then promotes into model **`Extracted\`**
5. Optionally fills WinPE model `Extracted\` from `-WinPESourcePath`
6. Upserts manufacturer / model entries in `catalog.json` (including the WinPE model)
7. Or registers many supported FullOS models from a **CSV** (`-ModelsCsvPath`) — still ensures the WinPE model

Vendor catalog discovery (Dell `CatalogIndexPC`, HP `platformList`, Lenovo/Surface) is **not implemented yet**. Design (learned from FFU, LiteDeploy-owned): [LITEDEPLOY_OEM_CATALOG_SYNC.md](../../../docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md). Indexes will land under `Content\Temp\OemCatalogs\`.

## Supported-models CSV

Pass `-ModelsCsvPath` with manufacturer identity to register internal supported models (no pack required).

Comma-separated by default (`-CsvDelimiter ","`).

| Column | Required | Notes |
| --- | --- | --- |
| `Model` (or `ModelName`) | yes | Friendly model name |
| `SystemSku` (or `SkuId` / `Sku`) | yes | One SKU, or several separated by `;` or `\|` |
| `ModelId` | no | Auto-slug from Model when omitted |
| `FolderName` | no | Defaults to Model |
| `Version` | no | Falls back to `-Version`, else `unknown` |
| `Format` | no | `exe` / `cab`; falls back to `-Format`, else `cab` |
| `DownloadLink` | no | Optional URL stored on the model |

Example (`Examples/Dell-SupportedModels.csv`):

```csv
Model,SystemSku
Latitude 7450,0C09
Latitude 7440,0C08
OptiPlex 7010,05A1;05A2
```

```powershell
.\LiteDeploy.ImportOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -ManufacturerId "Dell Inc." `
  -ManufacturerName "Dell" `
  -ModelsCsvPath ".\Examples\Dell-SupportedModels.csv" `
  -Version "2026.01" `
  -Format cab
```

Creates empty FullOS `Extracted\` folders, ensures the manufacturer **WinPE model** (`WinPE\Extracted\`, catalog `modelId: winpe`), and upserts `catalog.json`.

## Staging vs published layout

```text
Content\Temp\ImportOEMDrivers\<Mfr>\<ModelId>\
  Download\pack.cab
  Extracted\...                    ← temporary expand

Content\Drivers\<Mfr>\
  WinPE\                           ← WinPE model (role winpe)
    Extracted\...
  <Model>\                         ← FullOS model (role fullOs)
    pack.cab
    Extracted\...
```

## Download transfer modes

| Mode | When | Behavior |
| --- | --- | --- |
| **Native (default)** | `-DownloadLink` without `-UseCurl` | `Start-BitsTransfer`, then `Invoke-WebRequest` |
| **Curl (optional)** | `-DownloadLink -UseCurl` | `Engine\Tools\Curl\curl.exe` if present, else `Tools\Curl\curl.exe`, else OS `curl.exe` |

Default never calls curl. `-UseCurl` fails closed if no curl binary is found.

## Parameters

| Parameter | Required | Notes |
| --- | --- | --- |
| `-DeploymentRoot` | yes | Share root containing `Content\Drivers` |
| `-ManufacturerId` | yes | Exact WMI value (`Dell Inc.`) |
| `-ManufacturerName` | yes | Friendly / folder (`Dell`) |
| `-ModelsCsvPath` | CSV mode | Supported models list (`Model`,`SystemSku`) |
| `-CsvDelimiter` | no | Default `,` (also `;` or tab) |
| `-ModelId` / `-ModelName` / `-SystemSku` | single-model | Not used in CSV mode |
| `-Version` | single-model; optional for CSV | Pack / default version label |
| `-SourcePath` | local single-model | `.cab`, `.exe`, or extracted folder |
| `-DownloadLink` | remote single-model | Vendor URL |
| `-Format` | as needed | `exe` \| `cab` |
| `-UseCurl` | no | Optional curl transfer |
| `-Force` | no | Replace existing catalog rows / content |

## Notes

- `.exe` packs are stored in the model folder; populate `Extracted\` by passing an extracted folder as `-SourcePath`.
- `.cab` packs expand under `Content\Temp`, then promote to `Extracted\`.
- Runtime: FullOS `manufacturerId` + `systemSku` → model `path\Extracted` for Setup; WinPE uses the manufacturer **WinPE model** (`modelId: winpe`) → `path\Extracted`.
