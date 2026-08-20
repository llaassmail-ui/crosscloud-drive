$ErrorActionPreference = "Stop"
. "$PSScriptRoot\TestHelpers.ps1"
. "$PSScriptRoot\..\scripts\OssMount.RamPolicy.ps1"

$prefix = New-CrossCloudPrefixPolicyDocument -BucketName "example-workspace" -Prefix "users/alice"
Assert-Equal "acs:oss:*:*:example-workspace" $prefix.Statement[0].Resource "Prefix policy lists only the selected bucket"
Assert-True ($prefix.Statement[0].Condition.StringLike."oss:Prefix" -contains "users/alice/*") "Prefix list condition is scoped to the user"
Assert-Equal "acs:oss:*:*:example-workspace/users/alice/*" $prefix.Statement[1].Resource "Object actions are scoped to the user prefix"
Assert-True ($prefix.Statement[1].Action -contains "oss:DeleteObject") "Prefix policy supports file deletion"
Assert-True (-not ($prefix.Statement[1].Action -contains "oss:DeleteBucket")) "Prefix policy cannot delete the bucket"

$full = New-CrossCloudFullBucketPolicyDocument -BucketName "example-workspace"
Assert-Equal "acs:oss:*:*:example-workspace" $full.Statement[0].Resource[0] "Full policy grants bucket metadata and listing actions"
Assert-Equal "acs:oss:*:*:example-workspace/*" $full.Statement[1].Resource[0] "Full policy grants all object paths"
Assert-True ($full.Statement[1].Action -contains "oss:DeleteObjectVersion") "Full policy can manage object versions"
Assert-True (-not ($full.Statement[0].Action -contains "oss:DeleteBucket")) "Full object policy cannot delete the bucket"

Assert-Throws { New-CrossCloudPrefixPolicyDocument -BucketName "" -Prefix "users/alice" } "Policy requires an explicit bucket"
Assert-Throws { New-CrossCloudPrefixPolicyDocument -BucketName "example-workspace" -Prefix "/" } "Prefix policy requires a non-root prefix"
Assert-Throws { New-CrossCloudPrefixPolicyDocument -BucketName "example-workspace" -Prefix "users/../admin" } "Policy rejects parent traversal"

$json = ConvertTo-CrossCloudPolicyJson -PolicyDocument $prefix
Assert-True ($json.Contains('"Version":"1"')) "Policy converts to compact JSON"
Assert-True (-not $json.Contains("AccessKey")) "Policy JSON never contains credentials"

Complete-TestFile
