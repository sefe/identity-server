[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactPath,
    [Parameter(Mandatory)][string]$SchemaPath,
    [string]$SchemaRoot,
    # Returns what is wrong instead of throwing it. A caller that intends to
    # act on a specific failure needs the errors as data: parsing them back out
    # of an exception message is how a fix ends up depending on wording.
    [switch]$NoThrow
)

. (Join-Path $PSScriptRoot "Common.ps1")
$root = Get-QaFoundryRoot
if (-not $SchemaRoot) {
    $SchemaRoot = Join-Path $root "schemas"
}

if (-not (Test-Path $ArtifactPath -PathType Leaf)) {
    throw "Artifact does not exist: $ArtifactPath"
}
if (-not (Test-Path $SchemaPath -PathType Leaf)) {
    throw "Schema does not exist: $SchemaPath"
}

$helper = Join-Path $root "scripts/helpers/Validate-JsonSchema.mjs"
$resultJson = & node $helper $SchemaPath $ArtifactPath $SchemaRoot
$exitCode = $LASTEXITCODE
# A rejected artifact is the normal retry path, not a process failure. Build 455
# lost a whole relay leg because node's exit code survived the caught exception:
# the leg script ends without an explicit exit, so Azure DevOps read the stale
# $LASTEXITCODE and failed a leg that had in fact paused cleanly.
$global:LASTEXITCODE = 0
if (-not $resultJson) {
    throw "Schema validator returned no result for $ArtifactPath"
}
$result = $resultJson | ConvertFrom-Json -Depth 100
if ($exitCode -ne 0 -or -not $result.valid) {
    # Ajv puts the offending property name in params, not in the message, so a bare
    # "must NOT have additional properties" tells an agent nothing it can act on.
    $messages = @($result.errors | ForEach-Object {
        $detail = ""
        if (((Get-QaFoundryPropertyNames -InputObject $_) -contains "params") -and $null -ne $_.params) {
            $names = @(Get-QaFoundryPropertyNames -InputObject $_.params)
            if ($names -contains "additionalProperty") {
                $detail = " ('$($_.params.additionalProperty)')"
            }
            elseif ($names -contains "missingProperty") {
                $detail = " ('$($_.params.missingProperty)')"
            }
            elseif ($names -contains "limit") {
                $detail = " (limit $($_.params.limit))"
            }
        }
        "$($_.instancePath): $($_.message)$detail"
    } | Select-Object -Unique) -join "; "
    $message = "Schema validation failed for $ArtifactPath. $messages"
    if ($NoThrow) {
        return [pscustomobject]@{
            valid = $false
            errors = @($result.errors)
            message = $message
        }
    }
    throw $message
}
if ($NoThrow) {
    return [pscustomobject]@{ valid = $true; errors = @(); message = "" }
}
return $result

