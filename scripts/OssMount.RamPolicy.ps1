function Assert-CrossCloudPolicyBucketName {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$BucketName)

    $value = $BucketName.Trim().ToLowerInvariant()
    if ($value -notmatch '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$') {
        throw "Bucket name must be 3-63 lowercase letters, numbers, or hyphens."
    }
    return $value
}

function Normalize-CrossCloudPolicyPrefix {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Prefix)

    $value = ($Prefix.Trim().Replace("\", "/") -replace '/+', '/').Trim("/")
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Prefix policy requires a non-root object prefix."
    }
    if ($value -match '(^|/)\.\.(/|$)' -or $value -match '[\x00-\x1F]') {
        throw "Object prefix contains an invalid segment."
    }
    return $value
}

function New-CrossCloudPrefixPolicyDocument {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$BucketName,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Prefix
    )

    $bucket = Assert-CrossCloudPolicyBucketName -BucketName $BucketName
    $normalizedPrefix = Normalize-CrossCloudPolicyPrefix -Prefix $Prefix
    return [ordered]@{
        Version = "1"
        Statement = @(
            [ordered]@{
                Effect = "Allow"
                Action = @(
                    "oss:GetBucketLocation",
                    "oss:ListObjects",
                    "oss:ListObjectsV2"
                )
                Resource = "acs:oss:*:*:$bucket"
                Condition = [ordered]@{
                    StringLike = [ordered]@{
                        "oss:Prefix" = @(
                            "$normalizedPrefix/",
                            "$normalizedPrefix/*"
                        )
                    }
                }
            },
            [ordered]@{
                Effect = "Allow"
                Action = @(
                    "oss:GetObject",
                    "oss:PutObject",
                    "oss:DeleteObject",
                    "oss:AbortMultipartUpload",
                    "oss:ListParts",
                    "oss:RestoreObject"
                )
                Resource = "acs:oss:*:*:$bucket/$normalizedPrefix/*"
            }
        )
    }
}

function New-CrossCloudFullBucketPolicyDocument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$BucketName)

    $bucket = Assert-CrossCloudPolicyBucketName -BucketName $BucketName
    return [ordered]@{
        Version = "1"
        Statement = @(
            [ordered]@{
                Effect = "Allow"
                Action = @(
                    "oss:GetBucketLocation",
                    "oss:GetBucketInfo",
                    "oss:GetBucketStat",
                    "oss:ListObjects",
                    "oss:ListObjectsV2",
                    "oss:ListObjectVersions"
                )
                Resource = @("acs:oss:*:*:$bucket")
            },
            [ordered]@{
                Effect = "Allow"
                Action = @(
                    "oss:GetObject",
                    "oss:PutObject",
                    "oss:DeleteObject",
                    "oss:DeleteObjectVersion",
                    "oss:AbortMultipartUpload",
                    "oss:ListParts",
                    "oss:RestoreObject"
                )
                Resource = @("acs:oss:*:*:$bucket/*")
            }
        )
    }
}

function ConvertTo-CrossCloudPolicyJson {
    param([Parameter(Mandatory = $true)]$PolicyDocument)

    return ($PolicyDocument | ConvertTo-Json -Depth 20 -Compress)
}
