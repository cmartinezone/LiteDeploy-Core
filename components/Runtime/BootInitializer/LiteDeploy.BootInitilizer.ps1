<#
.SYNOPSIS
    LiteDeploy WinPE Initialization & BootConfig Discovery Engine.

.DESCRIPTION
    Discovers BootConfig.json using a 3-priority hierarchy, performs network pre-validations,
    prompts for share credentials with a local Viewbox-scaled WPF dialog (Get-Credential fallback),
    maps deployment share Z:\ persistently, and launches LiteDeploy.DeploymentEngine.ps1
    with the in-memory BootObject.

    Boot-time helpers (Write-LiteDeployLog, Show-LiteDeployCredentialPrompt) live in this
    script. The deployment share — and therefore UiHost / LogWriter — is not available
    until after Connect-LiteDeployDeploymentShare succeeds.

.NOTES
    Compatible with Set-StrictMode 2.0 and WinPE 5.1/10/11.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ExplicitConfigPath = "",

    [Parameter(Mandatory = $false)]
    [switch]$MountShare,

    [Parameter(Mandatory = $false)]
    [switch]$ShowGuiError
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

# ==============================================================================
# 1. HELPERS & GUI DIALOGS
# ==============================================================================

function Write-LiteDeployLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White,
        [string]$Component = "BootInitilizer",
        [switch]$NoConsole
    )
    if ($Message -and -not $NoConsole) {
        Write-Host $Message -ForegroundColor $ForegroundColor
    }
    try {
        $sysDrive = if ($env:SystemDrive) { $env:SystemDrive } else { "X:" }
        $logDir = Join-Path $sysDrive "~LiteDeploy\WorkLogs"
        if (-not (Test-Path -LiteralPath $logDir)) {
            $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue
        }
        $logFile = Join-Path $logDir "LiteDeploy.Execution.log"
        $cleanMsg = $Message.Trim()
        if (-not [string]::IsNullOrWhiteSpace($cleanMsg)) {
            $now = Get-Date
            $timeStr = $now.ToString("HH:mm:ss.fff") + "+000"
            $dateStr = $now.ToString("MM-dd-yyyy")
            $typeCode = switch ($Level.ToUpper()) {
                "ERROR" { "3" }
                "WARNING" { "2" }
                "RETRY" { "2" }
                default { "1" }
            }
            # Official Microsoft CMTrace.exe XML Log Structure
            $logEntry = "<![LOG[$cleanMsg]LOG]!><time=""$timeStr"" date=""$dateStr"" component=""$Component"" context="""" type=""$typeCode"" thread=""1"" file=""LiteDeploy.BootInitilizer.ps1"">"
            Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue

            # Modern Newline-Delimited JSON (NDJSON) Log Structure
            $jsonFile = Join-Path $logDir "LiteDeploy.Execution.json"
            $isoTimestamp = $now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            $jsonRecord = [ordered]@{
                timestamp = $isoTimestamp
                level     = $Level.ToUpper()
                type      = [int]$typeCode
                component = $Component
                message   = $cleanMsg
                file      = "LiteDeploy.BootInitilizer.ps1"
            }
            $jsonEntry = $jsonRecord | ConvertTo-Json -Compress
            Add-Content -Path $jsonFile -Value $jsonEntry -ErrorAction SilentlyContinue
        }
    }
    catch {}
}

function Format-LiteDeployUncPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $clean = $Path -replace '/', '\'
    if ($clean -notlike '\\*') {
        $clean = "\\$($clean.TrimStart('\'))"
    }
    return $clean.TrimEnd('\')
}

function ConvertTo-LiteDeploySecureString {
    param([string]$PlainText = "")

    $secure = New-Object System.Security.SecureString
    if (-not [string]::IsNullOrEmpty($PlainText)) {
        foreach ($ch in $PlainText.ToCharArray()) {
            $secure.AppendChar($ch)
        }
    }
    $secure.MakeReadOnly()
    return $secure
}

function ConvertFrom-LiteDeploySecureString {
    param([System.Security.SecureString]$Secure)

    if ($null -eq $Secure -or $Secure.Length -eq 0) { return "" }
    $ptr = [System.IntPtr]::Zero
    try {
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        if ($ptr -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
    }
}

function Get-LiteDeployBootThemePalette {
    <#
    .SYNOPSIS
        Boot-local Light/Dark hex palette for the pre-mount credential dialog.
        Matches UiHost colors so a later BootConfig Ui.Theme value looks the same after Z: is mapped.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet("Light", "Dark")]
        [string]$Theme = "Light"
    )

    if ($Theme -eq "Dark") {
        return @{
            IsDark         = $true
            BgMain         = "#121212"
            BgInput        = "#2A2A2A"
            TextPrimary    = "#F3F4F6"
            TextSecondary  = "#9CA3AF"
            TextHeader     = "#E5E7EB"
            TextButton     = "#F3F4F6"
            TextOnBrand    = "#FFFFFF"
            Border         = "#333333"
            BrandPrimary   = "#3B82F6"
            StatusFail     = "#F87171"
            BgButton       = "#2A2A2A"
        }
    }

    return @{
        IsDark         = $false
        BgMain         = "#F4F6F8"
        BgInput        = "#FFFFFF"
        TextPrimary    = "#1B3A4B"
        TextSecondary  = "#4A5B67"
        TextHeader     = "#1B3A4B"
        TextButton     = "#1F2937"
        TextOnBrand    = "#FFFFFF"
        Border         = "#D9E0E7"
        BrandPrimary   = "#005A9E"
        StatusFail     = "#D13438"
        BgButton       = "#FFFFFF"
    }
}

function Show-LiteDeployCredentialPrompt {
    <#
    .SYNOPSIS
        Boot-local share credential dialog. Returns PSCredential (SecureString password).
        Self-contained: the deployment share and UiHost are not available until after mount.
        -Theme Light|Dark (default Light). Later BootConfig Ui.Theme is resolved by the caller.
    #>
    [CmdletBinding()]
    param(
        [string]$Message = "Enter credentials to connect the deployment share.",
        [string]$Title = "LiteDeploy - Deployment Share",
        [string]$UserName = "",
        [ValidateSet("Light", "Dark")]
        [string]$Theme = "Light"
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
        throw "Show-LiteDeployCredentialPrompt requires an STA thread (startnet should launch powershell.exe -STA)."
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml -ErrorAction Stop
    try {
        [System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::SoftwareOnly
    }
    catch {}

    $screenHeight = 768
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        if ([System.Windows.Forms.Screen]::PrimaryScreen) {
            $screenHeight = [int][System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
        }
    }
    catch {}
    $height = [Math]::Min(480, [Math]::Max(300, [int]($screenHeight * 0.38)))
    $width = [int]($height * 460 / 280)

    $p = Get-LiteDeployBootThemePalette -Theme $Theme
    $escapedMessage = [System.Security.SecurityElement]::Escape($Message)
    $escapedTitle = [System.Security.SecurityElement]::Escape($Title)
    $escapedUser = [System.Security.SecurityElement]::Escape($UserName)

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$escapedTitle"
        Width="$width" Height="$height"
        MinWidth="360" MinHeight="260"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        WindowStyle="SingleBorderWindow"
        Background="$($p.BgMain)"
        Topmost="True"
        ShowInTaskbar="False">
    <Viewbox Stretch="Uniform">
        <Grid Width="440" Height="248" Margin="20,16">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="Connect to deployment share" FontSize="16" FontWeight="SemiBold"
                       Foreground="$($p.TextHeader)" FontFamily="Segoe UI" Margin="0,0,0,8"/>
            <TextBlock Grid.Row="1" Name="TxtMessage" Text="$escapedMessage" TextWrapping="Wrap"
                       FontSize="12" Foreground="$($p.TextSecondary)" FontFamily="Segoe UI" Margin="0,0,0,14"/>
            <StackPanel Grid.Row="2" Margin="0,0,0,10">
                <TextBlock Text="User name" FontSize="11" Foreground="$($p.TextSecondary)" Margin="0,0,0,4" FontFamily="Segoe UI"/>
                <TextBox Name="TxtUserName" Height="30" FontSize="13" Padding="6,4" FontFamily="Segoe UI"
                         Text="$escapedUser" Background="$($p.BgInput)" Foreground="$($p.TextPrimary)"
                         BorderBrush="$($p.Border)" CaretBrush="$($p.TextPrimary)" BorderThickness="1"/>
            </StackPanel>
            <StackPanel Grid.Row="3" Margin="0,0,0,8">
                <TextBlock Text="Password" FontSize="11" Foreground="$($p.TextSecondary)" Margin="0,0,0,4" FontFamily="Segoe UI"/>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <PasswordBox Grid.Column="0" Name="PwdPassword" Height="30" FontSize="13" Padding="6,4"
                                 FontFamily="Segoe UI" Background="$($p.BgInput)" Foreground="$($p.TextPrimary)"
                                 BorderBrush="$($p.Border)" CaretBrush="$($p.TextPrimary)" BorderThickness="1"/>
                    <TextBox Grid.Column="0" Name="TxtPasswordReveal" Height="30" FontSize="13" Padding="6,4"
                             FontFamily="Segoe UI" Visibility="Collapsed" Background="$($p.BgInput)"
                             Foreground="$($p.TextPrimary)" BorderBrush="$($p.Border)"
                             CaretBrush="$($p.TextPrimary)" BorderThickness="1"/>
                    <Button Grid.Column="1" Name="BtnReveal" Width="56" Height="30" Margin="8,0,0,0"
                            Content="Show" FontSize="11" FontFamily="Segoe UI"
                            Background="$($p.BgButton)" Foreground="$($p.TextButton)" BorderBrush="$($p.Border)"
                            ToolTip="Show or hide password" Cursor="Hand"/>
                </Grid>
            </StackPanel>
            <TextBlock Grid.Row="4" Name="TxtError" Foreground="$($p.StatusFail)" FontSize="11" Height="16"
                       Visibility="Hidden" FontFamily="Segoe UI"/>
            <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right">
                <Button Name="BtnCancel" Content="Cancel" Width="88" Height="30" Margin="0,0,8,0" IsCancel="True"
                        FontSize="12" FontFamily="Segoe UI" Background="$($p.BgButton)"
                        Foreground="$($p.TextButton)" BorderBrush="$($p.Border)"/>
                <Button Name="BtnOk" Content="OK" Width="88" Height="30" IsDefault="True"
                        FontSize="12" FontWeight="SemiBold" FontFamily="Segoe UI"
                        Background="$($p.BrandPrimary)" Foreground="$($p.TextOnBrand)" BorderBrush="$($p.BrandPrimary)"/>
            </StackPanel>
        </Grid>
    </Viewbox>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $txtUser = $window.FindName("TxtUserName")
    $pwdBox = $window.FindName("PwdPassword")
    $txtReveal = $window.FindName("TxtPasswordReveal")
    $btnReveal = $window.FindName("BtnReveal")
    $btnOk = $window.FindName("BtnOk")
    $btnCancel = $window.FindName("BtnCancel")
    $txtError = $window.FindName("TxtError")

    $script:LiteDeployCredRevealOn = $false
    $script:LiteDeployCredResult = $null

    $hideError = {
        $txtError.Visibility = [System.Windows.Visibility]::Hidden
        $txtError.Text = ""
    }

    $btnReveal.add_Click({
        if (-not $script:LiteDeployCredRevealOn) {
            $txtReveal.Text = ConvertFrom-LiteDeploySecureString -Secure $pwdBox.SecurePassword
            $pwdBox.Visibility = [System.Windows.Visibility]::Collapsed
            $txtReveal.Visibility = [System.Windows.Visibility]::Visible
            $btnReveal.Content = "Hide"
            $script:LiteDeployCredRevealOn = $true
            $txtReveal.Focus()
        }
        else {
            $pwdBox.Password = $txtReveal.Text
            $txtReveal.Clear()
            $txtReveal.Visibility = [System.Windows.Visibility]::Collapsed
            $pwdBox.Visibility = [System.Windows.Visibility]::Visible
            $btnReveal.Content = "Show"
            $script:LiteDeployCredRevealOn = $false
            $pwdBox.Focus()
        }
    }.GetNewClosure())

    $accept = {
        $user = ([string]$txtUser.Text).Trim()
        if ([string]::IsNullOrWhiteSpace($user)) {
            $txtError.Text = "User name is required."
            $txtError.Visibility = [System.Windows.Visibility]::Visible
            $txtUser.Focus()
            return
        }
        $secure = $null
        if ($script:LiteDeployCredRevealOn) {
            $secure = ConvertTo-LiteDeploySecureString -PlainText ([string]$txtReveal.Text)
            $txtReveal.Clear()
        }
        else {
            $secure = $pwdBox.SecurePassword.Copy()
        }
        $script:LiteDeployCredResult = New-Object System.Management.Automation.PSCredential ($user, $secure)
        $window.DialogResult = $true
    }.GetNewClosure()

    $btnOk.add_Click($accept)
    $btnCancel.add_Click({
        $txtReveal.Clear()
        $window.DialogResult = $false
    }.GetNewClosure())
    $txtUser.add_TextChanged($hideError)

    $window.add_Loaded({
        if ([string]::IsNullOrWhiteSpace([string]$txtUser.Text)) { $txtUser.Focus() }
        else { $pwdBox.Focus() }
    }.GetNewClosure())

    $ok = $false
    try {
        $ok = [bool]$window.ShowDialog()
    }
    finally {
        $txtReveal.Clear()
    }

    if ($ok -and $script:LiteDeployCredResult) {
        return $script:LiteDeployCredResult
    }
    return $null
}

function Get-LiteDeployShareCredential {
    param(
        [string]$NetworkPath,
        [ValidateSet("Light", "Dark")]
        [string]$Theme = "Light"
    )

    $message = "Enter credentials to connect the deployment share.`n$($NetworkPath)"
    $title = "LiteDeploy - Deployment Share"
    try {
        return Show-LiteDeployCredentialPrompt -Message $message -Title $title -Theme $Theme
    }
    catch {
        Write-LiteDeployLog " [WARNING] Credential prompt UI failed; using Get-Credential. $($_.Exception.Message)" -Level "WARNING" -ForegroundColor Yellow
        return Get-Credential -Message $message -ErrorAction Stop
    }
}

function Show-LiteDeployGuiError {
    param(
        [string]$Message,
        [string]$Title = "LiteDeploy Error",
        [bool]$IsRetryDialog = $false
    )
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $buttons = if ($IsRetryDialog) { [System.Windows.Forms.MessageBoxButtons]::RetryCancel } else { [System.Windows.Forms.MessageBoxButtons]::OK }
        $result = [System.Windows.Forms.MessageBox]::Show($Message, $Title, $buttons, [System.Windows.Forms.MessageBoxIcon]::Error)
        return ($result -eq [System.Windows.Forms.DialogResult]::Retry)
    }
    catch {
        Write-Warning "$($Title): $($Message)"
        return $true
    }
}

function Get-LiteDeployCfgProperty {
    param(
        $InputObject,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Resolve-LiteDeployUiTheme {
    <#
    .SYNOPSIS
        Reads Light/Dark from BootConfig when present. Default Light.
        Preferred key is Ui.Theme (reserved for a later BootConfig field).
        Also accepts Metadata.Theme, Startup.Theme, or a top-level Theme.
    #>
    param(
        $Config,
        [string]$Fallback = "Light"
    )

    $ui = Get-LiteDeployCfgProperty -InputObject $Config -Name "Ui"
    $metadata = Get-LiteDeployCfgProperty -InputObject $Config -Name "Metadata"
    $startup = Get-LiteDeployCfgProperty -InputObject $Config -Name "Startup"
    $candidates = @(
        (Get-LiteDeployCfgProperty -InputObject $ui -Name "Theme"),
        (Get-LiteDeployCfgProperty -InputObject $metadata -Name "Theme"),
        (Get-LiteDeployCfgProperty -InputObject $startup -Name "Theme"),
        (Get-LiteDeployCfgProperty -InputObject $Config -Name "Theme")
    )

    foreach ($value in $candidates) {
        if ($null -eq $value) { continue }
        $normalized = ([string]$value).Trim()
        if ($normalized -eq "Dark" -or $normalized -eq "Light") {
            return $normalized
        }
    }

    if ($Fallback -eq "Dark") { return "Dark" }
    return "Light"
}

function Read-LiteDeployConfigFields {
    param($Config)

    $metadata = Get-LiteDeployCfgProperty -InputObject $Config -Name "Metadata"
    $deployment = Get-LiteDeployCfgProperty -InputObject $Config -Name "Deployment"
    return [PSCustomObject]@{
        AppName        = Get-LiteDeployCfgProperty -InputObject $metadata -Name "Name"
        Environment    = Get-LiteDeployCfgProperty -InputObject $metadata -Name "Environment"
        AppVersion     = Get-LiteDeployCfgProperty -InputObject $metadata -Name "Version"
        DeploymentType = Get-LiteDeployCfgProperty -InputObject $deployment -Name "Type"
        NetworkPath    = Get-LiteDeployCfgProperty -InputObject $deployment -Name "NetworkPath"
        LocalRootName  = Get-LiteDeployCfgProperty -InputObject $deployment -Name "LocalRootName"
        Theme          = Resolve-LiteDeployUiTheme -Config $Config
    }
}

function Resolve-LiteDeployEnginePath {
    param([string]$RootPath)
    # Prefer the deployment engine orchestrator. PreCheck is invoked by the engine, not BootInitializer.
    $candidates = [System.Collections.Generic.List[string]]::new()

    # Production: BootInitializer and DeploymentEngine are siblings under Engine\Scripts.
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $candidates.Add((Join-Path $PSScriptRoot "LiteDeploy.DeploymentEngine.ps1"))
        # Development repository layout (numbered component folders).
        $candidates.Add((Join-Path $PSScriptRoot "..\DeploymentEngine\LiteDeploy.DeploymentEngine.ps1"))
    }

    if (-not [string]::IsNullOrWhiteSpace($RootPath)) {
        $candidates.Add((Join-Path $RootPath "Engine\Scripts\LiteDeploy.DeploymentEngine.ps1"))
    }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate -ErrorAction SilentlyContinue).Path
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($RootPath)) {
        return (Join-Path $RootPath "Engine\Scripts\LiteDeploy.DeploymentEngine.ps1")
    }
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return (Join-Path $PSScriptRoot "LiteDeploy.DeploymentEngine.ps1")
    }
    return ""
}

function Get-LiteDeployRuntimeConfig {
    param(
        [string]$RootPath,
        [string]$LocalRootName = "~LiteDeploy"
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) { return $null }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($LocalRootName)) {
        $candidates.Add((Join-Path $RootPath "$LocalRootName\Config\BootConfig.json"))
    }
    $candidates.Add((Join-Path $RootPath "Config\BootConfig.json"))
    $candidates.Add((Join-Path $RootPath "*\Config\BootConfig.json"))

    foreach ($candidate in $candidates) {
        $resolved = Resolve-Path -Path $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $resolved -or -not (Test-Path -LiteralPath $resolved.Path -PathType Leaf)) { continue }

        try {
            $runtimeConfig = Get-Content -LiteralPath $resolved.Path -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            return [PSCustomObject]@{
                Path   = $resolved.Path
                Config = $runtimeConfig
            }
        }
        catch {
            throw "Runtime BootConfig.json is invalid at '$($resolved.Path)': $($_.Exception.Message)"
        }
    }

    return $null
}

function Get-LiteDeployExternalMediaRoots {
    param([string]$RamDrive = "")

    $roots = [System.Collections.Generic.List[string]]::new()
    $ram = if ($RamDrive) { $RamDrive.TrimEnd(':') } else { if ($env:SystemDrive) { $env:SystemDrive.TrimEnd(':') } else { "X" } }

    try {
        if (Get-Command Get-Volume -ErrorAction SilentlyContinue) {
            $externalVolumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object {
                $vol = $_
                if (-not $vol.DriveLetter -or $vol.DriveLetter -eq $ram) { return $false }
                $isRemovable = $vol.DriveType -in @('Removable', 'CD-ROM', 'CDROM')
                $isUsbBus = $false
                if ($vol.PSObject.Properties['DiskNumber'] -and $null -ne $vol.DiskNumber) {
                    $disk = Get-Disk -Number $vol.DiskNumber -ErrorAction SilentlyContinue
                    if ($disk -and $disk.PSObject.Properties['BusType'] -and $disk.BusType -in @('USB', '1394', 'SD')) {
                        $isUsbBus = $true
                    }
                }
                return ($isRemovable -or $isUsbBus)
            }
            foreach ($vol in $externalVolumes) {
                $roots.Add("$($vol.DriveLetter):")
            }
        }
    }
    catch {}

    return @($roots.ToArray())
}

function Resolve-LiteDeployDeploymentRoot {
    param(
        [string]$ConfigPath = "",
        [string]$DriveLetter = "",
        [string]$LocalRootName = "~LiteDeploy"
    )

    $candidates = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        $configDir = Split-Path -Parent $ConfigPath
        if ([string]::Equals((Split-Path -Leaf $configDir), "Config", [StringComparison]::OrdinalIgnoreCase)) {
            $candidates.Add((Split-Path -Parent $configDir))
        }
    }

    $drive = if ($DriveLetter) { $DriveLetter.TrimEnd('\') } else { "" }
    if ($drive -and $drive -notmatch ':$') { $drive = "${drive}:" }
    if ($drive -and -not [string]::IsNullOrWhiteSpace($LocalRootName)) {
        $candidates.Add((Join-Path $drive $LocalRootName))
    }
    if ($drive) { $candidates.Add($drive) }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $resolved = $null
        try { $resolved = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path } catch { continue }
        if (Test-Path -LiteralPath (Join-Path $resolved "Content\Drivers") -PathType Container) {
            return $resolved
        }
        if (Test-Path -LiteralPath (Join-Path $resolved "Content") -PathType Container) {
            return $resolved
        }
    }

    return ""
}

if (-not (Test-Path Variable:global:LiteDeployCredential)) {
    $global:LiteDeployCredential = $null
}

$isWinPE = Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT" -ErrorAction SilentlyContinue

if ($isWinPE) {
    # Activate High Performance power plan
    try { powercfg.exe /setactive '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' 2>$null } catch {}

    # Initialize WinPE components and network stack
    try { wpeinit.exe 2>$null } catch {}
    try { wpeutil.exe InitializeNetwork 2>$null } catch {}
}

# Set the title of the console window while LiteDeploy is loading.
$Host.UI.RawUI.WindowTitle = "LiteDeploy Loading..."
Write-LiteDeployLog "LiteDeploy Loading..." -Level "INFO" -ForegroundColor DarkGray
$Host.UI.RawUI.WindowTitle = "LiteDeploy v1.0"
Clear-Host

Write-LiteDeployLog "==========================================================================" -Level "INFO" -ForegroundColor Cyan
Write-LiteDeployLog "                LiteDeploy WinPE Initialization Engine v1.0               " -Level "INFO" -ForegroundColor White
Write-LiteDeployLog "==========================================================================" -Level "INFO" -ForegroundColor Cyan
Write-LiteDeployLog "" -Level "INFO"
if ($isWinPE) {
    Write-LiteDeployLog " [INIT]    WinPE Environment & High Performance Power Plan initialized." -Level "INIT" -ForegroundColor DarkGray
}

# ==============================================================================
# 2. NETWORK VALIDATIONS
# ==============================================================================

function Test-LiteDeployNetworkHardware {
    try {
        $nicName = ""
        $isLinkUp = $false

        if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
            $nics = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne "Disabled" }
            if ($nics) {
                # Prioritize an adapter that is actively connected
                $connectedNic = $nics | Where-Object { $_.MediaConnectionState -eq "Connected" -or $_.Status -eq "Up" } | Select-Object -First 1
                $targetNic = if ($connectedNic) { $connectedNic } else { $nics | Select-Object -First 1 }
                
                $nicName = if ($targetNic.InterfaceDescription) { $targetNic.InterfaceDescription.Trim() } else { $targetNic.Name }
                if ($connectedNic) { $isLinkUp = $true }
            }
        }

        if ([string]::IsNullOrWhiteSpace($nicName)) {
            try {
                $allNics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | 
                Where-Object { $_.NetworkInterfaceType -ne 'Loopback' }
                if ($allNics) {
                    $connectedNic = $allNics | Where-Object { $_.OperationalStatus -eq 'Up' } | Select-Object -First 1
                    $targetNic = if ($connectedNic) { $connectedNic } else { $allNics | Select-Object -First 1 }
                    
                    $nicName = $targetNic.Description.Trim()
                    if ($connectedNic) { $isLinkUp = $true }
                }
            }
            catch {}
        }
        else {
            if (-not $isLinkUp) {
                try {
                    $upNic = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | 
                    Where-Object { $_.NetworkInterfaceType -ne 'Loopback' -and $_.OperationalStatus -eq 'Up' }
                    if ($upNic) { $isLinkUp = $true }
                }
                catch {}
            }
        }

        return [PSCustomObject]@{
            AdapterFound    = (-not [string]::IsNullOrWhiteSpace($nicName))
            AdapterName     = $nicName
            IsLinkConnected = $isLinkUp
        }
    }
    catch {
        return [PSCustomObject]@{ AdapterFound = $false; AdapterName = ""; IsLinkConnected = $false }
    }
}

function Test-LiteDeployIPAddress {
    param([int]$TimeoutSeconds = 30)
    try {
        $ipAddress = ""; $ipv4Address = ""; $ipv6Address = ""
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $lastReport = -1

        while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            try {
                $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
                Where-Object { $_.NetworkInterfaceType -ne 'Loopback' -and $_.OperationalStatus -eq 'Up' }

                foreach ($nic in $nics) {
                    foreach ($addr in $nic.GetIPProperties().UnicastAddresses) {
                        $family = $addr.Address.AddressFamily
                        $ipStr = $addr.Address.IPAddressToString
                        if ($family -eq 'InterNetwork' -and $ipStr -notlike "169.254.*" -and $ipStr -ne "127.0.0.1") {
                            if ([string]::IsNullOrWhiteSpace($ipv4Address)) { $ipv4Address = $ipStr }
                        }
                        elseif ($family -eq 'InterNetworkV6' -and $ipStr -ne "::1" -and $ipStr -notlike "fe80:*") {
                            if ([string]::IsNullOrWhiteSpace($ipv6Address)) { $ipv6Address = $ipStr }
                        }
                    }
                }
                $ipAddress = if ($ipv4Address) { $ipv4Address } else { $ipv6Address }
            }
            catch {}
            if ($ipAddress) { break }

            $elapsedSec = [math]::Floor($timer.Elapsed.TotalSeconds)
            if ($elapsedSec -gt $lastReport -and $elapsedSec % 3 -eq 0 -and $elapsedSec -gt 0) {
                Write-Host "           Waiting for DHCP IP assignment ($($elapsedSec)s / $($TimeoutSeconds)s)..." -ForegroundColor DarkGray
                $lastReport = $elapsedSec
            }

            Start-Sleep -Milliseconds 250
        }
        return [PSCustomObject]@{ IPAddress = $ipAddress; IPv4Address = $ipv4Address; IPv6Address = $ipv6Address; HasValidIP = [bool]$ipAddress }
    }
    catch {
        return [PSCustomObject]@{ IPAddress = ""; IPv4Address = ""; IPv6Address = ""; HasValidIP = $false }
    }
}

function Test-LiteDeployDeploymentShare {
    param([string]$SharePath, [int]$TimeoutMs = 5000)
    try {
        if ([string]::IsNullOrWhiteSpace($SharePath)) { return [PSCustomObject]@{ Reachable = $false; Server = "" } }
        $cleanPath = Format-LiteDeployUncPath -Path $SharePath
        $server = $cleanPath.TrimStart('\').Split('\')[0]
        if ([string]::IsNullOrWhiteSpace($server)) { return [PSCustomObject]@{ Reachable = $false; Server = "" } }

        $smbOK = $false
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $connect = $tcp.BeginConnect($server, 445, $null, $null)
            if ($connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
                $tcp.EndConnect($connect)
                $smbOK = $true
            }
            else { $tcp.Close() }
        }
        catch {} finally { $tcp.Dispose() }

        # Secondary fallback: If socket check timed out during WinPE DNS lookup, test UNC path directly
        if (-not $smbOK) {
            try {
                if (Test-Path -Path $cleanPath -ErrorAction SilentlyContinue) {
                    $smbOK = $true
                }
            }
            catch {}
        }

        return [PSCustomObject]@{ Reachable = $smbOK; Server = $server }
    }
    catch { return [PSCustomObject]@{ Reachable = $false; Server = "" } }
}

# ==============================================================================
# 3. SHARE MOUNTING
# ==============================================================================

function Connect-LiteDeployDeploymentShare {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NetworkPath,
        [string]$DriveLetter = "Z:",
        [ValidateSet("Light", "Dark")]
        [string]$Theme = "Light",
        [switch]$ShowGuiError
    )

    $isWinPE = Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT" -ErrorAction SilentlyContinue
    $driveName = $DriveLetter.TrimEnd(':', '\')
    $cleanDrive = "$($driveName):"

    # Purge stale net use mappings or orphaned sessions prior to drive verification
    if (Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue) {
        # Test if the existing drive connection is actually responsive
        $driveResponsive = Test-Path -Path "$($cleanDrive)\" -ErrorAction SilentlyContinue
        if (-not $driveResponsive) {
            Write-Warning "Stale or unmapped drive detected on $($cleanDrive). Purging existing SMB session..."
            try {
                if (Get-Command Remove-SmbMapping -ErrorAction SilentlyContinue) {
                    Remove-SmbMapping -LocalPath $cleanDrive -Force -UpdateProfile -ErrorAction SilentlyContinue | Out-Null
                }
            }
            catch {}
            Remove-PSDrive -Name $driveName -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # Fast-Path: Check if drive Z:\ is already connected
    if (Test-Path -Path "$($cleanDrive)\" -ErrorAction SilentlyContinue) {
        Write-LiteDeployLog "Deployment share is already connected to $($cleanDrive)\ ($NetworkPath)." -Level "SUCCESS" -ForegroundColor Green
        $existingCred = if (Test-Path Variable:global:LiteDeployCredential) { $global:LiteDeployCredential } else { $null }
        return [PSCustomObject]@{ Mounted = $true; DriveLetter = $cleanDrive; NetworkPath = $NetworkPath; Credential = $existingCred }
    }

    try {
        if (Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue) {
            Remove-PSDrive -Name $driveName -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
    catch {}

    $mounted = $false
    $userCred = $null

    while (-not $mounted) {
        try {
            $userCred = Get-LiteDeployShareCredential -NetworkPath $NetworkPath -Theme $Theme
        }
        catch {
            Write-LiteDeployLog "Deployment share authentication cancelled by user." -Level "WARNING" -ForegroundColor Yellow
            Write-Host ""
            Write-Host " [NOTICE]  Deployment initialization paused." -ForegroundColor Yellow
            Write-Host "           To restart this process, run 'startnet' below." -ForegroundColor Yellow
            Write-Host ""
            break
        }
        if ($null -eq $userCred) { break }

        # Native PowerShell persistent global drive mapping
        try {
            New-PSDrive -Name $driveName -PSProvider FileSystem -Root $NetworkPath -Credential $userCred -Persist -Scope Global -ErrorAction Stop | Out-Null
            $mounted = $true
        }
        catch {
            try {
                if (Get-Command New-SmbMapping -ErrorAction SilentlyContinue) {
                    New-SmbMapping -LocalPath $cleanDrive -RemotePath $NetworkPath -Credential $userCred -ErrorAction Stop | Out-Null
                    $mounted = $true
                }
            }
            catch {}
        }

        if ($mounted -or (Test-Path -Path "$($cleanDrive)\")) {
            $mounted = $true
            $global:LiteDeployCredential = $userCred
            $global:LiteDeployShareMounted = $true
            Write-LiteDeployLog " [SUCCESS] Deployment share connected successfully to $($cleanDrive)\ ($NetworkPath)." -Level "SUCCESS" -ForegroundColor Green
            break
        }

        Write-LiteDeployLog " [ERROR]   Authentication failed for user '$($userCred.UserName)' on share '$($NetworkPath)'." -Level "ERROR" -ForegroundColor Red
        $shouldRetry = $true
        if (-not $shouldRetry) { break }

        if ($isWinPE) {
            try { wpeutil.exe InitializeNetwork 2>$null } catch {}
        }
        try { [System.Console]::Out.Flush() } catch {}
        Write-LiteDeployLog " [RETRY]   Re-prompting for Credentials for $($NetworkPath)..." -Level "RETRY" -ForegroundColor DarkYellow
    }

    return [PSCustomObject]@{ Mounted = $mounted; DriveLetter = $cleanDrive; NetworkPath = $NetworkPath; Credential = $userCred }
}

# ==============================================================================
# 4. MAIN CONFIGURATION DISCOVERY ENGINE
# ==============================================================================

function Get-LiteDeployBootConfig {
    param(
        [string]$ConfigPath = "",
        [switch]$ShowGuiError,
        [switch]$MountShare
    )

    $isWinPE = Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT" -ErrorAction SilentlyContinue

    # Discover BootConfig.json
    Write-Host ""
    Write-LiteDeployLog " [CHECK]   Searching for BootConfig.json..." -Level "INFO" -ForegroundColor Cyan
    $ramDrive = if ($env:SystemDrive) { $env:SystemDrive } else { "X:" }
    $ramConfigPaths = @()
    if ($ConfigPath) { $ramConfigPaths += $ConfigPath }
    if ($isWinPE) {
        $ramConfigPaths += "$ramDrive\~LiteDeploy\Config\BootConfig.json"
        $ramConfigPaths += "$ramDrive\*\Config\BootConfig.json"
        $ramConfigPaths += "$ramDrive\Windows\System32\BootConfig.json"
    }

    $FoundConfigPath = $null
    foreach ($path in $ramConfigPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        try {
            $resolved = Resolve-Path -Path $path -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($resolved -and (Test-Path -LiteralPath $resolved.Path -PathType Leaf)) {
                $FoundConfigPath = $resolved.Path
                break
            }
        }
        catch {}
    }

    # Only enumerate external USB/CD drives if config was NOT found in RAM or explicit path
    if (-not $FoundConfigPath) {
        foreach ($extRoot in @(Get-LiteDeployExternalMediaRoots -RamDrive $ramDrive)) {
            $extCandidate = Resolve-Path -Path @(
                "$extRoot\~LiteDeploy\Config\BootConfig.json",
                "$extRoot\*\Config\BootConfig.json"
            ) -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($extCandidate -and (Test-Path -LiteralPath $extCandidate.Path -PathType Leaf)) {
                $FoundConfigPath = $extCandidate.Path
                break
            }
        }
    }

    $appName = "LiteDeploy"; $appVersion = "1.0"; $envName = ""; $deploymentType = $null; $networkPath = $null; $localRootName = "~LiteDeploy"; $uiTheme = "Light"; $configFound = $false; $cfg = $null

    if ($FoundConfigPath) {
        Write-LiteDeployLog " [SUCCESS] BootConfig.json discovered at '$($FoundConfigPath)'." -Level "SUCCESS" -ForegroundColor Green
        try {
            $jsonContent = Get-Content -LiteralPath $FoundConfigPath -Raw -ErrorAction Stop
            if ($jsonContent) {
                $cfg = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                if ($cfg) {
                    $configFound = $true
                    $bootFields = Read-LiteDeployConfigFields -Config $cfg
                    if ($bootFields.AppName) { $appName = $bootFields.AppName }
                    if ($bootFields.Environment) { $envName = $bootFields.Environment }
                    if ($bootFields.AppVersion) { $appVersion = $bootFields.AppVersion }
                    if ($bootFields.DeploymentType) { $deploymentType = $bootFields.DeploymentType }
                    if ($bootFields.NetworkPath) { $networkPath = Format-LiteDeployUncPath -Path $bootFields.NetworkPath }
                    if ($bootFields.LocalRootName) { $localRootName = $bootFields.LocalRootName }
                    if ($bootFields.Theme) { $uiTheme = $bootFields.Theme }
                }
            }
        }
        catch {
            Write-LiteDeployLog " [WARNING] Failed to parse bootstrap BootConfig.json at '$FoundConfigPath': $($_.Exception.Message)" -Level "WARNING" -ForegroundColor Yellow
        }
    }

    if (-not $configFound) {
        Write-LiteDeployLog " [WARNING] BootConfig.json file was not found." -Level "WARNING" -ForegroundColor Yellow
        if ($isWinPE -or $ShowGuiError) {
            Show-LiteDeployGuiError -Message "BootConfig.json was not found in WinPE RAM ($ramDrive\), external media, or script path.`n`Please rebuild the boot image." -Title "LiteDeploy - Config Missing"
        }
    }

    # Resolution & Validations
    $netAdapterFound = $true; $netAdapterName = ""; $ipAddress = ""; $ipv4Address = ""; $ipv6Address = ""
    $serverReachable = $true; $serverName = ""; $shareMounted = $false; $mountedDrive = ""; $mediaDriveLetter = ""; $engineScriptPath = ""; $userCred = $null

    if ($deploymentType -eq "Media") {
        # Bootstrap BootConfig on the boot WIM (X:) is only a pointer. Prefer the
        # loaded USB/ISO environment for the full runtime config, engine, and content.
        $mediaRoots = [System.Collections.Generic.List[string]]::new()
        foreach ($ext in @(Get-LiteDeployExternalMediaRoots -RamDrive $ramDrive)) {
            $mediaRoots.Add($ext)
        }
        if ($FoundConfigPath) {
            $bootstrapDrive = Split-Path -Qualifier $FoundConfigPath
            if ($bootstrapDrive -and $bootstrapDrive.TrimEnd(':') -ne $ramDrive.TrimEnd(':')) {
                $mediaRoots.Insert(0, $bootstrapDrive)
            }
        }

        $promoted = $false
        foreach ($mediaRoot in @($mediaRoots | Select-Object -Unique)) {
            $runtimeConfig = Get-LiteDeployRuntimeConfig -RootPath $mediaRoot -LocalRootName $localRootName
            if (-not $runtimeConfig) { continue }

            $FoundConfigPath = $runtimeConfig.Path
            $cfg = $runtimeConfig.Config
            $configFound = $true
            $mediaDriveLetter = $mediaRoot
            $mountedDrive = $mediaRoot
            $promoted = $true

            $mediaFields = Read-LiteDeployConfigFields -Config $cfg
            if ($mediaFields.AppName) { $appName = $mediaFields.AppName }
            if ($mediaFields.Environment) { $envName = $mediaFields.Environment }
            if ($mediaFields.AppVersion) { $appVersion = $mediaFields.AppVersion }
            if ($mediaFields.LocalRootName) { $localRootName = $mediaFields.LocalRootName }
            if ($mediaFields.NetworkPath) { $networkPath = Format-LiteDeployUncPath -Path $mediaFields.NetworkPath }
            if ($mediaFields.Theme) { $uiTheme = $mediaFields.Theme }

            $engineScriptPath = Resolve-LiteDeployEnginePath -RootPath $mediaRoot
            if (-not $engineScriptPath -or -not (Test-Path -LiteralPath $engineScriptPath -PathType Leaf)) {
                $engineScriptPath = Resolve-LiteDeployEnginePath -RootPath (Join-Path $mediaRoot $localRootName)
            }
            Write-LiteDeployLog " [SUCCESS] Media runtime configuration promoted from '$($FoundConfigPath)'." -Level "SUCCESS" -ForegroundColor Green
            break
        }

        if (-not $promoted -and $FoundConfigPath) {
            $mediaDriveLetter = Split-Path -Qualifier $FoundConfigPath
            if ([string]::IsNullOrWhiteSpace($mediaDriveLetter)) { $mediaDriveLetter = $ramDrive }
            $mountedDrive = $mediaDriveLetter
            $engineScriptPath = Resolve-LiteDeployEnginePath -RootPath $mediaDriveLetter
            Write-LiteDeployLog " [WARNING] Media runtime BootConfig was not found on USB/ISO; using bootstrap '$FoundConfigPath'." -Level "WARNING" -ForegroundColor Yellow
        }

        if ($mediaDriveLetter) {
            Write-LiteDeployLog " [INFO]    Deployment Mode: Media (Offline Drive: $($mediaDriveLetter))." -Level "INFO" -ForegroundColor DarkCyan
        }
    }
    elseif ($deploymentType -eq "Network") {
        if ([string]::IsNullOrWhiteSpace($networkPath)) {
            $serverReachable = $false
            Write-LiteDeployLog " [WARNING] Misconfigured Network Deployment: NetworkPath is missing in BootConfig.json." -Level "WARNING" -ForegroundColor Yellow
            if ($isWinPE -or $ShowGuiError) {
                Show-LiteDeployGuiError -Message "NetworkPath is missing in BootConfig.json.`n`Please update BootConfig.json with a valid network share path." -Title "LiteDeploy - Misconfigured NetworkPath"
            }
        }
        else {
            # Network Deployment Mode: Check NIC Hardware & IP Assignment (Interactive Retry Loops)
            if ($networkPath) {
                Write-LiteDeployLog " [INFO]    Deployment Mode: Network (Share: $($networkPath))." -Level "INFO" -ForegroundColor DarkCyan
            }
            $netAdapterFound = $false
            $netAdapterName = ""
            $isLinkConnected = $false

            # Step 1: Check NIC Hardware & Driver
            Write-Host ""
            Write-LiteDeployLog " [CHECK]   Scanning Network Adapters..." -Level "INFO" -ForegroundColor Cyan
            while (-not $netAdapterFound) {
                $netHw = Test-LiteDeployNetworkHardware
                $netAdapterFound = $netHw.AdapterFound
                $netAdapterName = $netHw.AdapterName
                $isLinkConnected = $netHw.IsLinkConnected

                if (-not $netAdapterFound) {
                    Write-LiteDeployLog " [ERROR]   Network Card Not Detected! (Driver missing)" -Level "ERROR" -ForegroundColor Red
                    $shouldRetry = $true
                    if ($isWinPE -or $ShowGuiError) {
                        $msg = "Network Card Not Detected: No active network adapter found.`n`Please load the required network card driver.`n`nWould you like to try scanning again?"
                        $shouldRetry = Show-LiteDeployGuiError -Message $msg -Title "LiteDeploy - Network Driver Missing" -IsRetryDialog $true
                    }
                    else {
                        $shouldRetry = $false
                    }
                    if (-not $shouldRetry) { break }

                    if ($isWinPE) {
                        try { wpeutil.exe InitializeNetwork 2>$null } catch {}
                    }
                    try { [System.Console]::Out.Flush() } catch {}
                    Write-LiteDeployLog " [RETRY]   Re-scanning network hardware adapters..." -Level "RETRY" -ForegroundColor DarkYellow
                }
                else {
                    Write-LiteDeployLog " [SUCCESS] Adapter Found: '$($netAdapterName)'." -Level "SUCCESS" -ForegroundColor Green
                }
            }

            # Step 2: Check Physical Link / Cable Connection
            if ($netAdapterFound) {
                Write-Host ""
                Write-LiteDeployLog " [CHECK]   Verifying Network Link Connection..." -Level "INFO" -ForegroundColor Cyan
                while (-not $isLinkConnected) {
                    $netHw = Test-LiteDeployNetworkHardware
                    $isLinkConnected = $netHw.IsLinkConnected
                    if ($netHw.AdapterName) { $netAdapterName = $netHw.AdapterName }

                    if (-not $isLinkConnected) {
                        Write-LiteDeployLog " [WARNING] Network Cable Disconnected on '$($netAdapterName)'!" -Level "WARNING" -ForegroundColor Yellow
                        $shouldRetry = $true
                        if ($isWinPE -or $ShowGuiError) {
                            $msg = "Network Cable Disconnected: Adapter '$($netAdapterName)' is detected, but no network link/cable is connected.`n`Please connect an Ethernet cable to the network port.`n`nWould you like to check again?"
                            $shouldRetry = Show-LiteDeployGuiError -Message $msg -Title "LiteDeploy - Network Cable Disconnected" -IsRetryDialog $true
                        }
                        else {
                            $shouldRetry = $false
                        }
                        if (-not $shouldRetry) { break }

                        if ($isWinPE) {
                            try { wpeutil.exe InitializeNetwork 2>$null } catch {}
                        }
                        try { [System.Console]::Out.Flush() } catch {}
                        Write-LiteDeployLog " [RETRY]   Re-checking network cable connection on '$($netAdapterName)'..." -Level "RETRY" -ForegroundColor DarkYellow
                    }
                    else {
                        Write-LiteDeployLog " [SUCCESS] Network Link Active (Cable Connected)." -Level "SUCCESS" -ForegroundColor Green
                    }
                }
            }

            # Step 3: Poll IP Address Assignment (Only if NIC is present and cable is connected)
            if ($netAdapterFound -and $isLinkConnected) {
                Write-Host ""
                Write-LiteDeployLog " [CHECK]   Polling IPv4 / IPv6 Address Assignment..." -Level "INFO" -ForegroundColor Cyan
                while ([string]::IsNullOrWhiteSpace($ipAddress)) {
                    $ipCheck = Test-LiteDeployIPAddress -TimeoutSeconds 30
                    $ipAddress = $ipCheck.IPAddress
                    $ipv4Address = $ipCheck.IPv4Address
                    $ipv6Address = $ipCheck.IPv6Address

                    if ($ipAddress) {
                        Write-LiteDeployLog " [SUCCESS] IP Address Assigned: $($ipAddress)" -Level "SUCCESS" -ForegroundColor Green
                    }
                    else {
                        Write-LiteDeployLog " [WARNING] Could not obtain IP Address (30s DHCP Timeout) on '$($netAdapterName)'!" -Level "WARNING" -ForegroundColor Yellow
                        $shouldRetry = $true
                        if ($isWinPE -or $ShowGuiError) {
                            $msg = "No IP Address Assigned: Network adapter '$($netAdapterName)' is connected, but could not obtain an IPv4/IPv6 address after 30 seconds.`n`Please check your DHCP server or network connection.`n`nWould you like to try obtaining an IP address again?"
                            $shouldRetry = Show-LiteDeployGuiError -Message $msg -Title "LiteDeploy - IP Address Assignment Failed" -IsRetryDialog $true
                        }
                        else {
                            $shouldRetry = $false
                        }
                        if (-not $shouldRetry) { break }

                        if ($isWinPE) {
                            try { wpeutil.exe InitializeNetwork 2>$null } catch {}
                        }
                        try { [System.Console]::Out.Flush() } catch {}
                        Write-LiteDeployLog " [RETRY]   Retrying IP address assignment for '$($netAdapterName)'..." -Level "RETRY" -ForegroundColor DarkYellow
                    }
                }
            }

            # Only test deployment server reachability if local network hardware and valid IP assignment are present
            $hasNetworkAccess = $netAdapterFound -and [bool]$ipAddress

            if (-not $hasNetworkAccess) {
                $serverReachable = $false
                Write-LiteDeployLog " [WARNING] Deployment Server check skipped: Local network access unavailable (NIC missing or IP unassigned)." -Level "WARNING" -ForegroundColor Yellow
            }
            else {
                # Step 4: Check Deployment Server Reachability (SMB Port 445 Interactive Retry Loop)
                $serverReachable = $false
                $serverName = ""
                $serverHost = if ($networkPath) { (Format-LiteDeployUncPath -Path $networkPath).TrimStart('\').Split('\')[0] } else { "" }

                Write-Host ""
                Write-LiteDeployLog " [CHECK]   Testing SMB Connectivity to Server '$($serverHost)' (Port 445)..." -Level "INFO" -ForegroundColor Cyan
                while (-not $serverReachable) {
                    $shareCheck = Test-LiteDeployDeploymentShare -SharePath $networkPath -TimeoutMs 5000
                    $serverReachable = $shareCheck.Reachable
                    $serverName = $shareCheck.Server

                    if (-not $serverReachable) {
                        Write-LiteDeployLog " [ERROR]   Server '$($serverName)' is Unreachable on SMB Port 445!" -Level "ERROR" -ForegroundColor Red
                        $shouldRetry = $true
                        if ($isWinPE -or $ShowGuiError) {
                            $msg = "Deployment Server '$($serverName)' (from NetworkPath: $($networkPath)) could not be reached on SMB Port 445.`n`Please ensure the deployment server is online, SMB sharing is enabled, and firewall allows port 445.`n`nWould you like to try connecting again?"
                            $shouldRetry = Show-LiteDeployGuiError -Message $msg -Title "LiteDeploy - Server Unreachable" -IsRetryDialog $true
                        }
                        else {
                            $shouldRetry = $false
                        }
                        if (-not $shouldRetry) { break }

                        if ($isWinPE) {
                            try { wpeutil.exe InitializeNetwork 2>$null } catch {}
                        }
                        try { [System.Console]::Out.Flush() } catch {}
                        Write-LiteDeployLog " [RETRY]   Retrying SMB connectivity test to server '$($serverHost)'..." -Level "RETRY" -ForegroundColor DarkYellow
                    }
                    else {
                        Write-LiteDeployLog " [SUCCESS] Server '$($serverName)' is Reachable over SMB Port 445." -Level "SUCCESS" -ForegroundColor Green
                    }
                }

                if ($serverReachable -and ($MountShare -or $isWinPE)) {
                    Write-Host ""
                    Write-LiteDeployLog " [CHECK]   Connecting Deployment Share to Z:\..." -Level "INFO" -ForegroundColor Cyan
                    $mountRes = Connect-LiteDeployDeploymentShare -NetworkPath $networkPath -DriveLetter "Z:" -Theme $uiTheme -ShowGuiError:$ShowGuiError
                    $mountObj = if ($mountRes -is [array]) { $mountRes | Where-Object { $_ -is [PSCustomObject] -and $_.PSObject.Properties['Mounted'] } | Select-Object -Last 1 } else { $mountRes }
                    $shareMounted = [bool]($mountObj -and $mountObj.PSObject.Properties['Mounted'] -and $mountObj.Mounted)
                    $mountedDrive = if ($mountObj -and $mountObj.PSObject.Properties['DriveLetter']) { $mountObj.DriveLetter } else { "Z:" }
                    $userCred = if ($mountObj -and $mountObj.PSObject.Properties['Credential']) { $mountObj.Credential } else { $null }
                    if ($shareMounted) {
                        $shareRoot = if ($mountedDrive) { $mountedDrive } else { "Z:" }
                        $engineScriptPath = Resolve-LiteDeployEnginePath -RootPath $shareRoot

                        # The WinPE BootConfig is only a bootstrap contract. Once the
                        # deployment source is mounted, promote its full configuration
                        # into BootObject so every downstream script consumes the same
                        # in-memory object and credential-bearing process.
                        $runtimeConfig = Get-LiteDeployRuntimeConfig -RootPath $shareRoot -LocalRootName $localRootName
                        if ($runtimeConfig) {
                            $FoundConfigPath = $runtimeConfig.Path
                            $cfg = $runtimeConfig.Config
                            $configFound = $true

                            $runtimeFields = Read-LiteDeployConfigFields -Config $cfg
                            if ($runtimeFields.AppName) { $appName = $runtimeFields.AppName }
                            if ($runtimeFields.Environment) { $envName = $runtimeFields.Environment }
                            if ($runtimeFields.AppVersion) { $appVersion = $runtimeFields.AppVersion }
                            if ($runtimeFields.LocalRootName) { $localRootName = $runtimeFields.LocalRootName }
                            if ($runtimeFields.NetworkPath) { $networkPath = Format-LiteDeployUncPath -Path $runtimeFields.NetworkPath }
                            if ($runtimeFields.Theme) { $uiTheme = $runtimeFields.Theme }

                            Write-LiteDeployLog " [SUCCESS] Runtime configuration promoted from '$($FoundConfigPath)'." -Level "SUCCESS" -ForegroundColor Green
                        }
                        else {
                            Write-LiteDeployLog " [WARNING] Full runtime BootConfig.json was not found on the mounted deployment source; downstream defaults will be used." -Level "WARNING" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
    }

    $deploymentRoot = Resolve-LiteDeployDeploymentRoot `
        -ConfigPath $FoundConfigPath `
        -DriveLetter $(if ($mountedDrive) { $mountedDrive } else { $mediaDriveLetter }) `
        -LocalRootName $localRootName
    if ($deploymentRoot) {
        Write-LiteDeployLog " [INFO]    DeploymentRoot   : $deploymentRoot" -Level "INFO" -ForegroundColor DarkCyan
        Write-LiteDeployLog " [INFO]    UI Theme         : $uiTheme" -Level "INFO" -ForegroundColor DarkCyan
        if (-not $engineScriptPath -or -not (Test-Path -LiteralPath $engineScriptPath -PathType Leaf)) {
            $engineScriptPath = Resolve-LiteDeployEnginePath -RootPath $deploymentRoot
        }
    }

    return [PSCustomObject]@{
        ConfigFound         = $configFound
        ConfigPath          = $FoundConfigPath
        Config              = $cfg
        DeploymentRoot      = $deploymentRoot
        IsWinPE             = $isWinPE
        DeploymentType      = $deploymentType
        MediaDriveLetter    = $mediaDriveLetter
        LocalRootName       = $localRootName
        EngineScriptPath    = $engineScriptPath
        NetworkAdapterFound = $netAdapterFound
        NetworkAdapterName  = $netAdapterName
        IPAddress           = $ipAddress
        IPv4Address         = $ipv4Address
        IPv6Address         = $ipv6Address
        HasValidIP          = [bool]$ipAddress
        ServerReachable     = $serverReachable
        ServerName          = $serverName
        ShareMounted        = $shareMounted
        DriveLetter         = $mountedDrive
        Credential          = $userCred
        AppName             = $appName
        AppVersion          = $appVersion
        Environment         = $envName
        NetworkPath         = $networkPath
        Theme               = $uiTheme
    }
}

# ==============================================================================
# 5. STANDALONE LAUNCHER
# ==============================================================================

if ($MyInvocation.InvocationName -ne '.') {
    $res = Get-LiteDeployBootConfig -ConfigPath $ExplicitConfigPath -MountShare -ShowGuiError
    $bootObj = if ($res -is [array]) { $res | Where-Object { $_ -is [PSCustomObject] } | Select-Object -Last 1 } else { $res }

    $isMounted = [bool]($bootObj -and $bootObj.PSObject.Properties['ShareMounted'] -and $bootObj.ShareMounted)
    $isMedia = [bool]($bootObj -and $bootObj.PSObject.Properties['DeploymentType'] -and $bootObj.DeploymentType -eq "Media")

    if ($isMounted -or $isMedia) {
        $enginePath = if ($bootObj -and $bootObj.PSObject.Properties['EngineScriptPath']) { $bootObj.EngineScriptPath } else { "" }
        if ($enginePath -and (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
            Write-LiteDeployLog "Connection successful. Launching engine script: $($enginePath)..." -Level "INFO" -ForegroundColor Cyan
            
            # Check for HostShell script via EngineScriptPath folder or root DriveLetter, consume if present, and minimize console shell
            $engineFolder = Split-Path -Parent $enginePath
            $driveLetter = if ($bootObj.PSObject.Properties['DriveLetter']) { $bootObj.DriveLetter } else { "" }
            $hostShellResolved = Resolve-Path -Path @(
                "$engineFolder\LiteDeploy.HostShell.ps1",
                "$driveLetter\Engine\Scripts\LiteDeploy.HostShell.ps1",
                "$driveLetter\*\Engine\Scripts\LiteDeploy.HostShell.ps1"
            ) -ErrorAction SilentlyContinue | Select-Object -First 1
            $hostShellPath = if ($hostShellResolved) { $hostShellResolved.Path } else { $null }

            if ($hostShellPath) {
                try {
                    . $hostShellPath
                    if (Get-Command Set-HostShellWindow -ErrorAction SilentlyContinue) {
                        Set-HostShellWindow -Action Minimize
                    }
                    Write-LiteDeployLog "HostShell script '$($hostShellPath)' loaded successfully." -Level "INFO" -NoConsole
                }
                catch {
                    Write-LiteDeployLog "Failed to load HostShell script '$($hostShellPath)': $_" -Level "WARNING" -NoConsole
                }
            }
            else {
                Write-LiteDeployLog "HostShell script 'LiteDeploy.HostShell.ps1' not found. Continuing without window minimization." -Level "INFO" -NoConsole
            }

            try {
                $apartment = [System.Threading.Thread]::CurrentThread.GetApartmentState()
                if ($apartment -ne [System.Threading.ApartmentState]::STA) {
                    Write-LiteDeployLog " [WARNING] Host apartment is $apartment. WPF PreCheck/SelectWorkflow require STA (startnet should launch powershell.exe -STA). UiHost will not relaunch when BootObject is bound." -Level "WARNING" -ForegroundColor Yellow
                }
                # Deployment engine orchestrates PreCheck → SelectWorkflow → state init (and later Setup).
                $null = & $enginePath -BootObject $bootObj
            }
            catch {
                Write-LiteDeployLog " [ERROR] Execution failed for '$($enginePath)': $_" -Level "ERROR" -ForegroundColor Red
                Write-Warning "Engine script execution failed: $_"
                if ($isWinPE -or $ShowGuiError) {
                    Show-LiteDeployGuiError -Message "Engine Script Execution Failed: $($enginePath) encountered an unhandled error:`n`n$_" -Title "LiteDeploy - Execution Error"
                }
            }

            if (Get-Command Set-HostShellWindow -ErrorAction SilentlyContinue) {
                try { Set-HostShellWindow -Action Restore } catch {}
            }
        }
        else {
            $targetPath = if ($enginePath) { $enginePath } else { "Z:\Engine\Scripts\LiteDeploy.DeploymentEngine.ps1" }
            Write-LiteDeployLog " [ERROR] Engine script not found: 'LiteDeploy.DeploymentEngine.ps1' is missing at '$($targetPath)'." -Level "ERROR" -ForegroundColor Red
            Write-Warning "Engine script missing: Unable to locate LiteDeploy.DeploymentEngine.ps1 at '$($targetPath)'."
            if ($isWinPE -or $ShowGuiError) {
                Show-LiteDeployGuiError -Message "Engine Script Missing: LiteDeploy.DeploymentEngine.ps1 was not found on deployment share/media.`n`Target Path: $($targetPath)`n`Please ensure the deployment engine script exists on the deployment share." -Title "LiteDeploy - Script Missing"
            }
            Write-Host ""
            Write-Host " [NOTICE]  Deployment initialization paused." -ForegroundColor Yellow
            Write-Host "           To restart this process, run 'startnet' below." -ForegroundColor Yellow
            Write-Host ""
        }
    }
    else {
        Write-Host ""
        Write-Host " [NOTICE]  Deployment initialization paused." -ForegroundColor Yellow
        Write-Host "           To restart this process, run 'startnet' below." -ForegroundColor Yellow
        Write-Host ""
    }
}
