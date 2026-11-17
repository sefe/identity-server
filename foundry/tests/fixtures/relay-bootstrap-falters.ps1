# Stands in for Start-FoundryBootstrap.ps1 in relay leg tests: crashes the way
# leg 5 of build 474 crashed, when one model call came back 400 while the same
# profile answered eight other calls in the same run.
param(
    [string]$ConfigPath,
    [string]$Phase,
    [string]$ResumeRunRoot,
    [int]$BudgetMinutes
)

throw ('Copilot CLI exited with 1: Execution failed: 400 The resource you requested ' +
    'was not found. (Request ID: 9083:3F6DE9:1F48D55:238D784:6A968E9A)')
