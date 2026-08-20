[CmdletBinding()]
param(
    [ValidateSet("Manual", "SignIn", "Recovery")]
    [string]$LaunchReason = "Recovery"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "OssMount.State.ps1")
. (Join-Path $PSScriptRoot "OssMount.Core.ps1")

$paths = Get-CrossCloudPaths
$state = Get-CrossCloudConnectionState -Paths $paths
if ([string]::IsNullOrWhiteSpace([string]$state.Bucket)) { exit 0 }

$mountPaused = Test-CrossCloudMountPaused -Paths $paths
if ($LaunchReason -eq "SignIn" -and $mountPaused) {
    Clear-CrossCloudMountPaused -Paths $paths
    $mountPaused = $false
}

$remoteTarget = Get-CrossCloudRemoteTarget -State $state
$matchingProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'rclone.exe'" -ErrorAction SilentlyContinue | Where-Object {
    Test-CrossCloudMountProcess -Process $_ -RemoteTarget $remoteTarget -DriveLetter $state.DriveLetter
})
$driveExists = [bool](Get-PSDrive -Name $state.DriveLetter -ErrorAction SilentlyContinue)
if (-not (Test-CrossCloudShouldStartMount -DriveExists $driveExists -MatchingProcessCount $matchingProcesses.Count -MountPaused $mountPaused -LaunchReason $LaunchReason)) { exit 0 }

$rclone = Get-CrossCloudRcloneExe
if (-not $rclone) { exit 2 }
New-Item -ItemType Directory -Force -Path $state.CacheDir, $paths.LogRoot | Out-Null
$arguments = Get-CrossCloudMountArguments -State $state -LogFile (Join-Path $paths.LogRoot "mount.log")
$quoted = ($arguments | ForEach-Object { ConvertTo-CrossCloudProcessArgument -Value ([string]$_) }) -join " "
Start-Process -FilePath $rclone -ArgumentList $quoted -WindowStyle Hidden | Out-Null
