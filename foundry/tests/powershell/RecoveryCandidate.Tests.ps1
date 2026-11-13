BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
    . (Join-Path $script:Root 'scripts/RecoveryCandidate.ps1')
}
Describe 'Operator source remains subject to approved scope and real verification' {
    BeforeEach {
        $script:Candidate = [pscustomobject]@{path='candidate.json';sha256='source-hash';document=@{
            changes=@(@{path='automation/api/Program.cs';operation='create';content='real source';expectedSha256='';reason='Local runner';sourceRefs=@('candidate.json')});verification=@{scope='local only'}
        }}
        $script:Assignment = [pscustomobject]@{batchId='batch-1';assignedFiles=@(@{path='automation/api/Program.cs';operation='create'})}
    }
    It 'copies exact source with operator provenance and no claim of CI verification' {
        $batch = New-QaFoundryRecoveryCandidateBatch -Candidate $script:Candidate -Assignment $script:Assignment -AgentId generator -StageId generation -RunId run
        $batch.changes[0].content | Should -BeExactly 'real source'
        $batch.details.authorship | Should -Be 'operator'
        $batch.outcome | Should -Be 'proposed'
        $batch.summary | Should -Match 'CI verification and independent review remain required'
    }
    It 'never fills a partially matching assignment or invents missing source' {
        $script:Assignment.assignedFiles += @{path='automation/api/Other.cs';operation='create'}
        New-QaFoundryRecoveryCandidateBatch -Candidate $script:Candidate -Assignment $script:Assignment -AgentId generator -StageId generation -RunId run | Should -BeNullOrEmpty
    }
    It 'refuses a different approved operation' {
        $script:Assignment.assignedFiles[0].operation='update'
        {New-QaFoundryRecoveryCandidateBatch -Candidate $script:Candidate -Assignment $script:Assignment -AgentId generator -StageId generation -RunId run} | Should -Throw '*conflicts*'
    }
}
Describe 'Entry point errors are detected before materialization' {
    It 'rejects an npm test project without a runnable default test script' {
        $change=@{path='automation/ui/package.json';operation='create';content='{"devDependencies":{"@playwright/test":"1.63.0"},"scripts":{"test:deployed":"playwright test"}}'}
        $findings=@(& (Join-Path $script:Root 'scripts/Test-PlannedManifest.ps1') -Changes @($change) -Materializations @() -RequireTestCommand)
        $findings -join ' ' | Should -Match 'no scripts.test'
    }
    It 'accepts an explicit local runner while leaving actual execution to verification' {
        $change=@{path='automation/ui/package.json';operation='create';content='{"devDependencies":{"@playwright/test":"1.63.0"},"scripts":{"test":"playwright test --config playwright.local.config.ts","test:deployed":"playwright test"}}'}
        @(& (Join-Path $script:Root 'scripts/Test-PlannedManifest.ps1') -Changes @($change) -Materializations @() -RequireTestCommand).Count | Should -Be 0
    }
}
