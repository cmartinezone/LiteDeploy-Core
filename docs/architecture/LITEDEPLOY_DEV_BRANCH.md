# Dev branch model

LiteDeploy engine and Manager/Runtime work integrates on **`dev`**, not on `main`.

## Branches

| Branch | Role |
| --- | --- |
| `main` | Stable product baseline. Do not land in-progress DeploymentEngine / WinPE orchestration here. |
| `dev` | **Integration / development branch.** Manager + Runtime layout, BootInitializer → DeploymentEngine → PreCheck / SelectWorkflow / UiHost / Progress, workflow schema, BootConfig ComputerSetup extensions. |

## PR rules

1. **Feature PRs for engine/UI / Manager work**  
   - Head: `cursor/<feature>-bd4d` (short-lived agent or feature branches)  
   - **Base: `dev`**  
   - Not `main`

2. **Promotion to `main`**  
   - Only when a vertical slice is intentionally ready  
   - Open a separate PR: `dev` → `main`

3. **Accidental merges to `main`**  
   - Revert on `main`  
   - Keep the work on `dev`

## Current `dev` contents

- `components/Manager/` — Config, DeploymentShareACL, ImportOEMDrivers, SyncOEMDrivers, ImportOSMedia placeholder  
- `components/Shared/OemDriverPacks/` — Dell/HP/Lenovo pack catalog helpers (Manager + Media)  
- `components/Runtime/` — BootInitializer, DeploymentEngine, PreCheck, SelectWorkflow, Progress, UiHost, …  
- DeploymentEngine Phase A orchestration (Setup still stubbed)  
- Structured PreCheck / SelectWorkflow return contracts  
- `ComputerSetup.DriveSelection` / `ComputerSetup.ImageEngine` on BootConfig  
- `Drivers.AutoOnlineDownloadOnMedia` / `Drivers.CheckOnlineUpdateOnMedia` (Media pack download + update alert, after confirm)  
- `BootObject.DeploymentRoot` + promoted runtime `BootConfig` from the loaded share/USB (not the boot WIM)  
- Runtime/OEM audit: StrictMode-safe bootstrap parse; `DeploymentRoot` requires `Content\`; Sync prefers catalog `downloadLink`; WinPE metadata not clobbered by FullOS import; Lenovo 4-char MTM lookup  

- Workflow v1 schema + Standard / Intune examples under `DeploymentShare/WorkFlows`
- Drivers catalog v1 (`manufacturerId` / `systemSku` / `Extracted` + WinPE model) under `DeploymentShare/Content/Drivers`

## Related

- [LITEDEPLOY_DEPLOYMENT_PLAN.md](LITEDEPLOY_DEPLOYMENT_PLAN.md) — runtime orchestration sequence  
- [LITEDEPLOY_UI_HOST.md](LITEDEPLOY_UI_HOST.md) — shared UI chrome  
- [LITEDEPLOY_WORKFLOW_SCHEMA.md](LITEDEPLOY_WORKFLOW_SCHEMA.md) — workflow JSON reference  
- [LITEDEPLOY_DRIVERS_CATALOG.md](LITEDEPLOY_DRIVERS_CATALOG.md) — drivers catalog reference  
- [LITEDEPLOY_OEM_CATALOG_SYNC.md](LITEDEPLOY_OEM_CATALOG_SYNC.md) — OEM pack sync + Media download  
- [components/README.md](../../components/README.md) — Manager vs Runtime map  
