# A YAML file under the agent pipeline prefix is registered as automation, and once
# registered nobody looks at it again. Whether it will ever start, and whether anyone
# will hear it fail, is decided entirely by what the YAML says - and both failures are
# invisible: a pipeline that never triggers and a pipeline that triggers and passes
# look identical from the outside, and so do a suite that reports its failures and one
# that reports them to nobody.
#
# So the file is read as YAML, by the same parser the rest of the installation uses,
# and the three things that decide those outcomes are read out of the parsed document:
# that something starts it, that what starts it includes the branch this installation
# delivers to, and that each pipeline the installation requires is genuinely included
# as a template rather than merely mentioned in a comment.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
    [Parameter(Mandatory)][string]$TargetBranch,
    [string[]]$RequiredIncludes = @(),
    [Parameter(Mandatory)][string]$FrameworkRoot
)

. (Join-Path $PSScriptRoot "Common.ps1")

$problems = [System.Collections.Generic.List[string]]::new()

function Get-NormalisedBranch {
    param([AllowNull()]$Value)
    $text = ([string]$Value).Trim()
    if ($text -eq "") { return "" }
    foreach ($prefix in @("refs/heads/", "refs/tags/")) {
        if ($text.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $text.Substring($prefix.Length)
        }
    }
    return $text
}

function Test-BranchPattern {
    # Azure DevOps branch filters are not regular expressions; '*' stands for any run of
    # characters and everything else is literal. Comparing them as text would refuse the
    # ordinary 'include: [*]', and treating them as regular expressions would accept
    # 'release.develop' as a filter on 'develop'.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Pattern,
          [Parameter(Mandatory)][string]$Branch)
    $normalised = Get-NormalisedBranch -Value $Pattern
    if ($normalised -eq "") { return $false }
    # Split on the literal character: PowerShell's -split with a negative count
    # counts substrings from the end and would hand back the pattern unsplit,
    # turning '*' into a filter that matches only a branch called '*'.
    $expression = "^" + ((@($normalised.Split([char]"*")) | ForEach-Object { [regex]::Escape($_) }) -join ".*") + "$"
    return [regex]::IsMatch($Branch, $expression, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Get-YamlSequence {
    # The YAML parser answers a single scalar where a sequence was allowed, and $null
    # where the key was absent; both have to read as a list here.
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @($Value) }
    if ($Value -is [System.Collections.IEnumerable]) { return @($Value) }
    return @($Value)
}

function Get-TemplateReferences {
    # 'template' can appear on a step, a job, a stage, a variable block or on extends,
    # at any depth. Walking the document is the only way to find every one of them, and
    # a walk finds only real keys - never a path that happens to appear inside a comment
    # or a display name.
    param([AllowNull()]$Node)
    $found = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Node) { return $found }
    if ($Node -is [string] -or $Node -is [ValueType]) { return $found }
    # Sequences are tested before objects, and it is not a matter of taste. Every
    # .NET object answers a PSObject, arrays included, and the properties an array
    # answers with are Length, Rank, SyncRoot and the rest - SyncRoot being the
    # array itself. Walking those first means a list of steps recurses into itself
    # until the stack goes, and means no key inside any list element is ever read:
    # a pipeline whose only template reference sits in a step would pass this check
    # by never being looked at.
    if ($Node -isnot [System.Collections.IDictionary] -and
        $Node -is [System.Collections.IEnumerable]) {
        foreach ($item in $Node) {
            foreach ($nested in @(Get-TemplateReferences -Node $item)) { $found.Add($nested) }
        }
        return $found
    }
    if ($Node -is [System.Collections.IDictionary] -or $null -ne $Node.PSObject) {
        foreach ($name in @(Get-QaFoundryPropertyNames -InputObject $Node)) {
            $child = if ($Node -is [System.Collections.IDictionary]) { $Node[$name] } else { $Node.$name }
            if ($name -eq "template" -and $child -is [string]) {
                $found.Add([string]$child)
                continue
            }
            foreach ($nested in @(Get-TemplateReferences -Node $child)) { $found.Add($nested) }
        }
        return $found
    }
    return $found
}

$document = $null
try {
    $document = ConvertFrom-QaFoundryYamlText -Text $Content -Root $FrameworkRoot
}
catch {
    $problems.Add(
        "The pipeline at '$Path' is not valid YAML, so Azure DevOps would refuse it and the suite " +
        "it was written to run would never start: $($_.Exception.Message)")
    return @($problems)
}

if ($null -eq $document -or $document -is [string] -or
    @(Get-QaFoundryPropertyNames -InputObject $document).Count -eq 0) {
    $problems.Add(
        "The pipeline at '$Path' does not read as a YAML mapping, so it declares no trigger and " +
        "no work. A file that looks like automation and starts nothing is worse than no file.")
    return @($problems)
}

$keys = @(Get-QaFoundryPropertyNames -InputObject $document)

# Something has to start it.
if ($keys -notcontains "trigger") {
    $problems.Add(
        "The pipeline at '$Path' declares no trigger, so nothing would ever run it. " +
        "Give it a branch trigger on '$TargetBranch'.")
}
else {
    $trigger = $document.trigger
    if ($trigger -is [string] -and [string]$trigger -eq "none") {
        $problems.Add(
            "The pipeline at '$Path' declares 'trigger: none', which switches continuous " +
            "integration off. The suite it runs would never start, and a suite that never " +
            "starts is indistinguishable from a suite that passes.")
    }
    elseif ($null -eq $trigger) {
        $problems.Add(
            "The pipeline at '$Path' declares an empty trigger, so nothing would ever run it. " +
            "Give it a branch trigger on '$TargetBranch'.")
    }
    else {
        # A trigger names its branches either directly as a sequence or through a
        # branches block. A branches block with no include list means every branch,
        # which does include the one this installation delivers to.
        $includes = @()
        $excludes = @()
        $namesBranches = $true
        if ($trigger -is [System.Collections.IEnumerable] -and $trigger -isnot [string]) {
            $includes = @(Get-YamlSequence -Value $trigger)
        }
        else {
            $triggerKeys = @(Get-QaFoundryPropertyNames -InputObject $trigger)
            if ($triggerKeys -contains "branches") {
                $branchKeys = @(Get-QaFoundryPropertyNames -InputObject $trigger.branches)
                if ($branchKeys -contains "include") {
                    $includes = @(Get-YamlSequence -Value $trigger.branches.include)
                }
                else { $namesBranches = $false }
                if ($branchKeys -contains "exclude") {
                    $excludes = @(Get-YamlSequence -Value $trigger.branches.exclude)
                }
            }
            else { $namesBranches = $false }
        }

        if ($namesBranches) {
            $included = @($includes | Where-Object { Test-BranchPattern -Pattern $_ -Branch $TargetBranch })
            $excluded = @($excludes | Where-Object { Test-BranchPattern -Pattern $_ -Branch $TargetBranch })
            if ($included.Count -eq 0) {
                $problems.Add(
                    "The pipeline at '$Path' triggers on " +
                    "$(if (@($includes).Count -eq 0) { 'no branch at all' } else { "'" + ((@($includes) -join "', '")) + "'" }) " +
                    "but not on '$TargetBranch', the branch this installation delivers to. A " +
                    "trigger on any other branch never fires, and the suite it runs would look " +
                    "like a suite that passes.")
            }
            elseif ($excluded.Count -gt 0) {
                $problems.Add(
                    "The pipeline at '$Path' excludes '$TargetBranch' from its trigger through " +
                    "'$((@($excluded) -join "', '"))', so the branch this installation delivers " +
                    "to is the one branch it will never run on.")
            }
        }
    }
}

# It has to do something when it starts.
$declaresWork = @("stages", "jobs", "steps", "extends") |
    Where-Object { $keys -contains $_ }
if (@($declaresWork).Count -eq 0) {
    $problems.Add(
        "The pipeline at '$Path' declares no stages, jobs, steps or extends, so a run of it " +
        "would succeed without executing anything. A green run that ran nothing is the most " +
        "expensive kind of silence.")
}

# Somebody has to hear it fail.
if (@($RequiredIncludes).Count -gt 0) {
    $referenced = @(Get-TemplateReferences -Node $document | ForEach-Object {
        # 'path@repository' names the same template in another repository; the
        # repository alias says where it lives, not which template it is.
        $value = ([string]$_).Split("@", 2)[0].Replace("\", "/").Trim()
        if ($value -ne "" -and -not $value.StartsWith("/")) { $value = "/$value" }
        $value
    } | Where-Object { $_ -ne "" })
    $referencedSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($referenced), [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($include in @($RequiredIncludes)) {
        $wanted = ([string]$include).Replace("\", "/").Trim()
        if ($wanted -eq "") { continue }
        if (-not $wanted.StartsWith("/")) { $wanted = "/$wanted" }
        if (-not $referencedSet.Contains($wanted)) {
            $problems.Add(
                "The pipeline at '$Path' does not include '$wanted' as a template. Without it a " +
                "failing suite reports to nobody: Azure DevOps has no failed-build trigger, so " +
                "a run that fails has to hand itself to triage.")
        }
    }
}

return @($problems)
