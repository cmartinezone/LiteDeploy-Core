# SyncOEMDrivers

LiteDeployManager tool that refreshes Dell/HP/Lenovo **driver pack** catalogs, compares pack **versions** to your share’s `Content/Drivers/catalog.json`, and can re-download packs into each model’s `Extracted\` folder.

Unlike FFU, we do **not** build a `DriverMapping.json` matching repo or harvest individual SoftPaqs. The runtime resolves the FullOS model folder (`catalog.json` + SKU / UI), then **`Setup.exe` receives that directory path as a switch**. WinPE drivers are a separate catalog **model** (`modelId: winpe`) under the manufacturer: `WinPE\Extracted\`.

**Script:** `LiteDeploy.SyncOEMDrivers.ps1`  
**Design:** [LITEDEPLOY_OEM_CATALOG_SYNC.md](../../../docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md)

## Supported OEMs (online catalog)

**Dell, HP, Lenovo only.** Surface is out of scope.

## Modes

### Check status (shell table)

Compares **local version** vs **online pack version** and outlines newer packs:

```powershell
.\LiteDeploy.SyncOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -CheckStatus
```

Table columns include `LocalVersion`, `OnlineVersion`, `OnlineDate`, `Status`.  
Rows with `UpdateAvailable` are also printed in a **Newer packs online** section.

Optional allow-list CSV to surface SKUs not yet in your catalog:

```powershell
.\LiteDeploy.SyncOEMDrivers.ps1 `
  -DeploymentRoot "D:\DeploymentShare" `
  -CheckStatus `
  -ManufacturerName "Dell" `
  -ModelsCsvPath "..\ImportOEMDrivers\Examples\Dell-SupportedModels.csv"
```

| Status | Meaning |
| --- | --- |
| `Current` | Local pack version/date is current vs vendor pack catalog |
| `UpdateAvailable` | Newer pack online — table shows `OnlineVersion` / `OnlineDate` |
| `MissingContent` | Catalog row exists; `Extracted` empty/missing |
| `MissingFromVendor` | Local SKU not found in vendor pack catalog |
| `NewInAllowList` | CSV SKU in vendor catalog but not in our share yet |
| `NoVendorIndex` | Pack catalog missing/failed for that OEM |
| `WinPeModel` | Manufacturer WinPE model (not compared to FullOS packs) |

### Update

```powershell
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -UpdateAll -ManufacturerName Dell -Force
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Model "Latitude 7450" -Force
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -SystemSku "0C09" -Force
```

Updates call `ImportOEMDrivers` with the model’s stored `downloadLink` → download pack → extract into FullOS model `Extracted\`.

## Vendor pack catalog cache

Under `Content\Temp\OemCatalogs\` (refresh if older than 7 days, or `-RefreshCatalog`):

| OEM | Sources |
| --- | --- |
| Dell | `DriverPackCatalog.cab` (versions) + `CatalogIndexPC.cab` |
| HP | `HPClientDriverPackCatalog.cab` (versions) + `platformList.cab` |
| Lenovo | `catalogv2.xml` (SCCM pack version/date/url) |
