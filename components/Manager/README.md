# LiteDeployManager

Administrator-side components. These run on a management workstation or build host — not in the WinPE `startnet` chain.

| Folder | Status |
| --- | --- |
| [Config](Config/) | Exists — `BootConfig.json` generator |
| [DeploymentShareACL](DeploymentShareACL/) | Exists — share + ACL provisioning |
| [ImportOEMDrivers](ImportOEMDrivers/) | Exists — local/`-DownloadLink`/CSV import into `Content/Drivers` + catalog |
| [SyncOEMDrivers](SyncOEMDrivers/) | Exists — `-CheckStatus` / `-Update All|"Model"|"sku"` vs Dell/HP/Lenovo indexes |
| [ImportOSMedia](ImportOSMedia/) | Exists — ISO/WIM/ESD importer + GUI → `Content/OperatingSystems` catalog |

Shared OEM pack helpers (also used by Media SelectWorkflow): [`../Shared/OemDriverPacks/`](../Shared/OemDriverPacks/).

Outputs land on the deployment share (`Config\`, `Content\OperatingSystems\`, `Content\Drivers\`, workflows, etc.). Runtime only **consumes** those artifacts by ID and path.
