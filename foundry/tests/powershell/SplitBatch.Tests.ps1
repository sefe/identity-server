BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
    function Invoke-TestSplit {
        param([string]$Mode = 'complete')
        $config = Import-QaFoundryYaml -Path (Join-Path $script:Root 'tests/fixtures/sample-project-config.yaml') -Root $script:Root
        $profile = & (Join-Path $script:Root 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach ($name in @('provider','model','reasoning_effort','command','timeout_seconds','max_artifact_bytes')) {
            $config.ai | Add-Member -NotePropertyName $name -NotePropertyValue $profile.$name -Force
        }
        $config.ai.provider = 'command'
        $config.ai.command = "node $script:Root/tests/fixtures/split-batch-provider.mjs $Mode"
        $config.runtime.agent_schema_retries = 0
        & (Join-Path $script:Root 'scripts/Invoke-Agent.ps1') -AgentId 'bootstrap-change-generator-batch-01' `
            -StageId bootstrap-change-generation -RunId run-split -PromptPath (Join-Path $script:Root 'prompts/sdlc/bootstrap-plan-generator.md') `
            -ContextPaths @() -PriorityContextPaths @($script:Assignment) -OutputPath $script:Output `
            -SchemaPath (Join-Path $script:Root 'schemas/actions/change-set-batch.schema.json') -Config $config -AllowExistingArtifact
    }
}
Describe 'Truncated batches resume as complete single-file assignments' {
    BeforeEach {
        $directory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $directory | Out-Null
        $script:Output = Join-Path $directory 'change-set-batch-01.json'
        $script:Assignment = Join-Path $directory 'assignment-batch-01.json'
        @{ batchId = 'batch-01'; ordinal = 1; batchCount = 1; estimatedBytes = 1000
           allApprovedPaths = @('automation/lib/file-1.ts','automation/lib/file-2.ts')
           assignedPaths = @('automation/lib/file-1.ts','automation/lib/file-2.ts')
           assignedFiles = @(1..2 | ForEach-Object { @{ path = "automation/lib/file-$_.ts"; operation = 'create'; purpose = 'Module'; contentContract = 'Export a constant'; dependsOn = @() } }) } |
            ConvertTo-Json -Depth 50 | Set-Content $script:Assignment
    }
    It 'splits on the first truncation even when no whole-batch retry remains' {
        $result = Invoke-TestSplit
        $result.changes.Count | Should -Be 2
        $result.details.splitAfterTruncation | Should -BeTrue
        Test-Path "$script:Output.attempt-2.request.md" | Should -BeFalse
        $coverage = Get-Content "$script:Output.coverage.json" -Raw | ConvertFrom-Json
        $coverage.status | Should -Be covered
        $validation = & (Join-Path $script:Root 'scripts/Test-RunArtifacts.ps1') -RunRoot (Split-Path $script:Output -Parent)
        $validation.valid | Should -BeTrue
    }
    It 'resumes after interruption without regenerating the parent or completed part' {
        { Invoke-TestSplit -Mode interrupt } | Should -Throw '*Simulated process interruption*'
        $parentTime = (Get-Item "$script:Output.attempt-1.request.md").LastWriteTimeUtc
        $part = Get-ChildItem "$script:Output.parts" -Recurse -Filter 'change-set-batch-split.json' | Select-Object -First 1
        $partTime = $part.LastWriteTimeUtc
        $result = Invoke-TestSplit
        $result.changes.Count | Should -Be 2
        (Get-Item "$script:Output.attempt-1.request.md").LastWriteTimeUtc | Should -Be $parentTime
        (Get-Item $part.FullName).LastWriteTimeUtc | Should -Be $partTime
    }
    It 'propagates a blocked part without publishing partial changes' {
        $result = Invoke-TestSplit -Mode blocked
        $result.status | Should -Be blocked
        $result.changes.Count | Should -Be 0
        $result.details.requiredRepairPaths | Should -Contain 'automation/lib/dependency.ts'
    }
    It 'rejects an unassigned path instead of claiming complete coverage' {
        { Invoke-TestSplit -Mode wrong-path } | Should -Throw
        Test-Path $script:Output | Should -BeFalse
    }
    It 'does not reuse a completed part after the contract changes' {
        { Invoke-TestSplit -Mode interrupt } | Should -Throw '*Simulated process interruption*'
        $assignment = Get-Content $script:Assignment -Raw | ConvertFrom-Json -Depth 50
        $assignment.assignedFiles[0].contentContract = 'Export the revised constant'
        $assignment | ConvertTo-Json -Depth 50 | Set-Content $script:Assignment
        $result = Invoke-TestSplit
        $result.changes.Count | Should -Be 2
        @(Get-ChildItem "$script:Output.parts" -Directory).Count | Should -Be 2
        @(Get-ChildItem "$script:Output.parts" -Filter change-set-batch-split.json -Recurse).Count | Should -Be 3
    }
}

Describe 'Evidence based relay admission' {
    BeforeEach {
        $script:History = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $script:History | Out-Null
        function Get-Minimum {
            Get-QaFoundryMinimumAttemptSeconds -ConfiguredTimeout 1500 -Directory $script:History `
                -RunId run -StageId review -Provider command -Model model -RequestBytes 1000
        }
        function Add-History {
            param([int]$Index, [int]$Seconds = 90, [string]$Model = 'model', [string]$Status = 'answered')
            @{ runId='run'; stageId='review'; model=$Model; provider='command'; purpose='artifact'; status=$Status
               durationMs=$Seconds*1000; request=@{bytes=1000} } | ConvertTo-Json -Depth 20 |
                Set-Content (Join-Path $script:History "result-$Index.json.attempt-1.provider-metadata.json")
            @{status='covered';deferrals=@()} | ConvertTo-Json | Set-Content (Join-Path $script:History "result-$Index.json.coverage.json")
            @{status='completed'} | ConvertTo-Json | Set-Content (Join-Path $script:History "result-$Index.json")
        }
    }
    It 'preserves the old allowance for unknown work or a single sample' {
        Get-Minimum | Should -Be 750
        Add-History 1
        Get-Minimum | Should -Be 750
    }
    It 'admits historically short reviews with five minutes left for work' {
        Add-History 1
        Add-History 2
        Get-Minimum | Should -Be 300
    }
    It 'does not apply fast model measurements to another model' {
        Add-History 1 -Model other
        Add-History 2 -Model other
        Get-Minimum | Should -Be 750
    }
    It 'keeps the conservative allowance after a slow call or timeout' {
        Add-History 1 -Seconds 600
        Add-History 2
        Get-Minimum | Should -Be 750
        Add-History 1 -Seconds 90 -Status timed_out
        Get-Minimum | Should -Be 750
    }
}
