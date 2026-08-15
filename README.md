# LiteDeploy Core

Development repository for LiteDeploy. Components are split into **Manager** (admin prepares the share) and **Runtime** (device executes the deployment).

The production product repo is **LiteDeploy**. A component moves there only after it is approved.

## Layout

```text
LiteDeployManager (admin)          LiteDeployRuntime (device)
─────────────────────────          ──────────────────────────
Config → BootConfig.json           BootInitializer (startnet)
DeploymentShareACL                 DeploymentEngine
ImportOEMDrivers                     → PreCheck
SyncOEMDrivers                       → SelectWorkflow (+ Media OEM pack)
ImportOSMedia (planned)              → Setup /NoReboot (planned)
Shared/OemDriverPacks              Progress | Credentials / WinPECT
WinPEBuilder (separate repo)       LogWriter | HostShell | UiHost
DeploymentShare/ (share skeleton)
```

## Manager

| Component | What it does | Status |
| --- | --- | --- |
| [Config](components/Manager/Config) | Generates `BootConfig.json` for BootWim, DeploymentShare, and Media | Exists |
| [DeploymentShareACL](components/Manager/DeploymentShareACL) | Share folders, SMB, and NTFS log isolation | Exists |
| [ImportOEMDrivers](components/Manager/ImportOEMDrivers) | Local/`-DownloadLink`/CSV import into `Content/Drivers` + catalog | Exists |
| [SyncOEMDrivers](components/Manager/SyncOEMDrivers) | `-CheckStatus` / `-Update All\|"Model"\|"sku"` vs Dell/HP/Lenovo pack catalogs | Exists |
| [ImportOSMedia](components/Manager/ImportOSMedia) | Publishes OS catalog for SelectWorkflow / engine | Placeholder |
| [OemDriverPacks](components/Shared/OemDriverPacks) | Shared Dell/HP/Lenovo catalog helpers (Manager + Media) | Exists |
| [WinPEBuilder](https://github.com/cmartinezone/WinPEBuilder) | Builds boot ISO or `Boot.wim` for WDS/PXE | Separate repo |
| [DeploymentShare](DeploymentShare) | Initial deployment-share folder layout | Exists |

## Runtime

| Component | What it does | Status |
| --- | --- | --- |
| [BootInitializer](components/Runtime/BootInitializer) | Discovers config, maps `Z:\`, builds `BootObject`, starts DeploymentEngine | Exists |
| [DeploymentEngine](components/Runtime/DeploymentEngine) | Orchestrates PreCheck → SelectWorkflow → Setup (Setup stubbed) | Scaffold |
| [PreCheck](components/Runtime/PreCheck) | Nine-point readiness UI; returns structured result | Exists |
| [SelectWorkflow](components/Runtime/SelectWorkflow) | Computer, workflow, disk, and driver UI; Media online pack download / update alert | Exists |
| [Progress](components/Runtime/Progress) | Reads `DeploymentState.json` and renders progress | Exists |
| [LogWriter](components/Runtime/LogWriter) | CMTrace + NDJSON logging | Exists |
| [HostShell](components/Runtime/HostShell) | WinPE console geometry, theme, and presets | Exists |
| [UiHost](components/Runtime/UiHost) | Shared WPF chrome (theme, buttons, backdrop, messages) | Exists |
| [Credentials](components/Runtime/Credentials) | [DeployVault](https://github.com/cmartinezone/DeployVault) + [WinPECT](https://github.com/cmartinezone/WinPECT) | Separate repos |

On a device, the live chain is:

```text
startnet
  → BootInitializer
  → DeploymentEngine
       → PreCheck
       → SelectWorkflow
       → (planned) Setup /NoReboot + handoff
  → Progress (separate process, read-only)
  → Credentials (handoff, then FullOS import)
```

## Repository layout

```text
LiteDeploy Core/
  components/
    Manager/                  Admin / authoring
    Runtime/                  WinPE / FullOS execution
    Shared/                   Cross-cutting helpers (OemDriverPacks)
  DeploymentShare/            Initial deployment-share folder layout
  tests/WinPEEnv/             Generated WinPE + share layout (sync after component changes)
  docs/architecture/          Product design, diagrams, and status
  experiments/                Historical and scratch scripts; not shippable
```

Script file names stay as they are so WinPE and the future `Engine\Scripts` layout do not change.

## Related repositories

These stay in their own GitHub repos. LiteDeploy Core consumes them; it does not copy their source.

| Repository | Role in LiteDeploy |
| --- | --- |
| [WinPEBuilder](https://github.com/cmartinezone/WinPEBuilder) | Creates WinPE boot media as ISO or `Boot.wim` for WDS/PXE. |
| [DeployVault](https://github.com/cmartinezone/DeployVault) | Encrypted credential vault on the deployment share. |
| [WinPECT](https://github.com/cmartinezone/WinPECT) | Hardware-bound credential transfer from WinPE to FullOS. |

## Architecture

- [Deployment plan](docs/architecture/LITEDEPLOY_DEPLOYMENT_PLAN.md)
- [Workflow schema](docs/architecture/LITEDEPLOY_WORKFLOW_SCHEMA.md)
- [Drivers catalog](docs/architecture/LITEDEPLOY_DRIVERS_CATALOG.md)
- [OEM catalog sync](docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md)
- [Dev branch](docs/architecture/LITEDEPLOY_DEV_BRANCH.md)
- [UiHost](docs/architecture/LITEDEPLOY_UI_HOST.md)
- [Components](components/README.md)
