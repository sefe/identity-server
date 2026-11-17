function Get-QaFoundryActiveToolchainPath {
    param([Parameter(Mandatory)][string]$RunRoot)
    $baseline = Join-Path $RunRoot 'context/toolchain-lock.json'
    $pointerPath = Join-Path $RunRoot 'context/toolchain-current.json'
    if (-not (Test-Path -LiteralPath $pointerPath)) { return $baseline }
    $pointer = Get-Content -LiteralPath $pointerPath -Raw | ConvertFrom-Json
    $path = [IO.Path]::GetFullPath((Join-Path $RunRoot ([string]$pointer.relativePath)))
    $revisionRoot = Join-Path $RunRoot 'dependency-updates'
    if (-not (Test-PathWithinRoot -Candidate $path -Root $revisionRoot) -or
        -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Active dependency revision is missing or outside its run.' }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$pointer.sha256) {
        throw 'Active dependency revision hash does not match its recorded identity.'
    }
    return $path
}
