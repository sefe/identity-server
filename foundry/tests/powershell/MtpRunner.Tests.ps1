BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
    $script:Adapter = Get-QaFoundryEcosystemAdapter -Ecosystem 'nuget'
}

Describe 'Running the test platform the project built' {
    BeforeEach {
        $script:Project = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $script:Project | Out-Null
    }
    It 'uses the embedded MTP runner without a product global.json change' {
        $intermediate = Join-Path $script:Project 'obj/Release/net10.0'
        New-Item -ItemType Directory $intermediate -Force | Out-Null
        Set-Content (Join-Path $intermediate 'MicrosoftTestingPlatformEntryPoint.cs') '// emitted by MTP'
        $command = & $script:Adapter.GetTestCommand @{} $script:Project
        $command.arguments | Should -Be @('run', '--no-build', '--no-restore', '--configuration', 'Release')
        Test-Path (Join-Path $script:Project 'global.json') | Should -BeFalse
    }
    It 'rebuilds the negative probe with the same MTP runner' {
        $intermediate = Join-Path $script:Project 'obj/Release/net10.0'
        New-Item -ItemType Directory $intermediate -Force | Out-Null
        Set-Content (Join-Path $intermediate 'MicrosoftTestingPlatformEntryPoint.cs') '// emitted by MTP'
        $command = & $script:Adapter.GetNegativeProbeTestCommand @{} $script:Project
        $command.arguments | Should -Be @('run', '--no-restore', '--configuration', 'Release')
    }
    It 'preserves VSTest for projects without an MTP entry point' {
        $command = & $script:Adapter.GetTestCommand @{} $script:Project
        $command.arguments | Should -Be @('test', '--no-build', '--configuration', 'Release')
    }
    It 'runs a custom MTP entry point and includes rebuilt negative probes' {
        $intermediate = Join-Path $script:Project 'obj/Release/net10.0'
        $output = Join-Path $script:Project 'bin/Release/net10.0'
        New-Item -ItemType Directory $intermediate,$output -Force | Out-Null
        Set-Content (Join-Path $intermediate 'SelfRegisteredExtensions.cs') 'Microsoft.Testing.Platform.MSBuild.TestingPlatformBuilderHook.AddExtensions(builder, args);'
        Set-Content (Join-Path $output 'Tests.runtimeconfig.json') '{}'
        (& $script:Adapter.GetTestCommand @{} $script:Project).arguments | Should -Be @('run','--no-build','--no-restore','--configuration','Release')
        (& $script:Adapter.GetNegativeProbeTestCommand @{} $script:Project).arguments | Should -Be @('run','--no-restore','--configuration','Release')
    }
    It 'does not mistake a platform-referencing library for a runnable application' {
        $intermediate = Join-Path $script:Project 'obj/Release/net10.0'
        New-Item -ItemType Directory $intermediate -Force | Out-Null
        Set-Content (Join-Path $intermediate 'SelfRegisteredExtensions.cs') 'Microsoft.Testing.Platform.MSBuild.TestingPlatformBuilderHook.AddExtensions(builder, args);'
        (& $script:Adapter.GetTestCommand @{} $script:Project).arguments[0] | Should -Be 'test'
    }
    It 'does not choose a runner using a different build configuration' {
        $intermediate = Join-Path $script:Project 'obj/Debug/net10.0'
        New-Item -ItemType Directory $intermediate -Force | Out-Null
        Set-Content (Join-Path $intermediate 'MicrosoftTestingPlatformEntryPoint.cs') '// emitted by MTP'
        (& $script:Adapter.GetTestCommand @{} $script:Project).arguments[0] | Should -Be 'test'
    }
    It 'reads colored MTP failures without treating the run as unreadable' {
        $escape = [char]27
        $output = "${escape}[31mTest run summary: Failed!${escape}[m`r`n${escape}[m  total: 229`r`n${escape}[31m  failed: 56`r`n${escape}[m  succeeded: 173`r`n  skipped: 0`r`n"
        $verdict = Get-QaFoundryTestRunVerdict -Ecosystem 'nuget' -Output $output -ExitCode 2
        $verdict.verdict | Should -Be 'failed'
        $verdict.total | Should -Be 229
        $verdict.failed | Should -Be 56
    }
    It 'reads colored MTP success and the negative probe with the same parser' {
        $escape = [char]27
        $output = "${escape}[32mTest run summary: Passed!${escape}[m`n${escape}[m  total: 4`n${escape}[32m  succeeded: 4`n  skipped: 0`n"
        (Get-QaFoundryTestRunVerdict -Ecosystem 'nuget' -Output $output -ExitCode 0).verdict | Should -Be 'proved'
        $probe = & $script:Adapter.ReadTestRunSummary "${escape}[m  total: 5`n${escape}[31m  failed: 1`n${escape}[m  succeeded: 4`n" 2
        $probe.parsed | Should -BeTrue
        $probe.total | Should -Be 5
        $probe.failed | Should -Be 1
    }
}
