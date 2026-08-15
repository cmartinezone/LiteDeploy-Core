[CmdletBinding()]
param(
    [psobject]$BootObject = $null,

    [ValidateSet("Light", "Dark")]
    [string]$Theme = "Light"
)

# ------------------------------------------------------------------------------
# Shared UiHost bootstrap (theme, assemblies, messages)
# ------------------------------------------------------------------------------
$uiHostPath = Join-Path $PSScriptRoot "LiteDeploy.UiHost.ps1"
if (-not (Test-Path -LiteralPath $uiHostPath)) {
    $uiHostPath = Join-Path $PSScriptRoot "..\UiHost\LiteDeploy.UiHost.ps1"
}
if (-not (Test-Path -LiteralPath $uiHostPath)) {
    throw "LiteDeploy.UiHost.ps1 was not found beside SelectWorkflow or under components/Runtime/UiHost."
}
. $uiHostPath

$uiInit = Initialize-LiteDeployUiHost `
    -EnforceSta `
    -ScriptPath $PSCommandPath `
    -AbortStaRelaunchWhenCredentialBound:([bool]$BootObject)
if ($uiInit.Relaunched) { return }

$script:WindowsFormsAlertsAvailable = [bool]$uiInit.WindowsForms

if ($BootObject) {
    $global:LiteDeployBootObject = $BootObject
} elseif (Test-Path Variable:global:LiteDeployBootObject) {
    $BootObject = $global:LiteDeployBootObject
}

if (-not $PSBoundParameters.ContainsKey("Theme") -and $BootObject -and $BootObject.PSObject.Properties["Theme"]) {
    $bootTheme = [string]$BootObject.Theme
    if ($bootTheme -eq "Dark" -or $bootTheme -eq "Light") {
        $Theme = $bootTheme
    }
}

$palette = Get-LiteDeployUiThemePalette -Theme $Theme
$buttonStyles = Get-LiteDeployUiButtonStyleXaml -Palette $palette -Density Default
$windowSize = Get-LiteDeployUiWindowSize -HeightFraction 0.85 -MinHeight 600 -MaxHeight 900 -AspectWidth 1024 -AspectHeight 820

function Get-LiteDeployProperty {
    param(
        $InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Show-DeploymentWarning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Title = "Missing Deployment Information"
    )

    $null = Show-LiteDeployUiMessage -Message $Message -Title $Title -Buttons OK -Icon Warning
}

# Load the WPF-only folder picker used by the driver selection control.
$driverPathPickerScript = Join-Path $PSScriptRoot "LiteDeploy.SelecWorkflowDriverPicker.ps1"
if (Test-Path -LiteralPath $driverPathPickerScript) {
    . $driverPathPickerScript
}

function Resolve-LiteDeployDeploymentRoot {
    param(
        [string]$ConfigPath,
        $BootObject
    )

    if ($BootObject -and $BootObject.PSObject.Properties["DeploymentRoot"] -and -not [string]::IsNullOrWhiteSpace([string]$BootObject.DeploymentRoot)) {
        return [string]$BootObject.DeploymentRoot
    }

    $drive = ""
    $localRoot = "~LiteDeploy"
    if ($BootObject) {
        if ($BootObject.PSObject.Properties["DriveLetter"] -and $BootObject.DriveLetter) {
            $drive = [string]$BootObject.DriveLetter
        }
        elseif ($BootObject.PSObject.Properties["MediaDriveLetter"] -and $BootObject.MediaDriveLetter) {
            $drive = [string]$BootObject.MediaDriveLetter
        }
        if ($BootObject.PSObject.Properties["LocalRootName"] -and $BootObject.LocalRootName) {
            $localRoot = [string]$BootObject.LocalRootName
        }
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        $configDir = Split-Path -Parent $ConfigPath
        if ([string]::Equals((Split-Path -Leaf $configDir), "Config", [StringComparison]::OrdinalIgnoreCase)) {
            $candidates.Add((Split-Path -Parent $configDir))
        }
    }
    if ($drive) {
        $drive = $drive.TrimEnd('\')
        if ($drive -notmatch ':$') { $drive = "${drive}:" }
        $candidates.Add((Join-Path $drive $localRoot))
        $candidates.Add($drive)
    }
    if (-not $BootObject) {
        $candidates.Add((Join-Path $PSScriptRoot "..\..\.."))
        $candidates.Add((Join-Path $PSScriptRoot "..\.."))
    }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $resolved = try { (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path } catch { $null }
        if (-not $resolved) { continue }
        if (Test-Path -LiteralPath (Join-Path $resolved "Content\Drivers") -PathType Container) {
            return $resolved
        }
        if (Test-Path -LiteralPath (Join-Path $resolved "Content") -PathType Container) {
            return $resolved
        }
    }

    return ""
}

# Shared Dell/HP/Lenovo pack catalog helpers (also used by SyncOEMDrivers).
$oemPackLibCandidates = [System.Collections.Generic.List[string]]::new()
$oemPackLibCandidates.Add((Join-Path $PSScriptRoot "LiteDeploy.OemDriverPackCatalog.ps1"))
$oemPackLibCandidates.Add((Join-Path $PSScriptRoot "..\..\Shared\OemDriverPacks\LiteDeploy.OemDriverPackCatalog.ps1"))
$oemPackLibCandidates.Add((Join-Path $PSScriptRoot "..\Shared\OemDriverPacks\LiteDeploy.OemDriverPackCatalog.ps1"))
if ($BootObject -and $BootObject.PSObject.Properties["EngineScriptPath"] -and $BootObject.EngineScriptPath) {
    $oemPackLibCandidates.Add((Join-Path (Split-Path -Parent ([string]$BootObject.EngineScriptPath)) "LiteDeploy.OemDriverPackCatalog.ps1"))
}
if ($BootObject -and $BootObject.PSObject.Properties["DeploymentRoot"] -and $BootObject.DeploymentRoot) {
    $oemPackLibCandidates.Add((Join-Path ([string]$BootObject.DeploymentRoot) "Engine\Scripts\LiteDeploy.OemDriverPackCatalog.ps1"))
    $oemPackLibCandidates.Add((Join-Path ([string]$BootObject.DeploymentRoot) "components\Shared\OemDriverPacks\LiteDeploy.OemDriverPackCatalog.ps1"))
}
$oemPackLib = @($oemPackLibCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1)
if ($oemPackLib) {
    . $oemPackLib
}

# Resolve BootConfig.json in the same order as LiteDeploy.PreCheck.ps1.
function Find-Configuration {
    $paths = @(
        (Join-Path $PSScriptRoot "..\..\Manager\Config\BootConfig.json"),
        (Join-Path $PSScriptRoot "Config\BootConfig.json"),
        (Join-Path $PSScriptRoot "BootConfig.json")
    )

    foreach ($path in $paths) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    return $null
}

$configPath = $null
$bootConfig = $null

# Prefer the exact configuration object already validated by BootInitializer and
# PreCheck. Standalone launches retain the existing local discovery behavior.
if ($BootObject -and $BootObject.PSObject.Properties['Config'] -and $BootObject.Config) {
    $bootConfig = $BootObject.Config
    if ($BootObject.PSObject.Properties['ConfigPath']) {
        $configPath = [string]$BootObject.ConfigPath
    }
} elseif ($BootObject) {
    Show-DeploymentWarning -Title "Missing Deployment Configuration" -Message (
        "BootObject.Config is missing. The runtime BootConfig was not promoted from the mounted share or USB media."
    )
    return $false
} else {
    $configPath = Find-Configuration
}

if ($bootConfig) {
    # Configuration was supplied in memory by the trusted WinPE parent process.
} elseif ($configPath) {
    try {
        $bootConfig = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    } catch {
        Show-DeploymentWarning -Title "Invalid Deployment Configuration" -Message (
            "BootConfig.json could not be parsed:`r`n`r`n$configPath`r`n`r`n$($_.Exception.Message)"
        )
        return $false
    }
} else {
    Show-DeploymentWarning -Title "Deployment Configuration Not Found" -Message (
        "BootConfig.json was not found in any expected LiteDeploy configuration location."
    )
    return $false
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Setup" 
        WindowState="Normal" 
        WindowStyle="SingleBorderWindow"
        ResizeMode="NoResize"
        Width="$($windowSize.Width)" Height="$($windowSize.Height)"
        MinWidth="800" MinHeight="600"
        WindowStartupLocation="CenterScreen"
        Background="$($palette.BgMain)">
    
    <Window.Resources>
        <Style x:Key="ActionLinkStyle" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Foreground" Value="$($palette.BrandPrimary)"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="0,0,16,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Center"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

$($buttonStyles.PrimaryButtonStyleXaml)
$($buttonStyles.SecondaryButtonStyleXaml)

        <!-- Modern Clean Styled TextBox -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="$($palette.BgMain)"/>
            <Setter Property="Foreground" Value="$($palette.TextPrimary)"/>
            <Setter Property="BorderBrush" Value="$($palette.Border)"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- Workflow / Parent Header Template -->
        <DataTemplate x:Key="WorkflowHeaderTemplate">
            <StackPanel Orientation="Horizontal" Margin="0,2">
                <Path Width="18" Height="18" Stretch="Uniform" Fill="$($palette.BrandPrimary)" Margin="0,0,8,0"
                      Data="M19,13H13V19H19V13M11,13H5V19H11V13M19,5H13V11H19V5M11,5H5V11H11V5M3,3H21V21H3V3Z"/>
                <TextBlock Text="{Binding HeaderText}" FontWeight="Bold" FontSize="13" Foreground="$($palette.BrandPrimary)" VerticalAlignment="Center"/>
            </StackPanel>
        </DataTemplate>

        <!-- OS Item Template -->
        <DataTemplate x:Key="OSItemTemplate">
            <Grid Margin="0,2">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto" SharedSizeGroup="OSNameGroup"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <Path x:Name="ItemIcon" Grid.Column="0" Width="16" Height="16" Stretch="Uniform" Fill="$($palette.BrandPrimary)" Margin="0,0,10,0" VerticalAlignment="Center"
                      Data="M6,2H18A2,2 0 0,1 20,4V20A2,2 0 0,1 18,22H6A2,2 0 0,1 4,20V4A2,2 0 0,1 6,2M6,4V8H18V4H6M6,20H18V10H6V20M16,15A1,1 0 0,0 15,14A1,1 0 0,0 14,15A1,1 0 0,0 16,15Z"/>

                <TextBlock x:Name="ItemName" Grid.Column="1" Text="{Binding Name}" FontSize="13" Foreground="#1F2937" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,30,0"/>

                <TextBlock x:Name="ItemDate" Grid.Column="3" Text="{Binding DateText}" FontSize="12" Foreground="#6B7280" VerticalAlignment="Center" Margin="0,0,16,0"/>
            </Grid>

            <DataTemplate.Triggers>
                <DataTrigger Binding="{Binding RelativeSource={RelativeSource AncestorType=TreeViewItem}, Path=IsSelected}" Value="True">
                    <Setter TargetName="ItemName" Property="Foreground" Value="#FFFFFF"/>
                    <Setter TargetName="ItemDate" Property="Foreground" Value="#E0E0E0"/>
                    <Setter TargetName="ItemIcon" Property="Fill" Value="#FFFFFF"/>
                </DataTrigger>
            </DataTemplate.Triggers>
        </DataTemplate>

        <!-- Custom TreeViewItem Style -->
        <Style TargetType="TreeViewItem">
            <Setter Property="Padding" Value="4,2"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Style.Resources>
                <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="$($palette.BrandHover)" />
                <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#FFFFFF" />
                <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightBrushKey}" Color="$($palette.BrandHover)" />
                <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightTextBrushKey}" Color="#FFFFFF" />
            </Style.Resources>
        </Style>

        <Style x:Key="HeaderNodeStyle" TargetType="TreeViewItem" BasedOn="{StaticResource {x:Type TreeViewItem}}">
            <Setter Property="IsExpanded" Value="True"/>
            <Setter Property="HeaderTemplate" Value="{StaticResource WorkflowHeaderTemplate}"/>
        </Style>

        <Style x:Key="ChildNodeStyle" TargetType="TreeViewItem" BasedOn="{StaticResource {x:Type TreeViewItem}}">
            <Setter Property="HeaderTemplate" Value="{StaticResource OSItemTemplate}"/>
        </Style>
    </Window.Resources>

    <DockPanel LastChildFill="True" Margin="48,20">
        
        <!-- Header (Docked Top) -->
        <TextBlock DockPanel.Dock="Top" Name="TxtHeader" 
                   Text="Configure deployment settings" 
                   FontSize="24" FontFamily="Segoe UI Light" 
                   Foreground="$($palette.BrandPrimary)" Margin="0,0,0,12"/>

        <!-- Footer Navigation Bar (Docked Bottom) -->
        <DockPanel DockPanel.Dock="Bottom" Margin="0,16,0,0">
            <!-- Navigation Buttons -->
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" HorizontalAlignment="Right">
                <Button Name="BtnBack" Content="Cancel" Width="90" Height="32" Style="{StaticResource SecondaryButtonStyle}" Margin="0,0,10,0"/>
                <Button Name="BtnNext" Content="Start Deployment" Width="135" Height="32" Style="{StaticResource PrimaryButtonStyle}"/>
            </StackPanel>
        </DockPanel>

        <!-- Main Body Area -->
        <StackPanel Name="MainSetupPanel" VerticalAlignment="Top" HorizontalAlignment="Stretch">
            
            <!-- SECTION 1: Computer Identification -->
            <TextBlock Name="HeaderComputerID" Text="Computer Identification" FontSize="13" FontWeight="SemiBold" Foreground="$($palette.BrandPrimary)" Margin="0,2,0,4" FontFamily="Segoe UI"/>

            <Border Name="CardComputerID" Background="#FFFFFF" BorderBrush="#D9E0E7" BorderThickness="1" CornerRadius="5" Padding="12,10" Margin="0,0,0,8" HorizontalAlignment="Stretch">
                <StackPanel Name="ContainerComputerID" HorizontalAlignment="Stretch">
                    <Grid Name="RowComputerName" Margin="0,0,0,8" Visibility="Collapsed" HorizontalAlignment="Stretch">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="170"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="Computer name" VerticalAlignment="Center" FontSize="12.5" Foreground="#374151" FontFamily="Segoe UI"/>
                        <Grid Grid.Column="1" HorizontalAlignment="Stretch">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBox Grid.Row="0" Name="TxtComputerName" Height="28" HorizontalAlignment="Stretch"/>
                            <TextBlock Grid.Row="1" Name="TxtComputerNameError" Foreground="#D13438" FontSize="11" Margin="2,2,0,0" Height="14" Visibility="Hidden" TextWrapping="NoWrap" FontFamily="Segoe UI"/>
                        </Grid>
                    </Grid>

                    <Grid Name="RowComputerDescription" Margin="0,0,0,0" Visibility="Collapsed" HorizontalAlignment="Stretch">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="170"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="Computer description" VerticalAlignment="Center" FontSize="12.5" Foreground="#374151" FontFamily="Segoe UI"/>
                        <TextBox Grid.Column="1" Name="TxtComputerDescription" Height="28" HorizontalAlignment="Stretch"/>
                    </Grid>
                </StackPanel>
            </Border>

            <!-- SECTION 2: Deployment Workflow Selection -->
            <TextBlock Text="Select deployment workflow" FontSize="13" FontWeight="SemiBold" Foreground="$($palette.BrandPrimary)" Margin="0,2,0,4" FontFamily="Segoe UI"/>
            
            <Border Background="#FFFFFF" BorderBrush="#D9E0E7" BorderThickness="1" CornerRadius="5" Height="200" Margin="0,0,0,8" HorizontalAlignment="Stretch">
                <TreeView Name="treeViewWorkflows" Grid.IsSharedSizeScope="True" Background="Transparent" BorderThickness="0" Padding="4" HorizontalContentAlignment="Stretch" ScrollViewer.VerticalScrollBarVisibility="Auto">
                    
                    <!-- Standard Workflow -->
                    <TreeViewItem Style="{StaticResource HeaderNodeStyle}" Name="nodeStandard">
                        <TreeViewItem Style="{StaticResource ChildNodeStyle}" Name="itemStdEnt" Tag="W11-ENT-STD"/>
                        <TreeViewItem Style="{StaticResource ChildNodeStyle}" Name="itemStdPro" Tag="W11-PRO-STD"/>
                    </TreeViewItem>

                    <!-- Intune Workflow -->
                    <TreeViewItem Style="{StaticResource HeaderNodeStyle}" Name="nodeIntune">
                        <TreeViewItem Style="{StaticResource ChildNodeStyle}" Name="itemApEnt" Tag="W11-ENT-AP"/>
                        <TreeViewItem Style="{StaticResource ChildNodeStyle}" Name="itemApPro" Tag="W11-PRO-AP"/>
                    </TreeViewItem>

                </TreeView>
            </Border>

            <!-- Workflow Validation Error Message -->
            <TextBlock Name="TxtWorkflowError" Foreground="#D13438" FontSize="11" Margin="2,-5,0,6" Height="14" Visibility="Hidden" TextWrapping="NoWrap" FontFamily="Segoe UI"/>

            <!-- SECTION 3: Hard Drive Selection -->
            <Grid Name="HeaderDriveSelection" Margin="0,2,0,4" HorizontalAlignment="Stretch">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="Select target hard drive" FontSize="13" FontWeight="SemiBold" Foreground="$($palette.BrandPrimary)" VerticalAlignment="Center" FontFamily="Segoe UI"/>
                <Button Grid.Column="1" Name="BtnRefresh" Content="Refresh Disks" Style="{StaticResource ActionLinkStyle}"/>
            </Grid>

            <Border Name="CardDriveSelection" Background="#FFFFFF" BorderBrush="#CCCCCC" BorderThickness="1" CornerRadius="4" Height="100" Margin="0,0,0,8" HorizontalAlignment="Stretch">
                <DataGrid Name="GridDisks" AutoGenerateColumns="False" 
                          HeadersVisibility="Column" GridLinesVisibility="None" 
                          Background="White" BorderThickness="0" 
                          RowHeight="28" SelectionMode="Single" IsReadOnly="True"
                          CanUserAddRows="False" CanUserDeleteRows="False"
                          CanUserResizeColumns="True" HorizontalAlignment="Stretch">
                    <DataGrid.Resources>
                        <!-- Keep the selected disk blue when keyboard focus moves elsewhere. -->
                        <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="$($palette.BrandHover)"/>
                        <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightBrushKey}" Color="$($palette.BrandHover)"/>
                    </DataGrid.Resources>
                    <DataGrid.CellStyle>
                        <Style TargetType="DataGridCell">
                            <Style.Triggers>
                                <!-- PowerShell 5 otherwise changes inactive selected text to black. -->
                                <Trigger Property="IsSelected" Value="True">
                                    <Setter Property="Foreground" Value="#FFFFFF"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </DataGrid.CellStyle>
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="Disk Index" Binding="{Binding Index}" Width="100"/>
                        <DataGridTextColumn Header="Model / Drive Name" Binding="{Binding Model}" Width="*"/>
                        <DataGridTextColumn Header="Capacity" Binding="{Binding Capacity}" Width="110"/>
                        <DataGridTextColumn Header="Estimated Usage" Binding="{Binding UsedSpace}" Width="120"/>
                        <DataGridTextColumn Header="Available Space" Binding="{Binding FreeSpace}" Width="120"/>
                    </DataGrid.Columns>
                </DataGrid>
            </Border>

            <!-- Disk Validation Error Message -->
            <TextBlock Name="TxtDiskError" Foreground="#D13438" FontSize="11" Margin="2,-5,0,6" Height="14" Visibility="Hidden" TextWrapping="NoWrap" FontFamily="Segoe UI"/>

            <!-- SECTION 4: Drivers & Hardware Injections -->
            <TextBlock Text="Drivers &amp; Hardware Injections" FontSize="13" FontWeight="SemiBold" Foreground="$($palette.BrandPrimary)" Margin="0,2,0,4" FontFamily="Segoe UI"/>
            
            <Border Background="#FFFFFF" BorderBrush="#D9E0E7" BorderThickness="1" CornerRadius="5" Padding="12,10" HorizontalAlignment="Stretch">
                <StackPanel Name="ContainerDrivers" HorizontalAlignment="Stretch">
                    
                    <!-- WMI Detection Hardware Banner -->
                    <Grid Margin="0,0,0,8" HorizontalAlignment="Stretch">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="170"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="Manufacturer &amp; Model:" FontWeight="SemiBold" FontSize="12.5" Foreground="#374151" FontFamily="Segoe UI"/>
                        <TextBlock Grid.Column="1" Name="TxtDetectedHardware" Text="Detecting..." FontSize="12.5" Foreground="$($palette.BrandPrimary)" FontWeight="SemiBold" FontFamily="Segoe UI"/>
                    </Grid>

                    <!-- Manual Driver Pack Selection -->
                    <Grid Name="RowManualDriverSelection" Margin="0,0,0,8" Visibility="Collapsed" HorizontalAlignment="Stretch">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="170"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="Driver pack location" VerticalAlignment="Center" FontSize="12.5" Foreground="#374151" FontFamily="Segoe UI"/>
                        <ComboBox Grid.Column="1" Name="CmbDriverPackPath" Height="28" VerticalContentAlignment="Center" FontSize="12" Margin="0,0,8,0" HorizontalAlignment="Stretch"/>
                        <Button Grid.Column="2" Name="BtnBrowseDriverFolder" Content="Select Folder..." Style="{StaticResource ActionLinkStyle}" Height="28"/>
                    </Grid>

                    <!-- Auto Online Download Checkbox -->
                    <CheckBox Name="ChkOnlineDrivers" Content="Automatically download driver pack online during USB media imaging" 
                              FontSize="12.5" Foreground="#374151" FontFamily="Segoe UI" Margin="0,0,0,6"/>

                    <!-- Optional update check when a local pack already exists (Dell/HP/Lenovo compare only) -->
                    <CheckBox Name="ChkCheckOnlineUpdate" Content="Check for a newer driver pack online when the model folder already exists on media"
                              FontSize="12.5" Foreground="#374151" FontFamily="Segoe UI"/>
                </StackPanel>
            </Border>

        </StackPanel>
    </DockPanel>
</Window>
"@

# Load XAML safely
$reader = New-Object System.Xml.XmlNodeReader $xaml

try {
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Error "Failed to parse XAML: $_"
    return $false
}

if ($null -eq $window) {
    Write-Error "Window object returned null."
    return $false
}

# -------------------------------------------------------------------
# BUSINESS LOGIC
# -------------------------------------------------------------------

# Map UI Elements
$btnNext                  = $window.FindName("BtnNext")
$btnBack                  = $window.FindName("BtnBack")
$btnRefresh               = $window.FindName("BtnRefresh")
$txtHeader                = $window.FindName("TxtHeader")
$headerDriveSelection     = $window.FindName("HeaderDriveSelection")
$cardDriveSelection       = $window.FindName("CardDriveSelection")
$gridDisks                = $window.FindName("GridDisks")
$headerComputerID         = $window.FindName("HeaderComputerID")
$cardComputerID           = $window.FindName("CardComputerID")
$rowComputerName          = $window.FindName("RowComputerName")
$txtComputerName          = $window.FindName("TxtComputerName")
$txtComputerNameError     = $window.FindName("TxtComputerNameError")
$rowComputerDescription   = $window.FindName("RowComputerDescription")
$txtComputerDescription   = $window.FindName("TxtComputerDescription")
$treeView                 = $window.FindName("treeViewWorkflows")
$txtWorkflowError         = $window.FindName("TxtWorkflowError")
$txtDiskError             = $window.FindName("TxtDiskError")
$txtDetectedHardware      = $window.FindName("TxtDetectedHardware")
$rowManualDriverSelection = $window.FindName("RowManualDriverSelection")
$cmbDriverPackPath        = $window.FindName("CmbDriverPackPath")
$btnBrowseDriverFolder    = $window.FindName("BtnBrowseDriverFolder")
$chkOnlineDrivers         = $window.FindName("ChkOnlineDrivers")
$chkCheckOnlineUpdate     = $window.FindName("ChkCheckOnlineUpdate")

function Clear-InlineValidationError {
    param([System.Windows.Controls.TextBlock]$ErrorTextBlock)

    if ($null -ne $ErrorTextBlock) {
        $ErrorTextBlock.Text = ""
        $ErrorTextBlock.Visibility = [System.Windows.Visibility]::Hidden
    }
}

# Clear stale validation text as soon as the user completes the related action.
if ($null -ne $txtComputerName) {
    $txtComputerName.Add_TextChanged({
        Clear-InlineValidationError -ErrorTextBlock $txtComputerNameError
    })
}

if ($null -ne $gridDisks) {
    $gridDisks.Add_SelectionChanged({
        if ($null -ne $gridDisks.SelectedItem) {
            Clear-InlineValidationError -ErrorTextBlock $txtDiskError
        }
    })
}

# Bind Parent Nodes
$nodeStandard = $window.FindName("nodeStandard")
$nodeIntune   = $window.FindName("nodeIntune")
if ($null -ne $nodeStandard) { $nodeStandard.Header = [PSCustomObject]@{ HeaderText = "Standard Workflow (Zero Touch)" } }
if ($null -ne $nodeIntune)   { $nodeIntune.Header   = [PSCustomObject]@{ HeaderText = "Intune Autopilot Workflow" } }

# Helper function to create clean OS objects for DataBinding
function New-OSItem {
    param([string]$Name, [string]$Date)
    $formattedDate = [datetime]::Parse($Date).ToString("MMM dd, yyyy")
    return [PSCustomObject]@{
        Name     = $Name
        DateText = "Updated: $formattedDate"
    }
}

# Bind OS Child Item Data
if ($null -ne $window.FindName("itemStdEnt")) { $window.FindName("itemStdEnt").Header = New-OSItem -Name "Windows 11 Enterprise" -Date "2026-03-15" }
if ($null -ne $window.FindName("itemStdPro")) { $window.FindName("itemStdPro").Header = New-OSItem -Name "Windows 11 Professional" -Date "2026-03-20" }
if ($null -ne $window.FindName("itemApEnt"))  { $window.FindName("itemApEnt").Header  = New-OSItem -Name "Windows 11 Enterprise Autopilot" -Date "2026-04-01" }
if ($null -ne $window.FindName("itemApPro"))  { $window.FindName("itemApPro").Header  = New-OSItem -Name "Windows 11 Professional Autopilot" -Date "2026-04-05" }

# Prevent parent categories from being selected directly
if ($null -ne $treeView) {
    $treeView.add_SelectedItemChanged({
        param($sender, $e)
        if ($treeView.SelectedItem -and $treeView.SelectedItem.HasItems) {
            $firstChild = $treeView.SelectedItem.Items[0]
            $firstChild.IsSelected = $true
        }
        if ($treeView.SelectedItem -and $treeView.SelectedItem.Tag) {
            Clear-InlineValidationError -ErrorTextBlock $txtWorkflowError
        }
    })
}

# Read Configuration Options from BootConfig -> Deployment
$deploymentType = "Media"
$deploymentConfig = Get-LiteDeployProperty $bootConfig "Deployment"
$configuredDeploymentType = Get-LiteDeployProperty $deploymentConfig "Type"
if (-not [string]::IsNullOrWhiteSpace([string]$configuredDeploymentType)) {
    $deploymentType = [string]$configuredDeploymentType
}

# Read Configuration Options from BootConfig -> ComputerSetup
$promptComputerName = $true
$maxNameLength      = 15
$namePrefix         = ""
$promptDescription  = $true
$driveSelection     = $true
$imageEngine        = "Setup.exe"

$computerSetupConfig = Get-LiteDeployProperty $bootConfig "ComputerSetup"
if ($null -ne $computerSetupConfig) {
    $configuredPromptComputerName = Get-LiteDeployProperty $computerSetupConfig "PromptForComputerName"
    $configuredMaxNameLength = Get-LiteDeployProperty $computerSetupConfig "MaxComputerNameLength"
    $configuredNamePrefix = Get-LiteDeployProperty $computerSetupConfig "ComputerNamePrefix"
    $configuredPromptDescription = Get-LiteDeployProperty $computerSetupConfig "PromptForComputerDescription"
    $configuredDriveSelection = Get-LiteDeployProperty $computerSetupConfig "DriveSelection"
    $configuredImageEngine = Get-LiteDeployProperty $computerSetupConfig "ImageEngine"

    if ($null -ne $configuredPromptComputerName) {
        $promptComputerName = [bool]$configuredPromptComputerName
    }
    if ($null -ne $configuredMaxNameLength -and [int]$configuredMaxNameLength -gt 0) {
        $maxNameLength = [int]$configuredMaxNameLength
    }
    if (-not [string]::IsNullOrEmpty([string]$configuredNamePrefix)) {
        $namePrefix = [string]$configuredNamePrefix
    }
    if ($null -ne $configuredPromptDescription) {
        $promptDescription = [bool]$configuredPromptDescription
    }
    if ($null -ne $configuredDriveSelection) {
        $driveSelection = [bool]$configuredDriveSelection
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$configuredImageEngine)) {
        switch -Regex ([string]$configuredImageEngine.Trim()) {
            '^(?i)setup(\.exe)?$' { $imageEngine = 'Setup.exe' }
            '^(?i)dism(\.exe)?$'  { $imageEngine = 'Dism.exe' }
            default {
                Write-Warning "Unknown ComputerSetup.ImageEngine '$configuredImageEngine'; defaulting to Setup.exe."
                $imageEngine = 'Setup.exe'
            }
        }
    }
}

# Read Configuration Options from BootConfig -> Drivers
$autoDetectDrivers     = $true
$allowManualSelection  = $true
$autoOnlineDownload    = $true
$checkOnlineUpdate     = $true

$driversConfig = Get-LiteDeployProperty $bootConfig "Drivers"
if ($null -ne $driversConfig) {
    $configuredAutoDetect = Get-LiteDeployProperty $driversConfig "AutoDetectDrivers"
    $configuredManualSelection = Get-LiteDeployProperty $driversConfig "AllowManualSelection"
    $configuredOnlineDownload = Get-LiteDeployProperty $driversConfig "AutoOnlineDownloadOnMedia"
    $configuredCheckOnlineUpdate = Get-LiteDeployProperty $driversConfig "CheckOnlineUpdateOnMedia"

    if ($null -ne $configuredAutoDetect) {
        $autoDetectDrivers = [bool]$configuredAutoDetect
    }
    if ($null -ne $configuredManualSelection) {
        $allowManualSelection = [bool]$configuredManualSelection
    }
    if ($null -ne $configuredOnlineDownload) {
        $autoOnlineDownload = [bool]$configuredOnlineDownload
    }
    if ($null -ne $configuredCheckOnlineUpdate) {
        $checkOnlineUpdate = [bool]$configuredCheckOnlineUpdate
    }
}

$script:DeploymentRoot = Resolve-LiteDeployDeploymentRoot -ConfigPath $configPath -BootObject $BootObject
if ($BootObject -and [string]::IsNullOrWhiteSpace($script:DeploymentRoot)) {
    Show-DeploymentWarning -Title "Missing Deployment Root" -Message (
        "BootObject.DeploymentRoot is empty and no share/USB folder containing Content\ was found. Driver packs cannot be resolved from the loaded environment."
    )
}
$script:OemPackLibLoaded = [bool](Get-Command Invoke-MediaOemDriverPackAction -ErrorAction SilentlyContinue)

# Apply Computer Identification Card & Field Settings
if ($promptComputerName -or $promptDescription) {
    if ($null -ne $headerComputerID) { $headerComputerID.Visibility = [System.Windows.Visibility]::Visible }
    if ($null -ne $cardComputerID)   { $cardComputerID.Visibility   = [System.Windows.Visibility]::Visible }

    if ($promptComputerName) {
        if ($null -ne $rowComputerName) { $rowComputerName.Visibility = [System.Windows.Visibility]::Visible }
        if ($null -ne $txtComputerName) {
            $txtComputerName.MaxLength = $maxNameLength
            if (-not [string]::IsNullOrEmpty($namePrefix)) {
                $txtComputerName.Text = $namePrefix
            }
        }
    } else {
        if ($null -ne $rowComputerName) { $rowComputerName.Visibility = [System.Windows.Visibility]::Collapsed }
    }

    if ($promptDescription) {
        if ($null -ne $rowComputerDescription) { $rowComputerDescription.Visibility = [System.Windows.Visibility]::Visible }
    } else {
        if ($null -ne $rowComputerDescription) { $rowComputerDescription.Visibility = [System.Windows.Visibility]::Collapsed }
    }
} else {
    # If BOTH PromptForComputerName and PromptForComputerDescription are false, collapse Section 1 completely!
    if ($null -ne $headerComputerID)       { $headerComputerID.Visibility       = [System.Windows.Visibility]::Collapsed }
    if ($null -ne $cardComputerID)         { $cardComputerID.Visibility         = [System.Windows.Visibility]::Collapsed }
    if ($null -ne $rowComputerName)        { $rowComputerName.Visibility        = [System.Windows.Visibility]::Collapsed }
    if ($null -ne $rowComputerDescription) { $rowComputerDescription.Visibility = [System.Windows.Visibility]::Collapsed }
}

# Apply DriveSelection policy (ComputerSetup.DriveSelection)
if ($driveSelection) {
    if ($null -ne $headerDriveSelection) { $headerDriveSelection.Visibility = [System.Windows.Visibility]::Visible }
    if ($null -ne $cardDriveSelection)   { $cardDriveSelection.Visibility   = [System.Windows.Visibility]::Visible }
    if ($null -ne $txtDiskError)         { $txtDiskError.Visibility         = [System.Windows.Visibility]::Hidden }
} else {
    if ($null -ne $headerDriveSelection) { $headerDriveSelection.Visibility = [System.Windows.Visibility]::Collapsed }
    if ($null -ne $cardDriveSelection)   { $cardDriveSelection.Visibility   = [System.Windows.Visibility]::Collapsed }
    if ($null -ne $txtDiskError)         { $txtDiskError.Visibility         = [System.Windows.Visibility]::Collapsed }
}

# Apply Manual Selection Settings
if ($null -ne $rowManualDriverSelection) {
    $rowManualDriverSelection.Visibility = [System.Windows.Visibility]::Visible
}

if ($allowManualSelection) {
    if ($null -ne $cmbDriverPackPath)     { $cmbDriverPackPath.IsEnabled = $true }
    if ($null -ne $btnBrowseDriverFolder) { $btnBrowseDriverFolder.Visibility = [System.Windows.Visibility]::Visible }
} else {
    if ($null -ne $cmbDriverPackPath)     { $cmbDriverPackPath.IsEnabled = $false }
    if ($null -ne $btnBrowseDriverFolder) { $btnBrowseDriverFolder.Visibility = [System.Windows.Visibility]::Collapsed }
}

# Hide Online Driver Download checkbox unless Deployment Type is Media AND AutoOnlineDownloadOnMedia is true
if ($null -ne $chkOnlineDrivers) {
    if ($deploymentType -eq "Media" -and $autoOnlineDownload) {
        $chkOnlineDrivers.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $chkOnlineDrivers.Visibility = [System.Windows.Visibility]::Collapsed
        $chkOnlineDrivers.IsChecked = $false
    }
}

if ($null -ne $chkCheckOnlineUpdate) {
    if ($deploymentType -eq "Media" -and $autoOnlineDownload -and $checkOnlineUpdate) {
        $chkCheckOnlineUpdate.Visibility = [System.Windows.Visibility]::Visible
        $chkCheckOnlineUpdate.IsChecked = $true
    } else {
        $chkCheckOnlineUpdate.Visibility = [System.Windows.Visibility]::Collapsed
        $chkCheckOnlineUpdate.IsChecked = $false
    }
}

# WMI Driver Detection Engine (catalog.json SKU/model, then Content\Drivers\<Manufacturer>\<Model>)
function Get-SystemDriverDetection {
    $hardware = if (Get-Command Get-SystemHardwareIdentity -ErrorAction SilentlyContinue) {
        Get-SystemHardwareIdentity
    } else {
        [pscustomobject]@{
            ManufacturerId   = "Unknown"
            ManufacturerName = "Unknown"
            ModelName        = "Unknown"
            SystemSku        = @()
            CompareSupported = $false
        }
    }

    $local = $null
    if ($script:DeploymentRoot -and (Get-Command Find-LocalMediaDriverModel -ErrorAction SilentlyContinue)) {
        $local = Find-LocalMediaDriverModel -DeploymentRoot $script:DeploymentRoot -Hardware $hardware
    }

    if (-not $local) {
        $driversRoot = Join-Path $script:DeploymentRoot "Content\Drivers"
        $targetFolder = Join-Path $driversRoot (Join-Path $hardware.ManufacturerName $hardware.ModelName)
        $detected = Test-Path -LiteralPath $targetFolder
        return [PSCustomObject]@{
            Manufacturer     = $hardware.ManufacturerName
            ManufacturerId   = $hardware.ManufacturerId
            Model            = $hardware.ModelName
            SystemSku        = @($hardware.SystemSku)
            CompareSupported = [bool]$hardware.CompareSupported
            RelativePath     = if ($detected) { "Content\Drivers\$($hardware.ManufacturerName)\$($hardware.ModelName)" } else { "Standard OS In-Box Drivers" }
            FullPath         = if ($detected) { $targetFolder } else { $null }
            IsDetected       = $detected
            LocalVersion     = ""
            Hardware         = $hardware
            Local            = $null
        }
    }

    return [PSCustomObject]@{
        Manufacturer     = $hardware.ManufacturerName
        ManufacturerId   = $hardware.ManufacturerId
        Model            = $local.ModelName
        SystemSku        = @($hardware.SystemSku)
        CompareSupported = [bool]$hardware.CompareSupported
        RelativePath     = $local.Path
        FullPath         = $local.FullPath
        IsDetected       = [bool]$local.PathOk
        LocalVersion     = [string]$local.Version
        Hardware         = $hardware
        Local            = $local
    }
}

# Run WMI Auto-Detection if policy enables it
if ($autoDetectDrivers) {
    $script:DetectionResult = Get-SystemDriverDetection

    if ($null -ne $txtDetectedHardware) {
        $txtDetectedHardware.Text = "$($script:DetectionResult.Manufacturer) $($script:DetectionResult.Model)"
    }
} else {
    $script:DetectionResult = [PSCustomObject]@{
        Manufacturer     = "N/A"
        ManufacturerId   = ""
        Model            = "Auto-Detect Disabled"
        SystemSku        = @()
        CompareSupported = $false
        RelativePath     = "Standard OS In-Box Drivers"
        FullPath         = $null
        IsDetected       = $false
        LocalVersion     = ""
        Hardware         = $null
        Local            = $null
    }

    if ($null -ne $txtDetectedHardware) {
        $txtDetectedHardware.Text = "Auto-Detection Disabled by Policy"
    }
}

# When local pack exists on comparable OEM media, default check-update on if policy allows.
if ($null -ne $chkCheckOnlineUpdate -and $script:DetectionResult.CompareSupported -eq $false) {
    $chkCheckOnlineUpdate.IsEnabled = $false
    $chkCheckOnlineUpdate.Content = "Online pack update check is only available for Dell, HP, and Lenovo"
}

# Populate Driver Selection ComboBox cleanly
if ($null -ne $cmbDriverPackPath) {
    $cmbDriverPackPath.Items.Clear()

    # Auto-Detect Option (Only included if a matching driver pack was found on disk/share)
    if ($script:DetectionResult.IsDetected) {
        $null = $cmbDriverPackPath.Items.Add("Auto-Detect: $($script:DetectionResult.RelativePath)")
    }

    # Standard OS In-Box Drivers Option
    $null = $cmbDriverPackPath.Items.Add("Standard OS In-Box Drivers (Windows Default)")

    # Online Download Option (If Media mode & AutoOnlineDownloadOnMedia is enabled)
    if ($deploymentType -eq "Media" -and $autoOnlineDownload) {
        $null = $cmbDriverPackPath.Items.Add("Online Download (Web Repository)")
    }

    # Precedence Rules on Window Launch:
    # 1. Local driver pack detected -> Default to Auto-Detect local pack
    # 2. Local driver pack missing & Media Online Download enabled -> Default to Online Download
    # 3. Otherwise -> Default to Standard OS In-Box Drivers
    if ($script:DetectionResult.IsDetected) {
        $cmbDriverPackPath.SelectedIndex = 0
        if ($null -ne $chkOnlineDrivers) { $chkOnlineDrivers.IsChecked = $false }
    } elseif ($deploymentType -eq "Media" -and $autoOnlineDownload) {
        for ($i = 0; $i -lt $cmbDriverPackPath.Items.Count; $i++) {
            if ($cmbDriverPackPath.Items[$i].ToString() -like "*Online Download*") {
                $cmbDriverPackPath.SelectedIndex = $i
                break
            }
        }
        if ($null -ne $chkOnlineDrivers) { $chkOnlineDrivers.IsChecked = $true }
    } else {
        $cmbDriverPackPath.SelectedIndex = 0
        if ($null -ne $chkOnlineDrivers) { $chkOnlineDrivers.IsChecked = $false }
    }
}

# Browse Folder Button Event Handler
if ($null -ne $btnBrowseDriverFolder) {
    $btnBrowseDriverFolder.Add_Click({
        if (-not (Get-Command Show-DriverPathDialog -ErrorAction SilentlyContinue)) {
            [System.Windows.MessageBox]::Show(
                "The WinPE driver folder picker could not be loaded from:`n$driverPathPickerScript",
                "Driver Folder Picker",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
            return
        }

        $initialDriverPath = if ($script:DetectionResult.FullPath) {
            $script:DetectionResult.FullPath
        } else {
            Join-Path $script:DeploymentRoot "Content\Drivers"
        }

        $customPath = Show-DriverPathDialog -WindowTitle "Select Driver Folder" -InitialPath $initialDriverPath -Owner $window
        if ($customPath) {
            $customEntry = "Custom: $customPath"
            $existingIndex = $cmbDriverPackPath.Items.IndexOf($customEntry)
            if ($existingIndex -lt 0) {
                $existingIndex = $cmbDriverPackPath.Items.Add($customEntry)
            }
            $cmbDriverPackPath.SelectedIndex = $existingIndex
        }
    })
}

# Sync Online Download Checkbox & ComboBox Selection
if ($null -ne $chkOnlineDrivers -and $null -ne $cmbDriverPackPath) {
    $chkOnlineDrivers.add_Checked({
        for ($i = 0; $i -lt $cmbDriverPackPath.Items.Count; $i++) {
            if ($cmbDriverPackPath.Items[$i].ToString() -like "*Online Download*") {
                $cmbDriverPackPath.SelectedIndex = $i
                break
            }
        }
    })

    $chkOnlineDrivers.add_Unchecked({
        if ($cmbDriverPackPath.SelectedItem -and $cmbDriverPackPath.SelectedItem.ToString() -like "*Online Download*") {
            $cmbDriverPackPath.SelectedIndex = 0
        }
    })

    $cmbDriverPackPath.add_SelectionChanged({
        if ($cmbDriverPackPath.SelectedItem) {
            if ($cmbDriverPackPath.SelectedItem.ToString() -like "*Online Download*") {
                $chkOnlineDrivers.IsChecked = $true
            } else {
                $chkOnlineDrivers.IsChecked = $false
            }
        }
    })
}

# Returns free filesystem bytes plus unallocated bytes. Unreadable partitions
# contribute no free bytes and are therefore conservatively counted as used.
function Get-StorageAvailableBytes {
    param(
        [int]$DiskNumber,
        [double]$TotalBytes
    )

    if (-not (Get-Command Get-Partition -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        $partitions = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction Stop)
        $partitionedBytes = 0.0
        $readableFreeBytes = 0.0
        $canReadVolumes = $null -ne (Get-Command Get-Volume -ErrorAction SilentlyContinue)

        foreach ($partition in $partitions) {
            $partitionBytes = [math]::Max(0.0, [double]$partition.Size)
            $partitionedBytes += $partitionBytes

            if ($canReadVolumes) {
                try {
                    $volume = $partition | Get-Volume -ErrorAction Stop | Select-Object -First 1
                    if ($null -ne $volume -and $null -ne $volume.SizeRemaining) {
                        $volumeFreeBytes = [math]::Max(0.0, [double]$volume.SizeRemaining)
                        $readableFreeBytes += [math]::Min($partitionBytes, $volumeFreeBytes)
                    }
                } catch {
                    # Locked, RAW, hidden, or unmounted partitions count fully as used.
                }
            }
        }

        $unallocatedBytes = [math]::Max(0.0, $TotalBytes - $partitionedBytes)
        return [math]::Min($TotalBytes, $unallocatedBytes + $readableFreeBytes)
    } catch {
        return $null
    }
}

# WMI fallback for WinPE images without the Storage PowerShell cmdlets.
function Get-WmiAvailableBytes {
    param(
        [int]$DiskIndex,
        [double]$TotalBytes,
        [int]$ExpectedPartitionCount = 0
    )

    try {
        $partitions = @(Get-WmiObject -Class Win32_DiskPartition -Filter "DiskIndex = $DiskIndex" -ErrorAction Stop)
        if ($ExpectedPartitionCount -gt 0 -and $partitions.Count -eq 0) {
            return $null
        }

        $partitionedBytes = 0.0
        $readableFreeBytes = 0.0

        foreach ($partition in $partitions) {
            $partitionBytes = [math]::Max(0.0, [double]$partition.Size)
            $partitionedBytes += $partitionBytes

            try {
                $partitionId = ([string]$partition.DeviceID).Replace("'", "''")
                $query = "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$partitionId'} WHERE AssocClass=Win32_LogicalDiskToPartition"
                $logicalDisks = @(Get-WmiObject -Query $query -ErrorAction Stop)
                $partitionFreeBytes = 0.0

                foreach ($logicalDisk in $logicalDisks) {
                    if ($null -ne $logicalDisk.FreeSpace) {
                        $partitionFreeBytes += [math]::Max(0.0, [double]$logicalDisk.FreeSpace)
                    }
                }

                $readableFreeBytes += [math]::Min($partitionBytes, $partitionFreeBytes)
            } catch {
                # If WMI cannot map a filesystem, count the partition fully as used.
            }
        }

        $unallocatedBytes = [math]::Max(0.0, $TotalBytes - $partitionedBytes)
        return [math]::Min($TotalBytes, $unallocatedBytes + $readableFreeBytes)
    } catch {
        return $null
    }
}

function New-WinPEDiskRow {
    param(
        [int]$DiskNumber,
        [string]$Model,
        [double]$TotalBytes,
        $AvailableBytes
    )

    # Unknown space is handled conservatively: all capacity is considered used.
    $safeAvailableBytes = if ($null -eq $AvailableBytes) {
        0.0
    } else {
        [math]::Min($TotalBytes, [math]::Max(0.0, [double]$AvailableBytes))
    }

    # Derive usage from rounded display values so Capacity = Usage + Available.
    $totalGB = [math]::Round($TotalBytes / 1GB, 1)
    $availableGB = [math]::Round($safeAvailableBytes / 1GB, 1)
    $usedGB = [math]::Max(0.0, [math]::Round($totalGB - $availableGB, 1))

    return [PSCustomObject]@{
        Index      = "Disk $DiskNumber"
        Model      = $Model
        Capacity   = "$totalGB GB"
        UsedSpace  = "$usedGB GB"
        FreeSpace  = "$availableGB GB"
        DiskNumber = $DiskNumber
    }
}

# Physical Hard Drive Retrieval Logic (aligned with LiteDeploy.PreCheck.ps1)
function Get-WinPEPhysicalDisks {
    $diskList = @()

    try {
        if (Get-Command Get-Disk -ErrorAction SilentlyContinue) {
            $disks = @(Get-Disk -ErrorAction Stop | Where-Object {
                $_.BusType -ne "USB" -and [double]$_.Size -gt 0 -and
                ($_.OperationalStatus -eq "Online" -or $_.OperationalStatus -contains "Online")
            } | Sort-Object Number)

            foreach ($disk in $disks) {
                $totalBytes = [double]$disk.Size
                $model = if ($disk.Model) {
                    $disk.Model.Trim()
                } elseif ($disk.FriendlyName) {
                    $disk.FriendlyName.Trim()
                } else {
                    "Internal Drive"
                }

                $availableBytes = Get-StorageAvailableBytes -DiskNumber $disk.Number -TotalBytes $totalBytes
                if ($null -eq $availableBytes) {
                    $availableBytes = Get-WmiAvailableBytes -DiskIndex $disk.Number -TotalBytes $totalBytes -ExpectedPartitionCount $disk.NumberOfPartitions
                }

                $diskList += New-WinPEDiskRow -DiskNumber $disk.Number -Model $model -TotalBytes $totalBytes -AvailableBytes $availableBytes
            }
        }
    } catch {
        $diskList = @()
    }

    if ($diskList.Count -eq 0) {
        try {
            $wmiDisks = @(Get-WmiObject -Class Win32_DiskDrive -ErrorAction Stop | Where-Object {
                $_.InterfaceType -ne "USB" -and $_.MediaType -notlike "*Removable*" -and [double]$_.Size -gt 0
            } | Sort-Object Index)

            foreach ($disk in $wmiDisks) {
                $totalBytes = [double]$disk.Size
                $model = if ($disk.Model) { $disk.Model.Trim() } else { "Internal Drive" }
                $availableBytes = Get-WmiAvailableBytes -DiskIndex $disk.Index -TotalBytes $totalBytes -ExpectedPartitionCount $disk.Partitions
                $diskList += New-WinPEDiskRow -DiskNumber $disk.Index -Model $model -TotalBytes $totalBytes -AvailableBytes $availableBytes
            }
        } catch {
            $diskList = @()
        }
    }

    if ($diskList.Count -gt 0) {
        return $diskList
    }

    # Never expose sample disks in WinPE; an empty result safely blocks deployment.
    return @()
}

# Auto-populate physical disk list on launch
if ($null -ne $gridDisks) {
    [object[]]$detectedDisks = @(Get-WinPEPhysicalDisks)
    $gridDisks.ItemsSource = $detectedDisks
}

# Unified Action Handler (Start Deployment / Validate All Sections)
# Returns a structured selection to LiteDeploy.DeploymentEngine; does not start Setup.
$script:DeploymentRequested = $false
$script:ComputerName = ""
$script:ComputerDescription = ""
$script:SelectedWorkflowTag = $null
$script:SelectedOSName = ""
$script:SelectedDiskIndex = $null
$script:SelectedDiskNumber = $null
$script:SelectedDiskModel = ""
$script:SelectedDriverFolderPath = ""
$script:AutoDetectDrivers = $autoDetectDrivers
$script:DriveSelection = [bool]$driveSelection
$script:ImageEngine = [string]$imageEngine

if ($null -ne $btnNext) {
    $btnNext.Add_Click({
        $hasError = $false
        $validationMessages = @()
        $firstInvalidControl = $null

        # Hidden preserves the reserved validation rows so errors never shift the UI.
        if ($null -ne $txtComputerNameError) { $txtComputerNameError.Visibility = [System.Windows.Visibility]::Hidden; $txtComputerNameError.Text = "" }
        if ($null -ne $txtWorkflowError)     { $txtWorkflowError.Visibility     = [System.Windows.Visibility]::Hidden; $txtWorkflowError.Text = "" }
        if ($null -ne $txtDiskError)         { $txtDiskError.Visibility         = [System.Windows.Visibility]::Hidden; $txtDiskError.Text = "" }

        # 1. Validate Computer Name (if enabled)
        if ($promptComputerName -and $null -ne $txtComputerName) {
            $compName = $txtComputerName.Text.Trim()

            if ([string]::IsNullOrWhiteSpace($compName)) {
                $txtComputerNameError.Text = "Computer name cannot be empty."
                $txtComputerNameError.Visibility = [System.Windows.Visibility]::Visible
                $validationMessages += "- Enter a computer name."
                $firstInvalidControl = $txtComputerName
                $hasError = $true
            } elseif ($compName.Length -gt $maxNameLength) {
                $txtComputerNameError.Text = "Computer name must not exceed $maxNameLength characters."
                $txtComputerNameError.Visibility = [System.Windows.Visibility]::Visible
                $validationMessages += "- Computer name must not exceed $maxNameLength characters."
                $firstInvalidControl = $txtComputerName
                $hasError = $true
            } elseif ($compName -match '[\\/:\*\?"<>\|\s]') {
                $txtComputerNameError.Text = 'Computer name contains invalid characters (\ / : * ? " < > | or spaces).'
                $txtComputerNameError.Visibility = [System.Windows.Visibility]::Visible
                $validationMessages += '- Computer name contains invalid characters (\ / : * ? " < > | or spaces).'
                $firstInvalidControl = $txtComputerName
                $hasError = $true
            } else {
                $script:ComputerName = $compName
            }
        }

        if ($promptDescription -and $null -ne $txtComputerDescription) {
            $script:ComputerDescription = $txtComputerDescription.Text.Trim()
        }

        # 2. Validate Deployment Workflow Selection
        $selectedItem = $treeView.SelectedItem
        if (-not $selectedItem -or -not $selectedItem.Tag) {
            $txtWorkflowError.Text = "Please select an OS workflow from the list above."
            $txtWorkflowError.Visibility = [System.Windows.Visibility]::Visible
            $validationMessages += "- Select an operating-system workflow."
            if ($null -eq $firstInvalidControl) { $firstInvalidControl = $treeView }
            $hasError = $true
        } else {
            $script:SelectedWorkflowTag = $selectedItem.Tag
            $script:SelectedOSName      = $selectedItem.Header.Name
        }

        # 3. Validate Target Hard Drive Selection (or auto-pick when DriveSelection is false)
        if ($driveSelection) {
            $selectedDisk = $gridDisks.SelectedItem
            if (-not $selectedDisk) {
                if ($gridDisks.Items.Count -eq 0) {
                    $txtDiskError.Text = "No internal disks were detected. Load the storage driver and refresh."
                    $validationMessages += "- No internal disks were detected. Load the storage driver and refresh."
                } else {
                    $txtDiskError.Text = "Please select a target hard drive from the table above."
                    $validationMessages += "- Select a target hard drive."
                }
                $txtDiskError.Visibility = [System.Windows.Visibility]::Visible
                if ($null -eq $firstInvalidControl) { $firstInvalidControl = $gridDisks }
                $hasError = $true
            } else {
                $script:SelectedDiskIndex = $selectedDisk.Index
                $script:SelectedDiskModel = $selectedDisk.Model
                # Numeric DiskNumber is the execution identifier for the engine (not the display Index).
                if ($selectedDisk.PSObject.Properties['DiskNumber']) {
                    $script:SelectedDiskNumber = [int]$selectedDisk.DiskNumber
                } else {
                    $script:SelectedDiskNumber = $null
                }
            }
        } else {
            # Policy hides the picker: use the first detected internal disk.
            $autoDisk = $null
            if ($null -ne $gridDisks -and $gridDisks.Items.Count -gt 0) {
                $autoDisk = $gridDisks.Items[0]
            }
            if (-not $autoDisk) {
                $validationMessages += "- No internal disks were detected. Load the storage driver and retry."
                $hasError = $true
            } else {
                $script:SelectedDiskIndex = $autoDisk.Index
                $script:SelectedDiskModel = $autoDisk.Model
                if ($autoDisk.PSObject.Properties['DiskNumber']) {
                    $script:SelectedDiskNumber = [int]$autoDisk.DiskNumber
                } else {
                    $script:SelectedDiskNumber = $null
                }
            }
        }

        # 4. Save Driver Selection Path (+ Media online download / update check)
        $script:AutoDetectDrivers = $autoDetectDrivers
        if ($null -ne $cmbDriverPackPath -and $null -ne $cmbDriverPackPath.SelectedItem) {
            $selectedDriverChoice = $cmbDriverPackPath.SelectedItem.ToString()
            if ($selectedDriverChoice.StartsWith("Custom: ")) {
                $script:SelectedDriverFolderPath = $selectedDriverChoice.Substring(8)
            } elseif ($selectedDriverChoice.StartsWith("Auto-Detect: ") -and $script:DetectionResult.FullPath) {
                $script:SelectedDriverFolderPath = $script:DetectionResult.FullPath
            } else {
                $script:SelectedDriverFolderPath = $selectedDriverChoice
            }
        } else {
            $script:SelectedDriverFolderPath = $script:DetectionResult.RelativePath
        }

        $script:WantsOnlineDownload = $false
        if ($null -ne $chkOnlineDrivers -and $chkOnlineDrivers.IsChecked) { $script:WantsOnlineDownload = $true }
        if ($script:SelectedDriverFolderPath -like "*Online Download*") { $script:WantsOnlineDownload = $true }
        $script:WantsUpdateCheck = ($null -ne $chkCheckOnlineUpdate -and $chkCheckOnlineUpdate.IsChecked -eq $true)

        if ($hasError) {
            Show-DeploymentWarning -Message ("Complete the following before starting deployment:`r`n`r`n" + ($validationMessages -join "`r`n"))
            if ($null -ne $firstInvalidControl) {
                $firstInvalidControl.Focus() | Out-Null
            }
            return
        }

        # Confirm & Complete Setup
        $confirmMsg = "Ready to proceed with deployment?`n`n" +
                      "Computer Name: $($script:ComputerName)`n" +
                      "Workflow: $($script:SelectedOSName)`n" +
                      "Target Disk: $($script:SelectedDiskIndex) ($($script:SelectedDiskModel))`n" +
                      "Driver Path: $($script:SelectedDriverFolderPath)"

        $confirm = [System.Windows.MessageBox]::Show(
            $confirmMsg,
            "Confirm Deployment",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Information
        )

        if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
            $needsOemLib = $script:WantsOnlineDownload -or $script:WantsUpdateCheck
            if ($deploymentType -eq "Media" -and $autoOnlineDownload -and $needsOemLib) {
                if (-not $script:OemPackLibLoaded) {
                    Show-DeploymentWarning -Title "Online Driver Pack" -Message (
                        "OemDriverPackCatalog.ps1 was not found beside the engine scripts or under the loaded deployment root.`r`n`r`nCopy LiteDeploy.OemDriverPackCatalog.ps1 to Engine\Scripts to enable Media online download."
                    )
                    return
                }
                if ([string]::IsNullOrWhiteSpace($script:DeploymentRoot)) {
                    Show-DeploymentWarning -Title "Online Driver Pack" -Message (
                        "Deployment root was not resolved from the loaded environment (share or USB media). Cannot download a driver pack."
                    )
                    return
                }

                $hardware = if ($script:DetectionResult.Hardware) { $script:DetectionResult.Hardware } else { Get-SystemHardwareIdentity }
                $localExists = [bool]$script:DetectionResult.IsDetected

                try {
                    if ($script:WantsOnlineDownload -and -not $localExists) {
                        $downloadResult = Invoke-MediaOemDriverPackAction -DeploymentRoot $script:DeploymentRoot -Hardware $hardware
                        if ($downloadResult.Action -in @("Downloaded", "Replaced") -and $downloadResult.DriverFolderPath) {
                            $script:SelectedDriverFolderPath = $downloadResult.DriverFolderPath
                            $script:DetectionResult.IsDetected = $true
                            $script:DetectionResult.FullPath = $downloadResult.DriverFolderPath
                        }
                        elseif ($downloadResult.Action -in @("PackNotFound", "CompareNotSupported")) {
                            $confirmFallback = [System.Windows.MessageBox]::Show(
                                "$($downloadResult.Message)`r`n`r`nContinue with Standard OS In-Box Drivers?",
                                "Online Driver Pack",
                                [System.Windows.MessageBoxButton]::YesNo,
                                [System.Windows.MessageBoxImage]::Warning
                            )
                            if ($confirmFallback -ne [System.Windows.MessageBoxResult]::Yes) {
                                return
                            }
                            $script:SelectedDriverFolderPath = "Standard OS In-Box Drivers (Windows Default)"
                        }
                    }
                    elseif ($localExists -and $script:WantsUpdateCheck -and $hardware.CompareSupported) {
                        $checkResult = Invoke-MediaOemDriverPackAction -DeploymentRoot $script:DeploymentRoot -Hardware $hardware -CheckUpdate
                        if ($checkResult.Action -eq "UpdateAvailable") {
                            $updateChoice = [System.Windows.MessageBox]::Show(
                                "$($checkResult.Message)`r`n`r`nDownload and replace the pack on this media?",
                                "Driver Pack Update Available",
                                [System.Windows.MessageBoxButton]::YesNo,
                                [System.Windows.MessageBoxImage]::Information
                            )
                            if ($updateChoice -eq [System.Windows.MessageBoxResult]::Yes) {
                                $replaceResult = Invoke-MediaOemDriverPackAction -DeploymentRoot $script:DeploymentRoot -Hardware $hardware -ForceDownload
                                if ($replaceResult.DriverFolderPath) {
                                    $script:SelectedDriverFolderPath = $replaceResult.DriverFolderPath
                                }
                            }
                            else {
                                $script:SelectedDriverFolderPath = $script:DetectionResult.FullPath
                            }
                        }
                        elseif ($checkResult.DriverFolderPath) {
                            $script:SelectedDriverFolderPath = $checkResult.DriverFolderPath
                        }
                    }
                    elseif ($localExists -and $script:DetectionResult.FullPath) {
                        $script:SelectedDriverFolderPath = $script:DetectionResult.FullPath
                    }
                }
                catch {
                    Show-DeploymentWarning -Title "Online Driver Pack" -Message (
                        "Online driver pack action failed:`r`n`r`n$($_.Exception.Message)"
                    )
                    return
                }
            }

            $script:DeploymentRequested = $true
            $window.Close()
        }
    })
}

if ($null -ne $btnBack) {
    $btnBack.Add_Click({
        $window.Close()
    })
}

if ($null -ne $btnRefresh) {
    $btnRefresh.Add_Click({
        if ($null -ne $gridDisks) {
            [object[]]$detectedDisks = @(Get-WinPEPhysicalDisks)
            $gridDisks.ItemsSource = $detectedDisks
            if ($null -ne $txtDiskError) {
                if ($detectedDisks.Count -eq 0) {
                    $txtDiskError.Text = ""
                    $txtDiskError.Visibility = [System.Windows.Visibility]::Hidden
                    Show-DeploymentWarning -Message "No internal disks were detected. Load the storage driver and refresh."
                } else {
                    $txtDiskError.Text = ""
                    $txtDiskError.Visibility = [System.Windows.Visibility]::Hidden
                }
            }
        }
    })
}

$window.Add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Escape) { $window.Close() }
})

# Display Window
$window.ShowDialog() | Out-Null

if (-not $script:DeploymentRequested) {
    return [PSCustomObject]@{
        DeploymentRequested = $false
        Status              = "Cancelled"
    }
}

# Structured selection for LiteDeploy.DeploymentEngine.
# osId / editionId / workflowId remain null until ImportOSMedia catalogs drive the UI.
return [PSCustomObject]@{
    DeploymentRequested = $true
    Status              = "Confirmed"
    ComputerName        = [string]$script:ComputerName
    ComputerDescription = [string]$script:ComputerDescription
    WorkflowName        = [string]$script:SelectedOSName
    WorkflowTag         = $script:SelectedWorkflowTag
    OsId                = $null
    EditionId           = $null
    WorkflowId          = $null
    DiskNumber          = $script:SelectedDiskNumber
    DiskIndex           = $script:SelectedDiskIndex
    DiskModel           = [string]$script:SelectedDiskModel
    DriveSelection      = [bool]$script:DriveSelection
    ImageEngine         = [string]$script:ImageEngine
    DriverFolderPath    = [string]$script:SelectedDriverFolderPath
    AutoDetectDrivers   = [bool]$script:AutoDetectDrivers
}
