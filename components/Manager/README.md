# LiteDeployManager

Administrator-side components. These run on a management workstation or build host — not in the WinPE `startnet` chain.

| Folder | Status |
| --- | --- |
| [Config](Config/) | Exists — `BootConfig.json` generator |
| [DeploymentShareACL](DeploymentShareACL/) | Exists — share + ACL provisioning |
| [ImportOSMedia](ImportOSMedia/) | Placeholder — bring local importer here when ready |

Outputs land on the deployment share (`Config\`, `Content\OperatingSystems\`, workflows, etc.). Runtime only **consumes** those artifacts by ID and path.
