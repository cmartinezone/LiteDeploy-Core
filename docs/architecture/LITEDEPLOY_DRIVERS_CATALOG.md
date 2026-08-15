# LiteDeploy Drivers Catalog (reference)

Status: **v1 reference contract** on the `dev` branch.  
Schema and examples: [`DeploymentShare/Content/Drivers`](../../DeploymentShare/Content/Drivers).

Related: [LITEDEPLOY_WORKFLOW_SCHEMA.md](LITEDEPLOY_WORKFLOW_SCHEMA.md), [LITEDEPLOY_CATALOG_WORKFLOW_SPEC.md](LITEDEPLOY_CATALOG_WORKFLOW_SPEC.md).

## Goal

Keep driver packs simple: manufacturer (as WMI reports it) → **models** with **SystemSKU** match keys. No INF lists in the catalog.

**WinPE is a model** under each manufacturer (`modelId: winpe`, `role: winpe`), sibling to FullOS hardware models.

```text
Content/Drivers/
  catalog.json
  <ManufacturerName>/
    WinPE/                 ← model (role winpe)
      Extracted/
    <HardwareModel>/       ← model (role fullOs)
      Extracted/
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
| `models` | Includes hardware models **and** the WinPE model |

## Model

| Field | Role |
| --- | --- |
| `modelId` | Stable id (`latitude-7450`, or reserved `winpe`) |
| `name` | Friendly model name (`WinPE` for the WinPE model) |
| `systemSku` | Hardware match keys; WinPE model uses `["WINPE"]` |
| `role` | `fullOs` (Setup.exe) or `winpe` (Boot.wim / WinPE injection). Persisted on every Import rewrite. |
| `version` | Pack version label |
| `releaseDate` | Vendor release date (`YYYY-MM-DD`) |
| `importedDate` | Import into the share (`YYYY-MM-DD`) |
| `format` | `exe` \| `cab` |
| `downloadLink` | Optional last-known vendor URL (reference; Sync may reuse it, else resolves live OEM catalog URL) |
| `enabled` | Hide when false |
| `path` | Repository-relative model folder |

## On-disk layout

```text
Content/Drivers/<ManufacturerName>/
  WinPE/                              ← WinPE model
    Extracted/                        ← WinPE storage/NIC INF tree
  <ModelOrType>/                      ← FullOS model
    <original>.cab | <original>.exe
    Extracted/                        ← FullOS / Setup.exe injection
```

| Consumer | Root |
| --- | --- |
| FullOS / Setup.exe | hardware model `path\Extracted` (`role: fullOs`) |
| WinPE (Boot.wim) | manufacturer WinPE model `path\Extracted` (`modelId: winpe`) |

## Runtime match → Setup.exe path

1. Read WMI `Manufacturer` → equal `manufacturerId`.  
2. Read SystemSKU / Machine Type / BaseBoardProduct → any value in a **fullOs** model’s `systemSku`.  
3. Pass that model’s directory path to **Setup.exe**.  
4. For WinPE boot drivers, load the manufacturer’s **WinPE model** (`role: winpe` / `modelId: winpe`) → `path\Extracted`.  
5. If no FullOS match → in-box / manual selection (SelectWorkflow policy).

No FFU-style `DriverMapping.json`: Setup.exe receives the FullOS model folder path after catalog/SKU (or UI) resolution.

## Intentionally out of scope here

| Concern | Where |
| --- | --- |
| BootConfig auto-detect / manual pick | `ComputerSetup` / `Drivers` in BootConfig |
| Online download during Media | `Drivers.AutoOnlineDownloadOnMedia` + [OemDriverPacks](../../components/Shared/OemDriverPacks/) — after confirm; uses `BootObject.DeploymentRoot` |
| Check for newer pack on Media | `Drivers.CheckOnlineUpdateOnMedia` (this OEM only; alert only unless confirmed) |
| INF-level inventory | Inside each model’s `Extracted/` |
| Import / CSV scaffold | [`ImportOEMDrivers`](../../components/Manager/ImportOEMDrivers/) |
| OEM vendor catalog sync | [`SyncOEMDrivers`](../../components/Manager/SyncOEMDrivers/) ([design](./LITEDEPLOY_OEM_CATALOG_SYNC.md)) |
| Shared catalog helpers | [`OemDriverPacks`](../../components/Shared/OemDriverPacks/) |
