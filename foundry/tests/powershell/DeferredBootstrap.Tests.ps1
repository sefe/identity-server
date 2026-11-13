BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
}

Describe 'Deferred bootstrap execution' {
    It 'collects evidence without running configured or automatically detected commands' {
        $config = Import-QaFoundryYaml -Path (Join-Path $script:Root 'config/project.yaml') -Root $script:Root
        $policy = Import-QaFoundryYaml -Path (Join-Path $script:Root 'policies/bootstrap-policy.yaml') -Root $script:Root
        $config.quality.auto_detect = $true
        $config.quality.security.secret_scan = $false
        $config.quality.commands = @([pscustomobject]@{
            id='must-not-run';category='test';executable='must-not-execute';arguments=@();working_directory='.';required=$true
        })
        $config.quality.automation_gates = @([pscustomobject]@{path='missing-suite';required=$true})
        $output = Join-Path $TestDrive 'quality-evidence.json'
        $result = & (Join-Path $script:Root 'scripts/collectors/Collect-QualityEvidence.ps1') `
            -RunId deferred -Config $config -Policy $policy -RepositoryRoot $TestDrive -OutputPath $output -DeferExecution
        $result.commands.Count | Should -Be 0
        $result.summary.commandCount | Should -Be 0
        ($result.warnings -join ' ') | Should -Match 'not executed'
        $config.quality.auto_detect | Should -BeTrue
        $config.quality.commands.Count | Should -Be 1
        $null = & (Join-Path $script:Root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $output `
            -SchemaPath (Join-Path $script:Root 'schemas/runtime/quality-evidence.schema.json') -SchemaRoot (Join-Path $script:Root 'schemas')
    }

    It 'does not run a toolchain probe when execution is deferred' {
        $lock = Join-Path $TestDrive 'toolchain.json'
        '{"toolchains":[{"id":"unavailable-runtime","ecosystem":"npm"}]}' | Set-Content $lock
        $work = Join-Path $TestDrive 'probe-work'
        $result = & (Join-Path $script:Root 'scripts/actions/Test-ToolchainReadiness.ps1') `
            -ToolchainLockPath $lock -OutputPath (Join-Path $TestDrive 'toolchain-smoke.json') `
            -WorkRoot $work -DeferExecution
        $result.status | Should -Be completed
        $result.checks[0].detail | Should -Match 'deferred'
        Test-Path $work | Should -BeFalse
    }
}
