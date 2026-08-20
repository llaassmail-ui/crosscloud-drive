[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot "OssMount.State.ps1")
. (Join-Path $PSScriptRoot "OssMount.Localization.ps1")
. (Join-Path $PSScriptRoot "OssMount.Core.ps1")
. (Join-Path $PSScriptRoot "OssMount.Tasks.ps1")
. (Join-Path $PSScriptRoot "OssMount.Removal.ps1")
. (Join-Path $PSScriptRoot "providers\AlibabaOss.Provider.ps1")

$script:Paths = Get-CrossCloudPaths
$script:State = Import-CrossCloudLegacyConnection -Paths $script:Paths
if (-not $script:State) { $script:State = Get-CrossCloudConnectionState -Paths $script:Paths }
$savedLanguage = Get-SavedCrossCloudLanguage -SettingsFile $script:Paths.SettingsFile
$windowsLanguage = [Globalization.CultureInfo]::InstalledUICulture.Name
$script:Language = Resolve-CrossCloudLanguage -SavedLanguage $savedLanguage -WindowsLanguage $windowsLanguage
$script:Locale = Import-CrossCloudLocale -Language $script:Language
$script:ActivityLines = New-Object Collections.ArrayList
$script:LastError = ""
$script:LastChecked = $null
$script:TranslatableControls = New-Object Collections.ArrayList
$script:ActivityFilter = "All"
$script:OperationBusy = $false
$script:RegionChoices = @()

function Get-UiText {
    param([string]$Key, [object[]]$Arguments = @())
    return Get-CrossCloudText -Dictionary $script:Locale -Key $Key -Arguments $Arguments
}

function Get-LanguageSwitchText {
    if ($script:Language -eq "zh-CN") { return "English" }
    return ([char]0x4E2D).ToString() + ([char]0x6587).ToString()
}

function New-UiLabel {
    param([string]$Key, [int]$X, [int]$Y, [int]$Width = 180, [int]$Height = 24, [int]$FontSize = 9)
    $label = New-Object Windows.Forms.Label
    $label.Tag = $Key
    $label.Text = Get-UiText $Key
    $label.Location = New-Object Drawing.Point($X, $Y)
    $label.Size = New-Object Drawing.Size($Width, $Height)
    $label.Font = New-Object Drawing.Font("Segoe UI", $FontSize)
    $label.ForeColor = [Drawing.Color]::FromArgb(70, 80, 92)
    [void]$script:TranslatableControls.Add($label)
    return $label
}

function New-UiTextBox {
    param([int]$X, [int]$Y, [int]$Width = 300, [bool]$Password = $false)
    $box = New-Object Windows.Forms.TextBox
    $box.Location = New-Object Drawing.Point($X, $Y)
    $box.Size = New-Object Drawing.Size($Width, 28)
    $box.BorderStyle = "FixedSingle"
    $box.UseSystemPasswordChar = $Password
    return $box
}

function New-UiButton {
    param([string]$Key, [int]$X, [int]$Y, [int]$Width = 140, [bool]$Primary = $false)
    $button = New-Object Windows.Forms.Button
    $button.Tag = $Key
    $button.Text = Get-UiText $Key
    $button.Location = New-Object Drawing.Point($X, $Y)
    $button.Size = New-Object Drawing.Size($Width, 34)
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = if ($Primary) { [Drawing.Color]::FromArgb(28, 104, 150) } else { [Drawing.Color]::FromArgb(232, 237, 242) }
    $button.ForeColor = if ($Primary) { [Drawing.Color]::White } else { [Drawing.Color]::FromArgb(35, 48, 61) }
    $button.Cursor = [Windows.Forms.Cursors]::Hand
    [void]$script:TranslatableControls.Add($button)
    return $button
}

function New-UiPoint {
    param([int]$X, [int]$Y)

    return New-Object -TypeName Drawing.Point -ArgumentList ([int]$X), ([int]$Y)
}

function New-SectionHeader {
    param([string]$Key, [int]$X, [int]$Y)
    $label = New-UiLabel -Key $Key -X $X -Y $Y -Width 650 -Height 30 -FontSize 12
    $label.Font = New-Object Drawing.Font("Segoe UI Semibold", 12)
    $label.ForeColor = [Drawing.Color]::FromArgb(30, 45, 60)
    return $label
}

function Add-Activity {
    param([string]$Message, [string]$Kind = "Info")
    [void]$script:ActivityLines.Insert(0, [pscustomobject]@{
        Text = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
        Kind = $Kind
    })
    while ($script:ActivityLines.Count -gt 500) { $script:ActivityLines.RemoveAt($script:ActivityLines.Count - 1) }
    if ($script:ActivityList) { Update-ActivityList }
}

function Update-ActivityList {
    $script:ActivityList.Items.Clear()
    foreach ($item in $script:ActivityLines) {
        if ($script:ActivityFilter -eq "All" -or $item.Kind -eq $script:ActivityFilter) {
            [void]$script:ActivityList.Items.Add($item.Text)
        }
    }
    if ($script:ActivityList.Items.Count -eq 0) {
        [void]$script:ActivityList.Items.Add((Get-UiText "ActivityEmpty"))
    }
}

function Set-ActivityFilter {
    param([ValidateSet("All", "Error", "Mount", "Upload")][string]$Filter)

    $script:ActivityFilter = $Filter
    Update-ActivityList
}

function Set-OperationBusy {
    param([bool]$Busy)

    $script:OperationBusy = $Busy
    foreach ($control in @(
        $script:InstallButton, $script:TestButton, $script:ConnectButton,
        $script:ReconnectButton, $script:StopButton, $script:RemoveButton
    )) {
        if ($control) { $control.Enabled = -not $Busy }
    }
}

function Test-WinFspInstalled {
    $roots = @(
        (Join-Path $env:ProgramFiles "WinFsp\bin"),
        (Join-Path ${env:ProgramFiles(x86)} "WinFsp\bin")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($root in $roots) {
        if (Test-Path -LiteralPath $root) {
            $dll = Get-ChildItem -LiteralPath $root -Filter "winfsp-*.dll" -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($dll) { return $true }
        }
    }
    return [bool](Get-Service -Name "WinFsp.Launcher" -ErrorAction SilentlyContinue)
}

function Update-Components {
    $rcloneInstalled = [bool](Get-CrossCloudRcloneExe)
    $winFspInstalled = Test-WinFspInstalled
    $script:RcloneValue.Text = if ($rcloneInstalled) { Get-UiText "Installed" } else { Get-UiText "NotInstalled" }
    $script:WinFspValue.Text = if ($winFspInstalled) { Get-UiText "Installed" } else { Get-UiText "NotInstalled" }
    $script:RcloneValue.ForeColor = if ($rcloneInstalled) { [Drawing.Color]::FromArgb(40, 120, 86) } else { [Drawing.Color]::FromArgb(180, 90, 40) }
    $script:WinFspValue.ForeColor = if ($winFspInstalled) { [Drawing.Color]::FromArgb(40, 120, 86) } else { [Drawing.Color]::FromArgb(180, 90, 40) }
}

function Set-ConnectionStatus {
    param([string]$Key, [Drawing.Color]$Color = [Drawing.Color]::FromArgb(40, 120, 86))
    $text = Get-UiText $Key
    $script:StatusValue.Text = $text
    $script:ConnectionStatus.Text = $text
    $script:StatusValue.ForeColor = $Color
    $script:ConnectionStatus.ForeColor = $Color
}

function Show-ApplicationPage {
    param([ValidateSet("Connection", "Settings", "Activity")][string]$Name)
    $script:ConnectionPage.Visible = ($Name -eq "Connection")
    $script:SettingsPage.Visible = ($Name -eq "Settings")
    $script:ActivityPage.Visible = ($Name -eq "Activity")
    if ($Name -eq "Connection") { $script:ConnectionPage.BringToFront() }
    if ($Name -eq "Settings") { $script:SettingsPage.BringToFront() }
    if ($Name -eq "Activity") { $script:ActivityPage.BringToFront() }
}

function Update-ConnectionPage {
    $configured = -not [string]::IsNullOrWhiteSpace([string]$script:State.Bucket)
    if ($configured) {
        $script:ConnectionTarget.Text = "{0}:  {1}" -f $script:State.DriveLetter, (Get-CrossCloudRemoteTarget -State $script:State)
        $script:ConnectionEndpoint.Text = "{0}:  {1}" -f (Get-UiText "EndpointSummary"), $script:State.Endpoint
        $script:ConnectionHint.Text = if ($script:LastChecked) { "{0}:  {1}" -f (Get-UiText "LastChecked"), $script:LastChecked.ToString("HH:mm:ss") } else { Get-UiText "NotChecked" }
        $script:ConfigureButton.Visible = $false
        $script:OpenButton.Visible = $true
        $script:ReconnectButton.Visible = $true
        $script:StopButton.Visible = $true
    }
    else {
        $script:ConnectionTarget.Text = Get-UiText "ConnectionEmptyTitle"
        $script:ConnectionEndpoint.Text = Get-UiText "ConnectionEmptyBody"
        $script:ConnectionHint.Text = Get-UiText "ConfigureHint"
        $script:ConfigureButton.Visible = $true
        $script:OpenButton.Visible = $false
        $script:ReconnectButton.Visible = $false
        $script:StopButton.Visible = $false
        Set-ConnectionStatus -Key "StatusUnconfigured" -Color ([Drawing.Color]::FromArgb(95, 105, 115))
    }
    Update-Components
}

function Update-Endpoint {
    $region = Get-SelectedRegionId
    if (-not $region) { return }
    $script:EndpointBox.ReadOnly = ($region -ne "custom")
    if ($region -ne "custom") { $script:EndpointBox.Text = Resolve-AlibabaOssEndpoint -Region $region }
}

function Get-SelectedRegionId {
    if (-not $script:RegionChoice -or -not $script:RegionChoices -or $script:RegionChoice.SelectedIndex -lt 0) {
        return ""
    }
    if ($script:RegionChoice.SelectedIndex -ge $script:RegionChoices.Count) {
        return ""
    }
    return [string]$script:RegionChoices[$script:RegionChoice.SelectedIndex].Id
}

function Set-SelectedRegionId {
    param([AllowEmptyString()][string]$Region)

    $target = if ([string]::IsNullOrWhiteSpace($Region)) { "ap-southeast-1" } else { $Region }
    $selectedIndex = -1
    for ($i = 0; $i -lt $script:RegionChoices.Count; $i++) {
        if ([string]$script:RegionChoices[$i].Id -eq $target) {
            $selectedIndex = $i
            break
        }
    }
    if ($selectedIndex -lt 0) {
        for ($i = 0; $i -lt $script:RegionChoices.Count; $i++) {
            if ([string]$script:RegionChoices[$i].Id -eq "custom") {
                $selectedIndex = $i
                break
            }
        }
    }
    if ($selectedIndex -ge 0) { $script:RegionChoice.SelectedIndex = $selectedIndex }
}

function Update-CacheAdvice {
    if (-not $script:CacheChoice.Text) { return }
    try {
        $driveInfo = New-Object IO.DriveInfo($env:SystemDrive)
        $freeBytes = [decimal]$driveInfo.AvailableFreeSpace
        $advice = Get-CrossCloudCacheAdvice -CacheMaxSize $script:CacheChoice.Text -FreeBytes $freeBytes
        $freeText = "{0} GB" -f ([math]::Round($freeBytes / 1GB, 1))
        $recommendationKey = switch -Regex ($script:CacheChoice.Text.Trim().ToUpperInvariant()) {
            '^5G$' { "CacheRecommendation5"; break }
            '^10G$' { "CacheRecommendation10"; break }
            '^20G$' { "CacheRecommendation20"; break }
            default { "CacheRecommendationCustom" }
        }
        $secondLine = if ($advice.Warning) { Get-UiText "DiskLowWarning" } else { Get-UiText $recommendationKey }
        $script:CacheAdviceLabel.Text = (Get-UiText "DiskFree" $freeText) + "`r`n" + $secondLine
        $script:CacheAdviceLabel.ForeColor = if ($advice.Warning) { [Drawing.Color]::FromArgb(170, 85, 35) } else { [Drawing.Color]::FromArgb(75, 90, 105) }
    }
    catch { $script:CacheAdviceLabel.Text = Get-UiText "CacheNotHardLimit" }
}

function Load-StateIntoForm {
    $script:EndpointBox.Text = [string]$script:State.Endpoint
    $script:BucketBox.Text = [string]$script:State.Bucket
    $script:PathBox.Text = if ($script:State.RemotePath) { "/$($script:State.RemotePath)" } else { "/" }
    $script:AccessKeyIdBox.Text = [string]$script:State.AccessKeyId
    $script:DriveChoice.SelectedItem = [string]$script:State.DriveLetter
    $script:CacheChoice.Text = [string]$script:State.CacheMaxSize
    $script:AutoMountCheck.Checked = [bool]$script:State.AutoMount
    $script:AutoRecoverCheck.Checked = [bool]$script:State.AutoRecover
    $selectedRegion = if ($script:State.Region) { [string]$script:State.Region } else { "ap-southeast-1" }
    Set-SelectedRegionId -Region $selectedRegion
}

function Get-ValidatedFormValues {
    $drive = if ($script:DriveChoice.SelectedIndex -eq 0) { Get-CrossCloudAvailableDriveLetter } else { Normalize-DriveLetter $script:DriveChoice.Text }
    $cacheSize = Normalize-CacheSize $script:CacheChoice.Text
    $region = Get-SelectedRegionId
    $endpoint = if ($region -eq "custom") { Normalize-AlibabaOssEndpoint $script:EndpointBox.Text } else { Resolve-AlibabaOssEndpoint $region }
    $bucket = Normalize-AlibabaOssBucket $script:BucketBox.Text
    $prefix = Normalize-AlibabaOssPrefix $script:PathBox.Text
    if ([string]::IsNullOrWhiteSpace($script:AccessKeyIdBox.Text)) {
        throw (Get-UiText "AccessKeyRequired")
    }
    if ([string]::IsNullOrWhiteSpace($script:SecretBox.Text) -and [string]::IsNullOrWhiteSpace([string]$script:State.Bucket)) {
        throw (Get-UiText "AccessKeyRequired")
    }
    return [pscustomobject]@{
        Provider = "AlibabaOss"; Region = $region; Endpoint = $endpoint; Bucket = $bucket
        RemotePath = $prefix; RemoteName = "crosscloud-main"; DriveLetter = $drive
        CacheDir = $script:Paths.CacheRoot; CacheMaxSize = $cacheSize; DirCacheTime = "1m"
        AutoMount = [bool]$script:AutoMountCheck.Checked; AutoRecover = [bool]$script:AutoRecoverCheck.Checked
        AccessKeyId = $script:AccessKeyIdBox.Text.Trim(); AccessKeySecret = $script:SecretBox.Text
    }
}

function Save-FormState {
    param($Values)
    $state = New-CrossCloudConnectionState -Paths $script:Paths
    foreach ($name in @("Provider", "Region", "Endpoint", "Bucket", "RemotePath", "RemoteName", "DriveLetter", "CacheDir", "CacheMaxSize", "DirCacheTime", "AutoMount", "AutoRecover", "AccessKeyId")) {
        $state.$name = $Values.$name
    }
    Save-CrossCloudConnectionState -State $state -Paths $script:Paths | Out-Null
    $script:State = Get-CrossCloudConnectionState -Paths $script:Paths
}

function Set-RcloneRemote {
    param($Values)
    $rclone = Get-CrossCloudRcloneExe
    if (-not $rclone) { throw (Get-UiText "InstallHint") }
    if ([string]::IsNullOrWhiteSpace([string]$Values.AccessKeySecret)) { return }
    $definition = New-AlibabaOssRemoteDefinition -RemoteName $Values.RemoteName -Endpoint $Values.Endpoint -AccessKeyId $Values.AccessKeyId -AccessKeySecret $Values.AccessKeySecret
    $arguments = Get-CrossCloudRemoteConfigArguments -Definition $definition
    $result = Invoke-CrossCloudProcess -FilePath $rclone -Arguments $arguments -SensitiveValues @($Values.AccessKeyId, $Values.AccessKeySecret)
    if ($result.ExitCode -ne 0) { throw $result.Stderr }
}

function Test-OssAccess {
    param($Values)

    Set-RcloneRemote -Values $Values
    $testState = New-CrossCloudConnectionState -Paths $script:Paths
    $testState.RemoteName = $Values.RemoteName
    $testState.Bucket = $Values.Bucket
    $testState.RemotePath = $Values.RemotePath
    $result = Invoke-CrossCloudProcess -FilePath (Get-CrossCloudRcloneExe) `
        -Arguments @("lsf", (Get-CrossCloudRemoteTarget $testState), "--max-depth", "1") `
        -SensitiveValues @($Values.AccessKeyId, $Values.AccessKeySecret)
    if ($result.ExitCode -ne 0) { throw $result.Stderr }
}

function Invoke-AccessTest {
    if ($script:OperationBusy) { return }
    Set-OperationBusy -Busy $true
    try {
        Set-ConnectionStatus -Key "StatusChecking" -Color ([Drawing.Color]::FromArgb(177, 108, 28))
        Add-Activity -Message (Get-UiText "TestStarted") -Kind "Mount"
        $values = Get-ValidatedFormValues
        Test-OssAccess -Values $values
        $script:LastChecked = Get-Date
        Add-Activity -Message (Get-UiText "TestSucceeded") -Kind "Mount"
        Set-ConnectionStatus -Key "StatusConnected"
    }
    catch {
        $script:LastError = $_.Exception.Message
        Add-Activity -Message (Get-UiText "OperationFailed" $script:LastError) -Kind "Error"
        Set-ConnectionStatus -Key "StatusFailed" -Color ([Drawing.Color]::FromArgb(174, 62, 53))
    }
    finally { Set-OperationBusy -Busy $false }
    Update-ConnectionPage
}

function Connect-CloudDrive {
    if ($script:OperationBusy) { return }
    Set-OperationBusy -Busy $true
    try {
        Set-ConnectionStatus -Key "StatusChecking" -Color ([Drawing.Color]::FromArgb(177, 108, 28))
        $values = Get-ValidatedFormValues
        Test-OssAccess -Values $values
        Set-ConnectionStatus -Key "StatusConnecting" -Color ([Drawing.Color]::FromArgb(177, 108, 28))
        Save-FormState -Values $values
        New-Item -ItemType Directory -Force -Path $script:State.CacheDir, $script:Paths.RuntimeRoot, $script:Paths.LogRoot | Out-Null
        $runtime = Install-CrossCloudRuntimeFiles -SourceScriptsRoot $PSScriptRoot -RuntimeRoot $script:Paths.RuntimeRoot
        Set-CrossCloudScheduledTasks -LauncherPath $runtime.Launcher -AutoMount $script:State.AutoMount -AutoRecover $script:State.AutoRecover
        Clear-CrossCloudMountPaused -Paths $script:Paths
        $mountArguments = Get-CrossCloudMountArguments -State $script:State -LogFile (Join-Path $script:Paths.LogRoot "mount.log")
        $argumentLine = ($mountArguments | ForEach-Object { ConvertTo-CrossCloudProcessArgument ([string]$_) }) -join " "
        Start-Process -FilePath (Get-CrossCloudRcloneExe) -ArgumentList $argumentLine -WindowStyle Hidden | Out-Null
        $script:LastChecked = Get-Date
        Add-Activity -Message (Get-UiText "MountSucceeded") -Kind "Mount"
        Set-ConnectionStatus -Key "StatusConnected"
    }
    catch {
        $script:LastError = $_.Exception.Message
        Add-Activity -Message (Get-UiText "OperationFailed" $script:LastError) -Kind "Error"
        Set-ConnectionStatus -Key "StatusFailed" -Color ([Drawing.Color]::FromArgb(174, 62, 53))
    }
    finally { Set-OperationBusy -Busy $false }
    Update-ConnectionPage
}

function Stop-CloudDrive {
    if ($script:OperationBusy) { return }
    Set-OperationBusy -Busy $true
    try {
        Set-CrossCloudMountPaused -Paths $script:Paths
        Stop-CrossCloudManagedMounts -States @($script:State) | Out-Null
        Remove-CrossCloudDriveRecord -DriveLetter $script:State.DriveLetter
        Add-Activity -Message (Get-UiText "StopSucceeded") -Kind "Mount"
        Set-ConnectionStatus -Key "StatusStopped" -Color ([Drawing.Color]::FromArgb(95, 105, 115))
    }
    catch { Add-Activity -Message (Get-UiText "OperationFailed" $_.Exception.Message) -Kind "Error" }
    finally { Set-OperationBusy -Busy $false }
}

function Remove-LocalConnection {
    if ($script:OperationBusy) { return }
    $answer = [Windows.Forms.MessageBox]::Show(
        (Get-UiText "RemoveConfirm"),
        (Get-UiText "ConfirmRemovalTitle"),
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
    $removeDependencies = [Windows.Forms.MessageBox]::Show(
        (Get-UiText "RemoveWithDependencies"),
        (Get-UiText "ConfirmRemovalTitle"),
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question
    ) -eq [Windows.Forms.DialogResult]::Yes
    Set-OperationBusy -Busy $true
    try {
        Set-ConnectionStatus -Key "StatusRemoving" -Color ([Drawing.Color]::FromArgb(177, 108, 28))
        Remove-CrossCloudConnection -State $script:State -Paths $script:Paths -RemoveDependencies:$removeDependencies | Out-Null
        $script:State = Get-CrossCloudConnectionState -Paths $script:Paths
        Add-Activity -Message (Get-UiText "RemovalSucceeded") -Kind "Mount"
        Set-ConnectionStatus -Key "StatusStopped" -Color ([Drawing.Color]::FromArgb(95, 105, 115))
        Load-StateIntoForm
        Update-ConnectionPage
    }
    catch { Add-Activity -Message (Get-UiText "OperationFailed" $_.Exception.Message) -Kind "Error" }
    finally { Set-OperationBusy -Busy $false }
}

function Refresh-LocalizedChoices {
    $selectedRegion = Get-SelectedRegionId
    $script:RegionChoices = @(Get-AlibabaOssRegions | ForEach-Object {
        [pscustomobject]@{ Id = $_.Id; Display = Get-UiText $_.LocaleKey }
    })
    $script:RegionChoices += [pscustomobject]@{ Id = "custom"; Display = Get-UiText "Custom" }
    $script:RegionChoice.BeginUpdate()
    try {
        $script:RegionChoice.Items.Clear()
        foreach ($region in $script:RegionChoices) { [void]$script:RegionChoice.Items.Add([string]$region.Display) }
    }
    finally { $script:RegionChoice.EndUpdate() }
    Set-SelectedRegionId -Region $selectedRegion

    $autoDriveSelected = ($script:DriveChoice.SelectedIndex -le 0)
    $selectedDrive = [string]$script:DriveChoice.SelectedItem
    $script:DriveChoice.Items[0] = Get-UiText "AutoSelect"
    if ($autoDriveSelected) {
        $script:DriveChoice.SelectedIndex = 0
    }
    elseif ($selectedDrive) {
        $script:DriveChoice.SelectedItem = $selectedDrive
    }
}

function Apply-Language {
    Save-CrossCloudLanguage -Language $script:Language -SettingsFile $script:Paths.SettingsFile
    $script:Locale = Import-CrossCloudLocale -Language $script:Language
    foreach ($control in $script:TranslatableControls) {
        if ($control.Tag) { $control.Text = Get-UiText ([string]$control.Tag) }
    }
    Refresh-LocalizedChoices
    $script:LanguageButton.Text = Get-LanguageSwitchText
    $form.Text = Get-UiText "AppName"
    Update-ConnectionPage
    Update-CacheAdvice
}

function Set-ResponsiveLayout {
    $width = [Math]::Max(620, $content.ClientSize.Width)
    $leftMargin = 38
    $rightMargin = 34
    $columnGap = if ($width -lt 700) { 24 } else { 34 }
    $columnWidth = [Math]::Max(250, [Math]::Floor(($width - $leftMargin - $rightMargin - $columnGap) / 2))
    $rightX = $leftMargin + $columnWidth + $columnGap

    foreach ($control in @($script:RegionChoice, $script:BucketBox, $script:AccessKeyIdBox, $script:DriveChoice)) {
        $control.Location = New-UiPoint -X $leftMargin -Y $control.Location.Y
        $control.Width = if ($control -eq $script:DriveChoice) { 200 } else { $columnWidth }
    }
    foreach ($control in @($script:EndpointBox, $script:PathBox)) {
        $control.Location = New-UiPoint -X $rightX -Y $control.Location.Y
        $control.Width = $columnWidth
    }
    $script:SecretBox.Location = New-UiPoint -X $rightX -Y $script:SecretBox.Location.Y
    $script:SecretBox.Width = [Math]::Max(160, $columnWidth - 80)
    $script:ShowSecretCheck.Location = New-UiPoint -X ($rightX + $script:SecretBox.Width + 8) -Y $script:ShowSecretCheck.Location.Y
    $script:CacheChoice.Location = New-UiPoint -X 270 -Y $script:CacheChoice.Location.Y
    $script:CacheChoice.Width = 190
    $script:CacheAdviceLabel.Location = New-UiPoint -X $leftMargin -Y 558
    $script:CacheAdviceLabel.Width = [Math]::Max(500, $width - $leftMargin - $rightMargin)
    $script:CacheAdviceLabel.Height = 42
    $script:AutoMountCheck.Location = New-UiPoint -X $leftMargin -Y 616
    $script:AutoRecoverCheck.Location = New-UiPoint -X $rightX -Y 616

    $script:TestButton.Location = New-UiPoint -X $leftMargin -Y 656
    $script:ConnectButton.Location = New-UiPoint -X 170 -Y 656
    $removeWidth = 190
    $script:RemoveButton.Width = $removeWidth
    $script:RemoveButton.Location = New-UiPoint -X ([Math]::Max($leftMargin, $width - $removeWidth - $rightMargin)) -Y 656

    foreach ($label in @($script:SettingsPage.Controls | Where-Object { $_.Tag -in @("Region", "Bucket", "AccessKeyId") })) {
        $label.Location = New-UiPoint -X $leftMargin -Y $label.Location.Y
        $label.Width = $columnWidth
    }
    $settingsLabels = @($script:SettingsPage.Controls | Where-Object { $_.Tag -in @("EndpointSummary", "RemotePath", "AccessKeySecret") })
    foreach ($label in $settingsLabels) {
        $label.Location = New-UiPoint -X $rightX -Y $label.Location.Y
        $label.Width = $columnWidth
    }
    $autoRecoveryLabel = @($script:SettingsPage.Controls | Where-Object { $_.Tag -eq "AutoRecovery" }) | Select-Object -First 1
    if ($autoRecoveryLabel) {
        $autoRecoveryLabel.Location = New-UiPoint -X ($rightX + 26) -Y 616
        $autoRecoveryLabel.Width = [Math]::Max(180, $columnWidth - 26)
    }
    $autoMountLabel = @($script:SettingsPage.Controls | Where-Object { $_.Tag -eq "AutoMount" }) | Select-Object -First 1
    if ($autoMountLabel) {
        $autoMountLabel.Location = New-UiPoint -X ($leftMargin + 26) -Y 616
        $autoMountLabel.Width = [Math]::Max(180, $columnWidth - 26)
    }

    $status = @($script:ConnectionPage.Controls | Where-Object { $_.Tag -eq "StatusUnconfigured" }) | Select-Object -First 1
    if ($status) {
        $status.Location = New-UiPoint -X ([Math]::Max(430, $width - 215)) -Y $status.Location.Y
        $status.Width = 180
    }
    foreach ($control in @($script:ConnectionTarget, $script:ConnectionEndpoint, $script:ConnectionHint)) {
        $control.Width = [Math]::Max(500, $width - 76)
    }
    $script:ConnectionDivider.Width = [Math]::Max(500, $width - 80)
    $activityWidth = [Math]::Max(500, $width - 70)
    $activityButtonY = [Math]::Min(526, [Math]::Max(440, $content.ClientSize.Height - 48))
    $script:OpenLogButton.Location = New-UiPoint -X 36 -Y $activityButtonY
    $script:CopyDiagnosticsButton.Location = New-UiPoint -X 198 -Y $activityButtonY
    $script:ActivityList.Width = $activityWidth
    $script:ActivityList.Height = [Math]::Max(250, $activityButtonY - 182)
    foreach ($control in @($script:ActivityPage.Controls | Where-Object { $_.Tag -in @("ActivityHint") })) {
        $control.Width = $activityWidth
    }
}

$form = New-Object Windows.Forms.Form
$form.Text = Get-UiText "AppName"
$form.ClientSize = New-Object Drawing.Size(980, 700)
$form.MinimumSize = New-Object Drawing.Size(820, 560)
$form.AutoScaleMode = "Dpi"
$form.StartPosition = "CenterScreen"
$form.Font = New-Object Drawing.Font("Segoe UI", 9)
$form.BackColor = [Drawing.Color]::FromArgb(246, 248, 250)
$form.FormBorderStyle = "Sizable"
$form.MaximizeBox = $false

$nav = New-Object Windows.Forms.Panel
$nav.Dock = "Left"; $nav.Width = 176; $nav.BackColor = [Drawing.Color]::White
$form.Controls.Add($nav)
$brand = New-UiLabel -Key "AppName" -X 22 -Y 24 -Width 155 -Height 32 -FontSize 16
$brand.Font = New-Object Drawing.Font("Segoe UI Semibold", 16); $brand.ForeColor = [Drawing.Color]::FromArgb(31, 35, 40)
$nav.Controls.Add($brand)
$subtitle = New-UiLabel -Key "AppSubtitle" -X 24 -Y 58 -Width 150 -Height 40 -FontSize 8
$subtitle.ForeColor = [Drawing.Color]::FromArgb(89, 99, 110); $nav.Controls.Add($subtitle)

$content = New-Object Windows.Forms.Panel
$content.Location = New-Object Drawing.Point(176, 0)
$content.Size = New-Object Drawing.Size(804, 700)
$content.Anchor = "Top,Bottom,Left,Right"
$form.Controls.Add($content)

$script:ConnectionPage = New-Object Windows.Forms.Panel; $script:ConnectionPage.Dock = "Fill"; $content.Controls.Add($script:ConnectionPage)
$title = New-UiLabel -Key "NavConnection" -X 34 -Y 28 -Width 400 -Height 38 -FontSize 20
$title.Font = New-Object Drawing.Font("Segoe UI Semibold", 20); $script:ConnectionPage.Controls.Add($title)
$script:StatusValue = New-UiLabel -Key "StatusUnconfigured" -X 555 -Y 32 -Width 170 -Height 28
$script:StatusValue.TextAlign = "MiddleRight"; $script:ConnectionPage.Controls.Add($script:StatusValue)
$script:ConnectionDivider = New-Object Windows.Forms.Label; $script:ConnectionDivider.Location = New-Object Drawing.Point(34, 75); $script:ConnectionDivider.Size = New-Object Drawing.Size(690, 1); $script:ConnectionDivider.BackColor = [Drawing.Color]::FromArgb(219, 225, 231); $script:ConnectionPage.Controls.Add($script:ConnectionDivider)
$script:ConnectionPage.Controls.Add((New-SectionHeader -Key "ConnectionOverview" -X 34 -Y 102))
$script:ConnectionTarget = New-Object Windows.Forms.Label; $script:ConnectionTarget.Location = New-Object Drawing.Point(38, 145); $script:ConnectionTarget.Size = New-Object Drawing.Size(660, 34); $script:ConnectionTarget.Font = New-Object Drawing.Font("Segoe UI Semibold", 16); $script:ConnectionTarget.ForeColor = [Drawing.Color]::FromArgb(28, 52, 72); $script:ConnectionPage.Controls.Add($script:ConnectionTarget)
$script:ConnectionEndpoint = New-Object Windows.Forms.Label; $script:ConnectionEndpoint.Location = New-Object Drawing.Point(38, 190); $script:ConnectionEndpoint.Size = New-Object Drawing.Size(660, 24); $script:ConnectionEndpoint.ForeColor = [Drawing.Color]::FromArgb(75, 90, 105); $script:ConnectionPage.Controls.Add($script:ConnectionEndpoint)
$script:ConnectionHint = New-Object Windows.Forms.Label; $script:ConnectionHint.Location = New-Object Drawing.Point(38, 220); $script:ConnectionHint.Size = New-Object Drawing.Size(660, 38); $script:ConnectionHint.ForeColor = [Drawing.Color]::FromArgb(95, 108, 120); $script:ConnectionPage.Controls.Add($script:ConnectionHint)
$script:ConnectionStatus = New-Object Windows.Forms.Label; $script:ConnectionStatus.Location = New-Object Drawing.Point(38, 266); $script:ConnectionStatus.Size = New-Object Drawing.Size(500, 24); $script:ConnectionPage.Controls.Add($script:ConnectionStatus)
$script:ConfigureButton = New-UiButton -Key "ConfigureConnection" -X 38 -Y 310 -Width 150 -Primary $true; $script:ConnectionPage.Controls.Add($script:ConfigureButton)
$script:OpenButton = New-UiButton -Key "OpenDrive" -X 38 -Y 310 -Width 130 -Primary $true; $script:ConnectionPage.Controls.Add($script:OpenButton)
$script:ReconnectButton = New-UiButton -Key "Reconnect" -X 180 -Y 310 -Width 120; $script:ConnectionPage.Controls.Add($script:ReconnectButton)
$script:StopButton = New-UiButton -Key "Stop" -X 312 -Y 310 -Width 100; $script:ConnectionPage.Controls.Add($script:StopButton)
$script:ConnectionPage.Controls.Add((New-SectionHeader -Key "ComponentStatus" -X 34 -Y 390))
$script:ConnectionPage.Controls.Add((New-UiLabel -Key "ComponentRclone" -X 38 -Y 434 -Width 110))
$script:RcloneValue = New-Object Windows.Forms.Label; $script:RcloneValue.Location = New-Object Drawing.Point(158, 434); $script:RcloneValue.Size = New-Object Drawing.Size(120, 24); $script:ConnectionPage.Controls.Add($script:RcloneValue)
$script:ConnectionPage.Controls.Add((New-UiLabel -Key "ComponentWinFsp" -X 320 -Y 434 -Width 110))
$script:WinFspValue = New-Object Windows.Forms.Label; $script:WinFspValue.Location = New-Object Drawing.Point(440, 434); $script:WinFspValue.Size = New-Object Drawing.Size(120, 24); $script:ConnectionPage.Controls.Add($script:WinFspValue)
$script:InstallButton = New-UiButton -Key "InstallComponents" -X 38 -Y 486 -Width 160; $script:ConnectionPage.Controls.Add($script:InstallButton)

$script:SettingsPage = New-Object Windows.Forms.Panel; $script:SettingsPage.Dock = "Fill"; $script:SettingsPage.AutoScroll = $true; $script:SettingsPage.AutoScrollMinSize = New-Object Drawing.Size(0, 720); $script:SettingsPage.Visible = $false; $content.Controls.Add($script:SettingsPage)
$title = New-UiLabel -Key "NavSettings" -X 34 -Y 28 -Width 400 -Height 38 -FontSize 20; $title.Font = New-Object Drawing.Font("Segoe UI Semibold", 20); $script:SettingsPage.Controls.Add($title)
$script:SettingsPage.Controls.Add((New-SectionHeader -Key "StorageLocation" -X 34 -Y 92))
$script:RegionChoice = New-Object Windows.Forms.ComboBox; $script:RegionChoice.Location = New-Object Drawing.Point(38, 158); $script:RegionChoice.Size = New-Object Drawing.Size(310, 28); $script:RegionChoice.DropDownStyle = "DropDownList"
$script:SettingsPage.Controls.Add($script:RegionChoice)
$script:EndpointBox = New-UiTextBox -X 382 -Y 158 -Width 310; $script:SettingsPage.Controls.Add($script:EndpointBox)
$script:BucketBox = New-UiTextBox -X 38 -Y 231 -Width 310; $script:SettingsPage.Controls.Add($script:BucketBox)
$script:PathBox = New-UiTextBox -X 382 -Y 231 -Width 310; $script:SettingsPage.Controls.Add($script:PathBox)
$script:SettingsPage.Controls.Add((New-UiLabel -Key "Region" -X 38 -Y 132 -Width 310)); $script:SettingsPage.Controls.Add((New-UiLabel -Key "EndpointSummary" -X 382 -Y 132 -Width 310)); $script:SettingsPage.Controls.Add((New-UiLabel -Key "Bucket" -X 38 -Y 205 -Width 310)); $script:SettingsPage.Controls.Add((New-UiLabel -Key "RemotePath" -X 382 -Y 205 -Width 310))
$script:SettingsPage.Controls.Add((New-SectionHeader -Key "Credentials" -X 34 -Y 292))
$script:AccessKeyIdBox = New-UiTextBox -X 38 -Y 358 -Width 310; $script:SecretBox = New-UiTextBox -X 382 -Y 358 -Width 240 -Password $true; $script:SettingsPage.Controls.Add($script:AccessKeyIdBox); $script:SettingsPage.Controls.Add($script:SecretBox)
$script:ShowSecretCheck = New-Object Windows.Forms.CheckBox; $script:ShowSecretCheck.Tag = "ShowSecret"; $script:ShowSecretCheck.Text = Get-UiText "ShowSecret"; $script:ShowSecretCheck.Location = New-Object Drawing.Point(632, 358); $script:ShowSecretCheck.Size = New-Object Drawing.Size(72, 26); [void]$script:TranslatableControls.Add($script:ShowSecretCheck); $script:SettingsPage.Controls.Add($script:ShowSecretCheck)
$script:SettingsPage.Controls.Add((New-UiLabel -Key "AccessKeyId" -X 38 -Y 332 -Width 310)); $script:SettingsPage.Controls.Add((New-UiLabel -Key "AccessKeySecret" -X 382 -Y 332 -Width 310)); $script:SettingsPage.Controls.Add((New-UiLabel -Key "CredentialsHint" -X 38 -Y 397 -Width 650 -Height 34 -FontSize 8))
$script:SettingsPage.Controls.Add((New-SectionHeader -Key "LocalMount" -X 34 -Y 452))
$script:DriveChoice = New-Object Windows.Forms.ComboBox; $script:DriveChoice.Location = New-Object Drawing.Point(38, 518); $script:DriveChoice.Size = New-Object Drawing.Size(200, 28); $script:DriveChoice.DropDownStyle = "DropDownList"; [void]$script:DriveChoice.Items.Add((Get-UiText "AutoSelect")); foreach ($code in 68..90) { [void]$script:DriveChoice.Items.Add([string][char]$code) }; $script:SettingsPage.Controls.Add($script:DriveChoice)
$script:CacheChoice = New-Object Windows.Forms.ComboBox; $script:CacheChoice.Location = New-Object Drawing.Point(270, 518); $script:CacheChoice.Size = New-Object Drawing.Size(200, 28); foreach ($size in @("5G", "10G", "20G")) { [void]$script:CacheChoice.Items.Add($size) }; $script:SettingsPage.Controls.Add($script:CacheChoice)
$script:SettingsPage.Controls.Add((New-UiLabel -Key "DriveLetter" -X 38 -Y 492 -Width 200)); $script:SettingsPage.Controls.Add((New-UiLabel -Key "CacheLimit" -X 270 -Y 492 -Width 200))
$script:CacheAdviceLabel = New-UiLabel -Key "CacheUsageUnknown" -X 38 -Y 558 -Width 650 -Height 42 -FontSize 8; $script:SettingsPage.Controls.Add($script:CacheAdviceLabel)
$script:AutoMountCheck = New-Object Windows.Forms.CheckBox; $script:AutoMountCheck.Location = New-Object Drawing.Point(38, 616); $script:AutoMountCheck.Size = New-Object Drawing.Size(22, 24); $script:SettingsPage.Controls.Add($script:AutoMountCheck)
$script:AutoRecoverCheck = New-Object Windows.Forms.CheckBox; $script:AutoRecoverCheck.Location = New-Object Drawing.Point(382, 616); $script:AutoRecoverCheck.Size = New-Object Drawing.Size(22, 24); $script:SettingsPage.Controls.Add($script:AutoRecoverCheck)
$script:SettingsPage.Controls.Add((New-UiLabel -Key "AutoMount" -X 64 -Y 616 -Width 280)); $script:SettingsPage.Controls.Add((New-UiLabel -Key "AutoRecovery" -X 408 -Y 616 -Width 280))
$script:TestButton = New-UiButton -Key "TestOnly" -X 38 -Y 656 -Width 120; $script:SettingsPage.Controls.Add($script:TestButton)
$script:ConnectButton = New-UiButton -Key "SaveAndConnect" -X 170 -Y 656 -Width 160 -Primary $true; $script:SettingsPage.Controls.Add($script:ConnectButton)
$script:RemoveButton = New-UiButton -Key "RemoveLocalAction" -X 500 -Y 656 -Width 190; $script:SettingsPage.Controls.Add($script:RemoveButton)

$script:ActivityPage = New-Object Windows.Forms.Panel; $script:ActivityPage.Dock = "Fill"; $script:ActivityPage.Visible = $false; $content.Controls.Add($script:ActivityPage)
$title = New-UiLabel -Key "NavActivity" -X 34 -Y 28 -Width 400 -Height 38 -FontSize 20; $title.Font = New-Object Drawing.Font("Segoe UI Semibold", 20); $script:ActivityPage.Controls.Add($title)
$script:ActivityPage.Controls.Add((New-UiLabel -Key "ActivityHint" -X 36 -Y 76 -Width 650 -Height 30 -FontSize 8))
$activityFilterDefinitions = @(
    @{ Key = "ActivityAll"; Filter = "All" }, @{ Key = "ActivityErrors"; Filter = "Error" },
    @{ Key = "ActivityMount"; Filter = "Mount" }, @{ Key = "ActivityUpload"; Filter = "Upload" }
)
$script:ActivityFilterButtons = @()
$filterX = 36
foreach ($definition in $activityFilterDefinitions) {
    $filterButton = New-UiButton -Key $definition.Key -X $filterX -Y 110 -Width 92
    $filterValue = $definition.Filter
    $filterButton.Add_Click({ Set-ActivityFilter -Filter $this.AccessibleDescription })
    $filterButton.AccessibleDescription = $filterValue
    $script:ActivityPage.Controls.Add($filterButton)
    $script:ActivityFilterButtons += $filterButton
    $filterX += 100
}
$script:ActivityList = New-Object Windows.Forms.ListBox; $script:ActivityList.Location = New-Object Drawing.Point(36, 156); $script:ActivityList.Size = New-Object Drawing.Size(690, 344); $script:ActivityList.Font = New-Object Drawing.Font("Consolas", 9); $script:ActivityPage.Controls.Add($script:ActivityList)
$script:OpenLogButton = New-UiButton -Key "OpenLogFolder" -X 36 -Y 526 -Width 150; $script:ActivityPage.Controls.Add($script:OpenLogButton)
$script:CopyDiagnosticsButton = New-UiButton -Key "CopyDiagnostics" -X 198 -Y 526 -Width 150; $script:ActivityPage.Controls.Add($script:CopyDiagnosticsButton)

$connectionNav = New-UiButton -Key "NavConnection" -X 20 -Y 150 -Width 150; $settingsNav = New-UiButton -Key "NavSettings" -X 20 -Y 198 -Width 150; $activityNav = New-UiButton -Key "NavActivity" -X 20 -Y 246 -Width 150
foreach ($button in @($connectionNav, $settingsNav, $activityNav)) { $button.BackColor = [Drawing.Color]::FromArgb(246, 248, 250); $button.ForeColor = [Drawing.Color]::FromArgb(31, 35, 40); $button.FlatAppearance.BorderSize = 1; $button.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(208, 215, 222); $nav.Controls.Add($button) }
$script:LanguageButton = New-Object Windows.Forms.Button; $script:LanguageButton.Location = New-Object Drawing.Point(20, 552); $script:LanguageButton.Size = New-Object Drawing.Size(150, 30); $script:LanguageButton.Anchor = "Left,Bottom"; $script:LanguageButton.FlatStyle = "Flat"; $script:LanguageButton.FlatAppearance.BorderSize = 1; $script:LanguageButton.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(208, 215, 222); $script:LanguageButton.BackColor = [Drawing.Color]::White; $script:LanguageButton.ForeColor = [Drawing.Color]::FromArgb(31, 35, 40); $nav.Controls.Add($script:LanguageButton)
$version = New-UiLabel -Key "Version" -X 24 -Y 592 -Width 150 -Height 22 -FontSize 8; $version.Anchor = "Left,Bottom"; $version.ForeColor = [Drawing.Color]::FromArgb(89, 99, 110); $nav.Controls.Add($version)

$connectionNav.Add_Click({ Show-ApplicationPage "Connection" }); $settingsNav.Add_Click({ Show-ApplicationPage "Settings" }); $activityNav.Add_Click({ Show-ApplicationPage "Activity" })
$script:ConfigureButton.Add_Click({ Show-ApplicationPage "Settings" })
$script:RegionChoice.Add_SelectedIndexChanged({ Update-Endpoint }); $script:CacheChoice.Add_TextChanged({ Update-CacheAdvice })
$script:ShowSecretCheck.Add_CheckedChanged({ $script:SecretBox.UseSystemPasswordChar = -not $script:ShowSecretCheck.Checked })
$script:TestButton.Add_Click({ Invoke-AccessTest }); $script:ConnectButton.Add_Click({ Connect-CloudDrive }); $script:ReconnectButton.Add_Click({ Connect-CloudDrive }); $script:StopButton.Add_Click({ Stop-CloudDrive }); $script:RemoveButton.Add_Click({ Remove-LocalConnection })
$script:OpenButton.Add_Click({ $drive = "$($script:State.DriveLetter):"; if (Test-Path $drive) { Start-Process explorer.exe $drive } else { Add-Activity -Message (Get-UiText "DriveNotMounted") -Kind "Error" } })
$script:OpenLogButton.Add_Click({ New-Item -ItemType Directory -Force -Path $script:Paths.LogRoot | Out-Null; Start-Process explorer.exe $script:Paths.LogRoot })
$script:CopyDiagnosticsButton.Add_Click({ $text = "CrossCloud Drive V2`r`nProvider: AlibabaOss`r`nEndpoint: $($script:State.Endpoint)`r`nDrive: $($script:State.DriveLetter)`r`nStatus: $($script:StatusValue.Text)`r`nLast error: $($script:LastError)"; [Windows.Forms.Clipboard]::SetText($text); Add-Activity -Message (Get-UiText "CopyDiagnosticsDone") })
$script:InstallButton.Add_Click({ try { $winget = Get-Command winget -ErrorAction Stop; foreach ($package in @("WinFsp.WinFsp", "Rclone.Rclone")) { $result = Invoke-CrossCloudProcess -FilePath $winget.Source -Arguments @("install", "--id", $package, "--exact", "--silent", "--accept-package-agreements", "--accept-source-agreements"); if ($result.ExitCode -ne 0) { throw $result.Stderr } }; Add-Activity -Message (Get-UiText "DependenciesReady"); Update-Components } catch { Add-Activity -Message (Get-UiText "OperationFailed" $_.Exception.Message) -Kind "Error" } })
$script:LanguageButton.Add_Click({ $script:Language = if ($script:Language -eq "zh-CN") { "en-US" } else { "zh-CN" }; Apply-Language })
$form.Add_Resize({ Set-ResponsiveLayout })

Refresh-LocalizedChoices
Load-StateIntoForm
Apply-Language
Set-ResponsiveLayout
Update-Endpoint
Add-Activity -Message (Get-UiText "AppSubtitle")
Show-ApplicationPage "Connection"
[void]$form.ShowDialog()
