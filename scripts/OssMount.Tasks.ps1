function Get-CrossCloudTaskNames {
    return [pscustomobject]@{
        SignIn = "CrossCloud Drive - Sign-in mount"
        Recovery = "CrossCloud Drive - Recovery"
        LegacyPattern = "Mount OSS workspace drive *"
    }
}

function Get-CrossCloudTaskDefinitions {
    param(
        [Parameter(Mandatory = $true)][string]$LauncherPath,
        [bool]$AutoMount,
        [bool]$AutoRecover,
        [string]$WindowsRoot = $env:WINDIR
    )

    $names = Get-CrossCloudTaskNames
    $execute = Join-Path $WindowsRoot "System32\wscript.exe"
    $arguments = '"' + $LauncherPath + '"'
    $definitions = @()
    if ($AutoMount) {
        $definitions += [pscustomobject]@{
            Name = $names.SignIn; Execute = $execute; Arguments = "$arguments SignIn"
            TriggerType = "Logon"; IntervalMinutes = 0; Hidden = $true
        }
    }
    if ($AutoRecover) {
        $definitions += [pscustomobject]@{
            Name = $names.Recovery; Execute = $execute; Arguments = "$arguments Recovery"
            TriggerType = "Interval"; IntervalMinutes = 5; Hidden = $true
        }
    }
    return @($definitions)
}

function Test-CrossCloudShouldStartMount {
    param(
        [bool]$DriveExists,
        [int]$MatchingProcessCount,
        [bool]$MountPaused = $false,
        [ValidateSet("Manual", "SignIn", "Recovery")][string]$LaunchReason = "Manual"
    )

    if ($MountPaused -and $LaunchReason -eq "Recovery") { return $false }
    return (-not $DriveExists -and $MatchingProcessCount -eq 0)
}

function Install-CrossCloudRuntimeFiles {
    param(
        [Parameter(Mandatory = $true)][string]$SourceScriptsRoot,
        [Parameter(Mandatory = $true)][string]$RuntimeRoot
    )

    $providerRoot = Join-Path $RuntimeRoot "providers"
    New-Item -ItemType Directory -Force -Path $providerRoot | Out-Null
    foreach ($fileName in @("OssMount.State.ps1", "OssMount.Core.ps1", "OssMount.MountWorker.ps1")) {
        Copy-Item -LiteralPath (Join-Path $SourceScriptsRoot $fileName) -Destination (Join-Path $RuntimeRoot $fileName) -Force
    }
    Copy-Item -LiteralPath (Join-Path $SourceScriptsRoot "providers\AlibabaOss.Provider.ps1") `
        -Destination (Join-Path $providerRoot "AlibabaOss.Provider.ps1") -Force

    $workerPath = Join-Path $RuntimeRoot "OssMount.MountWorker.ps1"
    $launcherPath = Join-Path $RuntimeRoot "MountWorker.vbs"
    $escapedWorkerPath = $workerPath.Replace('"', '""')
    $launcher = @"
Set shell = CreateObject("WScript.Shell")
launchReason = "Recovery"
If WScript.Arguments.Count > 0 Then launchReason = WScript.Arguments(0)
shell.Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$escapedWorkerPath"" -LaunchReason """ & launchReason & """", 0, False
"@
    Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding ASCII
    return [pscustomobject]@{ Worker = $workerPath; Launcher = $launcherPath; RuntimeRoot = $RuntimeRoot }
}

function Remove-CrossCloudScheduledTasks {
    $names = Get-CrossCloudTaskNames
    foreach ($name in @($names.SignIn, $names.Recovery)) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Set-CrossCloudScheduledTasks {
    param(
        [Parameter(Mandatory = $true)][string]$LauncherPath,
        [bool]$AutoMount,
        [bool]$AutoRecover,
        [string]$UserId = "$env:USERDOMAIN\$env:USERNAME"
    )

    Remove-CrossCloudScheduledTasks
    $principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -Hidden
    foreach ($definition in @(Get-CrossCloudTaskDefinitions -LauncherPath $LauncherPath -AutoMount $AutoMount -AutoRecover $AutoRecover)) {
        $action = New-ScheduledTaskAction -Execute $definition.Execute -Argument $definition.Arguments
        if ($definition.TriggerType -eq "Logon") {
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserId
        }
        else {
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
                -RepetitionInterval (New-TimeSpan -Minutes $definition.IntervalMinutes) `
                -RepetitionDuration (New-TimeSpan -Days 3650)
        }
        Register-ScheduledTask -TaskName $definition.Name -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null
    }
}
