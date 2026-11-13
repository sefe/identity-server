[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$Root
)

$temporary = [System.IO.Path]::GetTempFileName()
try {
    $Config | ConvertTo-Json -Depth 100 | Set-Content -Path $temporary -Encoding utf8
    $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
        -ArtifactPath $temporary `
        -SchemaPath (Join-Path $Root "schemas/bootstrap/bootstrap-config.schema.json") `
        -SchemaRoot (Join-Path $Root "schemas")
}
finally {
    Remove-Item -Path $temporary -Force -ErrorAction SilentlyContinue
}
return [pscustomobject]@{ valid = $true }
