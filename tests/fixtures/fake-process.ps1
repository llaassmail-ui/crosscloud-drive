param(
    [Parameter(Mandatory = $true)][string]$OutputValue,
    [Parameter(Mandatory = $true)][string]$ErrorValue,
    [int]$ExitCode = 0
)

[Console]::Out.Write($OutputValue)
[Console]::Error.Write($ErrorValue)
exit $ExitCode
