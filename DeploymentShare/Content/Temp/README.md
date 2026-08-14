# Content\Temp

Scratch area for Manager downloads and extracts. Not published as deployment content.

```text
Content\Temp\
  ImportOEMDrivers\
    <ManufacturerName>\
      <ModelId>\
        Download\     ← pack .cab / .exe from -DownloadLink
        Extracted\    ← CAB expand staging before promote to Drivers\...\Extracted
  OemCatalogs\        ← vendor catalog CAB/XML cache (Dell / HP / Lenovo / Surface) — not built yet
```

`ImportOEMDrivers` downloads online packs here, extracts CABs here, then copies the driver tree into `Content\Drivers\<Manufacturer>\<Model>\Extracted` (and optional `WinPE`).

OEM **index** catalog sync (learn-from-FFU design): [LITEDEPLOY_OEM_CATALOG_SYNC.md](../../../docs/architecture/LITEDEPLOY_OEM_CATALOG_SYNC.md).
