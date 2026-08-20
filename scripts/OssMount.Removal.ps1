function Get-CrossCloudManagedMountProcesses {
    param(
        [Parameter(Mandatory = $true)][array]$States,
        [array]$Processes = @(Get-CimInstance Win32_Process -Filter "Name = 'rclone.exe'" -ErrorAction SilentlyContinue)
    )

    $matches = @()
    foreach ($process in $Processes) {
        foreach ($state in $States) {
            if (-not $state -or -not $state.RemoteName -or -not $state.Bucket -or -not $state.DriveLetter) { continue }
            $target = Get-CrossCloudRemoteTarget -State $state
            if (Test-CrossCloudMountProcess -Process $process -RemoteTarget $target -DriveLetter $state.DriveLetter) {
                $matches += $process
                break
            }
        }
    }
    return @($matches | Sort-Object ProcessId -Unique)
}

function Stop-CrossCloudManagedMounts {
    param([Parameter(Mandatory = $true)][array]$States)

    $processes = @(Get-CrossCloudManagedMountProcesses -States $States)
    foreach ($process in $processes) {
        Invoke-CimMethod -InputObject $process -MethodName Terminate -ErrorAction SilentlyContinue | Out-Null
    }
    return $processes.Count
}

function Get-CrossCloudRemovalPlan {
    param(
        [Parameter(Mandatory = $true)]$State,
        $Paths = (Get-CrossCloudPaths)
    )

    $cacheDir = [string]$State.CacheDir
    $removeCache = $false
    if ($cacheDir) {
        try {
            $cachePath = [IO.Path]::GetFullPath($cacheDir).TrimEnd("\")
            $defaultCache = [IO.Path]::GetFullPath($Paths.CacheRoot).TrimEnd("\")
            $removeCache = ($cachePath.Equals($defaultCache, [StringComparison]::OrdinalIgnoreCase) -or
                $cachePath.StartsWith($defaultCache + "\", [StringComparison]::OrdinalIgnoreCase))
        }
        catch { $removeCache = $false }
    }
    $remoteNames = @([string]$State.RemoteName)
    $legacy = Get-LegacyOssConnectionState -Paths $Paths
    if ($legacy -and $legacy.RemoteName -and $legacy.RemoteName -notin $remoteNames) { $remoteNames += [string]$legacy.RemoteName }
    return [pscustomobject]@{
        States = @($State, $legacy | Where-Object { $null -ne $_ })
        RemoteNames = @($remoteNames | Where-Object { $_ } | Select-Object -Unique)
        DriveLetters = @($State.DriveLetter, $legacy.DriveLetter | Where-Object { $_ } | Select-Object -Unique)
        CacheDir = $cacheDir
        RemoveCache = $removeCache
        RemoveRuntime = $true
        RemovePauseMarker = $true
        RemoveLegacyRoot = [bool](Test-Path -LiteralPath $Paths.LegacyRoot)
    }
}

function Remove-CrossCloudOwnedDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$OwnedRoots
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    if (-not (Test-CrossCloudOwnedPath -Path $Path -OwnedRoots $OwnedRoots)) { return $false }
    Remove-Item -LiteralPath $Path -Recurse -Force
    return $true
}

function Remove-CrossCloudLegacyDirectory {
    param($Paths = (Get-CrossCloudPaths))

    if (-not (Test-Path -LiteralPath $Paths.LegacyRoot)) { return $true }
    try {
        $localAppData = Split-Path -Parent ([IO.Path]::GetFullPath([string]$Paths.Root).TrimEnd("\"))
        $expectedLegacyRoot = [IO.Path]::GetFullPath((Join-Path $localAppData "rclone\oss-mount")).TrimEnd("\")
        $candidateLegacyRoot = [IO.Path]::GetFullPath([string]$Paths.LegacyRoot).TrimEnd("\")
        if (-not $candidateLegacyRoot.Equals($expectedLegacyRoot, [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        return Remove-CrossCloudOwnedDirectory -Path $candidateLegacyRoot -OwnedRoots @((Split-Path -Parent $expectedLegacyRoot))
    }
    catch { return $false }
}

function Import-CrossCloudLegacyConnection {
    param($Paths = (Get-CrossCloudPaths))

    if (Test-Path -LiteralPath $Paths.StateFile) { return Get-CrossCloudConnectionState -Paths $Paths }
    $legacy = Get-LegacyOssConnectionState -Paths $Paths
    if (-not $legacy) { return $null }
    $regionMap = @{
        "oss-ap-southeast-1.aliyuncs.com" = "ap-southeast-1"
        "oss-ap-northeast-1.aliyuncs.com" = "ap-northeast-1"
        "oss-ap-southeast-2.aliyuncs.com" = "ap-southeast-2"
        "oss-eu-central-1.aliyuncs.com" = "eu-central-1"
        "oss-eu-west-1.aliyuncs.com" = "eu-west-1"
        "oss-us-west-1.aliyuncs.com" = "us-west-1"
        "oss-us-east-1.aliyuncs.com" = "us-east-1"
    }
    $endpoint = ([string]$legacy.Endpoint).Trim().TrimEnd("/").ToLowerInvariant() -replace '^https?://', ''
    $legacy.Region = if ($regionMap.ContainsKey($endpoint)) { $regionMap[$endpoint] } else { "custom" }
    Save-CrossCloudConnectionState -State $legacy -Paths $Paths | Out-Null
    return Get-CrossCloudConnectionState -Paths $Paths
}

function Remove-CrossCloudDriveRecord {
    param([Parameter(Mandatory = $true)][string]$DriveLetter)

    $drive = Normalize-DriveLetter -DriveLetter $DriveLetter
    Invoke-CrossCloudProcess -FilePath "$env:WINDIR\System32\net.exe" -Arguments @("use", "${drive}:", "/delete", "/y") | Out-Null
    Invoke-CrossCloudProcess -FilePath "$env:WINDIR\System32\subst.exe" -Arguments @("${drive}:", "/d") | Out-Null
    Remove-PSDrive -Name $drive -Force -ErrorAction SilentlyContinue
    $networkPath = "HKCU:\Network\$drive"
    if (Test-Path -LiteralPath $networkPath) { Remove-Item -LiteralPath $networkPath -Recurse -Force }
}

function Remove-CrossCloudRemote {
    param([Parameter(Mandatory = $true)][string]$RemoteName)

    $rclone = Get-CrossCloudRcloneExe
    if (-not $rclone) { return $false }
    $remotes = Invoke-CrossCloudProcess -FilePath $rclone -Arguments @("listremotes")
    if ($remotes.ExitCode -ne 0 -or $RemoteName + ":" -notin @($remotes.Stdout -split "`r?`n")) { return $false }
    $result = Invoke-CrossCloudProcess -FilePath $rclone -Arguments @("config", "delete", $RemoteName)
    if ($result.ExitCode -ne 0) { throw "Could not remove the managed rclone remote: $($result.Stderr)" }
    return $true
}

function Remove-CrossCloudLegacyTasks {
    param([AllowEmptyString()][string]$LegacyTaskName = "")

    $names = @($LegacyTaskName) | Where-Object { $_ }
    $known = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -like "Mount OSS workspace drive *" -or $_.TaskName -in $names
    })
    foreach ($task in $known) {
        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Uninstall-CrossCloudDependencies {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { throw "winget is required to uninstall rclone and WinFsp." }
    $results = @()
    foreach ($package in @("Rclone.Rclone", "WinFsp.WinFsp")) {
        $results += Invoke-CrossCloudProcess -FilePath $winget.Source -Arguments @(
            "uninstall", "--id", $package, "--exact", "--silent", "--accept-source-agreements"
        )
    }
    return $results
}

function Remove-CrossCloudConnection {
    param(
        $State = (Get-CrossCloudConnectionState),
        $Paths = (Get-CrossCloudPaths),
        [switch]$RemoveDependencies
    )

    $plan = Get-CrossCloudRemovalPlan -State $State -Paths $Paths
    Remove-CrossCloudScheduledTasks
    $legacy = Get-LegacyOssConnectionState -Paths $Paths
    Remove-CrossCloudLegacyTasks -LegacyTaskName $(if ($legacy) { $legacy.LegacyTaskName } else { "" })
    Stop-CrossCloudManagedMounts -States $plan.States | Out-Null
    foreach ($drive in $plan.DriveLetters) { if ($drive) { Remove-CrossCloudDriveRecord -DriveLetter $drive } }
    foreach ($remote in $plan.RemoteNames) { Remove-CrossCloudRemote -RemoteName $remote | Out-Null }
    if ($plan.RemoveCache) { Remove-CrossCloudOwnedDirectory -Path $plan.CacheDir -OwnedRoots @($Paths.Root) | Out-Null }
    if (Test-Path -LiteralPath $Paths.RuntimeRoot) { Remove-CrossCloudOwnedDirectory -Path $Paths.RuntimeRoot -OwnedRoots @($Paths.Root) | Out-Null }
    if (Test-Path -LiteralPath $Paths.PauseFile) { Remove-Item -LiteralPath $Paths.PauseFile -Force }
    if (Test-Path -LiteralPath $Paths.StateFile) { Remove-Item -LiteralPath $Paths.StateFile -Force }
    if (Test-Path -LiteralPath $Paths.SettingsFile) { Remove-Item -LiteralPath $Paths.SettingsFile -Force }
    if (Test-Path -LiteralPath $Paths.LegacyRoot) { Remove-CrossCloudLegacyDirectory -Paths $Paths | Out-Null }
    if ($RemoveDependencies) { Uninstall-CrossCloudDependencies | Out-Null }
    return $plan
}
