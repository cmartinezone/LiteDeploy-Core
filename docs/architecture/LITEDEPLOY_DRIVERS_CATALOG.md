# LiteDeploy Drivers Catalog (reference)

Status: **v1 reference contract** on the `dev` branch.  
Schema and examples: [`DeploymentShare/Content/Drivers`](../../DeploymentShare/Content/Drivers).

Related: [LITEDEPLOY_WORKFLOW_SCHEMA.md](LITEDEPLOY_WORKFLOW_SCHEMA.md), [LITEDEPLOY_CATALOG_WORKFLOW_SPEC.md](LITEDEPLOY_CATALOG_WORKFLOW_SPEC.md).

## Goal

Keep driver packs simple: manufacturer (as WMI reports it) → models with **SystemSKU** match keys. No INF lists in the catalog.

```text
Content/Drivers/
  catalog.json
  <ManufacturerName>/
    WinPE/                 ← shared WinPE storage/NIC for this manufacturer
    <Model>/
      Extracted/           ← FullOS / Setup.exe (per model)
```

## Files

| Path | Role |
| --- | --- |
| `Content/Drivers/schemas/drivers-catalog.schema.json` | JSON Schema |
| `Content/Drivers/catalog.json` | Central catalog (examples until real packs are imported) |

## Manufacturer

| Field | Role |
| --- | --- |
| `manufacturerId` | Exact `Win32_ComputerSystem.Manufacturer` (e.g. `Dell Inc.` with the period) |
| `name` | Friendly UI / folder label (`Dell`) — also the on-disk folder that owns `WinPE\` |
| `enabled` | Hide when false |
| `models` | Model packs for this OEM |

## Model

| Field | Role |
| --- | --- |
| `modelId` | Stable id within the manufacturer |
| `name` | Friendly model name |
| `systemSku` | Match keys (Dell SystemSKU, Lenovo Type/MTM, HP BaseBoardProduct, …) |
| `version` | Pack version label |
| `releaseDate` | Vendor release date (`YYYY-MM-DD`) |
| `importedDate` | Import into the share (`YYYY-MM-DD`) |
| `format` | `exe` \| `cab` |
| `downloadLink` | Optional original vendor URL |
| `enabled` | Hide when false |
| `path` | Repository-relative **model** folder (FullOS under `path/Extracted`) |

## On-disk layout

```text
Content/Drivers/<ManufacturerName>/
  WinPE/                              ← manufacturer-root WinPE (storage, NIC, …)
    *.inf / driver tree
  <ModelOrType>/
    <original>.cab | <original>.exe   ← optional keep
    Extracted/                        ← FullOS / Setup.exe injection
      *.inf / driver tree
```

| Consumer | Root |
| --- | --- |
| FullOS / Setup.exe | `Join-Path $modelPath 'Extracted'` |
| WinPE (Boot.wim / runtime) | `Content\Drivers\<ManufacturerName>\WinPE` |

`WinPE\` is **shared per manufacturer**, not per model.

## Runtime match → Setup.exe path

1. Read WMI `Manufacturer` → equal `manufacturerId` (trim, case-insensitive).  
2. Read SystemSKU / Machine Type / BaseBoardProduct → any value in `systemSku`.  
3. Resolve that model’s directory (`path` → FullOS under `path\Extracted`).  
4. WinPE drivers for that OEM come from `Content\Drivers\<ManufacturerName>\WinPE`.  
5. When `ComputerSetup.ImageEngine` is `Setup.exe`, pass the **resolved model directory path** (FullOS pack) as a Setup switch.  
6. If no match → in-box / manual selection (existing SelectWorkflow policy).

This is why LiteDeploy does **not** maintain a `DriverMapping.json` matching repo: Setup.exe is given the model folder path directly after catalog/SKU (or UI) resolution.

## Intentionally out of scope here

| Concern | Where |
| --- | --- |
| BootConfig auto-detect / manual pick | `ComputerSetup` / `Drivers` in BootConfig |
| Online download during Media | `Drivers.AutoOnlineDownloadOnMedia` |
| INF-level inventory | Inside model `Extracted/` and manufacturer `WinPE/` only |
| Import / Driver Manager | [`ImportOEMDrivers`](../../components/Manager/ImportOEMDrivers/) — downloads/extracts under `Content\Temp`, publishes to `Content\Drivers`; also `-ModelsCsvPath` to register manufacturer-supported models (`Model`,`SystemSku` / `SkuId`) without a pack |
| OEM vendor catalog sync | [`SyncOEMDrivers`](../../components/Manager/SyncOEMDrivers/) — `-CheckStatus` table, `-UpdateAll` / `-Model` / `-SystemSku`; indexes in `Content\Temp\OemCatalogs\`; updates download **packs** into `Extracted\` (no FFU `DriverMapping.json`) ([design](./LITEDEPLOY_OEM_CATALOG_SYNC.md)) |
