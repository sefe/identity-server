[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$BootstrapResultPath = ''
)
$ErrorActionPreference = 'Stop'
$frameworkRoot = Split-Path $PSScriptRoot -Parent
& node (Join-Path $PSScriptRoot 'helpers/run-report.mjs') $RepositoryRoot $frameworkRoot $RunRoot $OutputPath $BootstrapResultPath
if ($LASTEXITCODE -ne 0) { throw 'Could not generate the Foundry report from the recorded evidence.' }
