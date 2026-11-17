# Stands in for Start-FoundryBootstrap.ps1 in relay leg tests: fails the way a
# real leg fails, by throwing rather than by returning a status.
param(
    [string]$ConfigPath,
    [string]$Phase,
    [string]$ResumeRunRoot,
    [int]$BudgetMinutes
)

throw "provider call failed after 3 attempts"
