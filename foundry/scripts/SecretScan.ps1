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
        # Installed provider configuration maps secret names to environment
        # variable names; an identity mapping contains no credential value.
        if ($Path.Replace('\','/') -ceq '.foundry/project.json' -and
            $Line -cmatch '^\s*"(?<symbol>[A-Z][A-Z0-9]*(?:_[A-Z0-9]+){2,})"\s*:\s*"\k<symbol>"\s*,?\s*$' -and
            $value -ceq $Matches.symbol) {
            return 'identity mapping to a named environment variable'
        }
        # Require a complete C# constant declaration, not merely a nearby
        # safe-looking identifier on a line containing another assignment.
        if ($Path -match '\.cs$' -and $Line -cmatch '^\s*(?:(?:public|private|internal|protected|static|new)\s+)*const\s+string\s+(?<member>\w+)\s*=\s*"(?<literal>[^"\r\n]+)"\s*;\s*$' -and
            $value -ceq $Matches.literal) {
            $member=$Matches.member
            if ($member -cmatch '^[A-Z]\w*Secret$' -and
                $value -ceq ($member+'Ext')) {
                return 'entity type name in a C# constant'
            }
            if ($member -cmatch '^(?<entity>[A-Z]\w*)Secret$' -and
                $value -ceq ('/api/'+$Matches.entity.ToLowerInvariant()+'/secret')) {
                return 'API route in a C# constant'
            }
            if ($member -ceq 'AccessToken' -and $value -ceq 'urn:ietf:params:oauth:token-type:access_token') {
                return 'OAuth access-token type identifier'
            }
        }
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
    # The generated report embeds JSON. Only its explicit suite-input metadata
    # can describe lists of environment variable names. Scan all other fields,
    # and leave malformed/unrecognised metadata untouched (fail closed).
    if ($Path.Replace('\','/') -ceq 'foundry-report.html' -and
        $Line -cmatch '^\s*<script id="report-data" type="application/json">(?<json>.*?)</script>') {
        try {
            $data=$Matches.json | ConvertFrom-Json -AsHashtable -Depth 100
            $symbol='[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+'
            $list="$symbol(?:, $symbol)*"
            foreach ($summary in $data['summaries']) {
                $details=$summary['details']
                if ($details -isnot [System.Collections.IDictionary]) { continue }
                $configuration=$details['configuration']
                if ($configuration -isnot [System.Collections.IDictionary]) { continue }
                $inputs=$configuration['suiteInputs']
                if ($inputs -isnot [System.Collections.IDictionary]) { continue }
                $original=$inputs | ConvertTo-Json -Compress -Depth 100
                if (-not $Line.Contains($original)) { continue }
                $safe=[ordered]@{}
                foreach ($key in $inputs.Keys) {
                    $value=$inputs[$key]
                    if ($value -is [string] -and $value -cmatch "^$list; \(s\) $list\.$") {
                        $safe[$key]='<environment variable names>'
                        [pscustomobject]@{rule='generic-secret-assignment';ignored=$true;reason='suite-input environment variable list in report metadata'}
                    } else { $safe[$key]=$value }
                }
                $Line=$Line.Replace($original,($safe | ConvertTo-Json -Compress -Depth 100))
            }
        } catch { } # Preserve ordinary scanning when the report cannot be parsed.
    }
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
