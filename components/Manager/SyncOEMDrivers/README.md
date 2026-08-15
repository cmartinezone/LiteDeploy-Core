# SyncOEMDrivers

LiteDeployManager tool that refreshes Dell/HP/Lenovo **driver pack** catalogs, compares pack **versions** to your share’s `Content/Drivers/catalog.json`, and can download/replace packs.

**Script:** `LiteDeploy.SyncOEMDrivers.ps1`  
**Design:** [LITEDEPLOY_OEM_CATALOG_SYNC.md](../../../docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md)

## Supported OEMs (online catalog)

**Dell, HP, Lenovo only.** Surface is out of scope.

## Modes

### Check status (compare + show only)

```powershell
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -CheckStatus
```

Shows `LocalVersion` vs `OnlineVersion` / `OnlineDate`. Does **not** download.

| Status | Meaning |
| --- | --- |
| `Current` | Local pack is current |
| `UpdateAvailable` | Newer pack online |
| `MissingContent` | Catalog row exists; `Extracted` empty/missing |
| `MissingFromVendor` | SKU not in vendor pack catalog |
| `NewInAllowList` | CSV SKU online but not in our share yet |
| `WinPeModel` | Manufacturer WinPE model (not FullOS pack compare) |

### Update (download + replace + update catalog)

Resolves pack URL from the OEM catalog when needed, downloads into the model folder, replaces `Extracted\`, and upserts `catalog.json` (version + `downloadLink`) via `ImportOEMDrivers`.

```powershell
# All models with UpdateAvailable
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -UpdateAll -Force

# One model
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Model "Latitude 7450" -Force

# One SKU
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -SystemSku "0C09" -Force
```

## Vendor pack catalog cache

Under `Content\Temp\OemCatalogs\` (refresh if older than 7 days, or `-RefreshCatalog`):

| OEM | Sources |
| --- | --- |
| Dell | `DriverPackCatalog.cab` (versions) + `CatalogIndexPC.cab` |
| HP | `HPClientDriverPackCatalog.cab` (versions) + `platformList.cab` |
| Lenovo | `catalogv2.xml` (SCCM pack version/date/url) |
