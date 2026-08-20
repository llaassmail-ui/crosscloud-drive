$script:AlibabaOssRegions = @(
    [pscustomobject]@{ Id = "ap-southeast-1"; Endpoint = "oss-ap-southeast-1.aliyuncs.com"; LocaleKey = "Singapore" }
    [pscustomobject]@{ Id = "ap-northeast-1"; Endpoint = "oss-ap-northeast-1.aliyuncs.com"; LocaleKey = "Japan" }
    [pscustomobject]@{ Id = "ap-southeast-2"; Endpoint = "oss-ap-southeast-2.aliyuncs.com"; LocaleKey = "Australia" }
    [pscustomobject]@{ Id = "eu-central-1"; Endpoint = "oss-eu-central-1.aliyuncs.com"; LocaleKey = "Germany" }
    [pscustomobject]@{ Id = "eu-west-1"; Endpoint = "oss-eu-west-1.aliyuncs.com"; LocaleKey = "UnitedKingdom" }
    [pscustomobject]@{ Id = "us-west-1"; Endpoint = "oss-us-west-1.aliyuncs.com"; LocaleKey = "UnitedStatesWest" }
    [pscustomobject]@{ Id = "us-east-1"; Endpoint = "oss-us-east-1.aliyuncs.com"; LocaleKey = "UnitedStatesEast" }
)

function Get-AlibabaOssRegions {
    return @($script:AlibabaOssRegions)
}

function Normalize-AlibabaOssEndpoint {
    param([Parameter(Mandatory = $true)][string]$Endpoint)

    $value = $Endpoint.Trim().TrimEnd("/")
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Endpoint is required."
    }
    if ($value -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $value = "https://$value"
    }

    $uri = $null
    if (-not [Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @("http", "https") -or
        [string]::IsNullOrWhiteSpace($uri.Host) -or
        $uri.AbsolutePath -ne "/" -or
        $uri.Query -or
        $uri.Fragment -or
        $uri.UserInfo -or
        -not $uri.IsDefaultPort) {
        throw "Endpoint must be an HTTP or HTTPS host without a path, query, credentials, or custom port."
    }
    if ($uri.Host -notmatch '^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$') {
        throw "Endpoint host is invalid."
    }
    return $uri.Host.ToLowerInvariant()
}

function Resolve-AlibabaOssEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$Region,
        [AllowEmptyString()][string]$CustomEndpoint = ""
    )

    if ($Region -eq "custom") {
        return Normalize-AlibabaOssEndpoint -Endpoint $CustomEndpoint
    }
    $match = $script:AlibabaOssRegions | Where-Object Id -eq $Region | Select-Object -First 1
    if (-not $match) {
        throw "Unsupported Alibaba OSS region: $Region"
    }
    return $match.Endpoint
}

function Normalize-AlibabaOssBucket {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Bucket)

    $value = $Bucket.Trim().ToLowerInvariant()
    if ($value -notmatch '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$') {
        throw "Bucket must be 3-63 characters using lowercase letters, numbers, and hyphens, and must start and end with a letter or number."
    }
    return $value
}

function Normalize-AlibabaOssPrefix {
    param([AllowEmptyString()][string]$Prefix = "")

    if ($null -eq $Prefix) { return "" }
    $value = ($Prefix.Trim().Replace("\", "/") -replace '/+', '/').Trim("/")
    if (-not $value) { return "" }
    if ($value -match '(^|/)\.\.(/|$)' -or $value -match '[\x00-\x1F]') {
        throw "Object prefix contains an invalid segment."
    }
    return $value
}

function New-AlibabaOssRemoteDefinition {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteName,
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][string]$AccessKeyId,
        [Parameter(Mandatory = $true)][string]$AccessKeySecret
    )

    if ($RemoteName -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$') {
        throw "Remote name is invalid."
    }
    if ([string]::IsNullOrWhiteSpace($AccessKeyId) -or [string]::IsNullOrWhiteSpace($AccessKeySecret)) {
        throw "AccessKey ID and Secret are required."
    }

    return [pscustomobject][ordered]@{
        RemoteName = $RemoteName
        Type = "s3"
        Parameters = [ordered]@{
            provider = "Alibaba"
            env_auth = "false"
            access_key_id = $AccessKeyId.Trim()
            secret_access_key = $AccessKeySecret
            endpoint = Normalize-AlibabaOssEndpoint -Endpoint $Endpoint
            acl = "private"
        }
    }
}

function Get-AlibabaOssRemoteTarget {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteName,
        [Parameter(Mandatory = $true)][string]$Bucket,
        [AllowEmptyString()][string]$Prefix = ""
    )

    $normalizedBucket = Normalize-AlibabaOssBucket -Bucket $Bucket
    $normalizedPrefix = Normalize-AlibabaOssPrefix -Prefix $Prefix
    $target = "${RemoteName}:$normalizedBucket"
    if ($normalizedPrefix) { $target += "/$normalizedPrefix" }
    return $target
}
