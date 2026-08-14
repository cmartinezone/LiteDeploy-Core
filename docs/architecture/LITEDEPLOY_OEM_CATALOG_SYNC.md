# LiteDeploy OEM catalog sync (learned from FFU)

**Reference only:** [rbalsleyMSFT/FFU](https://github.com/rbalsleyMSFT/FFU)  
LiteDeploy does **not** import FFU code. We reuse the *vendor sources and match keys*, then own staging under `Content\Temp\OemCatalogs\` and publish into `Content\Drivers\` + `catalog.json`.

## Status

| Layer | LiteDeploy today |
| --- | --- |
| Pack download (`-DownloadLink`) | Implemented (`ImportOEMDrivers`) |
| Manual supported-models CSV | Implemented (`-ModelsCsvPath`) |
| Online vendor **catalog** sync | **Not built** — path reserved |

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

## LiteDeploy target design

```text
Content\Temp\OemCatalogs\
  Dell\
    CatalogIndexPC.xml          ← from CatalogIndexPC.cab
  HP\
    PlatformList.xml            ← from platformList.cab
  Lenovo\
    (search cache / catalog XML as needed)
  Surface\
    (index cache)

Content\Drivers\
  catalog.json                  ← manufacturerId + models[].systemSku + downloadLink + path
  <ManufacturerName>\<Model>\
    Extracted\   WinPE\
```

### Intended Manager operations (future)

1. **SyncOemCatalog** — download/refresh vendor index into `Content\Temp\OemCatalogs\<Vendor>\`  
2. **List / filter models** — optionally intersect with internal CSV (`Model` + `SkuId`)  
3. **Import pack** — reuse `ImportOEMDrivers` download path (Temp → Drivers → catalog upsert)

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
- **No Edge/PSREF cookie hacks in v1** — prefer Lenovo `catalogv2.xml` (or published CDRT) first; PSREF only if we later need the missing SKUs  
- **Reference only** — learn patterns; rewrite LiteDeploy-owned PowerShell

## Implementation order (suggested)

1. Dell: `CatalogIndexPC.cab` → Temp → emit model/SystemId/CabUrl list (and optional CSV filter)  
2. HP: `platformList.cab` → SystemId list + SoftPaq catalog URL pattern  
3. Lenovo: `catalogv2.xml` (subset) → MachineType; document PSREF gap  
4. Surface: Download Center index (if required)  
5. Wire selected rows into existing pack download / `catalog.json` upsert
