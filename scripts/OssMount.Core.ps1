function Get-CrossCloudRcloneExe {
    $command = Get-Command rclone -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles "rclone\rclone.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\rclone.exe")
    )
    $packageRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path -LiteralPath $packageRoot) {
        $packageExe = Get-ChildItem -LiteralPath $packageRoot -Filter "rclone.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object FullName -match 'Rclone\.Rclone' |
            Select-Object -First 1
        if ($packageExe) { $candidates += $packageExe.FullName }
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return [IO.Path]::GetFullPath($candidate) }
    }
    return $null
}

function ConvertTo-CrossCloudProcessArgument {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\*)"', '$1$1\"' -replace '(\+)$', '$1$1') + '"'
}

function Protect-CrossCloudText {
    param([AllowEmptyString()][string]$Text, [string[]]$SensitiveValues = @())

    $safe = [string]$Text
    foreach ($value in $SensitiveValues) {
        if (-not [string]::IsNullOrEmpty($value)) { $safe = $safe.Replace($value, "***") }
    }
    return $safe
}

function Invoke-CrossCloudProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string[]]$SensitiveValues = @()
    )

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-CrossCloudProcessArgument -Value ([string]$_) }) -join " ")
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = (Protect-CrossCloudText -Text $stdout.Trim() -SensitiveValues $SensitiveValues)
        Stderr = (Protect-CrossCloudText -Text $stderr.Trim() -SensitiveValues $SensitiveValues)
    }
}

function Get-CrossCloudAvailableDriveLetter {
    param(
        [string[]]$UsedDriveLetters = @((Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue).Name),
        [AllowEmptyString()][string]$PreferredDriveLetter = ""
    )

    $used = @($UsedDriveLetters | ForEach-Object { ([string]$_).Trim().TrimEnd(":").ToUpperInvariant() })
    if ($PreferredDriveLetter) {
        $preferred = Normalize-DriveLetter -DriveLetter $PreferredDriveLetter
        if ($preferred -notin $used) { return $preferred }
    }
    for ($code = [int][char]'Z'; $code -ge [int][char]'D'; $code--) {
        $letter = [string][char]$code
        if ($letter -notin $used) { return $letter }
    }
    throw "No drive letter from D through Z is available."
}

function Get-CrossCloudRemoteTarget {
    param([Parameter(Mandatory = $true)]$State)

    $target = "$([string]$State.RemoteName):$([string]$State.Bucket)"
    $path = Normalize-CloudPath -Path ([string]$State.RemotePath)
    if ($path) { $target += "/$path" }
    return $target
}

function Get-CrossCloudMountArguments {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$LogFile)

    $drive = Normalize-DriveLetter -DriveLetter ([string]$State.DriveLetter)
    $cacheSize = Normalize-CacheSize -CacheSize ([string]$State.CacheMaxSize)
    $dirCacheTime = if ([string]::IsNullOrWhiteSpace([string]$State.DirCacheTime)) { "1m" } else { [string]$State.DirCacheTime }
    return @(
        "mount", (Get-CrossCloudRemoteTarget -State $State), "${drive}:",
        "--network-mode", "--vfs-cache-mode", "full",
        "--vfs-cache-max-size", $cacheSize, "--cache-dir", [string]$State.CacheDir,
        "--dir-cache-time", $dirCacheTime, "--log-file", $LogFile, "--log-level", "INFO"
    )
}

function Get-CrossCloudRemoteConfigArguments {
    param([Parameter(Mandatory = $true)]$Definition)

    $arguments = @("config", "create", [string]$Definition.RemoteName, [string]$Definition.Type)
    foreach ($entry in $Definition.Parameters.GetEnumerator()) {
        $arguments += [string]$entry.Key
        $arguments += [string]$entry.Value
    }
    return $arguments
}

function Test-CrossCloudCommandToken {
    param([AllowEmptyString()][string]$CommandLine, [Parameter(Mandatory = $true)][string]$Token)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    $pattern = '(?i)(?:^|\s|")' + [regex]::Escape($Token) + '(?:$|\s|")'
    return [bool]($CommandLine -match $pattern)
}

function Test-CrossCloudMountProcess {
    param(
        [Parameter(Mandatory = $true)]$Process,
        [Parameter(Mandatory = $true)][string]$RemoteTarget,
        [Parameter(Mandatory = $true)][string]$DriveLetter
    )

    if ([string]$Process.Name -ine "rclone.exe") { return $false }
    $commandLine = [string]$Process.CommandLine
    $drive = (Normalize-DriveLetter -DriveLetter $DriveLetter) + ":"
    return ((Test-CrossCloudCommandToken -CommandLine $commandLine -Token "mount") -and
        (Test-CrossCloudCommandToken -CommandLine $commandLine -Token $RemoteTarget) -and
        (Test-CrossCloudCommandToken -CommandLine $commandLine -Token $drive))
}

function Convert-CrossCloudSizeToBytes {
    param([Parameter(Mandatory = $true)][string]$Size)

    $normalized = Normalize-CacheSize -CacheSize $Size
    if ($normalized -notmatch '^(?<amount>\d+)(?<unit>[KMGT])$') { throw "Cache size is invalid." }
    $multipliers = @{ K = 1KB; M = 1MB; G = 1GB; T = 1TB }
    return [decimal]$Matches.amount * [decimal]$multipliers[$Matches.unit]
}

function Get-CrossCloudCacheAdvice {
    param(
        [Parameter(Mandatory = $true)][string]$CacheMaxSize,
        [Parameter(Mandatory = $true)][decimal]$FreeBytes
    )

    $cacheBytes = Convert-CrossCloudSizeToBytes -Size $CacheMaxSize
    $reasons = @()
    if ($FreeBytes -lt 10GB) { $reasons += "LowDiskSpace" }
    if ($FreeBytes -gt 0 -and $cacheBytes -gt ($FreeBytes * [decimal]0.25)) { $reasons += "CacheLargeForDisk" }
    return [pscustomobject]@{
        Warning = ($reasons.Count -gt 0)
        Reasons = $reasons
        CacheBytes = $cacheBytes
        FreeBytes = $FreeBytes
    }
}
