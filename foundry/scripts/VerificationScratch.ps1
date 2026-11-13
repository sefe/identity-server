function New-QaFoundryVerificationScratch {
    param([switch]$Container, [string]$Parent = '')
    # Unix test runners create domain sockets below TMPDIR. A checkout-relative
    # home can exceed their path limit before the random pipe name is appended.
    if (-not $Parent) { $Parent = if ($IsWindows) { [IO.Path]::GetTempPath() } else { '/tmp' } }
    $Parent = [IO.Path]::GetFullPath($Parent)
    New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    $path = Join-Path $parent ('qaf-' + [guid]::NewGuid().ToString('N').Substring(0, 16))
    if (Test-Path -LiteralPath $path) { throw "Verification scratch already exists: $path" }
    if ($IsWindows) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
    else {
        $mode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute
        # A configured container can run under a different uid. Preserve the
        # previous directory traversal permissions for that execution mode.
        if ($Container) {
            $mode = $mode -bor [IO.UnixFileMode]::GroupRead -bor [IO.UnixFileMode]::GroupExecute `
                -bor [IO.UnixFileMode]::OtherRead -bor [IO.UnixFileMode]::OtherExecute
        }
        [IO.Directory]::CreateDirectory($path, $mode) | Out-Null
    }
    return $path
}

function Remove-QaFoundryVerificationScratch {
    param([Parameter(Mandatory)][string]$Path, [string]$Parent = '')
    if (-not $Parent) { $Parent = if ($IsWindows) { [IO.Path]::GetTempPath() } else { '/tmp' } }
    $Parent = [IO.Path]::GetFullPath($Parent)
    $absolute = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetDirectoryName($absolute).TrimEnd('\', '/') -ne $parent.TrimEnd('\', '/') -or
        [IO.Path]::GetFileName($absolute) -notmatch '^qaf-[a-f0-9]{16}$') {
        throw 'Refusing to remove a path outside the owned verification scratch directory.'
    }
    if (Test-Path -LiteralPath $absolute) {
        try { Remove-Item -LiteralPath $absolute -Recurse -Force -ErrorAction Stop }
        catch {
            # Preserve the verification result even if a tool still holds a
            # temporary file. The previous scratch cleanup was best-effort too.
            Write-Warning "Verification scratch cleanup was incomplete at '$absolute': $($_.Exception.Message)"
        }
    }
}
