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
    OperatingSystems\
      catalog.json
    Packages\
      catalog.json
    Temp\
    Unattend\
  Engine\
    Scripts\
    Tools\
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

Approved Core scripts promote into `Engine\Scripts`. [WinPEBuilder](https://github.com/cmartinezone/WinPEBuilder) writes ISO/`Boot.wim` under `Content\BootMedia`. [DeployVault](https://github.com/cmartinezone/DeployVault) stays on the share but is not part of this skeleton (no vault files in git).

[LiteDeploy.SetDeploymentShareAcl.ps1](../components/02-DeploymentShareACL/LiteDeploy.SetDeploymentShareAcl.ps1) applies SMB and NTFS permissions onto a provisioned copy of this tree.

OS, package, and driver catalogs here remain placeholders until ImportOSMedia / package publishing. Workflow schema and examples are the v1 reference contract — see [LITEDEPLOY_WORKFLOW_SCHEMA.md](../docs/architecture/LITEDEPLOY_WORKFLOW_SCHEMA.md).
