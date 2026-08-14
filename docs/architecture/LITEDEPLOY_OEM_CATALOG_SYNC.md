# LiteDeploy OEM catalog sync (learned from FFU)

**Reference only:** [rbalsleyMSFT/FFU](https://github.com/rbalsleyMSFT/FFU)  
LiteDeploy does **not** import FFU code. We reuse the *vendor sources and match keys*, then own staging under `Content\Temp\OemCatalogs\` and publish into `Content\Drivers\` + `catalog.json`.

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

**v1 limit:** Update refreshes packs via stored `downloadLink` (admin URL / enterprise pack). Resolving “latest” automatically from Dell PDK / HPIA SoftPaqs (FFU-style many-EXE) is a later phase — `-CheckStatus` still shows whether the SKU remains in the vendor **index**.

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

### FFU artifacts (concepts → LiteDeploy)

| FFU | LiteDeploy analogue |
| --- | --- |
| `Drivers.json` (selected models to download) | Supported-models CSV and/or future selection list |
| Vendor CAB/XML under `Drivers\<Make>\` | `Content\Temp\OemCatalogs\<Vendor>\` |
| `Drivers\<Make>\<Model>\` extracted INF tree | `Content\Drivers\<ManufacturerName>\<Folder>\Extracted\` |
| `DriverMapping.json` (`SystemId` / `MachineType`) | `Content\Drivers\catalog.json` (`systemSku[]`) |
| BITS + retry | Existing ImportOEMDrivers native BITS → IWR (`-UseCurl` optional) |

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

- **Own catalog contract** — LiteDeploy `catalog.json` v1, not FFU `DriverMapping.json`  
- **Optional enterprise CAB** — still allow `-DownloadLink` / DriverPack CABs when admins want them  
- **CSV as allow-list** — internal supported models stay authoritative; OEM catalogs are discovery + URLs  
- **CheckStatus table** — share vs vendor index in the shell before updating  
- **Update scoped** — `-UpdateAll`, `-Model`, or `-SystemSku`  
- **No Edge/PSREF cookie hacks in v1** — Lenovo uses `catalogv2.xml` first; PSREF only if we later need missing SKUs  
- **Reference only** — learn patterns; rewrite LiteDeploy-owned PowerShell

## Implementation order

1. ~~CLI surface: `-CheckStatus` / `-Update*` / Temp OemCatalogs refresh~~ (scaffolded)  
2. Dell index parse completeness + DriverPackCatalog version compare (true “new version”)  
3. HP SoftPaq / Lenovo package resolve for Update without manual `downloadLink`  
4. Surface index (if required)
