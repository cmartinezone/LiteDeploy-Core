# LiteDeploy Workflow Schema (reference)

Status: **v1 reference contract** on the `dev` branch.  
Schemas and examples live under [`DeploymentShare/WorkFlows`](../../DeploymentShare/WorkFlows).

Related: [LITEDEPLOY_CATALOG_WORKFLOW_SPEC.md](LITEDEPLOY_CATALOG_WORKFLOW_SPEC.md), [LITEDEPLOY_DEPLOYMENT_PLAN.md](LITEDEPLOY_DEPLOYMENT_PLAN.md).

## Goal

Keep workflows **simple**: ordered policy that binds enabled OS/editions and ordered actions. No WIM paths, Setup paths, image indexes, usernames, or passwords in workflow JSON.

```text
WorkFlows/catalog.json
  └── workflowId → WorkFlows/<Name>Workflow.json
        ├── osTargets[]   (osId + enabled editions, each with order)
        └── actions[]     (order → Package / packageId, phase, executionContext)
```

## Files

| Path | Role |
| --- | --- |
| `WorkFlows/schemas/workflow.schema.json` | Per-workflow JSON Schema |
| `WorkFlows/schemas/workflow-catalog.schema.json` | Catalog index schema |
| `WorkFlows/catalog.json` | Enabled workflow index for SelectWorkflow |
| `WorkFlows/StandardWorkflow.json` | Domain-join example |
| `WorkFlows/IntuneReadyWorkflow.json` | Intune / Autopilot example |

## Workflow object

| Field | Required | Notes |
| --- | --- | --- |
| `schemaVersion` | yes | `1` |
| `workflowId` | yes | Immutable ID |
| `name` / `description` | name yes | UI display only |
| `enabled` | yes | Hide when false |
| `order` | yes | UI sort among workflows |
| `revision` | yes | Pin on `DeploymentSelection` for resume |
| `requiredCredentialIds` | no | WinPECT staging IDs (workflow-wide) |
| `osTargets` | yes | Enabled OS/edition bindings |
| `actions` | yes | Ordered execution list |

### `osTargets[]`

| Field | Notes |
| --- | --- |
| `osId` | Must exist in `Content/OperatingSystems/catalog.json` |
| `order` | UI sort among OS entries |
| `enabled` | Hide when false |
| `editions[]` | `editionId` + `order` + `enabled` |

WIM / `setup.exe` / `imageIndex` stay in the OS catalog, not here.

### `actions[]`

| Field | Notes |
| --- | --- |
| `order` | Execution + FullOS resume sequence |
| `actionId` | Stable within the workflow |
| `name` | Progress / log display |
| `type` | v1: `Package` only |
| `packageId` | Required when `type` is `Package` |
| `phase` | `WinPE` \| `OfflineOS` \| `FullOS` \| `UserLogon` |
| `executionContext` | `System` \| `InteractiveUser` \| `RunAs` |
| `runAsCredentialId` | **Required** when `executionContext` is `RunAs` |
| `requiredCredentialIds` | Action-level credential IDs |
| `continueOnError` | Default `false` |
| `enabled` | Default `true`; skip when false |

### Execution context

| Value | Who runs | Credential |
| --- | --- | --- |
| `System` | `NT AUTHORITY\SYSTEM` | none |
| `InteractiveUser` | Logged-on user | none |
| `RunAs` | Imported `PSCredential` | `runAsCredentialId` (ID only) |

Credential IDs must be staged before reboot and imported under SYSTEM. Never place secrets in workflow, selection, or state JSON.

## SelectWorkflow consumption

1. Read `WorkFlows/catalog.json` → enabled workflows by `order`.
2. Load each workflow JSON → enabled `osTargets` / editions by `order`.
3. Technician picks **workflow + os + edition** (plus computer identity / disk / drivers from BootConfig).
4. Return / persist at least:

```json
{
  "workflowId": "standard-workstation",
  "workflowRevision": 1,
  "osId": "win11-26h2-es-es-26300.8772-x64",
  "editionId": "win11-26h2-windows-11-pro-26300.8772-x64"
}
```

Actions are not technician picks; the engine runs them after selection.

## Intentionally out of this schema (not missing forever)

Keep these elsewhere so workflows stay small:

| Concern | Where it belongs |
| --- | --- |
| Setup / WIM / image index | OS catalog (`osId` + `editionId`) |
| Installer command lines | `Packages/<packageId>/package.json` |
| Timeouts, exit codes, detection | Package definition |
| Reboot-after-action policy | Package exit codes → engine state machine |
| Share / media / DriveSelection / ImageEngine | `BootConfig.json` |
| Secrets | DeployVault + WinPECT (`Secrets.bin` / DPAPI) |
| Progress percents | `DeploymentState.json` |
| `dependsOn` graphs | Deferred — v1 uses flat `order` only |
| Action types beyond `Package` | Deferred (e.g. built-in DomainJoin) |
| Retry / conditions / manufacturers | Deferred optional fields |

## Validation checklist (runtime)

- Schema parse + `$schema` version supported  
- Unique `workflowId` / unique `order` + `actionId` within a file  
- Every `osId` / `editionId` exists and is enabled in the OS catalog  
- Every `packageId` exists and is enabled  
- `RunAs` always has `runAsCredentialId` present in required credential IDs  
- No path escape outside the deployment root when resolving packages/OS  
- Persist `workflowRevision` so FullOS cannot silently pick up a changed definition  

## Examples

See:

- [`StandardWorkflow.json`](../../DeploymentShare/WorkFlows/StandardWorkflow.json) — domain join + optional RunAs LOB action  
- [`IntuneReadyWorkflow.json`](../../DeploymentShare/WorkFlows/IntuneReadyWorkflow.json) — Autopilot path, fewer credentials  
