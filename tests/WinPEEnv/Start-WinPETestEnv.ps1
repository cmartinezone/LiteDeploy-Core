<#
.SYNOPSIS
    Sync the WinPE layout emulator and launch BootInitializer against it.

.DESCRIPTION
    Workstation stand-in for startnet.cmd:
      1. Promote components into Share\Engine\Scripts
      2. subst <DriveLetter> → Share  (so DeploymentRoot is a drive, not the repo root)
      3. powershell.exe -STA BootInitializer -ExplicitConfigPath <drive>\Config\BootConfig.json

    Default BootConfig Type is Media, so there is no share-credential prompt.
    This is not MiniNT WinPE: WMI, USB enumeration, and SystemDrive stay on the host OS.

.PARAMETER DriveLetter
    Letter used for the emulated loaded environment (USB/share). Default Z:.

.PARAMETER SkipSync
    Do not re-copy components (use existing Share\Engine\Scripts).

.PARAMETER SkipSubst
    Do not subst; pass the long Share\Config\BootConfig.json path (promotion may be weaker).

.EXAMPLE
    .\Start-WinPETestEnv.ps1
#>

[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z]$')]
    [string]$DriveLetter = "Z",

    [switch]$SkipSync,
    [switch]$SkipSubst
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$onWindows = $false
if ($env:OS -match 'Windows') { $onWindows = $true }
elseif (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) { $onWindows = [bool]$IsWindows }
if (-not $onWindows) {
    throw "Start-WinPETestEnv.ps1 must run on Windows (subst + powershell.exe -STA + WPF)."
}

$envRoot = $PSScriptRoot
$syncScript = Join-Path $envRoot "Sync-WinPETestEnv.ps1"
$shareRoot = Join-Path $envRoot "Share"

if (-not $SkipSync) {
    & $syncScript
}

$engine = Join-Path $shareRoot "Engine\Scripts\LiteDeploy.BootInitilizer.ps1"
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
    throw "BootInitializer not found. Run Sync-WinPETestEnv.ps1 first: $engine"
}

$letter = $DriveLetter.TrimEnd(':').ToUpperInvariant()
$drive = "${letter}:"
$configPath = Join-Path $shareRoot "Config\BootConfig.json"

if (-not $SkipSubst) {
    $shareResolved = (Resolve-Path -LiteralPath $shareRoot).Path
    if (Test-Path -LiteralPath "$drive\") {
        $existing = $null
        try { $existing = (Get-PSDrive -Name $letter -ErrorAction SilentlyContinue).Root } catch {}
        if ($existing -and -not [string]::Equals($existing.TrimEnd('\'), $shareResolved.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
            throw "$drive is already in use ($existing). Pass -DriveLetter or subst /d $drive"
        }
    }
    else {
        subst.exe $drive $shareResolved
        if ($LASTEXITCODE -ne 0) {
            throw "subst $drive $shareResolved failed (exit $LASTEXITCODE)."
        }
        Write-Host " [WinPEEnv] subst $drive → $shareResolved" -ForegroundColor Green
    }
    $configPath = "$drive\Config\BootConfig.json"
}

Write-Host " [WinPEEnv] ExplicitConfigPath = $configPath" -ForegroundColor Cyan
Write-Host " [WinPEEnv] Launching STA BootInitializer (Ctrl+C in this window after the UI closes)..." -ForegroundColor Cyan

$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path -LiteralPath $powershell)) {
    $powershell = "powershell.exe"
}

& $powershell -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -File $engine -ExplicitConfigPath $configPath -ShowGuiError
