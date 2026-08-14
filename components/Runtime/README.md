# LiteDeployRuntime

Device-side components for WinPE and FullOS. Promote approved scripts as siblings under `Engine\Scripts\`.

| Folder | Status |
| --- | --- |
| [BootInitializer](BootInitializer/) | Exists |
| [DeploymentEngine](DeploymentEngine/) | Scaffold (Phase A) |
| [PreCheck](PreCheck/) | Exists |
| [SelectWorkflow](SelectWorkflow/) | Exists |
| [Progress](Progress/) | Exists |
| [LogWriter](LogWriter/) | Exists |
| [HostShell](HostShell/) | Exists |
| [UiHost](UiHost/) | Exists |
| [Credentials](Credentials/) | Integration notes; code in DeployVault / WinPECT |

Development sibling resolution uses paths like `..\PreCheck\` and `..\UiHost\` under this `Runtime/` folder.
