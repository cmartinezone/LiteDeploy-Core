# ImportOSMedia (planned)

LiteDeployManager component that imports Windows Setup media and publishes:

```text
Content/OperatingSystems/catalog.json
Content/OperatingSystems/<media-folder>/os.json
```

## Status

Not in this repository yet. If you have the importer on a local machine, place it here as:

```text
components/Manager/ImportOSMedia/
  LiteDeploy.ImportOSMedia.ps1
  LiteDeploy.ImportOSMediaGUI.ps1   # optional
  README.md
```

## Contract consumed by Runtime

Workflows reference `osId` / `editionId` only. SelectWorkflow and DeploymentEngine resolve `setupPath`, `imagePath`, and `imageIndex` from the OS catalog — see [LITEDEPLOY_WORKFLOW_SCHEMA.md](../../../docs/architecture/LITEDEPLOY_WORKFLOW_SCHEMA.md) and [LITEDEPLOY_CATALOG_WORKFLOW_SPEC.md](../../../docs/architecture/LITEDEPLOY_CATALOG_WORKFLOW_SPEC.md).
