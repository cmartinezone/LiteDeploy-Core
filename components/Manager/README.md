# LiteDeployManager

Administrator-side components. These run on a management workstation or build host — not in the WinPE `startnet` chain.

| Folder | Status |
| --- | --- |
| [Config](Config/) | Exists — `BootConfig.json` generator |
| [DeploymentShareACL](DeploymentShareACL/) | Exists — share + ACL provisioning |
| [ImportOEMDrivers](ImportOEMDrivers/) | Exists — import OEM packs into `Content/Drivers` + catalog |
| [SyncOEMDrivers](SyncOEMDrivers/) | Exists — `-CheckStatus` / `-Update All|"Model"|"sku"` vs OEM indexes |
| [ImportOSMedia](ImportOSMedia/) | Placeholder — bring local importer here when ready |

Outputs land on the deployment share (`Config\`, `Content\OperatingSystems\`, `Content\Drivers\`, workflows, etc.). Runtime only **consumes** those artifacts by ID and path.
