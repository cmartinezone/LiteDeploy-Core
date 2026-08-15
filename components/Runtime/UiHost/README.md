# UiHost — shared WPF chrome for LiteDeploy

**Script:** `LiteDeploy.UiHost.ps1`  
**Plan:** [LITEDEPLOY_UI_HOST.md](../../../docs/architecture/LITEDEPLOY_UI_HOST.md)

Dot-sourced toolkit used by PreCheck, SelectWorkflow, and Progress. It does **not** replace those screens.

## What it shares

| Helper | Purpose |
| --- | --- |
| `Initialize-LiteDeployUiHost` | WPF assemblies, software rendering, optional STA guard |
| `Get-LiteDeployUiThemePalette` | Light/Dark hex (+ optional brushes) |
| `Get-LiteDeployUiWindowSize` | Adaptive 4:3 window size for Viewbox hosts |
| `Get-LiteDeployUiButtonStyleXaml` | Primary/secondary button Style fragments |
| `Show-LiteDeployUiMessage` | WinForms or WPF message box |
| `Show-LiteDeployCredentialPrompt` | Get-Credential-style share prompt (Viewbox + show password); returns `PSCredential` |
| `New-LiteDeployUiBackdrop` / `Close-LiteDeployUiBackdrop` | Full-screen backdrop |
| `ConvertTo-LiteDeployUiBrush` | Hex → WPF brush |
| `Find-LiteDeployUiControl` | Named control lookup |

## What stays separate

- PreCheck assessment logic and layout
- SelectWorkflow selection logic and layout
- Progress FullOS/WinPE layouts and `DeploymentState.json` polling

## Production layout

```text
Engine\Scripts\
  LiteDeploy.UiHost.ps1          # sibling of the UI scripts
  LiteDeploy.PreCheck.ps1
  LiteDeploy.SelectWorkFlow.ps1
  LiteDeploy.Progress.ps1
```

## Usage

```powershell
$uiHost = Join-Path $PSScriptRoot "LiteDeploy.UiHost.ps1"
if (-not (Test-Path -LiteralPath $uiHost)) {
    $uiHost = Join-Path $PSScriptRoot "..\UiHost\LiteDeploy.UiHost.ps1"
}
. $uiHost

$null = Initialize-LiteDeployUiHost -RequireWindowsForms
$palette = Get-LiteDeployUiThemePalette -Theme Light
$size = Get-LiteDeployUiWindowSize
```
