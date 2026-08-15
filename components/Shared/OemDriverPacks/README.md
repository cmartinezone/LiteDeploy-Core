# Shared OemDriverPacks

Reusable Dell / HP / Lenovo **driver-pack catalog** helpers shared by Manager and Media runtime.

**Script:** `LiteDeploy.OemDriverPackCatalog.ps1`

| Consumer | Role |
| --- | --- |
| [SyncOEMDrivers](../../Manager/SyncOEMDrivers/) | Manager: `-CheckStatus` / `-Update All\|Model\|sku` |
| [SelectWorkflow](../../Runtime/SelectWorkflow/) | Media: download missing pack / optional update alert |

## What the library provides

| Function area | Purpose |
| --- | --- |
| `Update-OemVendorIndexes` | Refresh Dell/HP/Lenovo indexes under `Content\Temp\OemCatalogs\` (optional `-VendorFamily` to refresh one OEM) |
| `Get-VendorPackMaps` | Parse pack version / URL / SKU maps |
| `Test-OnlinePackNewer` | Compare local vs online version/date |
| `Resolve-PackFromVendorMap` | Best pack URL for a model’s SystemSKU list |
| `Get-SystemHardwareIdentity` | WMI manuf / model / SystemSKU / BaseBoard / MTM |
| `Find-LocalMediaDriverModel` | Match `catalog.json` (SKU or name) or folder path |
| `Invoke-MediaOemDriverPackAction` | Media ensure / check-update / force download |

Override `Write-OemPackLog` before dot-sourcing to redirect logging (SyncOEMDrivers does this).

## Media behavior (`Invoke-MediaOemDriverPackAction`)

Requires `Deployment.Type = Media` policies in BootConfig (enforced by SelectWorkflow):

- `Drivers.AutoOnlineDownloadOnMedia` — download when pack missing  
- `Drivers.CheckOnlineUpdateOnMedia` — when folder exists, compare and **alert** (Dell/HP/Lenovo only)

| Condition | Result |
| --- | --- |
| Model folder exists with content, no `-CheckUpdate` | `SkippedExisting` (use local) |
| Model folder exists + `-CheckUpdate` (Dell/HP/Lenovo) | `Current` or `UpdateAvailable` (alert only; no silent replace) |
| Missing / empty + online | Download pack → extract CAB to `Extracted\` → upsert `catalog.json` |
| `-ForceDownload` | Replace even when local exists (after UI confirm) |
| Other OEMs | `CompareNotSupported` |

Match keys: SystemSKU / BaseBoardProduct / Lenovo MTM (first 4), plus model name via `catalog.json` or folder path.

## Layout (same as Manager)

```text
Content\Temp\OemCatalogs\<Dell|HP|Lenovo>\...
Content\Drivers\<ManufacturerName>\
  WinPE\Extracted\
  <Model>\Extracted\
```

## Related

- [LITEDEPLOY_OEM_CATALOG_SYNC.md](../../../docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md)  
- [LITEDEPLOY_DRIVERS_CATALOG.md](../../../docs/architecture/LITEDEPLOY_DRIVERS_CATALOG.md)  
