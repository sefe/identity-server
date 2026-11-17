# Provider redaction intentionally overmatches. Build failures need a narrower
# interpretation: source expressions and declared test data are not credentials.
function Get-QaFoundrySecretCandidateDisposition {
    param([object]$Rule, [System.Text.RegularExpressions.Match]$Match, [string]$Line, [string]$Path)
    if ($Rule.id -eq 'connection-string-secret') {
        $value = $Match.Groups[3].Value
        if ($Path -match '\.(cs|[cm]?[jt]sx?|ps1|md)$' -and (
            $value -match '^[A-Za-z_]\w*\.[A-Za-z_]\w*(?:\(|$)' -or
            $value -match '^[A-Za-z_]\w*\(' -or
            ($value -eq 'Read-Host' -and $Line -match '-AsSecureString'))) {
            return 'source expression, not a literal connection-string credential'
        }
    }
    if ($Rule.id -eq 'generic-secret-assignment') {
        $value = $Match.Groups[3].Value
        if ($Line -match '\bconst\s+(?:string\s+)?\w+\s*=' -and
            $value -cmatch '^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+){2,}$') {
            return 'constant naming an environment variable'
        }
        $testPath = $Path.Replace('\','/') -match '(?i)(^|/)(tests?|__tests__|specs?)/|[./](tests?|spec)\.'
        if ($testPath -and ($value -match '(?i)^(?:local)?(?:symbolic|synthetic|dummy|example|placeholder|redacted)' -or
            $value -cmatch '^(?:raw|row)-(?:[a-z]+-)*(?:value|password|token)$')) {
            return 'explicitly symbolic test fixture value'
        }
    }
    return ''
}

function Get-QaFoundrySecretLineFindings {
    param([string]$Line, [string]$Path, [object[]]$Rules)
    foreach ($rule in $Rules) {
        $pattern = [string]$rule.pattern
        if ($rule.id -eq 'aws-access-key-id') { $pattern = '(?<![A-Za-z0-9])(?:' + $pattern + ')(?![A-Za-z0-9])' }
        # PowerShell -match is case insensitive by default, which made mixed-case
        # base64 package hashes look like uppercase AWS access keys.
        foreach ($match in [regex]::Matches($Line, $pattern)) {
            $reason = Get-QaFoundrySecretCandidateDisposition -Rule $rule -Match $match -Line $Line -Path $Path
            [pscustomobject]@{ rule = $rule.id; ignored = [bool]$reason; reason = $reason }
        }
    }
}
