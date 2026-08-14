# Orchestrator branch model

LiteDeploy engine work integrates on a dedicated test branch, not on `main`.

## Branches

| Branch | Role |
| --- | --- |
| `main` | Stable product baseline. Do not land in-progress DeploymentEngine / WinPE orchestration here. |
| `cursor/engine-orchestration-bd4d` | **Orchestrator branch.** BootInitializer → DeploymentEngine → PreCheck / SelectWorkflow / UiHost / Progress wiring. |

## PR rules

1. **Feature PRs for engine/UI orchestration**  
   - Head: `cursor/<feature>-bd4d` (or commits on the orchestrator branch)  
   - **Base: `cursor/engine-orchestration-bd4d`**  
   - Not `main`

2. **Promotion to `main`**  
   - Only when a vertical slice is intentionally ready  
   - Open a separate PR: `cursor/engine-orchestration-bd4d` → `main`

3. **Accidental merges to `main`**  
   - Revert on `main`  
   - Keep the work on the orchestrator branch

## Current orchestrator contents

- `08-DeploymentEngine` — Phase A orchestration (Setup still stubbed)
- Structured PreCheck / SelectWorkflow return contracts
- `04-UiHost` — shared WPF chrome
- Progress `09`, Credentials `10`

## Related

- [LITEDEPLOY_DEPLOYMENT_PLAN.md](LITEDEPLOY_DEPLOYMENT_PLAN.md) — runtime orchestration sequence  
- [LITEDEPLOY_UI_HOST.md](LITEDEPLOY_UI_HOST.md) — shared UI chrome  
