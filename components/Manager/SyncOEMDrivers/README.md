# SyncOEMDrivers

LiteDeployManager tool that refreshes OEM vendor indexes, compares them to your share’s `Content/Drivers/catalog.json`, and can re-download **driver packs** into each model’s `Extracted\` folder.

Unlike FFU, we do **not** build a `DriverMapping.json` matching repo or harvest individual SoftPaqs. The runtime resolves the model folder (`catalog.json` + SKU / UI), then **`Setup.exe` receives that directory path as a switch**. Content is the extracted pack under `Extracted\`.

**Script:** `LiteDeploy.SyncOEMDrivers.ps1`  
**Design:** [LITEDEPLOY_OEM_CATALOG_SYNC.md](../../../docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md)

## Modes

### Check status (shell table)

```powershell
.\LiteDeploy.SyncOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -CheckStatus
```

Optional allow-list CSV to surface **new** vendor SKUs not yet in your catalog:

```powershell
.\LiteDeploy.SyncOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -CheckStatus `
  -ManufacturerName "Dell" `
  -ModelsCsvPath "..\ImportOEMDrivers\Examples\Dell-SupportedModels.csv"
```

| Status | Meaning |
| --- | --- |
| `Current` | In our catalog; SKU still in vendor index |
| `UpdateReady` | Has `downloadLink` — safe to `-Update*` |
| `MissingContent` | Catalog row exists; `Extracted` empty/missing |
| `MissingFromVendor` | Local SKU not found in vendor index |
| `NewInAllowList` | CSV SKU in vendor index but not in our catalog |
| `NoVendorIndex` | Index missing/failed for that OEM |

### Update

```powershell
# All models with downloadLink (optionally scoped)
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -UpdateAll -ManufacturerName Dell -Force

# One model (name or modelId substring)
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Model "Latitude 7450" -Force

# One SKU
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -SystemSku "0C09" -Force
```

Updates call `ImportOEMDrivers` with the model’s stored `downloadLink` → download pack → extract into `Extracted\` (optional `WinPE\`). No FFU-style mapping file is written.

## Vendor index cache

Downloaded under `Content\Temp\OemCatalogs\` (refresh if older than 7 days, or pass `-RefreshCatalog`):

| OEM | Source |
| --- | --- |
| Dell | `CatalogIndexPC.cab` |
| HP | HPIA `platformList.cab` |
| Lenovo | `catalogv2.xml` |
