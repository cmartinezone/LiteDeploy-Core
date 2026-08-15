# Shared OemDriverPacks

Reusable Dell / HP / Lenovo **driver-pack catalog** helpers for:

| Consumer | Role |
| --- | --- |
| [SyncOEMDrivers](../../Manager/SyncOEMDrivers/) | Manager: `-CheckStatus` / `-Update All\|Model\|sku` |
| [SelectWorkflow](../../Runtime/SelectWorkflow/) | Media: download missing pack / optional update alert |

**Script:** `LiteDeploy.OemDriverPackCatalog.ps1`

## Media behavior (`Invoke-MediaOemDriverPackAction`)

| Condition | Result |
| --- | --- |
| Model folder exists with content, no `-CheckUpdate` | `SkippedExisting` (use local) |
| Model folder exists + `-CheckUpdate` (Dell/HP/Lenovo) | `Current` or `UpdateAvailable` (alert only; no silent replace) |
| Missing / empty + online | Download pack → extract CAB to `Extracted\` → upsert `catalog.json` |
| `-ForceDownload` | Replace even when local exists (after UI confirm) |
| Other OEMs | `CompareNotSupported` |

Match keys: SystemSKU / BaseBoardProduct / Lenovo MTM (first 4), plus model name via `catalog.json` or folder path.
