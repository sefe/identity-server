[CmdletBinding()]
param([Parameter(Mandatory)][string]$GoPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../ecosystems/go.Ecosystem.ps1')
try {
    # Adding indirect requirements changes Go's pruned graph roots. Resolve
    # again before publishing the sum so their metadata is also pinned.
    for ($pass = 0; $pass -lt 8; $pass++) {
        & $GoPath mod download all | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Go dependency resolution failed ($LASTEXITCODE)." }
        $manifest = Get-Content -LiteralPath 'go.mod' -Raw
        $completed = Complete-QaFoundryGoManifestFromLock $manifest (Get-Content -LiteralPath 'go.sum' -Raw)
        if ($completed -ceq $manifest) { exit 0 }
        Set-Content -LiteralPath 'go.mod' -Value $completed -NoNewline -Encoding utf8
    }
    throw 'The Go dependency graph did not stabilize within eight preparation passes.'
}
catch { Write-Error $_ -ErrorAction Continue; exit 1 }
