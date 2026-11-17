BeforeAll {
    . (Join-Path $PSScriptRoot '../../scripts/Common.ps1')
}

Describe 'Runner summaries count tests rather than suites' {
    It 'does not count a Vitest import failure as an executed failed test' {
        $adapter = Get-QaFoundryEcosystemAdapter npm
        $result = & $adapter.ReadTestRunSummary @'
 Test Files  1 failed | 1 passed (2)
      Tests  1 passed (1)
ReferenceError: test is not defined
'@ 1
        $result.parsed | Should -BeTrue
        $result.total | Should -Be 1
        $result.failed | Should -Be 0
    }

    It 'reads Vitest assertion failures, skips and totals independently of file counts' {
        $adapter = Get-QaFoundryEcosystemAdapter npm
        $result = & $adapter.ReadTestRunSummary " Test Files  1 failed | 3 passed (4)`n      Tests  1 failed | 8 passed | 2 skipped (11)`n" 1
        $result.total | Should -Be 11
        $result.failed | Should -Be 1
        $result.skipped | Should -Be 2
    }

    It 'reads Jest test counts rather than its suite summary' {
        $adapter = Get-QaFoundryEcosystemAdapter npm
        $result = & $adapter.ReadTestRunSummary "Test Suites: 1 failed, 2 passed, 3 total`nTests: 2 failed, 20 passed, 22 total`n" 1
        $result.total | Should -Be 22
        $result.failed | Should -Be 2
    }

    It 'uses the final Robot aggregate rather than the first child suite' {
        $adapter = Get-QaFoundryEcosystemAdapter pypi
        $result = & $adapter.ReadTestRunSummary "1 test, 0 passed, 1 failed`n1 test, 1 passed, 0 failed`n2 tests, 1 passed, 1 failed`n" 1
        $result.total | Should -Be 2
        $result.failed | Should -Be 1
    }

    It 'keeps skipped Robot tests separate from executed tests' {
        $adapter = Get-QaFoundryEcosystemAdapter pypi
        $result = & $adapter.ReadTestRunSummary "3 tests, 1 passed, 1 failed, 1 skipped`n" 1
        $result.total | Should -Be 3
        $result.failed | Should -Be 1
        $result.skipped | Should -Be 1
    }
}

Describe 'Go manifests carry the resolved graph before compilation' {
    BeforeAll {
        $script:GoAdapter = Get-QaFoundryEcosystemAdapter go
        $script:Manifest = "module example.invalid/automation`n`ngo 1.26`nrequire example.org/direct v1.0.0 // scope: dev`n"
        $script:Lock = "example.org/direct v1.0.0 h1:AAAA`nexample.org/indirect v2.0.0 h1:BBBB`nexample.org/metadata v1.0.0/go.mod h1:CCCC`n"
    }
    It 'adds only checksum-pinned artifacts and is idempotent' {
        $completed = & $script:GoAdapter.CompleteManifestFromLock $script:Manifest $script:Lock
        $completed | Should -Match 'example.org/indirect v2.0.0 // indirect'
        $completed | Should -Not -Match 'example.org/metadata'
        (& $script:GoAdapter.CompleteManifestFromLock $completed $script:Lock) | Should -BeExactly $completed
        $dependencies = @(& $script:GoAdapter.ReadManifestDependencies $completed)
        @($dependencies | Where-Object { -not $_.isIndirect }).Count | Should -Be 1
        @($dependencies | Where-Object isIndirect).Count | Should -Be 1
    }
    It 'rejects an indirect dependency that was never resolved' {
        { & $script:GoAdapter.CompleteManifestFromLock ($script:Manifest + "require example.org/surprise v9.0.0 // indirect`n") $script:Lock } |
            Should -Throw '*absent from the resolved graph*'
    }
    It 'rejects an ambiguous artifact version instead of picking the latest' {
        { & $script:GoAdapter.CompleteManifestFromLock $script:Manifest ($script:Lock + "example.org/indirect v3.0.0 h1:DDDD`n") } |
            Should -Throw '*multiple artifact versions*'
    }
    It 'keeps build and test from editing go.mod' {
        foreach ($factory in @($script:GoAdapter.GetBuildCommand, $script:GoAdapter.GetTestCommand)) {
            (& $factory $null '/work').arguments | Should -Contain '-mod=readonly'
        }
    }
}

Describe 'Lock formats without an owning project identity' {
    It 'validates named projects without inventing an identity field in <Ecosystem> locks' -ForEach @(
        @{ Ecosystem = 'nuget'; Name = 'Example.Test'; Version = '1.0.0'; Registry = 'https://api.nuget.org/v3/index.json' },
        @{ Ecosystem = 'maven'; Name = 'org.example:test'; Version = '1.0.0'; Registry = 'https://repo.maven.apache.org/maven2' },
        @{ Ecosystem = 'go'; Name = 'example.org/test'; Version = 'v1.0.0'; Registry = 'https://proxy.golang.org' },
        @{ Ecosystem = 'pypi'; Name = 'example-test'; Version = '1.0.0'; Registry = 'https://pypi.org/simple' }
    ) {
        $hash = [Convert]::ToBase64String([byte[]](1..32))
        $content = switch ($Ecosystem) {
            'nuget' { '{"version":1,"dependencies":{"net10.0":{"Example.Test":{"type":"Direct","requested":"[1.0.0, )","resolved":"1.0.0","contentHash":"' + $hash + '"}}}}' }
            'maven' { "org.example:test:1.0.0 sha256:$('a' * 64) https://repo.maven.apache.org/maven2/org/example/test/1.0.0/test-1.0.0.jar" }
            'go' { "example.org/test v1.0.0 h1:$hash`nexample.org/test v1.0.0/go.mod h1:$hash`n" }
            'pypi' { "--index-url https://pypi.org/simple`nexample-test==1.0.0 \`n    --hash=sha256:$('a' * 64)`n" }
        }
        $toolchain = [pscustomobject]@{
            ecosystem = $Ecosystem; runtime = [pscustomobject]@{}
            source = [pscustomobject]@{ registry = $Registry }
            packages = @([pscustomobject]@{ name = $Name; version = $Version; scope = 'runtime' })
        }
        $verdict = & (Join-Path $PSScriptRoot '../../scripts/actions/Test-EcosystemLock.ps1') `
            -Toolchain $toolchain -LockJson $content -ManifestName 'named-project' -ManifestVersion '1.0.0'
        $verdict.accepted | Should -BeTrue -Because ($verdict.findings -join '; ')
    }
}
