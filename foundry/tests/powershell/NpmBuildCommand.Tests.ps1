BeforeAll {
    . (Join-Path $PSScriptRoot '../../scripts/Common.ps1')
    $script:Adapter = Get-QaFoundryEcosystemAdapter -Ecosystem 'npm'
}

Describe 'Checking npm projects with a declared typecheck command' {
    It 'runs typecheck when the project has no build script' {
        Set-Content (Join-Path $TestDrive 'package.json') '{"scripts":{"typecheck":"tsc --noEmit"}}'
        (& $script:Adapter.GetBuildCommand @{} $TestDrive).arguments | Should -Be @('run', 'typecheck')
    }
    It 'keeps the build command when both scripts exist' {
        Set-Content (Join-Path $TestDrive 'package.json') '{"scripts":{"build":"vite build","typecheck":"tsc --noEmit"}}'
        (& $script:Adapter.GetBuildCommand @{} $TestDrive).arguments | Should -Be @('run', 'build', '--if-present')
    }
    It 'supports JavaScript projects that need no separate build' {
        Set-Content (Join-Path $TestDrive 'package.json') '{"scripts":{"test":"node --test"}}'
        (& $script:Adapter.GetBuildCommand @{} $TestDrive).arguments | Should -Be @('run', 'build', '--if-present')
    }
}
