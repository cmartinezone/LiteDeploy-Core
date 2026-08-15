<#
.SYNOPSIS
    LiteDeploy shared WPF UI host toolkit.

.DESCRIPTION
    Dot-source into PreCheck, SelectWorkflow, Progress (and future WPF screens):

        . (Join-Path $PSScriptRoot "LiteDeploy.UiHost.ps1")
        # or development: ..\UiHost\LiteDeploy.UiHost.ps1

    Provides shared WinPE-safe WPF chrome without merging the three screens:

        Initialize-LiteDeployUiHost     Assemblies, software render, optional STA guard
        Get-LiteDeployUiThemePalette    Light/Dark hex + brush palette
        Get-LiteDeployUiWindowSize      Adaptive window size for Viewbox hosts
        Get-LiteDeployUiButtonStyleXaml Primary/secondary button Style XAML fragments
        Show-LiteDeployUiMessage        WinForms or WPF message box
        Show-LiteDeployCredentialPrompt Viewbox-scaled share credential dialog (PSCredential)
        New-LiteDeployUiBackdrop        Full-screen backdrop (WPF or WinForms)
        ConvertTo-LiteDeployUiBrush     Hex → WPF Brush
        ConvertTo-LiteDeployUiWinColor  Hex → System.Drawing.Color
        Find-LiteDeployUiControl        Named control lookup in a WPF tree

.NOTES
    PowerShell 5.1 / WinPE. Zero module dependencies. Console geometry stays in HostShell.
#>

Set-StrictMode -Version 2.0

#region Bootstrap

function Initialize-LiteDeployUiHost {
    <#
    .SYNOPSIS
        Loads WPF (+ optional WinForms), forces software rendering, optionally enforces STA.
    #>
    [CmdletBinding()]
    param(
        [switch]$RequireWindowsForms,
        [switch]$EnforceSta,
        [string]$ScriptPath = $PSCommandPath,
        [object[]]$RelaunchArgumentList = @(),
        [switch]$AbortStaRelaunchWhenCredentialBound
    )

    if ($EnforceSta -and
        [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {

        if ($AbortStaRelaunchWhenCredentialBound) {
            throw "LiteDeploy UI must run in the BootInitializer/DeploymentEngine STA process when BootObject is supplied. Relaunching would discard the in-memory credential."
        }

        $powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        if (-not (Test-Path -LiteralPath $powershellExe)) { $powershellExe = "powershell.exe" }
        if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
            throw "Initialize-LiteDeployUiHost -EnforceSta requires -ScriptPath when not running from a file."
        }
        & $powershellExe -STA -ExecutionPolicy Bypass -File $ScriptPath @RelaunchArgumentList
        return [PSCustomObject]@{ Relaunched = $true; AssembliesLoaded = $false }
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml -ErrorAction Stop
    try {
        [System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::SoftwareOnly
    }
    catch {}

    $formsLoaded = $false
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $formsLoaded = $true
        try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch {}
    }
    catch {
        if ($RequireWindowsForms) { throw }
    }

    $script:LiteDeployUiFormsAvailable = $formsLoaded
    return [PSCustomObject]@{
        Relaunched       = $false
        AssembliesLoaded = $true
        WindowsForms     = $formsLoaded
    }
}

#endregion

#region Theme & sizing

function ConvertTo-LiteDeployUiBrush {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hex)
    return [System.Windows.Media.BrushConverter]::new().ConvertFromString($Hex)
}

function ConvertTo-LiteDeployUiWinColor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hex)
    if (-not ("System.Drawing.ColorTranslator" -as [type])) {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

function Get-LiteDeployUiThemePalette {
    <#
    .SYNOPSIS
        Returns a hashtable of hex colors (and optional WPF brushes) for Light or Dark.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet("Light", "Dark")]
        [string]$Theme = "Light",

        [switch]$IncludeBrushes
    )

    $tables = @{
        Light = @{
            IsDark           = $false
            BgMain           = "#FFFFFF"
            BgSurface        = "#F7F9FB"
            BgSidebar        = "#FFFFFF"
            BgFooter         = "#F7F9FB"
            BgHeader         = "#F3F4F6"
            BgLogBox         = "#F3F6F9"
            BgButton         = "#FFFFFF"
            BgButtonHover    = "#F3F4F6"
            BgButtonPressed  = "#E5E7EB"
            BgTrack          = "#E6EBF0"
            BgDisabled       = "#F3F4F6"
            BgBackdrop       = "#002D50"
            TextPrimary      = "#111827"
            TextSecondary    = "#4B5563"
            TextMuted        = "#687684"
            TextHeader       = "#374151"
            TextButton       = "#1F2937"
            TextDisabled     = "#9CA3AF"
            Border           = "#D9E0E7"
            BorderDisabled   = "#E5E7EB"
            BrandPrimary     = "#005A9E"
            BrandHover       = "#0078D4"
            BrandPressed     = "#004E8C"
            BrandAccent      = "#0078D4"
            StatusOk         = "#107C10"
            StatusFail       = "#D13438"
            StatusWarn       = "#D97706"
            StatusInfo       = "#0078D4"
            StatusOkBg       = "#DCFCE7"
            StatusFailBg     = "#FEE2E2"
            StatusWarnBg     = "#FEF3C7"
            StatusInfoBg     = "#DBEAFE"
        }
        Dark = @{
            IsDark           = $true
            BgMain           = "#121212"
            BgSurface        = "#1E1E1E"
            BgSidebar        = "#181818"
            BgFooter         = "#181818"
            BgHeader         = "#2A2A2A"
            BgLogBox         = "#242424"
            BgButton         = "#2A2A2A"
            BgButtonHover    = "#383838"
            BgButtonPressed  = "#404040"
            BgTrack          = "#2D2D2D"
            BgDisabled       = "#262626"
            BgBackdrop       = "#0A0A0A"
            TextPrimary      = "#F3F4F6"
            TextSecondary    = "#9CA3AF"
            TextMuted        = "#9CA3AF"
            TextHeader       = "#E5E7EB"
            TextButton       = "#F3F4F6"
            TextDisabled     = "#6B7280"
            Border           = "#333333"
            BorderDisabled   = "#333333"
            BrandPrimary     = "#3B82F6"
            BrandHover       = "#2563EB"
            BrandPressed     = "#1D4ED8"
            BrandAccent      = "#60A5FA"
            StatusOk         = "#4ADE80"
            StatusFail       = "#F87171"
            StatusWarn       = "#FBBF24"
            StatusInfo       = "#60A5FA"
            StatusOkBg       = "#163820"
            StatusFailBg     = "#3E1719"
            StatusWarnBg     = "#3D3010"
            StatusInfoBg     = "#1E293B"
        }
    }

    $hex = $tables[$Theme]
    if (-not $hex) { $hex = $tables["Light"] }

    $palette = @{}
    foreach ($key in $hex.Keys) { $palette[$key] = $hex[$key] }

    # Progress-compatible aliases
    $palette["WpfBgMain"] = $palette.BgMain
    $palette["WpfBgSidebar"] = $palette.BgSidebar
    $palette["WpfBgFooter"] = $palette.BgFooter
    $palette["WpfBgLogBox"] = $palette.BgLogBox
    $palette["WpfBorder"] = $palette.Border
    $palette["WpfTextPrimary"] = $palette.TextPrimary
    $palette["WpfTextSec"] = $palette.TextSecondary
    $palette["WpfTextMuted"] = $palette.TextMuted
    $palette["WpfLogText"] = $palette.BrandAccent
    $palette["WpfTrackBg"] = $palette.BgTrack

    if ($IncludeBrushes) {
        foreach ($brushKey in @(
                "BgMain", "BgSurface", "BgSidebar", "BgFooter", "BgHeader", "BgLogBox",
                "BgButton", "BgTrack", "TextPrimary", "TextSecondary", "TextMuted",
                "TextHeader", "Border", "BrandPrimary", "BrandHover", "BrandAccent"
            )) {
            $palette["Brush_$brushKey"] = ConvertTo-LiteDeployUiBrush -Hex $palette[$brushKey]
        }
        $palette["WpfBgMain"] = ConvertTo-LiteDeployUiBrush -Hex $palette.BgMain
        $palette["WpfBgSidebar"] = ConvertTo-LiteDeployUiBrush -Hex $palette.BgSidebar
        $palette["WpfBgFooter"] = ConvertTo-LiteDeployUiBrush -Hex $palette.BgFooter
        $palette["WpfBgLogBox"] = ConvertTo-LiteDeployUiBrush -Hex $palette.BgLogBox
        $palette["WpfBorder"] = ConvertTo-LiteDeployUiBrush -Hex $palette.Border
        $palette["WpfTextPrimary"] = ConvertTo-LiteDeployUiBrush -Hex $palette.TextPrimary
        $palette["WpfTextSec"] = ConvertTo-LiteDeployUiBrush -Hex $palette.TextSecondary
        $palette["WpfTextMuted"] = ConvertTo-LiteDeployUiBrush -Hex $palette.TextMuted
        $palette["WpfLogText"] = ConvertTo-LiteDeployUiBrush -Hex $palette.BrandAccent
        $palette["WpfTrackBg"] = ConvertTo-LiteDeployUiBrush -Hex $palette.BgTrack
    }

    return $palette
}

function Get-LiteDeployUiWindowSize {
    <#
    .SYNOPSIS
        Adaptive window size used by Viewbox-hosted screens (PreCheck-style 4:3).
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(0.2, 1.0)]
        [double]$HeightFraction = 0.70,

        [ValidateRange(200, 2000)]
        [int]$MinHeight = 500,

        [ValidateRange(200, 2000)]
        [int]$MaxHeight = 840,

        [double]$AspectWidth = 800,
        [double]$AspectHeight = 600
    )

    $screenWidth = 1024
    $screenHeight = 768
    try {
        if ($script:LiteDeployUiFormsAvailable -or ("System.Windows.Forms.Screen" -as [type])) {
            $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $screenWidth = [int]$bounds.Width
            $screenHeight = [int]$bounds.Height
        }
    }
    catch {}

    $targetHeight = [Math]::Min($MaxHeight, [Math]::Max($MinHeight, [int]($screenHeight * $HeightFraction)))
    $targetWidth = [int]($targetHeight * ($AspectWidth / $AspectHeight))

    return [PSCustomObject]@{
        ScreenWidth  = $screenWidth
        ScreenHeight = $screenHeight
        Width        = $targetWidth
        Height       = $targetHeight
        DesignWidth  = [int]$AspectWidth
        DesignHeight = [int]$AspectHeight
    }
}

function Get-LiteDeployUiButtonStyleXaml {
    <#
    .SYNOPSIS
        Returns PrimaryButtonStyle / SecondaryButtonStyle XAML fragments using the palette.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Palette,

        [ValidateSet("Compact", "Default")]
        [string]$Density = "Default"
    )

    $fontSize = if ($Density -eq "Compact") { "11.5" } else { "13" }
    $primaryPad = if ($Density -eq "Compact") { "16,6" } else { "24,7" }
    $secondaryPad = if ($Density -eq "Compact") { "16,6" } else { "16,6" }

    $primary = @"
        <Style x:Key="PrimaryButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="$($Palette.BrandPrimary)"/><Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="$($Palette.BrandPrimary)"/><Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="$fontSize"/><Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="$primaryPad"/><Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="$($Palette.BrandHover)"/><Setter TargetName="border" Property="BorderBrush" Value="$($Palette.BrandHover)"/></Trigger>
                            <Trigger Property="IsPressed" Value="True"><Setter TargetName="border" Property="Background" Value="$($Palette.BrandPressed)"/></Trigger>
                            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="border" Property="Background" Value="$($Palette.BgDisabled)"/><Setter TargetName="border" Property="BorderBrush" Value="$($Palette.BorderDisabled)"/><Setter Property="Foreground" Value="$($Palette.TextDisabled)"/><Setter Property="Cursor" Value="No"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
"@

    $secondary = @"
        <Style x:Key="SecondaryButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="$($Palette.BgButton)"/><Setter Property="Foreground" Value="$($Palette.TextButton)"/>
            <Setter Property="BorderBrush" Value="$($Palette.Border)"/><Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="$fontSize"/><Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="$secondaryPad"/><Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="$($Palette.BgButtonHover)"/><Setter TargetName="border" Property="BorderBrush" Value="$($Palette.BrandPrimary)"/></Trigger>
                            <Trigger Property="IsPressed" Value="True"><Setter TargetName="border" Property="Background" Value="$($Palette.BgButtonPressed)"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
"@

    return [PSCustomObject]@{
        PrimaryButtonStyleXaml   = $primary
        SecondaryButtonStyleXaml = $secondary
    }
}

#endregion

#region Chrome helpers

function Show-LiteDeployUiMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Title = "LiteDeploy",

        [ValidateSet("OK", "OKCancel", "YesNo", "RetryCancel")]
        [string]$Buttons = "OK",

        [ValidateSet("None", "Info", "Warning", "Error", "Question")]
        [string]$Icon = "Warning"
    )

    $formsOk = $false
    if (Test-Path Variable:script:LiteDeployUiFormsAvailable) {
        $formsOk = [bool]$script:LiteDeployUiFormsAvailable
    }
    elseif ("System.Windows.Forms.MessageBox" -as [type]) {
        $formsOk = $true
    }

    if ($formsOk) {
        $btn = switch ($Buttons) {
            "OKCancel" { [System.Windows.Forms.MessageBoxButtons]::OKCancel }
            "YesNo" { [System.Windows.Forms.MessageBoxButtons]::YesNo }
            "RetryCancel" { [System.Windows.Forms.MessageBoxButtons]::RetryCancel }
            default { [System.Windows.Forms.MessageBoxButtons]::OK }
        }
        $ico = switch ($Icon) {
            "Info" { [System.Windows.Forms.MessageBoxIcon]::Information }
            "Error" { [System.Windows.Forms.MessageBoxIcon]::Error }
            "Question" { [System.Windows.Forms.MessageBoxIcon]::Question }
            "None" { [System.Windows.Forms.MessageBoxIcon]::None }
            default { [System.Windows.Forms.MessageBoxIcon]::Warning }
        }
        $result = [System.Windows.Forms.MessageBox]::Show($Message, $Title, $btn, $ico)
        return [string]$result
    }

    $wpfBtn = switch ($Buttons) {
        "OKCancel" { [System.Windows.MessageBoxButton]::OKCancel }
        "YesNo" { [System.Windows.MessageBoxButton]::YesNo }
        default { [System.Windows.MessageBoxButton]::OK }
    }
    $wpfIco = switch ($Icon) {
        "Info" { [System.Windows.MessageBoxImage]::Information }
        "Error" { [System.Windows.MessageBoxImage]::Error }
        "Question" { [System.Windows.MessageBoxImage]::Question }
        "None" { [System.Windows.MessageBoxImage]::None }
        default { [System.Windows.MessageBoxImage]::Warning }
    }
    $result = [System.Windows.MessageBox]::Show($Message, $Title, $wpfBtn, $wpfIco)
    return [string]$result
}

function New-LiteDeployUiBackdrop {
    <#
    .SYNOPSIS
        Creates and shows a full-screen backdrop. Returns an object with .Kind and .Close().
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Palette,
        [ValidateSet("Wpf", "WinForms", "Auto")]
        [string]$Kind = "Auto"
    )

    $isDark = $false
    $bgHex = "#002D50"
    if ($Palette) {
        if ($Palette.ContainsKey("IsDark")) { $isDark = [bool]$Palette.IsDark }
        if ($Palette.ContainsKey("BgBackdrop")) { $bgHex = [string]$Palette.BgBackdrop }
        elseif ($isDark) { $bgHex = "#0A0A0A" }
    }

    $useForms = $false
    if ($Kind -eq "WinForms") { $useForms = $true }
    elseif ($Kind -eq "Auto") {
        $useForms = $script:LiteDeployUiFormsAvailable -or ("System.Windows.Forms.Form" -as [type])
    }

    if ($useForms -and $Kind -ne "Wpf") {
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "LiteDeploy Backdrop"
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $form.BackColor = ConvertTo-LiteDeployUiWinColor -Hex $bgHex
        $form.ShowInTaskbar = $false
        $form.Show()
        return [PSCustomObject]@{
            Kind   = "WinForms"
            Handle = $form
        }
    }

    $window = New-Object System.Windows.Window
    $window.WindowStyle = [System.Windows.WindowStyle]::None
    $window.WindowState = [System.Windows.WindowState]::Maximized
    $window.Background = ConvertTo-LiteDeployUiBrush -Hex $(if ($isDark) { "#0A0A0A" } else { "#000000" })
    $window.ShowInTaskbar = $false
    $null = $window.Show()
    return [PSCustomObject]@{
        Kind   = "Wpf"
        Handle = $window
    }
}

function Close-LiteDeployUiBackdrop {
    param($Backdrop)
    if ($null -eq $Backdrop) { return }
    try {
        if ($Backdrop.PSObject.Properties['Handle'] -and $Backdrop.Handle) {
            if ($Backdrop.Kind -eq "WinForms") {
                if (-not $Backdrop.Handle.IsDisposed) { $Backdrop.Handle.Close() }
            }
            else {
                $Backdrop.Handle.Close()
            }
            return
        }
        if ($Backdrop -is [System.Windows.Window]) {
            $Backdrop.Close()
        }
    }
    catch {}
}

function Find-LiteDeployUiControl {
    param(
        [System.Windows.DependencyObject]$Parent,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $Parent) { return $null }

    if ($Parent -is [System.Windows.FrameworkElement] -and $Parent.Name -eq $Name) {
        return $Parent
    }

    if ($Parent -is [System.Windows.FrameworkElement]) {
        try {
            $found = $Parent.FindName($Name)
            if ($null -ne $found) { return $found }
        }
        catch {}
    }

    try {
        $children = [System.Windows.LogicalTreeHelper]::GetChildren($Parent)
        foreach ($child in $children) {
            if ($child -is [System.Windows.DependencyObject]) {
                $foundChild = Find-LiteDeployUiControl -Parent $child -Name $Name
                if ($null -ne $foundChild) { return $foundChild }
            }
        }
    }
    catch {}

    return $null
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

function Show-LiteDeployCredentialPrompt {
    <#
    .SYNOPSIS
        Get-Credential-style prompt that returns PSCredential (SecureString password).
        Viewbox-scaled for WinPE / large screens. Optional show-password toggle.
    #>
    [CmdletBinding()]
    param(
        [string]$Message = "Enter credentials to connect the deployment share.",
        [string]$Title = "LiteDeploy - Deployment Share",
        [string]$UserName = ""
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
        throw "Show-LiteDeployCredentialPrompt requires an STA thread (startnet should launch powershell.exe -STA)."
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml -ErrorAction Stop
    try {
        [System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::SoftwareOnly
    }
    catch {}

    $size = $null
    if (Get-Command Get-LiteDeployUiWindowSize -ErrorAction SilentlyContinue) {
        $size = Get-LiteDeployUiWindowSize -HeightFraction 0.38 -MinHeight 300 -MaxHeight 480 -AspectWidth 460 -AspectHeight 280
    }
    else {
        $screenHeight = 768
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            if ([System.Windows.Forms.Screen]::PrimaryScreen) {
                $screenHeight = [int][System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
            }
        }
        catch {}
        $h = [Math]::Min(480, [Math]::Max(300, [int]($screenHeight * 0.38)))
        $size = [PSCustomObject]@{ Width = [int]($h * 460 / 280); Height = $h }
    }

    $escapedMessage = [System.Security.SecurityElement]::Escape($Message)
    $escapedTitle = [System.Security.SecurityElement]::Escape($Title)
    $escapedUser = [System.Security.SecurityElement]::Escape($UserName)

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$escapedTitle"
        Width="$($size.Width)" Height="$($size.Height)"
        MinWidth="360" MinHeight="260"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        WindowStyle="SingleBorderWindow"
        Background="#F4F6F8"
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
                       Foreground="#1B3A4B" FontFamily="Segoe UI" Margin="0,0,0,8"/>
            <TextBlock Grid.Row="1" Name="TxtMessage" Text="$escapedMessage" TextWrapping="Wrap"
                       FontSize="12" Foreground="#4A5B67" FontFamily="Segoe UI" Margin="0,0,0,14"/>
            <StackPanel Grid.Row="2" Margin="0,0,0,10">
                <TextBlock Text="User name" FontSize="11" Foreground="#4A5B67" Margin="0,0,0,4" FontFamily="Segoe UI"/>
                <TextBox Name="TxtUserName" Height="30" FontSize="13" Padding="6,4" FontFamily="Segoe UI"
                         Text="$escapedUser"/>
            </StackPanel>
            <StackPanel Grid.Row="3" Margin="0,0,0,8">
                <TextBlock Text="Password" FontSize="11" Foreground="#4A5B67" Margin="0,0,0,4" FontFamily="Segoe UI"/>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <PasswordBox Grid.Column="0" Name="PwdPassword" Height="30" FontSize="13" Padding="6,4"
                                 FontFamily="Segoe UI"/>
                    <TextBox Grid.Column="0" Name="TxtPasswordReveal" Height="30" FontSize="13" Padding="6,4"
                             FontFamily="Segoe UI" Visibility="Collapsed"/>
                    <Button Grid.Column="1" Name="BtnReveal" Width="56" Height="30" Margin="8,0,0,0"
                            Content="Show" FontSize="11" FontFamily="Segoe UI"
                            ToolTip="Show or hide password" Cursor="Hand"/>
                </Grid>
            </StackPanel>
            <TextBlock Grid.Row="4" Name="TxtError" Foreground="#D13438" FontSize="11" Height="16"
                       Visibility="Hidden" FontFamily="Segoe UI"/>
            <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right">
                <Button Name="BtnCancel" Content="Cancel" Width="88" Height="30" Margin="0,0,8,0" IsCancel="True"
                        FontSize="12" FontFamily="Segoe UI"/>
                <Button Name="BtnOk" Content="OK" Width="88" Height="30" IsDefault="True"
                        FontSize="12" FontWeight="SemiBold" FontFamily="Segoe UI"/>
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

function Import-LiteDeployUiHost {
    <#
    .SYNOPSIS
        Resolves and dot-sources LiteDeploy.UiHost.ps1 from Engine\Scripts or Core layout.
        Prefer calling this only when the toolkit is not already loaded.
    #>
    [CmdletBinding()]
    param(
        [string]$FromScriptRoot = $PSScriptRoot
    )

    if (Get-Command Get-LiteDeployUiThemePalette -ErrorAction SilentlyContinue) {
        return $true
    }

    $candidates = @(
        (Join-Path $FromScriptRoot "LiteDeploy.UiHost.ps1"),
        (Join-Path $FromScriptRoot "..\UiHost\LiteDeploy.UiHost.ps1")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            . (Resolve-Path -LiteralPath $candidate).Path
            return $true
        }
    }

    throw "LiteDeploy.UiHost.ps1 was not found beside the caller or under components/Runtime/UiHost."
}

#endregion

# Mark loaded for Import-LiteDeployUiHost idempotency.
$script:LiteDeployUiHostLoaded = $true
