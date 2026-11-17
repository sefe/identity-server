BeforeAll {
    $script:Framework = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Framework 'scripts/Common.ps1')
    function New-RevisionFixture {
        $directory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $directory | Out-Null
        $base = Join-Path $directory 'base.json'
        @{agentId='producer';stageId='architecture';runId='run-revision';status='completed';summary='Base';evidence=@();unknowns=@();warnings=@();assumptions=@();
            deferrals=@(@{kind='output_budget';item='Default selection';reason='Specify local-only default.'});
            details=@{requirements=@('REQ-1','REQ-2');configuration=@{selection='all';'key/with~escapes'='before'};projects=@(@{name='API'},@{name='UI'})}
        } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $base
        $patch = @{baseSha256=(Get-FileHash $base).Hash.ToLowerInvariant();summary='Revised';status='completed';
            edits=@(@{path='/details/configuration/selection';value='local'});deferrals=@();
            resolvedDeferrals=@(@{item='Default selection';resolution='Explicit local default.';paths=@('/details/configuration/selection')})}
        return @{BasePath=$base;Patch=$patch}
    }
    function Apply-Revision($Fixture) {
        return (& (Join-Path $script:Framework 'scripts/Apply-BlueprintRevision.ps1') -BasePath $Fixture.BasePath `
            -RevisionJson ($Fixture.Patch | ConvertTo-Json -Depth 40) -RunId run-revision -StageId architecture -AgentId producer | ConvertFrom-Json -Depth 50)
    }
    function Invoke-ReturnedArchitecture($Run, [int]$Iteration = 2, [switch]$Reuse) {
        return & (Join-Path $script:Framework 'scripts/Invoke-Stage.ps1') -Stage $Run.Stage -Config $Run.Config -Policy $Run.Policy `
            -RunRoot $Run.Run -RepositoryRoot $script:Framework -RunId run-loop -Iteration $Iteration -ReuseExistingArtifacts:$Reuse
    }
    function Invoke-RevisionLoop([string]$Producer, [string]$Critic, [switch]$Incremental) {
        $config = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'tests/fixtures/sample-project-config.yaml') -Root $script:Framework
        $profile = & (Join-Path $script:Framework 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach ($property in $profile.PSObject.Properties) { $config.ai | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force }
        $config.ai.provider='command'
        $config.ai.command="node $script:Framework/tests/fixtures/producer-critic-loop-provider.mjs"
        $policy = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'policies/default-policy.yaml') -Root $script:Framework
        $stage=[pscustomobject]@{id='loop';type='producer_critic_loop';producer=[pscustomobject]@{
            agent=$Producer;prompt='prompts/architecture/automation-architect.md';schema='schemas/common/agent-result.schema.json';output='blueprint.json';incremental_revisions=[bool]$Incremental
        };critics=@([pscustomobject]@{agent=$Critic;prompt='prompts/architecture/architecture-critic.md';schema='schemas/common/agent-result.schema.json';output='review.json'});
            approval=@{max_iterations=2;on_exhaustion='proceed'}}
        $workflow=[pscustomobject]@{name='revision-loop';version=1;stages=@($stage)}
        $run=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $state=& (Join-Path $script:Framework 'scripts/Invoke-Workflow.ps1') -Workflow $workflow -Config $config -Policy $policy -RunRoot $run -RepositoryRoot $script:Framework -RunId run-loop
        return @{State=$state;Run=$run;Stage=$stage;Config=$config;Policy=$policy}
    }
}

Describe 'Incremental architecture revisions' {
    It 'changes only named paths and records explicit completion of old omissions' {
        $fixture=New-RevisionFixture
        $hash=(Get-FileHash $fixture.BasePath).Hash
        $fixture.Patch.edits += @{path='/details/projects/1/name';value='Browser'}
        $fixture.Patch.edits += @{path='/details/configuration/key~1with~0escapes';value='after'}
        $result=Apply-Revision $fixture
        $result.details.configuration.selection | Should -Be local
        $result.details.configuration.'key/with~escapes' | Should -Be after
        $result.details.projects[1].name | Should -Be Browser
        $result.details.requirements | Should -Be @('REQ-1','REQ-2')
        @($result.deferrals).Count | Should -Be 0
        (Get-FileHash $fixture.BasePath).Hash | Should -Be $hash
    }
    It 'rejects unsafe or ambiguous revisions: <Case>' -ForEach @(
        @{Case='base hash'},@{Case='identity'},@{Case='missing parent'},@{Case='overlap'},@{Case='removed omission'}
    ) {
        $fixture=New-RevisionFixture
        switch ($Case) {
            'base hash' {$fixture.Patch.baseSha256='a'*64}
            'identity' {$fixture.Patch.edits=@(@{path='/runId';value='another'})}
            'missing parent' {$fixture.Patch.edits=@(@{path='/details/absent/child';value='x'})}
            'overlap' {$fixture.Patch.edits+=@{path='/details/configuration';value=@{}}}
            'removed omission' {$fixture.Patch.resolvedDeferrals=@()}
        }
        {Apply-Revision $fixture} | Should -Throw
    }
    It 'converges through a patch and reuses it after relay interruption' {
        $run=Invoke-RevisionLoop -Producer loop-producer -Critic loop-critic-converges -Incremental
        $run.State.status | Should -Be completed
        $path=Join-Path $run.Run 'loop/critic-iteration-2/blueprint.json'
        $artifact=Get-Content $path -Raw | ConvertFrom-Json
        $artifact.details.contract | Should -Be revised
        $artifact.details.preserved | Should -Be 'Previously approved requirements stay intact.'
        Test-Path "$path.revision.json" | Should -BeTrue
        $request="$path.attempt-1.request.md"
        $stamp=(Get-Item $request).LastWriteTimeUtc
        $replay=& (Join-Path $script:Framework 'scripts/Invoke-Stage.ps1') -Stage $run.Stage -Config $run.Config -Policy $run.Policy `
            -RunRoot $run.Run -RepositoryRoot $script:Framework -RunId run-loop -ReuseExistingArtifacts
        $replay.Status | Should -Be approved
        (Get-Item $request).LastWriteTimeUtc | Should -Be $stamp
    }
    It 'does not restart an exhausted producer loop or review an incomplete producer' {
        $run=Invoke-RevisionLoop -Producer loop-producer-budget -Critic loop-critic-approves
        $run.State.status | Should -Be blocked
        $run.State.stages[0].iteration | Should -Be 1
        $run.State.blockedReason | Should -Be coverage_iteration_limit
        @(Get-ChildItem $run.Run -Recurse -Filter 'blueprint.json.attempt-1.request.md').Count | Should -Be 2
        @(Get-ChildItem $run.Run -Recurse -Filter 'review.json.attempt-1.request.md').Count | Should -Be 0
    }
    It 'revises the published final blueprint after downstream rejection and replays the same patch after a relay pause' {
        $run=Invoke-RevisionLoop -Producer loop-producer -Critic loop-critic-converges -Incremental
        $base=Join-Path $run.Run 'loop/critic-iteration-2/blueprint.json'
        $baseHash=(Get-FileHash $base).Hash.ToLowerInvariant()
        # A resolver result must remain in the context of the returning producer.
        $downstream=Join-Path $run.Run 'toolchain-smoke.json'
        @{status='blocked';checks=@(@{detail='Missing explicit Newtonsoft.Json package reference.'})} | ConvertTo-Json -Depth 10 | Set-Content $downstream
        $statePath=Join-Path $run.Run 'workflow-state.json'
        $state=Get-Content $statePath -Raw | ConvertFrom-Json -Depth 100
        $state.stages+= [pscustomobject]@{id='resolver';attempts=@(@{status='revision_required';artifacts=@(@{
            name='toolchain-smoke.json';relativePath='toolchain-smoke.json';sha256=(Get-FileHash $downstream).Hash
        })})}
        $state | ConvertTo-Json -Depth 100 | Set-Content $statePath
        $result=Invoke-ReturnedArchitecture $run
        $result.Status | Should -Be approved
        $output=Join-Path $run.Run 'loop/iteration-2/blueprint.json'
        $patch=Get-Content "$output.revision.json" -Raw | ConvertFrom-Json
        $patch.baseSha256 | Should -Be $baseHash
        $artifact=Get-Content $output -Raw | ConvertFrom-Json
        $artifact.details.preserved | Should -Be 'Previously approved requirements stay intact.'
        $ledger=Get-Content (Join-Path $run.Run 'loop/iteration-2/revision-ledger.json') -Raw | ConvertFrom-Json
        $ledger.revision | Should -Be 3
        $ledger.settledCritics[0].criticId | Should -Be loop-critic-converges
        $ledger.honouredCommitments[0].change | Should -Be 'Address the fixture finding.'
        $request="$output.attempt-1.request.md"
        Get-Content $request -Raw | Should -Match 'Missing explicit Newtonsoft.Json'
        @(Get-ChildItem (Join-Path $run.Run 'loop/iteration-2') -Recurse -Filter '*.raw.txt').Count | Should -Be 2
        $stamp=(Get-Item $request).LastWriteTimeUtc
        (Invoke-ReturnedArchitecture $run -Reuse).Status | Should -Be approved
        (Get-Item $request).LastWriteTimeUtc | Should -Be $stamp
        (Get-FileHash $base).Hash.ToLowerInvariant() | Should -Be $baseHash
    }
    It 'returns to the last published blueprint across a failed attempt and ignores unrecorded newer drafts' {
        $run=Invoke-RevisionLoop -Producer loop-producer -Critic loop-critic-approves -Incremental
        $statePath=Join-Path $run.Run 'workflow-state.json'
        $state=Get-Content $statePath -Raw | ConvertFrom-Json -Depth 100
        $state.stages[0].attempts+= [pscustomobject]@{iteration=2;status='failed';error='truncated response'}
        $state | ConvertTo-Json -Depth 100 | Set-Content $statePath
        $rejected=Join-Path $run.Run 'loop/iteration-2'
        New-Item -ItemType Directory $rejected | Out-Null
        'not an approved blueprint' | Set-Content (Join-Path $rejected 'blueprint.json')
        (Invoke-ReturnedArchitecture $run -Iteration 3).Status | Should -Be approved
        $patch=Get-Content (Join-Path $run.Run 'loop/iteration-3/blueprint.json.revision.json') -Raw | ConvertFrom-Json
        $patch.baseSha256 | Should -Be (Get-FileHash (Join-Path $run.Run 'loop/blueprint.json')).Hash.ToLowerInvariant()
    }
    It 'refuses a changed published base or review before requesting a revision: <File>' -ForEach @(
        @{File='blueprint.json'}, @{File='review.json'}
    ) {
        $run=Invoke-RevisionLoop -Producer loop-producer -Critic loop-critic-approves -Incremental
        Add-Content (Join-Path $run.Run "loop/$File") ' '
        {Invoke-ReturnedArchitecture $run} | Should -Throw '*integrity check*'
        Test-Path (Join-Path $run.Run 'loop/iteration-2/blueprint.json.attempt-1.request.md') | Should -BeFalse
    }
    It 'retries a valid patch whose merged artifact violates the original schema' {
        $run=Invoke-RevisionLoop -Producer loop-producer-retry -Critic loop-critic-converges -Incremental
        $run.State.status | Should -Be completed
        $path=Join-Path $run.Run 'loop/critic-iteration-2/blueprint.json'
        $artifact=Get-Content $path -Raw | ConvertFrom-Json
        $artifact.details.contract | Should -Be revised
        @($artifact.evidence).Count | Should -Be 1
        Test-Path "$path.attempt-2.request.md" | Should -BeTrue
        Get-Content "$path.attempt-2.request.md" -Raw | Should -Match '/evidence'
    }
    It 'does not call critics or repeat a producer with an external blocker' {
        $run=Invoke-RevisionLoop -Producer loop-producer-external -Critic loop-critic-approves -Incremental
        $run.State.status | Should -Be blocked
        @(Get-ChildItem $run.Run -Recurse -Filter 'blueprint.json.attempt-1.request.md').Count | Should -Be 1
        @(Get-ChildItem $run.Run -Recurse -Filter 'review.json.attempt-1.request.md').Count | Should -Be 0
    }
    It 'keeps an external prerequisite blocked even when the critic also asks for revision' {
        $run=Invoke-RevisionLoop -Producer loop-producer -Critic loop-critic-external
        $run.State.status | Should -Be blocked
        $run.State.stages[0].iteration | Should -Be 1
        Test-Path (Join-Path $run.Run 'loop/iteration-2') | Should -BeFalse
    }
}
