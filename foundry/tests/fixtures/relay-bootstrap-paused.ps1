# Stands in for Start-FoundryBootstrap.ps1 in relay leg tests: stops cleanly on
# an agent boundary, which is the normal way a leg ends its budget.
param(
    [string]$ConfigPath,
    [string]$Phase,
    [string]$ResumeRunRoot,
    [int]$BudgetMinutes
)

# A real leg leaves a non-zero exit code behind whenever an agent artifact was
# rejected and retried, which is what failed leg 2 of build 455.
& pwsh -NoProfile -Command "exit 1" 2>$null

return [pscustomobject]@{ status = "paused"; resumeRunRoot = $ResumeRunRoot }
