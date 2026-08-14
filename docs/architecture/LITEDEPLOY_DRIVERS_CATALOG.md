# LiteDeploy Drivers Catalog (reference)

Status: **v1 reference contract** on the `dev` branch.  
Schema and examples: [`DeploymentShare/Content/Drivers`](../../DeploymentShare/Content/Drivers).

Related: [LITEDEPLOY_WORKFLOW_SCHEMA.md](LITEDEPLOY_WORKFLOW_SCHEMA.md), [LITEDEPLOY_CATALOG_WORKFLOW_SPEC.md](LITEDEPLOY_CATALOG_WORKFLOW_SPEC.md).

## Goal

Keep driver packs simple: manufacturer (as WMI reports it) → models with **SystemSKU** match keys. No INF lists in the catalog.

```text
Content/Drivers/catalog.json
  └── manufacturers[]
        ├── manufacturerId  (WMI Manufacturer, e.g. "Dell Inc.")
        ├── name            (friendly, e.g. "Dell")
        └── models[]
              ├── systemSku[] / version / dates / format
              ├── downloadLink? 
              └── path → .../Extracted/   (DISM injection root)
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
| `name` | Friendly UI / folder label (`Dell`) |
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
| `path` | Repository-relative model folder |

## On-disk layout

```text
Content/Drivers/<FriendlyName>/<ModelOrType>/
  <original>.cab | <original>.exe     ← optional keep
  Extracted/                          ← runtime injection root
    *.inf / driver tree
```

`path` points at the model folder. Apply drivers from `Join-Path $path 'Extracted'`.

## Runtime match

1. Read WMI `Manufacturer` → equal `manufacturerId` (trim, case-insensitive).  
2. Read SystemSKU / Machine Type / BaseBoardProduct → any value in `systemSku`.  
3. Use that model’s `path\Extracted`.  
4. If no match → in-box / manual selection (existing SelectWorkflow policy).

## Intentionally out of scope here

| Concern | Where |
| --- | --- |
| BootConfig auto-detect / manual pick | `ComputerSetup` / `Drivers` in BootConfig |
| Online download during Media | `Drivers.AutoOnlineDownloadOnMedia` |
| INF-level inventory | Inside `Extracted/` only |
| Import tool | Future Manager importer (like ImportOSMedia) |
