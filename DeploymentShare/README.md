# Deployment share root

This directory is the initial folder layout of a LiteDeploy deployment share. Copy or provision it as the share root (for example `\\Server\DeploymentShare$` or a local `~LiteDeploy` tree). It does not contain OS images, drivers, packages, or secrets.

The five top-level roles:

| Folder | Role |
| --- | --- |
| `Config` | How LiteDeploy behaves (`BootConfig.json` and related policy). |
| `Content` | What LiteDeploy deploys (OS media, packages, drivers, boot media, unattend). |
| `Engine` | Reusable code that performs the work (`Scripts`, `Tools`). |
| `WorkFlows` | Ordered deployment process definitions (`catalog.json`, schema, per-workflow JSON). |
| `WorkLogs` | Record of what LiteDeploy did (`Admin`, `Deployments`). |

```text
DeploymentShare\
  Config\
  Content\
    BootMedia\
      ISO\
      WIM\
    Drivers\
      catalog.json
      schemas\
        drivers-catalog.schema.json
    OperatingSystems\
      catalog.json
    Packages\
      catalog.json
    Temp\
      README.md
      ImportOEMDrivers\     # pack download + CAB extract staging
      OemCatalogs\          # Dell/HP/Lenovo vendor catalog CAB/XML cache (SyncOEMDrivers / Media)
    Unattend\
  Engine\
    Scripts\
    Tools\
      Curl\                 # optional curl.exe for ImportOEMDrivers -UseCurl
  WorkFlows\
    catalog.json
    schemas\
      workflow.schema.json
      workflow-catalog.schema.json
    StandardWorkflow.json
    IntuneReadyWorkflow.json
  WorkLogs\
    Admin\
    Deployments\
```

Approved Core scripts promote into `Engine\Scripts` (include `LiteDeploy.OemDriverPackCatalog.ps1` for Media online driver packs). The same promote list is used by the workstation emulator at [tests/WinPEEnv](../tests/WinPEEnv/) (`Sync-WinPETestEnv.ps1`). [WinPEBuilder](https://github.com/cmartinezone/WinPEBuilder) writes ISO/`Boot.wim` under `Content\BootMedia`. [DeployVault](https://github.com/cmartinezone/DeployVault) stays on the share but is not part of this skeleton (no vault files in git).

[LiteDeploy.SetDeploymentShareAcl.ps1](../components/Manager/DeploymentShareACL/LiteDeploy.SetDeploymentShareAcl.ps1) applies SMB and NTFS permissions onto a provisioned copy of this tree.

OS and package catalogs remain placeholders until ImportOSMedia / package publishing. Workflow and drivers catalogs are v1 reference contracts — see [LITEDEPLOY_WORKFLOW_SCHEMA.md](../docs/architecture/LITEDEPLOY_WORKFLOW_SCHEMA.md), [LITEDEPLOY_DRIVERS_CATALOG.md](../docs/architecture/LITEDEPLOY_DRIVERS_CATALOG.md), and [LITEDEPLOY_OEM_CATALOG_SYNC.md](../docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md).
