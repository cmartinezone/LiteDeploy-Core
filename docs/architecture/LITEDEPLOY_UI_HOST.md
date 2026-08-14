# LiteDeploy Shared WPF UI Host

Status: **Adopted on the engine-orchestration test branch.**  
Shared chrome only — not a merge of PreCheck, SelectWorkflow, and Progress.

## Goal

Reduce duplicated WPF bootstrap (themes, buttons, STA/assemblies, backdrop, messages) while keeping three separate entry scripts with different jobs and lifetimes.

```text
LiteDeploy.UiHost.ps1          Shared toolkit (dot-sourced)
    ├── LiteDeploy.PreCheck.ps1           Returns structured PreCheck result
    ├── LiteDeploy.SelectWorkFlow.ps1     Returns structured selection
    └── LiteDeploy.Progress.ps1           Separate read-only process / state reader
```

## Why not one UI script?

| Concern | Shared toolkit | Single merged UI |
| --- | --- | --- |
| Readability | Each screen stays focused | Mega-file mixes three domains |
| Process model | Progress can stay a separate process | Harder to keep Progress isolated |
| Engine contracts | Structured returns stay clear | Easy to re-couple Continue → next screen |
| Testing | Theme/helpers unit-testable | Must drive full wizard to test chrome |

## Shared responsibilities (`components/Runtime/UiHost`)

1. WPF assembly load + WinPE software rendering  
2. Optional STA relaunch guard (never when `BootObject` is bound)  
3. Light/Dark theme palette (hex + brushes)  
4. Adaptive window size for Viewbox hosts  
5. Primary/secondary button Style XAML fragments  
6. Message box helper (WinForms with WPF fallback)  
7. Backdrop helper  

## Not shared

- Assessment checks (PreCheck)
- Disk / workflow / driver selection (SelectWorkflow)
- `DeploymentState.json` schema and progress layouts (Progress)
- Console geometry (HostShell)

## Production promotion

Copy `LiteDeploy.UiHost.ps1` to `Engine\Scripts\` beside the UI scripts. Callers resolve:

1. `$PSScriptRoot\LiteDeploy.UiHost.ps1` (production)
2. `$PSScriptRoot\..\UiHost\LiteDeploy.UiHost.ps1` (Core repo: components/Runtime/UiHost)

## Related

- [NATIVE_HOST_DOCUMENTATION.md](../../components/Runtime/Progress/NATIVE_HOST_DOCUMENTATION.md) — Progress-specific host behavior  
- [LITEDEPLOY_DEPLOYMENT_PLAN.md](LITEDEPLOY_DEPLOYMENT_PLAN.md) — engine orchestration and UI return contracts  
