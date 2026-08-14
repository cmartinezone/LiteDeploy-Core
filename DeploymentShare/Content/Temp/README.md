# Content\Temp

Scratch area for Manager downloads and extracts. Not published as deployment content.

```text
Content\Temp\
  ImportOEMDrivers\
    <ManufacturerName>\
      <ModelId>\
        Download\     ← pack .cab / .exe from -DownloadLink
        Extracted\    ← CAB expand staging before promote to Drivers\...\Extracted
  OemCatalogs\        ← future vendor catalog CAB/XML (Dell / HP / Lenovo / Surface)
```

`ImportOEMDrivers` downloads online packs here, extracts CABs here, then copies the driver tree into `Content\Drivers\<Manufacturer>\<Model>\Extracted` (and optional `WinPE`).
