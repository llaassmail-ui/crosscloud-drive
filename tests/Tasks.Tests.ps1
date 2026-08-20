$ErrorActionPreference = "Stop"
. "$PSScriptRoot\TestHelpers.ps1"
. "$PSScriptRoot\..\scripts\OssMount.State.ps1"
. "$PSScriptRoot\..\scripts\OssMount.Tasks.ps1"

$names = Get-CrossCloudTaskNames
Assert-Equal "CrossCloud Drive - Sign-in mount" $names.SignIn "Sign-in task name is stable"
Assert-Equal "CrossCloud Drive - Recovery" $names.Recovery "Recovery task name is stable"

$definitions = @(Get-CrossCloudTaskDefinitions -LauncherPath "C:\runtime path\MountWorker.vbs" -AutoMount $true -AutoRecover $true)
Assert-Equal 2 $definitions.Count "Both enabled tasks are described"
Assert-Equal "wscript.exe" ([IO.Path]::GetFileName($definitions[0].Execute)) "Tasks use the windowless VBS host"
Assert-True ($definitions[0].Arguments.Contains('"C:\runtime path\MountWorker.vbs"')) "Launcher path is quoted"
Assert-Equal "Logon" $definitions[0].TriggerType "Sign-in task uses a logon trigger"
Assert-Equal "Interval" $definitions[1].TriggerType "Recovery task uses an interval trigger"
Assert-True ($definitions[0].Arguments.Contains('SignIn')) "Sign-in task identifies its launch reason"
Assert-True ($definitions[1].Arguments.Contains('Recovery')) "Recovery task identifies its launch reason"
Assert-Equal 5 $definitions[1].IntervalMinutes "Recovery runs every five minutes"
Assert-Equal $true $definitions[0].Hidden "Sign-in task is hidden"
Assert-Equal $true $definitions[1].Hidden "Recovery task is hidden"
Assert-Equal 0 (@(Get-CrossCloudTaskDefinitions -LauncherPath "C:\worker.vbs" -AutoMount $false -AutoRecover $false)).Count "Disabled tasks are omitted"

Assert-Equal $false (Test-CrossCloudShouldStartMount -DriveExists $true -MatchingProcessCount 0) "Existing drive prevents duplicate mount"
Assert-Equal $false (Test-CrossCloudShouldStartMount -DriveExists $false -MatchingProcessCount 1) "Existing target process prevents duplicate mount"
Assert-Equal $true (Test-CrossCloudShouldStartMount -DriveExists $false -MatchingProcessCount 0) "Missing drive and process starts mount"
Assert-Equal $false (Test-CrossCloudShouldStartMount -DriveExists $false -MatchingProcessCount 0 -MountPaused $true -LaunchReason "Recovery") "Recovery honors a manual stop"
Assert-Equal $true (Test-CrossCloudShouldStartMount -DriveExists $false -MatchingProcessCount 0 -MountPaused $true -LaunchReason "SignIn") "Sign-in resumes a manually stopped mount"

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("CrossCloudDrive-TaskTests-" + [guid]::NewGuid().ToString("N"))
try {
    $runtimeRoot = Join-Path $tempRoot "runtime"
    $files = Install-CrossCloudRuntimeFiles -SourceScriptsRoot (Join-Path $PSScriptRoot "..\scripts") -RuntimeRoot $runtimeRoot
    Assert-True (Test-Path -LiteralPath $files.Worker) "Mount worker is deployed"
    Assert-True (Test-Path -LiteralPath $files.Launcher) "Hidden launcher is generated"
    Assert-True ((Get-Content -LiteralPath $files.Launcher -Raw).Contains('WindowStyle Hidden')) "Launcher requests hidden PowerShell"
    Assert-True ((Get-Content -LiteralPath $files.Launcher -Raw).Contains(', 0, False')) "VBS uses hidden non-blocking launch"
    Assert-True ((Get-Content -LiteralPath $files.Launcher -Raw).Contains('WScript.Arguments')) "VBS forwards the task launch reason"
    Assert-True (Test-Path -LiteralPath (Join-Path $runtimeRoot "providers\AlibabaOss.Provider.ps1")) "Provider dependency is deployed"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Complete-TestFile
