# Content\Temp

Scratch area for Manager downloads and extracts. Not published as deployment content.

```text
Content\Temp\
  ImportOEMDrivers\
    <ManufacturerName>\
      <ModelId>\
        Download\     ← pack .cab / .exe from -DownloadLink
        Extracted\    ← CAB expand staging before promote to Drivers\...\Extracted
  OemCatalogs\        ← vendor catalog CAB/XML cache (Dell / HP / Lenovo) via SyncOEMDrivers
```

`ImportOEMDrivers` downloads online packs here, extracts CABs here, then copies the driver tree into `Content\Drivers\<Manufacturer>\<Model>\Extracted` (and optional `WinPE`).

`SyncOEMDrivers` refreshes `OemCatalogs\`, runs `-CheckStatus` (shell table vs `catalog.json`), and `-UpdateAll` / `-Model` / `-SystemSku`. Design: [LITEDEPLOY_OEM_CATALOG_SYNC.md](../../../docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md).
