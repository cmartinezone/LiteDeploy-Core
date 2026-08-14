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

`ImportOEMDrivers` downloads online packs here, extracts CABs here, then copies into `Content\Drivers\<Manufacturer>\<Model>\Extracted`. The manufacturer WinPE **model** publishes to `Content\Drivers\<Manufacturer>\WinPE\Extracted`.

`SyncOEMDrivers` refreshes `OemCatalogs\`, runs `-CheckStatus` (shell table vs `catalog.json`), and `-UpdateAll` / `-Model` / `-SystemSku`. Design: [LITEDEPLOY_OEM_CATALOG_SYNC.md](../../../docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md).
