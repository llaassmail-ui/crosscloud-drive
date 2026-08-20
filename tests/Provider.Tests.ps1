$ErrorActionPreference = "Stop"
. "$PSScriptRoot\TestHelpers.ps1"
. "$PSScriptRoot\..\scripts\providers\AlibabaOss.Provider.ps1"

$regions = @(Get-AlibabaOssRegions)
Assert-True ($regions.Count -ge 7) "International OSS region list is available"
Assert-Equal "oss-ap-southeast-1.aliyuncs.com" (($regions | Where-Object Id -eq "ap-southeast-1").Endpoint) "Singapore endpoint is mapped"
Assert-Equal "oss-eu-west-1.aliyuncs.com" (($regions | Where-Object Id -eq "eu-west-1").Endpoint) "London endpoint is mapped"

Assert-Equal "oss-ap-southeast-1.aliyuncs.com" (Resolve-AlibabaOssEndpoint -Region "ap-southeast-1") "Known region resolves its endpoint"
Assert-Equal "oss-example.aliyuncs.com" (Resolve-AlibabaOssEndpoint -Region "custom" -CustomEndpoint " https://oss-example.aliyuncs.com/ ") "Custom endpoint is normalized"
Assert-Throws { Resolve-AlibabaOssEndpoint -Region "custom" -CustomEndpoint "https://example.com/path" } "Custom endpoint rejects paths"
Assert-Throws { Resolve-AlibabaOssEndpoint -Region "unknown" } "Unknown regions are rejected"

Assert-Equal "valid-bucket-123" (Normalize-AlibabaOssBucket -Bucket " valid-bucket-123 ") "Bucket is trimmed"
Assert-Throws { Normalize-AlibabaOssBucket -Bucket "" } "Empty bucket is rejected"
Assert-Throws { Normalize-AlibabaOssBucket -Bucket "Invalid_Bucket" } "Invalid bucket characters are rejected"
Assert-Throws { Normalize-AlibabaOssBucket -Bucket "ab" } "Short bucket names are rejected"

Assert-Equal "users/alice" (Normalize-AlibabaOssPrefix -Prefix " /users\\alice/ ") "Object prefix is normalized"
Assert-Equal "" (Normalize-AlibabaOssPrefix -Prefix "/") "Bucket root becomes an empty prefix"
Assert-Throws { Normalize-AlibabaOssPrefix -Prefix "users/../admin" } "Parent path segments are rejected"

$definition = New-AlibabaOssRemoteDefinition `
    -RemoteName "crosscloud-main" `
    -Endpoint "oss-ap-southeast-1.aliyuncs.com" `
    -AccessKeyId "test-access-id" `
    -AccessKeySecret "test-secret-value"

Assert-Equal "crosscloud-main" $definition.RemoteName "Remote name is retained"
Assert-Equal "s3" $definition.Type "Alibaba OSS uses the rclone S3 backend"
Assert-Equal "Alibaba" $definition.Parameters.provider "Alibaba provider is selected"
Assert-Equal "oss-ap-southeast-1.aliyuncs.com" $definition.Parameters.endpoint "Endpoint is included"
Assert-Equal "private" $definition.Parameters.acl "Objects default to private ACL"
Assert-Equal "test-secret-value" $definition.Parameters.secret_access_key "Secret is only carried in the transient remote definition"

Assert-Equal "crosscloud-main:example-bucket" (Get-AlibabaOssRemoteTarget -RemoteName "crosscloud-main" -Bucket "example-bucket" -Prefix "/") "Bucket root target has no trailing slash"
Assert-Equal "crosscloud-main:example-bucket/users/alice" (Get-AlibabaOssRemoteTarget -RemoteName "crosscloud-main" -Bucket "example-bucket" -Prefix "users/alice/") "Prefix target is normalized"

Complete-TestFile
