$script:TestCount = 0
$script:FailureCount = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    $script:TestCount++
    if ($Expected -ne $Actual) {
        $script:FailureCount++
        Write-Host "FAIL: $Message (expected '$Expected', got '$Actual')" -ForegroundColor Red
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:TestCount++
    if (-not $Condition) {
        $script:FailureCount++
        Write-Host "FAIL: $Message" -ForegroundColor Red
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $script:TestCount++
    try {
        & $Action
        $script:FailureCount++
        Write-Host "FAIL: $Message (no exception was thrown)" -ForegroundColor Red
    }
    catch { }
}

function Complete-TestFile {
    if ($script:FailureCount -gt 0) {
        throw "$($script:FailureCount) of $($script:TestCount) assertions failed."
    }
    Write-Host "PASS: $($script:TestCount) assertions" -ForegroundColor Green
}
