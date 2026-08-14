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

- `components/Manager/` — Config, DeploymentShareACL, ImportOSMedia placeholder  
- `components/Runtime/` — BootInitializer, DeploymentEngine, PreCheck, SelectWorkflow, Progress, UiHost, …  
- DeploymentEngine Phase A orchestration (Setup still stubbed)  
- Structured PreCheck / SelectWorkflow return contracts  
- `ComputerSetup.DriveSelection` / `ComputerSetup.ImageEngine` on BootConfig  
- Workflow v1 schema + Standard / Intune examples under `DeploymentShare/WorkFlows`
- Drivers catalog v1 (`manufacturerId` / `systemSku` / `Extracted`) under `DeploymentShare/Content/Drivers`

## Related

- [LITEDEPLOY_DEPLOYMENT_PLAN.md](LITEDEPLOY_DEPLOYMENT_PLAN.md) — runtime orchestration sequence  
- [LITEDEPLOY_UI_HOST.md](LITEDEPLOY_UI_HOST.md) — shared UI chrome  
- [LITEDEPLOY_WORKFLOW_SCHEMA.md](LITEDEPLOY_WORKFLOW_SCHEMA.md) — workflow JSON reference  
- [LITEDEPLOY_DRIVERS_CATALOG.md](LITEDEPLOY_DRIVERS_CATALOG.md) — drivers catalog reference  
- [components/README.md](../../components/README.md) — Manager vs Runtime map  
