# Components

LiteDeploy Core splits components by **who runs them**:

| Area | Role | Promotes to |
| --- | --- | --- |
| [**Manager**](Manager/) | Administrator tools that prepare BootConfig, share ACLs, and OEM/OS content | Share `Config\`, admin workstation scripts |
| [**Runtime**](Runtime/) | WinPE / FullOS execution chain started from `startnet` | `Engine\Scripts\` |
| [**Shared**](Shared/) | Helpers used by both Manager and Runtime | Deployed with whichever consumer needs them |

Production script **file names** stay the same (`LiteDeploy.PreCheck.ps1`, etc.). Folder names here are for Core development only.

## Manager

| Folder | What it does |
| --- | --- |
| [Config](Manager/Config/) | Generates `BootConfig.json` |
| [DeploymentShareACL](Manager/DeploymentShareACL/) | Share folders, SMB, and NTFS log isolation |
| [ImportOEMDrivers](Manager/ImportOEMDrivers/) | Local/`-DownloadLink`/CSV import into `Content/Drivers` + catalog |
| [SyncOEMDrivers](Manager/SyncOEMDrivers/) | Check/update Dell/HP/Lenovo driver packs vs online catalogs |
| [ImportOSMedia](Manager/ImportOSMedia/) | Planned OS importer → `Content/OperatingSystems/catalog.json` |

## Shared

| Folder | What it does |
| --- | --- |
| [OemDriverPacks](Shared/OemDriverPacks/) | Dell/HP/Lenovo pack catalog refresh, version compare, Media download helpers |

Adjacent (separate repos / share tree): [WinPEBuilder](https://github.com/cmartinezone/WinPEBuilder), [DeploymentShare](../DeploymentShare/), DeployVault admin tooling.

## Runtime

| Folder | What it does |
| --- | --- |
| [BootInitializer](Runtime/BootInitializer/) | `startnet` parent: config, `Z:`, `BootObject`, starts engine |
| [DeploymentEngine](Runtime/DeploymentEngine/) | Orchestrates PreCheck → SelectWorkflow → Setup (Setup stubbed) |
| [PreCheck](Runtime/PreCheck/) | Hardware / source readiness UI |
| [SelectWorkflow](Runtime/SelectWorkflow/) | Identity, workflow, disk, drivers (Media online pack download / update alert) |
| [Progress](Runtime/Progress/) | Read-only `DeploymentState.json` UI |
| [LogWriter](Runtime/LogWriter/) | CMTrace + NDJSON logging |
| [HostShell](Runtime/HostShell/) | WinPE console geometry / theme |
| [UiHost](Runtime/UiHost/) | Shared WPF chrome |
| [Credentials](Runtime/Credentials/) | WinPE → FullOS credential handoff notes ([DeployVault](https://github.com/cmartinezone/DeployVault) / [WinPECT](https://github.com/cmartinezone/WinPECT)) |

## Device chain

```text
startnet
  → Runtime/BootInitializer
  → Runtime/DeploymentEngine
       → PreCheck → SelectWorkflow → (Setup /NoReboot + handoff)
  → Progress (separate process)
  → Credentials / WinPECT
```

## Rules

- New admin/authoring work → `Manager/`.
- New WinPE/FullOS execution work → `Runtime/`.
- Keep production script names unchanged.
- `experiments/` is not part of Manager or Runtime and does not promote.
- Workstation layout emulator: [tests/WinPEEnv](../tests/WinPEEnv/) (`Sync-WinPETestEnv.ps1` copies Runtime + Shared into `Share\Engine\Scripts`).
