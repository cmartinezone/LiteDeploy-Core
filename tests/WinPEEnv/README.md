# WinPE layout emulator

A **generated** tree that looks like production WinPE + a loaded deployment source. Source of truth stays in `components/` and `DeploymentShare/`. Re-run sync after you change those.

This is **not** MiniNT. There is no RAM disk `X:` as `SystemDrive`, no USB bus, and no WPF on the Linux Cloud Agent. It is the promote layout + BootConfig split so a Windows workstation can run BootInitializer → engine the same way `startnet.cmd` will.

## Layout

```text
tests/WinPEEnv/
  BootWim/Config/BootConfig.json     ← bootstrap (Type / LocalRootName only)
  Share/                             ← subst this as Z: (loaded USB / share)
    Config/BootConfig.json           ← full runtime policy
    Content/                         ← copied from DeploymentShare/Content
    WorkFlows/                       ← copied from DeploymentShare/WorkFlows
    Engine/Scripts/                  ← copied Runtime + OemDriverPackCatalog.ps1
```

| Real WinPE | This harness |
| --- | --- |
| `X:\~LiteDeploy\Config\BootConfig.json` (bootstrap) | `BootWim/Config/BootConfig.json` |
| USB or `Z:\` with `Content\` | `Share\` after `subst Z:` |
| `Engine\Scripts\` siblings | `Share/Engine/Scripts\` after sync |
| `startnet` → `powershell.exe -STA` | `Start-WinPETestEnv.ps1` |

Default `Share/Config/BootConfig.json` is **Media** with online OEM download **off**, so a lab run does not prompt for share credentials or hit Dell/HP/Lenovo.

## After every component change

```powershell
cd tests\WinPEEnv
.\Sync-WinPETestEnv.ps1
```

Linux / this Cloud Agent:

```bash
./tests/WinPEEnv/Sync-WinPETestEnv.sh
```

## Run on a Windows box

```powershell
cd tests\WinPEEnv
.\Start-WinPETestEnv.ps1
```

That syncs, `subst Z:` → `Share`, then:

```text
powershell.exe -STA -File Z:\Engine\Scripts\LiteDeploy.BootInitilizer.ps1 `
  -ExplicitConfigPath Z:\Config\BootConfig.json -ShowGuiError
```

`Z:` must be a **drive** (not `D:\repo\tests\WinPEEnv\Share`). Media promotion keys off the config drive letter and looks for `Z:\Config\BootConfig.json` + `Z:\Content\`. A long repo path can wildcard-match the wrong `*\Config\BootConfig.json`.

If `Z:` is taken: `.\Start-WinPETestEnv.ps1 -DriveLetter W`

Remove the mapping when finished: `subst Z: /d`

## What this proves

- Scripts resolve as siblings under `Engine\Scripts`
- Runtime BootConfig is the **Share** file, not the BootWim bootstrap
- `BootObject.DeploymentRoot` is `Z:\` (folder that contains `Content\`)
- PreCheck / SelectWorkflow open (WPF) on Windows
- Engine writes `~\LiteDeploy\State\` on the **host** `SystemDrive` (usually `C:`), not a fake `X:`

## What this does not prove

- `HKLM\...\MiniNT` / `wpeinit` / real `X:` RAM disk
- USB/CD volume discovery (`Get-Volume` Removable)
- Share `Get-Credential` + SMB `Z:` (use Type `Network` and a real UNC if you need that)
- Hardware SKU / TPM / Secure Boot as they appear in WinPE
- Setup.exe / disk wipe (engine Phase A still stops after selection)

## Network mode (optional)

1. Point `BootWim/Config/BootConfig.json` at `Type: Network` and a UNC.
2. Keep `subst Z:` so `Connect-LiteDeployDeploymentShare` can take the “already mapped” fast path **after** SMB 445 to that UNC succeeds.
3. If 445 fails, you get the real network error — that is useful, not a harness bug.

Do not put passwords in these JSON files.
