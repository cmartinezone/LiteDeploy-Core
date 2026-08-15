# Content\Temp

Scratch area for Manager downloads and extracts. Not published as deployment content.

```text
Content\Temp\
  ImportOEMDrivers\
    <ManufacturerName>\
      <ModelId>\
        Download\     ← pack .cab / .exe from -DownloadLink
        Extracted\    ← CAB expand staging before promote to Drivers\...\Extracted
  OemCatalogs\        ← vendor catalog CAB/XML cache (Dell / HP / Lenovo)
```

`ImportOEMDrivers` downloads online packs here, extracts CABs here, then copies into `Content\Drivers\<Manufacturer>\<Model>\Extracted`. The manufacturer WinPE **model** publishes to `Content\Drivers\<Manufacturer>\WinPE\Extracted`.

`SyncOEMDrivers` and Media SelectWorkflow refresh `OemCatalogs\` via the shared [OemDriverPacks](../../../components/Shared/OemDriverPacks/) library, then:

- Manager: `-CheckStatus` / `-Update All|"Model"|"sku"`
- Media: download missing pack onto local media, or alert if a newer Dell/HP/Lenovo pack exists

Design: [LITEDEPLOY_OEM_CATALOG_SYNC.md](../../../docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md).
