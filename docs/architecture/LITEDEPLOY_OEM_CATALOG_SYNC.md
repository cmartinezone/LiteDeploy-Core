# LiteDeploy OEM catalog sync (learned from FFU)

**Reference only:** [rbalsleyMSFT/FFU](https://github.com/rbalsleyMSFT/FFU)  
LiteDeploy does **not** import FFU code. We reuse vendor *index URLs and SKU match keys* only.

## LiteDeploy vs FFU (important)

| | **FFU** | **LiteDeploy** |
| --- | --- | --- |
| What they download | Many **individual** latest drivers (SoftPaq / PDK EXE sets) | One **driver pack** per model (CAB/EXE) |
| On disk | Loose INF tree under `Drivers\Make\Model` (+ optional WIM) | Pack → model **`Extracted\`**; WinPE is a **catalog model** (`WinPE\Extracted\`) |
| How deploy matches hardware | Separate **`DriverMapping.json`** “matching repo” (SystemId / MachineType → folder); ApplyFFU picks the folder | Select/resolve model folder once → pass that **directory path into `Setup.exe` as a switch**; no separate mapping file |
| Why different | FFU applies drivers itself from a matched folder/WIM | **`ImageEngine: Setup.exe`** receives the model dir path; Setup installs from that folder |

So: learn *where* catalogs live from FFU; **do not** copy their per-driver download + mapping model. Our engine downloads the pack, extracts it into `Extracted\`, upserts `catalog.json`, and at deploy time the runtime hands **that model directory path** to Setup.exe.

## Status

| Layer | LiteDeploy today |
| --- | --- |
| Pack download (`-DownloadLink`) | Implemented (`ImportOEMDrivers`) |
| Manual supported-models CSV | Implemented (`-ModelsCsvPath`) — scaffolds models; does not download packs |
| Online vendor **catalog** sync + status/update | `SyncOEMDrivers` — `-CheckStatus` / `-Update All\|"Model"\|"sku"` |
| Shared catalog library | [`components/Shared/OemDriverPacks/`](../../components/Shared/OemDriverPacks/) |
| Media online download / update alert | SelectWorkflow + `AutoOnlineDownloadOnMedia` / `CheckOnlineUpdateOnMedia` |
| Online OEMs | **Dell, HP, Lenovo only** (Surface out of scope) |

## End-to-end example (Dell CSV → Sync → Media)

```powershell
# 1) Register two supported Dell models (empty Extracted + WinPE model)
.\ImportOEMDrivers\LiteDeploy.ImportOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -ManufacturerId "Dell Inc." `
  -ManufacturerName "Dell" `
  -ModelsCsvPath ".\Examples\Dell-SupportedModels.csv"

# 2) Compare local catalog to Dell/HP/Lenovo pack indexes
.\SyncOEMDrivers\LiteDeploy.SyncOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -CheckStatus

# 3) Download/replace packs for UpdateAvailable models
.\SyncOEMDrivers\LiteDeploy.SyncOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -Update All -Force
```

On **USB Media**, SelectWorkflow can download a missing pack for the current PC, or alert if a newer Dell/HP/Lenovo pack exists when `CheckOnlineUpdateOnMedia` is enabled.

## Manager CLI: SyncOEMDrivers

Script: [`components/Manager/SyncOEMDrivers/LiteDeploy.SyncOEMDrivers.ps1`](../../components/Manager/SyncOEMDrivers/LiteDeploy.SyncOEMDrivers.ps1)  
Library: [`components/Shared/OemDriverPacks/LiteDeploy.OemDriverPackCatalog.ps1`](../../components/Shared/OemDriverPacks/LiteDeploy.OemDriverPackCatalog.ps1)

### `-CheckStatus`

Compares **our** `Content\Drivers\catalog.json` to refreshed vendor **driver pack** catalogs under `Content\Temp\OemCatalogs\`, then prints a shell table with **LocalVersion** vs **OnlineVersion**.

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
| OnlineVersion | Vendor pack version (Dell `dellVersion`, HP SoftPaq version, Lenovo SCCM version) |
| OnlineDate | Vendor pack release date |
| Status | See below |

**Status values**

| Status | Meaning |
| --- | --- |
| `Current` | Local version/date is current vs online pack catalog |
| `UpdateAvailable` | Newer pack online — `OnlineVersion` / `OnlineDate` outlined |
| `MissingFromVendor` | Local model; SKU not found in vendor pack catalog |
| `NoVendorIndex` | Vendor pack catalog not available for that manufacturer |
| `MissingContent` | Catalog entry exists but `Extracted` empty / path missing |
| `NewInAllowList` | In CSV allow-list, in vendor catalog, **not** in our catalog yet |
| `WinPeModel` | Manufacturer WinPE model (skipped for FullOS pack compare) |

Without `-ModelsCsvPath`, vendor-only “new” rows are **not** dumped (indexes are huge). Pass CSV to surface **new** models/SKUs.

### `-Update All` / `-Update "Model"` / `-Update "sku"`

Download the pack (URL from OEM catalog when `downloadLink` is missing), **replace** `Extracted\`, and **update** `catalog.json` via `ImportOEMDrivers`.

```powershell
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Update All -Force
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Update "Latitude 7450" -Force
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Update "0C09" -Force
```

`-Update All` targets FullOS models with `UpdateAvailable`. A non-All value matches model name/id first, then SystemSKU.  
Optional: `-ManufacturerName Dell` to scope. `-Force` replaces existing `Extracted\` content.

**Update always means:** download pack → replace **`Extracted\`** → upsert **`catalog.json`**.

`downloadLink` on the catalog model is a **last-known / reference URL**. Sync prefers it when present; otherwise resolves a fresh URL from the live OEM pack catalog.

### `-RefreshCatalog`

Forces re-download of vendor catalogs into `Content\Temp\OemCatalogs\` (default: refresh when cache older than 7 days).

| Vendor | Pack version source | Also cached |
| --- | --- | --- |
| Dell | `DriverPackCatalog.cab` | `CatalogIndexPC.cab` |
| HP | `HPClientDriverPackCatalog.cab` | `platformList.cab` |
| Lenovo | `catalogv2.xml` (SCCM pack nodes) | — |

## Media runtime (SelectWorkflow)

When `Deployment.Type = Media`:

| Policy | Behavior |
| --- | --- |
| `Drivers.AutoOnlineDownloadOnMedia` | If the model folder is **missing**, download pack onto local media (same `Content\Drivers` layout) |
| `Drivers.CheckOnlineUpdateOnMedia` | If the folder **exists**, Dell/HP/Lenovo compare → **alert** if newer; replace only after technician confirms |

Shared implementation: `Invoke-MediaOemDriverPackAction` in OemDriverPacks.

## How FFU does it (summary)

FFU is a **two-phase** Manager flow:

1. **Get models** — download/parse OEM index → list `Model + SystemId/MachineType (+ pack URL)`  
2. **Download selected** — pull latest packages for chosen models → `Drivers\<Make>\<Model>\`  
3. **Map for deploy** — write `DriverMapping.json` so WinPE matches WMI → folder/WIM  

They prefer **latest individual drivers** (SupportAssist / HPIA / System Update style), not only enterprise DriverPack CABs.

### Per OEM (FFU reference)

| OEM | Catalog / discovery | Cache age | Match key (WMI) | Pack acquisition |
| --- | --- | --- | --- | --- |
| **Dell** (client ≤ Win11) | `CatalogIndexPC.cab` | ~7 days | SystemSku | Individual SoftPaq-style harvest (FFU) — we take pack CAB URL instead |
| **HP** | `platformList.cab` | ~7 days | BaseboardProduct | SoftPaq EXEs (FFU) — we use Client DriverPack catalog |
| **Lenovo** | PSREF + `catalogv2.xml` | Live / cached | Machine Type (4-char) | We use `catalogv2.xml` SCCM packs in v1 |
| **Microsoft Surface** | Download Center scrape | Cached JSON | Model string | **Out of scope** for LiteDeploy online sync |

### FFU artifacts — what we take / skip

| FFU | LiteDeploy |
| --- | --- |
| Vendor index CAB/XML URLs | **Take** → cache under `Content\Temp\OemCatalogs\<Vendor>\` |
| SystemId / MachineType match keys | **Take** → store as `systemSku[]` in `catalog.json` |
| `Drivers.json` selection list | Close to our supported-models CSV |
| Individual SoftPaq/PDK EXE harvest | **Skip** |
| `DriverMapping.json` matching repo | **Skip** — use `catalog.json` + `Extracted\` only |
| BITS download | Already in `ImportOEMDrivers` / shared lib |

## LiteDeploy layout

```text
Content\Temp\OemCatalogs\
  Dell\
    CatalogIndexPC.xml          ← from CatalogIndexPC.cab
    DriverPackCatalog.xml
  HP\
    PlatformList.xml
    HPClientDriverPackCatalog.xml
  Lenovo\
    catalogv2.xml

Content\Drivers\
  catalog.json
  <ManufacturerName>\
    WinPE\                      ← model role=winpe
      Extracted\
    <Model>\
      Extracted\                ← model role=fullOs / Setup.exe
```

### Match keys

| Manufacturer | `systemSku` source |
| --- | --- |
| Dell | SystemSKU |
| HP | BaseBoardProduct |
| Lenovo | Machine Type (MTM first 4) |
| Other / Surface | Manual import only (model name / any SKU you store) |

`manufacturerId` remains exact WMI `Win32_ComputerSystem.Manufacturer` (e.g. `Dell Inc.`).

## What we deliberately do differently

- **No `DriverMapping.json`** — resolve model dir once, pass path to **`Setup.exe`**; catalog only stores `manufacturerId` / `systemSku` / `path`  
- **Driver packs into `Extracted\`** — Setup (or DISM) consumes that folder, not a SoftPaq matching repository  
- **CSV as allow-list** — internal supported models stay authoritative; OEM indexes are discovery  
- **CheckStatus table** — share vs vendor index in the shell before updating  
- **Update scoped** — `-Update All` / `-Update "Model"` / `-Update "sku"` (always pack → Extracted)  
- **Media: no silent overwrite** — existing model folder is kept unless technician confirms update  
- **No Edge/PSREF cookie hacks in v1** — Lenovo uses `catalogv2.xml` first  
- **Reference only** — learn catalog URLs from FFU; rewrite LiteDeploy-owned PowerShell

## Implementation order

1. ~~CLI surface: `-CheckStatus` / `-Update*` / Temp OemCatalogs refresh~~  
2. ~~Version compare (local `version` vs pack catalog) + outline `OnlineVersion`~~  
3. ~~`-Update All|"Model"|"sku"` auto-resolve pack URL, download, replace, update catalog~~  
4. ~~Shared OemDriverPacks lib + Media download / update alert~~  
5. Prefer WinPE-type packs for the WinPE model compare (optional)  
