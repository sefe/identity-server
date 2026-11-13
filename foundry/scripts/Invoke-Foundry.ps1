[CmdletBinding()]
param(
    [string]$ConfigPath = "./config/project.yaml",
    [string]$WorkflowPath = "",
    [string]$PolicyPath = "./policies/default-policy.yaml",
    [string]$TargetRepositoryPath = "",
    [string[]]$DocumentationPath = @(),
    [string]$DocumentationLinks = '',
    [string[]]$RequirementsPath = @(),
    [string[]]$ArchitecturePath = @(),
    [string[]]$AdditionalContextPath = @(),
    [string]$EventPath = "",
    [string]$EventType = "auto",
    [string]$EventId = "",
    [string]$CiBuildId = "",
    [string]$CiRunId = "",
    [string]$SecretsPath = "",
    [string]$AiProfile = "",
    [string]$Model = "",
    [string]$ReasoningEffort = "",
    [string]$ResumeRunRoot = "",
    [string]$RestartStage = "",
    [int]$BudgetMinutes = 0,
    [switch]$Demo,
    [switch]$ValidateOnly
)

# Public entry point. DevOps delivery is Azure DevOps-only in this release;
# the original script name remains for compatibility with existing bootstrap calls.
& (Join-Path $PSScriptRoot "Invoke-QaFoundry.ps1") @PSBoundParameters
