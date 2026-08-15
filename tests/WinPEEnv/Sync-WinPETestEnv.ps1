<#
.SYNOPSIS
    Promote Core Runtime/Shared scripts and the DeploymentShare skeleton into tests/WinPEEnv.

.DESCRIPTION
    Copies the production Engine\Scripts set and the share Content/WorkFlows
    catalogs into the WinPE layout emulator. Source of truth stays under
    components/ and DeploymentShare/. Re-run after component changes.

    Does not overwrite Share\Config\BootConfig.json or BootWim\Config\BootConfig.json.

.PARAMETER RepoRoot
    LiteDeploy-Core repository root. Default: parent of tests/.

.EXAMPLE
    .\Sync-WinPETestEnv.ps1
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$envRoot = Join-Path $RepoRoot "tests\WinPEEnv"
$shareRoot = Join-Path $envRoot "Share"
$scriptsRoot = Join-Path $shareRoot "Engine\Scripts"

if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot "components\Runtime") -PathType Container)) {
    throw "RepoRoot does not look like LiteDeploy-Core: $RepoRoot"
}

function Copy-PromotedFile {
    param(
        [string]$Source,
        [string]$DestinationDir,
        [string]$FileName = ""
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        Write-Warning "Skip missing source: $Source"
        return $false
    }
    if (-not (Test-Path -LiteralPath $DestinationDir)) {
        $null = New-Item -Path $DestinationDir -ItemType Directory -Force
    }
    $leaf = if ($FileName) { $FileName } else { Split-Path -Leaf $Source }
    Copy-Item -LiteralPath $Source -Destination (Join-Path $DestinationDir $leaf) -Force
    return $true
}

function Copy-Tree {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-Warning "Skip missing tree: $Source"
        return
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -Path $parent -ItemType Directory -Force
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

$null = New-Item -Path $scriptsRoot -ItemType Directory -Force
$null = New-Item -Path (Join-Path $shareRoot "WorkLogs") -ItemType Directory -Force
$null = New-Item -Path (Join-Path $shareRoot "Engine\Tools") -ItemType Directory -Force

$runtime = Join-Path $RepoRoot "components\Runtime"
$copied = 0
$scriptMap = @(
    @{ Src = "BootInitializer\LiteDeploy.BootInitilizer.ps1" },
    @{ Src = "DeploymentEngine\LiteDeploy.DeploymentEngine.ps1" },
    @{ Src = "PreCheck\LiteDeploy.PreCheck.ps1" },
    @{ Src = "SelectWorkflow\LiteDeploy.SelectWorkFlow.ps1" },
    @{ Src = "SelectWorkflow\LiteDeploy.SelecWorkflowDriverPicker.ps1" },
    @{ Src = "UiHost\LiteDeploy.UiHost.ps1" },
    @{ Src = "Progress\LiteDeploy.Progress.ps1" },
    @{ Src = "HostShell\LiteDeploy.HostShell.ps1" },
    @{ Src = "LogWriter\LiteDeploy.LogWriter.ps1" }
)

foreach ($item in $scriptMap) {
    $src = Join-Path $runtime $item.Src
    if (Copy-PromotedFile -Source $src -DestinationDir $scriptsRoot) { $copied++ }
}

$oemLib = Join-Path $RepoRoot "components\Shared\OemDriverPacks\LiteDeploy.OemDriverPackCatalog.ps1"
if (Copy-PromotedFile -Source $oemLib -DestinationDir $scriptsRoot) { $copied++ }

Copy-Tree -Source (Join-Path $RepoRoot "DeploymentShare\Content") -Destination (Join-Path $shareRoot "Content")
Copy-Tree -Source (Join-Path $RepoRoot "DeploymentShare\WorkFlows") -Destination (Join-Path $shareRoot "WorkFlows")

Write-Host " [WinPEEnv] Promoted $copied scripts → $scriptsRoot" -ForegroundColor Green
Write-Host " [WinPEEnv] Share root             : $shareRoot" -ForegroundColor Cyan
Write-Host " [WinPEEnv] Bootstrap BootConfig   : $(Join-Path $envRoot 'BootWim\Config\BootConfig.json')" -ForegroundColor Cyan
Write-Host " [WinPEEnv] Runtime BootConfig     : $(Join-Path $shareRoot 'Config\BootConfig.json')" -ForegroundColor Cyan
Write-Host " [WinPEEnv] Next: .\Start-WinPETestEnv.ps1   (Windows, subst Z: + STA)" -ForegroundColor DarkCyan
