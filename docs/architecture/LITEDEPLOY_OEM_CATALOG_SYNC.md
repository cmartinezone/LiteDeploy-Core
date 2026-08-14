# LiteDeploy OEM catalog sync (learned from FFU)

**Reference only:** [rbalsleyMSFT/FFU](https://github.com/rbalsleyMSFT/FFU)  
LiteDeploy does **not** import FFU code. We reuse vendor *index URLs and SKU match keys* only.

## LiteDeploy vs FFU (important)

| | **FFU** | **LiteDeploy** |
| --- | --- | --- |
| What they download | Many **individual** latest drivers (SoftPaq / PDK EXE sets) | One **driver pack** per model (CAB/EXE) |
| On disk | Loose INF tree under `Drivers\Make\Model` (+ optional WIM) | Pack → **`Extracted\`** (FullOS) and optional **`WinPE\`** |
| How deploy matches hardware | Separate **`DriverMapping.json`** “matching repo” (SystemId / MachineType → folder) | **`catalog.json`** only: `manufacturerId` + `systemSku[]` → `path\Extracted` |
| Mapping file like FFU? | Yes | **No** — we will not create a DriverMapping-style matching repo |

So: learn *where* catalogs live from FFU; **do not** copy their per-driver download + mapping model. Our engine downloads the pack, extracts it into `Extracted\`, and upserts the model row in `catalog.json`.

## Status

| Layer | LiteDeploy today |
| --- | --- |
| Pack download (`-DownloadLink`) | Implemented (`ImportOEMDrivers`) |
| Manual supported-models CSV | Implemented (`-ModelsCsvPath`) |
| Online vendor **catalog** sync + status/update | Scaffolded (`SyncOEMDrivers`) — Dell/HP/Lenovo index refresh + `-CheckStatus` table; `-Update*` uses stored `downloadLink` |

## Manager CLI: SyncOEMDrivers

Script: [`components/Manager/SyncOEMDrivers/LiteDeploy.SyncOEMDrivers.ps1`](../../components/Manager/SyncOEMDrivers/LiteDeploy.SyncOEMDrivers.ps1)

### `-CheckStatus`

Compares **our** `Content\Drivers\catalog.json` to refreshed vendor indexes under `Content\Temp\OemCatalogs\`, then prints a shell table.

```powershell
.\LiteDeploy.SyncOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -CheckStatus

.\LiteDeploy.SyncOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -CheckStatus `
  -ManufacturerName "Dell" `
  -ModelsCsvPath ".\Examples\Dell-SupportedModels.csv"
```

Typical columns:

| Column | Meaning |
| --- | --- |
| Manufacturer | Friendly name |
| Model | Catalog model name |
| SystemSku | Local SKU(s) |
| LocalVersion | `models[].version` |
| PathOk | Model folder / `Extracted` present |
| VendorHit | SKU found in OEM index |
| VendorName | Name from vendor index (when hit) |
| Status | See below |

**Status values**

| Status | Meaning |
| --- | --- |
| `Current` | Local model; SKU still listed in vendor index |
| `MissingFromVendor` | Local model; SKU not found in vendor index (retired / rename / wrong SKU) |
| `NoVendorIndex` | Vendor index not available for that manufacturer |
| `MissingContent` | Catalog entry exists but `Extracted` empty / path missing |
| `UpdateReady` | Local has `downloadLink` (or resolved URL) — `-Update*` can refresh pack |
| `NewInAllowList` | In CSV allow-list / filter, in vendor index, **not** in our catalog yet |

Without `-ModelsCsvPath`, vendor-only “new” rows are **not** dumped (Dell/HP indexes are huge). Pass CSV (or later an allow-list) to surface **new** models/SKUs.

### `-UpdateAll` / model / SKU

Re-download packs into the deployment share for matching catalog rows that have a `downloadLink` (calls `ImportOEMDrivers`).

```powershell
# Everything with a downloadLink under the share catalog
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -UpdateAll

# One model (name or modelId, substring match)
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Model "Latitude 7450"

# One SystemSKU / Machine Type
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -SystemSku "0C09"
```

Optional: `-ManufacturerName Dell` to scope UpdateAll. `-Force` replaces existing Extracted content. `-WhatIf` supported.

**Update always means:** download the **driver pack** → extract into that model’s **`Extracted\`** (via `ImportOEMDrivers`). It does **not** build an FFU-style individual-driver matching repo. Vendor indexes are only for `-CheckStatus` discovery / SKU presence (and later resolving a pack URL into `downloadLink`).

### `-RefreshCatalog`

Forces re-download of vendor indexes into `Content\Temp\OemCatalogs\` (default: refresh when cache older than 7 days).

| Vendor | URL | Cache file |
| --- | --- | --- |
| Dell | `https://downloads.dell.com/catalog/CatalogIndexPC.cab` | `OemCatalogs\Dell\CatalogIndexPC.xml` |
| HP | `https://hpia.hpcloud.hp.com/ref/platformList.cab` | `OemCatalogs\HP\PlatformList.xml` |
| Lenovo | `https://download.lenovo.com/cdrt/td/catalogv2.xml` | `OemCatalogs\Lenovo\catalogv2.xml` |

## How FFU does it (summary)

FFU is a **two-phase** Manager flow:

1. **Get models** — download/parse OEM index → list `Model + SystemId/MachineType (+ pack URL)`  
2. **Download selected** — pull latest packages for chosen models → `Drivers\<Make>\<Model>\`  
3. **Map for deploy** — write `DriverMapping.json` so WinPE matches WMI → folder/WIM  

They prefer **latest individual drivers** (SupportAssist / HPIA / System Update style), not only enterprise DriverPack CABs.

### Per OEM

| OEM | Catalog / discovery | Cache age | Match key (WMI) | Pack acquisition |
| --- | --- | --- | --- | --- |
| **Dell** (client ≤ Win11) | `https://downloads.dell.com/catalog/CatalogIndexPC.cab` → `CatalogIndexPC.xml` | Refresh if XML &gt; ~7 days | `MS_SystemInformation.SystemSku` (`SystemId`) | Index gives per-model CAB URL → download CAB → parse model XML → pick latest `DRVR` components by arch → download each EXE |
| **Dell** (server path) | `Catalog.cab` | Same | Model name (legacy) | Different pathway |
| **HP** | `https://hpia.hpcloud.hp.com/ref/platformList.cab` → `PlatformList.xml` | ~7 days | `MS_SystemInformation.BaseboardProduct` (`SystemId`) | Per SystemID: `https://hpia.hpcloud.hp.com/ref/<SystemID>/<release>.cab` → XML → SoftPaq EXEs |
| **Lenovo** | **PSREF** search API (not only `catalogv2.xml`) | Live query | Machine Type (4-char MTM); `SystemProductName` / model | Model catalog XML → package XMLs → EXE extract. FFU notes `catalogv2.xml` misses many EDU/consumer SKUs (300w/500w/…) |
| **Microsoft Surface** | Scrape Download Center model index + per-model page | Cached JSON | Friendly `Model` string | MSI/ZIP for Win10/Win11 |

### FFU artifacts — what we take / skip

| FFU | LiteDeploy |
| --- | --- |
| Vendor index CAB/XML URLs | **Take** → cache under `Content\Temp\OemCatalogs\<Vendor>\` |
| SystemId / MachineType match keys | **Take** → store as `systemSku[]` in `catalog.json` |
| `Drivers.json` selection list | Close to our supported-models CSV |
| Individual SoftPaq/PDK EXE harvest | **Skip** |
| `DriverMapping.json` matching repo | **Skip** — use `catalog.json` + `Extracted\` only |
| BITS download | Already in `ImportOEMDrivers` |

## LiteDeploy layout

```text
Content\Temp\OemCatalogs\
  Dell\
    CatalogIndexPC.xml          ← from CatalogIndexPC.cab
  HP\
    PlatformList.xml            ← from platformList.cab
  Lenovo\
    catalogv2.xml

Content\Drivers\
  catalog.json                  ← manufacturerId + models[].systemSku + downloadLink + path
  <ManufacturerName>\<Model>\
    Extracted\   WinPE\
```

### Match keys we already agreed

| Manufacturer | `systemSku` source |
| --- | --- |
| Dell | SystemSKU |
| HP | BaseBoardProduct |
| Lenovo | Machine Type (MTM first 4) |
| Surface / Microsoft | Model name (and any SKU we store) |

`manufacturerId` remains exact WMI `Win32_ComputerSystem.Manufacturer` (e.g. `Dell Inc.`).

## What we deliberately do differently

- **Driver packs into `Extracted\`** — not a loose per-INF matching repository  
- **No `DriverMapping.json`** — runtime uses `catalog.json` → `path\Extracted` / `path\WinPE`  
- **CSV as allow-list** — internal supported models stay authoritative; OEM indexes are discovery  
- **CheckStatus table** — share vs vendor index in the shell before updating  
- **Update scoped** — `-UpdateAll`, `-Model`, or `-SystemSku` (always pack → Extracted)  
- **No Edge/PSREF cookie hacks in v1** — Lenovo uses `catalogv2.xml` first  
- **Reference only** — learn catalog URLs from FFU; rewrite LiteDeploy-owned PowerShell

## Implementation order

1. ~~CLI surface: `-CheckStatus` / `-Update*` / Temp OemCatalogs refresh~~ (scaffolded)  
2. Resolve **driver pack** download URLs from vendor catalogs (enterprise DriverPack-style), not SoftPaq trees  
3. Version compare (local `version` vs pack catalog) for clearer “new version out” in `-CheckStatus`  
4. Surface pack sources (if required)
