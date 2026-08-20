$script:CrossCloudStateVersion = 2

function Get-CrossCloudPaths {
    param([string]$LocalAppData = $env:LOCALAPPDATA)

    if ([string]::IsNullOrWhiteSpace($LocalAppData)) {
        throw "LOCALAPPDATA is not available."
    }

    $root = Join-Path $LocalAppData "CrossCloudDrive"
    return [pscustomobject]@{
        Root = $root
        StateFile = Join-Path $root "connection.json"
        SettingsFile = Join-Path $root "settings.json"
        PauseFile = Join-Path $root "mount-paused"
        RuntimeRoot = Join-Path $root "runtime"
        CacheRoot = Join-Path $root "cache"
        LogRoot = Join-Path $root "logs"
        LegacyRoot = Join-Path $LocalAppData "rclone\oss-mount"
    }
}

function Test-CrossCloudMountPaused {
    param($Paths = (Get-CrossCloudPaths))
    return Test-Path -LiteralPath $Paths.PauseFile
}

function Set-CrossCloudMountPaused {
    param($Paths = (Get-CrossCloudPaths))

    New-Item -ItemType Directory -Force -Path $Paths.Root | Out-Null
    Set-Content -LiteralPath $Paths.PauseFile -Value ([DateTime]::UtcNow.ToString("o")) -Encoding ASCII
}

function Clear-CrossCloudMountPaused {
    param($Paths = (Get-CrossCloudPaths))
    Remove-Item -LiteralPath $Paths.PauseFile -Force -ErrorAction SilentlyContinue
}

function Normalize-CloudPath {
    param([AllowEmptyString()][string]$Path)

    if ($null -eq $Path) { return "" }
    $normalized = $Path.Trim().Replace("\", "/").Trim("/")
    if (-not $normalized) { return "" }
    if ($normalized -match '(^|/)\.\.(/|$)' -or $normalized -match '[\x00-\x1F]') {
        throw "Cloud path contains an invalid segment."
    }
    return $normalized
}

function Normalize-DriveLetter {
    param([Parameter(Mandatory = $true)][string]$DriveLetter)

    $normalized = $DriveLetter.Trim().TrimEnd(":").ToUpperInvariant()
    if ($normalized -notmatch '^[D-Z]$') {
        throw "Drive letter must be one letter from D through Z."
    }
    return $normalized
}

function Normalize-CacheSize {
    param([Parameter(Mandatory = $true)][string]$CacheSize)

    $normalized = ($CacheSize.Trim().ToUpperInvariant() -replace '\s+', '') -replace 'B$', ''
    if ($normalized -notmatch '^(?<amount>\d+)(?<unit>[KMGT])$') {
        throw "Cache size must use K, M, G, or T, for example 5G."
    }

    $multipliers = @{ K = 1KB; M = 1MB; G = 1GB; T = 1TB }
    $bytes = [decimal]$Matches.amount * [decimal]$multipliers[$Matches.unit]
    if ($bytes -lt 1GB) {
        throw "Cache size must be at least 1 GB."
    }
    return "$($Matches.amount)$($Matches.unit)"
}

function New-CrossCloudConnectionState {
    param($Paths = (Get-CrossCloudPaths))

    return [pscustomobject][ordered]@{
        SchemaVersion = $script:CrossCloudStateVersion
        Provider = "AlibabaOss"
        Region = "ap-southeast-1"
        Endpoint = "oss-ap-southeast-1.aliyuncs.com"
        Bucket = ""
        RemotePath = ""
        RemoteName = "crosscloud-main"
        DriveLetter = "Z"
        CacheDir = $Paths.CacheRoot
        CacheMaxSize = "5G"
        DirCacheTime = "1m"
        AutoMount = $true
        AutoRecover = $true
        AccessKeyId = ""
        LastUpdatedUtc = $null
    }
}

function Save-CrossCloudConnectionState {
    param(
        [Parameter(Mandatory = $true)]$State,
        $Paths = (Get-CrossCloudPaths)
    )

    New-Item -ItemType Directory -Force -Path $Paths.Root | Out-Null
    $safeState = [ordered]@{
        SchemaVersion = $script:CrossCloudStateVersion
        Provider = [string]$State.Provider
        Region = [string]$State.Region
        Endpoint = [string]$State.Endpoint
        Bucket = [string]$State.Bucket
        RemotePath = Normalize-CloudPath ([string]$State.RemotePath)
        RemoteName = [string]$State.RemoteName
        DriveLetter = Normalize-DriveLetter ([string]$State.DriveLetter)
        CacheDir = [string]$State.CacheDir
        CacheMaxSize = Normalize-CacheSize ([string]$State.CacheMaxSize)
        DirCacheTime = [string]$State.DirCacheTime
        AutoMount = [bool]$State.AutoMount
        AutoRecover = [bool]$State.AutoRecover
        AccessKeyId = [string]$State.AccessKeyId
        LastUpdatedUtc = [DateTime]::UtcNow.ToString("o")
    }
    $safeState | ConvertTo-Json | Set-Content -LiteralPath $Paths.StateFile -Encoding UTF8
    return [pscustomobject]$safeState
}

function Get-CrossCloudConnectionState {
    param($Paths = (Get-CrossCloudPaths))

    $defaults = New-CrossCloudConnectionState -Paths $Paths
    if (-not (Test-Path -LiteralPath $Paths.StateFile)) { return $defaults }

    $saved = Get-Content -LiteralPath $Paths.StateFile -Raw | ConvertFrom-Json
    foreach ($property in $defaults.PSObject.Properties) {
        $savedProperty = $saved.PSObject.Properties[$property.Name]
        if ($null -ne $savedProperty) {
            $defaults.$($property.Name) = $savedProperty.Value
        }
    }
    $defaults.RemotePath = Normalize-CloudPath ([string]$defaults.RemotePath)
    $defaults.DriveLetter = Normalize-DriveLetter ([string]$defaults.DriveLetter)
    $defaults.CacheMaxSize = Normalize-CacheSize ([string]$defaults.CacheMaxSize)
    return $defaults
}

function Test-CrossCloudOwnedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$OwnedRoots
    )

    try {
        $candidate = [IO.Path]::GetFullPath($Path).TrimEnd("\")
        foreach ($root in $OwnedRoots) {
            $resolvedRoot = [IO.Path]::GetFullPath($root).TrimEnd("\")
            if ($candidate.StartsWith($resolvedRoot + "\", [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }
    catch { return $false }
    return $false
}

function Get-LegacyOssConnectionState {
    param($Paths = (Get-CrossCloudPaths))

    if (-not (Test-Path -LiteralPath $Paths.LegacyRoot)) { return $null }
    $legacyFile = Get-ChildItem -LiteralPath $Paths.LegacyRoot -Filter "mount-*.json" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $legacyFile) { return $null }

    $legacy = Get-Content -LiteralPath $legacyFile.FullName -Raw | ConvertFrom-Json
    $state = New-CrossCloudConnectionState -Paths $Paths
    $state.Bucket = [string]$legacy.Bucket
    $state.Endpoint = [string]$legacy.Endpoint
    $state.RemoteName = if ($legacy.RemoteName) { [string]$legacy.RemoteName } else { "aliyun-oss" }
    $state.RemotePath = Normalize-CloudPath ([string]$legacy.OssPath)
    if ($legacy.DriveLetter) { $state.DriveLetter = Normalize-DriveLetter ([string]$legacy.DriveLetter) }
    if ($legacy.CacheDir) { $state.CacheDir = [string]$legacy.CacheDir }
    $state | Add-Member -NotePropertyName LegacyTaskName -NotePropertyValue ([string]$legacy.TaskName)
    $state | Add-Member -NotePropertyName LegacyConfigFile -NotePropertyValue $legacyFile.FullName
    return $state
}
