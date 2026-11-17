[CmdletBinding()]
param([string]$Path,[string]$Content,[string]$TargetBranch,[string]$FrameworkRoot,[switch]$DeferredTests)
. (Join-Path $PSScriptRoot '../Common.ps1')
$problems=[Collections.Generic.List[string]]::new()
if ($Path -notmatch '^\.github/workflows/[^/]+\.ya?ml$') {$problems.Add("Workflow must be directly inside .github/workflows/: $Path")}
try {
    $yaml=ConvertFrom-QaFoundryYamlText -Text $Content -Root $FrameworkRoot
    $keys=@(Get-QaFoundryPropertyNames $yaml)
    if ($keys -contains 'trigger' -or $keys -contains 'pool' -or $keys -contains 'stages') {$problems.Add("Azure Pipelines syntax is not a GitHub Actions workflow: $Path")}
    if ($keys -notcontains 'on' -or $keys -notcontains 'jobs') {$problems.Add("Workflow needs on and jobs: $Path")}
    else {
        $events=@(Get-QaFoundryPropertyNames $yaml.on)
        if ($yaml.on -is [string]) {$events=@([string]$yaml.on)}
        if ($yaml.on -is [array]) {$events=@($yaml.on)}
        if ($events -contains 'pull_request_target') {$problems.Add("Generated test workflows must not use pull_request_target: $Path")}
        if ($DeferredTests) {
            if ($events.Count -ne 1 -or $events[0] -ne 'workflow_dispatch') {
                $problems.Add("Deferred test workflow must use workflow_dispatch only until credentials and execution are configured: $Path")
            }
        }
        elseif ($events -notcontains 'push' -or $events -notcontains 'pull_request') {$problems.Add("Automation workflow must run on push and pull_request: $Path")}
        if ($events -contains 'push' -and $null -ne $yaml.on.push) {
            $pushKeys=@(Get-QaFoundryPropertyNames $yaml.on.push)
            if ($pushKeys -contains 'branches') {
                $patterns=@($yaml.on.push.branches)
                if (-not @($patterns | Where-Object {$TargetBranch -like [string]$_}).Count) {$problems.Add("Workflow push trigger excludes $TargetBranch : $Path")}
            }
            if ($pushKeys -contains 'branches-ignore' -and @($yaml.on.push.'branches-ignore' | Where-Object {$TargetBranch -like [string]$_}).Count) {
                $problems.Add("Workflow push trigger ignores $TargetBranch : $Path")
            }
        }
        $jobs=@(Get-QaFoundryPropertyNames $yaml.jobs)
        if (-not $jobs.Count) {$problems.Add("Workflow contains no jobs: $Path")}
        $hasExecution=$false;$hasReport=$false
        foreach ($jobName in $jobs) {
            $job=$yaml.jobs.$jobName
            if (@(Get-QaFoundryPropertyNames $job) -contains 'steps') {
                foreach ($step in @($job.steps)) {
                    $stepKeys=@(Get-QaFoundryPropertyNames $step)
                    if ($stepKeys -contains 'run') {$hasExecution=$true}
                    if ($stepKeys -contains 'uses' -and [string]$step.uses -match '^actions/upload-artifact@') {
                        if ($stepKeys -contains 'if' -and [string]$step.if -match 'always\(\)|!cancelled\(\)') {$hasReport=$true}
                    }
                }
            }
        }
        if (-not $hasExecution) {$problems.Add("Workflow contains no executable test steps: $Path")}
        if (-not $hasReport) {$problems.Add("Workflow must upload test evidence even on failure: $Path")}
    }
}
catch {$problems.Add("Invalid GitHub workflow $Path : $($_.Exception.Message)")}
return @($problems)
