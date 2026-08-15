# Run the WinPE layout test from Windows

This guide is for a **Windows 10/11 workstation**. It launches the same chain WinPE will use (`BootInitializer` → `DeploymentEngine` → PreCheck → SelectWorkflow) against a local copy of the share layout.

You do **not** need a real WinPE ISO for this test. You **do** need Windows PowerShell 5.1 and a desktop session (WPF windows).

Related: [README.md](README.md) (layout and limits).

---

## 1. What you need

| Requirement | Notes |
| --- | --- |
| Windows 10 or 11 | Full OS, not WinPE, not this Linux Cloud Agent |
| Windows PowerShell 5.1 | `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` — **not** PowerShell 7 (`pwsh`) for the launch |
| A clone of LiteDeploy-Core | Branch `dev`, or `cursor/winpe-test-env-bd4d` until that PR is merged |
| Administrator **not** required | `subst` works as a normal user if the drive letter is free |

Do not use Windows Terminal’s PowerShell 7 profile as the **launcher** if you can avoid it. `Start-WinPETestEnv.ps1` starts 5.1 with `-STA` itself. You can open the script from either host.

---

## 2. Get the repo

In **Windows PowerShell** or Windows Terminal:

```powershell
git clone https://github.com/cmartinezone/LiteDeploy-Core.git
cd LiteDeploy-Core
git checkout dev
git pull origin dev
```

If the WinPEEnv PR is not on `dev` yet:

```powershell
git fetch origin cursor/winpe-test-env-bd4d
git checkout cursor/winpe-test-env-bd4d
```

Note the repo path (for example `C:\src\LiteDeploy-Core`).

---

## 3. Allow local scripts (once per machine)

If you see “running scripts is disabled”:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

The start script also passes `-ExecutionPolicy Bypass` to the STA child, so this is only for running `Start-WinPETestEnv.ps1` itself.

---

## 4. Sync, then start

```powershell
cd C:\src\LiteDeploy-Core\tests\WinPEEnv

# Copy components\ + DeploymentShare\ into Share\
.\Sync-WinPETestEnv.ps1

# subst Z: → Share, then launch BootInitializer in STA
.\Start-WinPETestEnv.ps1
```

`Start-WinPETestEnv.ps1` runs sync again unless you pass `-SkipSync`. First-time or after any `.ps1` edit: let it sync.

Expected console lines:

```text
 [WinPEEnv] Promoted 10 scripts → ...\Share\Engine\Scripts
 [WinPEEnv] subst Z: → C:\src\LiteDeploy-Core\tests\WinPEEnv\Share
 [WinPEEnv] ExplicitConfigPath = Z:\Config\BootConfig.json
 [WinPEEnv] Launching STA BootInitializer ...
```

Confirm the mapping:

```powershell
Get-PSDrive Z
dir Z:\Engine\Scripts
dir Z:\Config\BootConfig.json
dir Z:\Content\Drivers
```

---

## 5. What should appear

Default harness config is **Media** (no share password) with online OEM download **off**.

1. **BootInitializer** (console) — finds `Z:\Config\BootConfig.json`, promotes it as the runtime config, sets `DeploymentRoot` to `Z:\`, starts the engine.
2. **PreCheck** (WPF) — hardware / config checks against this PC. Click **Continue** if the result is acceptable. Cancel stops the engine; no disk changes.
3. **SelectWorkflow** (WPF) — computer name, Standard / Intune (hardcoded tags), disk, drivers. Click **Start Deployment**, then **Yes** on the summary.
4. **Engine stub** — writes state JSON and **stops**. Setup.exe does not run. Disks are not wiped.

That is a successful Phase A test.

---

## 6. What to check after a run

| Check | Where |
| --- | --- |
| Runtime config used | PreCheck “Configuration:” line should show `Z:\Config\BootConfig.json`, not a file under `X:\` or `components\` |
| Scripts are siblings | `Z:\Engine\Scripts\LiteDeploy.DeploymentEngine.ps1` next to PreCheck / SelectWorkflow |
| Deployment root | Console log `DeploymentRoot : Z:\` (or `Z:\` with `Content\`) |
| Selection / state | `%SystemDrive%\~LiteDeploy\State\DeploymentSelection.json` and `DeploymentState.json` (usually `C:\~LiteDeploy\State\`) |
| BootInitializer log | `%SystemDrive%\~LiteDeploy\WorkLogs\LiteDeploy.Execution.log` (CMTrace) and `.json` |

Open `DeploymentSelection.json` and confirm `deploymentRoot` is `Z:\` (or `Z:\` resolved path) and `deploymentType` is `Media`. There must be **no** password or `PSCredential` in that file.

---

## 7. After you change code

Edit files under `components\`, not under `Share\Engine\Scripts\` (those copies are overwritten).

```powershell
cd C:\src\LiteDeploy-Core\tests\WinPEEnv
.\Sync-WinPETestEnv.ps1
.\Start-WinPETestEnv.ps1
```

Or just `.\Start-WinPETestEnv.ps1` (it syncs first).

---

## 8. When you are done

Leave the mapping if you will test again today. To remove it:

```powershell
subst Z: /d
```

State and logs on `C:\~LiteDeploy\` are from the host OS. Delete that folder if you do not want leftover test JSON.

---

## 9. Common problems

| Symptom | What to do |
| --- | --- |
| `Z: is already in use` | `subst Z: /d` or `.\Start-WinPETestEnv.ps1 -DriveLetter W` |
| `subst ... failed` | Another app owns the letter; pick `-DriveLetter` that `Get-PSDrive` does not list |
| PreCheck / SelectWorkflow never opens | Confirm the console used `powershell.exe -STA`. The start script does this; do not launch `BootInitilizer.ps1` from `pwsh` |
| “UiHost … STA … BootObject” throw | Parent was MTA. Always use `Start-WinPETestEnv.ps1`, not a raw `-File` without `-STA` |
| Configuration path is under `components\` or the repo | You skipped `subst` or used `-SkipSubst`. Re-run without `-SkipSubst` so the path is `Z:\Config\...` |
| `BootInitializer not found` | Run `.\Sync-WinPETestEnv.ps1` and check `Share\Engine\Scripts` has 10 `.ps1` files |
| Credential prompt | `Share\Config\BootConfig.json` was changed to `Type: Network`. Default Media does not prompt. The dialog is built into BootInitializer (the share / UiHost is not available yet). Optional `Ui.Theme` (`Light` or `Dark`) on the bootstrap BootConfig paints the dialog; default is Light. |
| OEM download / vendor websites | Default `AutoOnlineDownloadOnMedia` / `CheckOnlineUpdateOnMedia` are `false`. Do not turn them on unless you want live Dell/HP/Lenovo traffic |
| PreCheck fails TPM / firmware | Normal on a VM or older PC. You can still Continue unless you treat that as a fail for your test |
| Nothing images the disk | Expected. Phase B (Setup) is not implemented |

---

## 10. Optional: run the two steps by hand

```powershell
cd C:\src\LiteDeploy-Core\tests\WinPEEnv
.\Sync-WinPETestEnv.ps1

subst Z: (Resolve-Path .\Share).Path

& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
  -STA -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File Z:\Engine\Scripts\LiteDeploy.BootInitilizer.ps1 `
  -ExplicitConfigPath Z:\Config\BootConfig.json `
  -ShowGuiError
```

Do not pass `C:\src\...\Share\Config\BootConfig.json` as the only config path if you can use `Z:\`. Promotion is written for a **drive** that contains `Content\`.

---

## 11. What this test is not

- Not MiniNT / `wpeinit` / a RAM-disk `X:`
- Not USB stick discovery
- Not a real SMB share login (unless you change Type to Network and supply a UNC)
- Not Setup.exe or a disk wipe

For those, use a WinPE ISO from [WinPEBuilder](https://github.com/cmartinezone/WinPEBuilder) and copy the same `Engine\Scripts` set onto the boot image / share.
