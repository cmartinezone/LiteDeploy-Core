# SyncOEMDrivers

LiteDeployManager tool that refreshes Dell/HP/Lenovo **driver pack** catalogs, compares pack **versions** to your share’s `Content/Drivers/catalog.json`, and can download/replace packs.

**Script:** `LiteDeploy.SyncOEMDrivers.ps1`  
**Shared library:** [`../../Shared/OemDriverPacks/`](../../Shared/OemDriverPacks/) (same helpers used by Media SelectWorkflow)  
**Design:** [LITEDEPLOY_OEM_CATALOG_SYNC.md](../../../docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md)

## Supported OEMs (online catalog)

**Dell, HP, Lenovo only.** Surface is out of scope for online sync.  
Manual import via [ImportOEMDrivers](../ImportOEMDrivers/) still works for any manufacturer folder you create.

## Typical workflow

```text
1. ImportOEMDrivers -ModelsCsvPath   → register supported models + WinPE (empty Extracted)
2. SyncOEMDrivers -CheckStatus       → LocalVersion vs OnlineVersion table
3. SyncOEMDrivers -Update All -Force → download newer packs → replace Extracted → catalog.json
```

## Modes

### Check status (compare + show only)

```powershell
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -CheckStatus

.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -CheckStatus `
  -ManufacturerName "Dell" `
  -ModelsCsvPath "..\ImportOEMDrivers\Examples\Dell-SupportedModels.csv"
```

Shows `LocalVersion` vs `OnlineVersion` / `OnlineDate`. Does **not** download.  
With `-ModelsCsvPath`, also surfaces `NewInAllowList` (CSV SKU online but not in the share yet).

### Update (download + replace + update catalog)

```powershell
# All models with a newer pack online
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Update All -Force

# One model (name or modelId)
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Update "Latitude 7450" -Force

# One SystemSKU / Machine Type
.\LiteDeploy.SyncOEMDrivers.ps1 -DeploymentRoot "D:\DeploymentShare" -Update "0C09" -Force
```

Resolves pack URL from the OEM catalog when `downloadLink` is missing → downloads via ImportOEMDrivers → replaces `Extracted\` → upserts `catalog.json`.

`-Update All` targets FullOS models with `UpdateAvailable` (or missing content with a catalog URL).  
A non-`All` value matches **model name / modelId first**, then SystemSKU.  
Optional: `-ManufacturerName Dell` to scope. `-Force` replaces existing `Extracted\` content.

| Status (from check) | Meaning |
| --- | --- |
| `Current` | Local pack is current |
| `UpdateAvailable` | Newer pack online |
| `MissingContent` | Catalog row exists; `Extracted` empty/missing |
| `MissingFromVendor` | SKU not in vendor pack catalog |
| `NewInAllowList` | CSV SKU online but not in our share yet |
| `WinPeModel` | Manufacturer WinPE model (not FullOS pack compare) |
| `NoVendorIndex` | Vendor pack catalog not available for that manufacturer |

## Vendor pack catalog cache

Under `Content\Temp\OemCatalogs\` (refresh if older than 7 days, or `-RefreshCatalog`).  
`-ManufacturerName Dell` (etc.) refreshes **that OEM’s** indexes only.

| OEM | Pack version source | Also cached | Match key |
| --- | --- | --- | --- |
| Dell | `DriverPackCatalog.cab` | `CatalogIndexPC.cab` | SystemSKU |
| HP | `HPClientDriverPackCatalog.cab` | `platformList.cab` | BaseBoardProduct |
| Lenovo | `catalogv2.xml` (SCCM pack nodes) | — | Machine Type (MTM first 4) |

## Related

- [ImportOEMDrivers](../ImportOEMDrivers/) — CSV scaffold + local/`-DownloadLink` import  
- [Shared OemDriverPacks](../../Shared/OemDriverPacks/) — reusable catalog parse / compare / media download  
- [SelectWorkflow](../../Runtime/SelectWorkflow/) — Media auto-download + optional update alert  
