BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
    . (Join-Path $script:Root 'scripts/QualityProductDefects.ps1')
    . (Join-Path $script:Root 'scripts/SecretScan.ps1')
}

Describe 'Delivery uses the built runner and confirmed product evidence' {
    BeforeEach {
        $script:Repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:Run = Join-Path $script:Repo 'evidence'
        New-Item -ItemType Directory "$script:Repo/automation/api" -Force | Out-Null
        New-Item -ItemType Directory $script:Run | Out-Null
        Set-Content "$script:Repo/requirements.md" 'An empty name is rejected with HTTP 400.'
        $script:Text = "failed RejectsEmptyName (14ms)`n  Assertion failed.`n  expected: 400`n  actual: 200`n at Tests in /work/automation/api/ProductTests.cs:line 17`nTest run summary: Failed!`n  total: 10`n  failed: 1`n  succeeded: 9`n  skipped: 0`n"
        $script:Changes = [pscustomobject]@{ runId = 'run'; changes = @([pscustomobject]@{
            path = 'automation/api/ProductTests.cs'; content = 'Assert.AreEqual(400, response.StatusCode);'; operation = 'create'
        }) }
        [IO.File]::WriteAllText("$script:Repo/automation/api/ProductTests.cs", $script:Changes.changes[0].content)
        $script:Cases = @(Get-QaFoundryFailedTestCases -Text $script:Text -ProjectPath automation/api)
        $finding = [pscustomobject]@{ sourceRef = $script:Cases[0].sourceRef; classification = 'product_defect'
            signature = 'Empty name accepted'; hypothesis = 'Response violates the documented contract.'
            evidence = @('test-path:automation/api/ProductTests.cs','requirement-path:requirements.md') }
        $script:Analysis = [pscustomobject]@{ agentId = 'analyst'; status = 'completed'; findings = @($finding) }
        $script:Reviews = @(1,2 | ForEach-Object { [pscustomobject]@{ agentId = "reviewer-$_"; status = 'completed'; findings = @($finding) } })
        $confirmed = @(Get-QaFoundryConfirmedProductDefects -Cases $script:Cases -Analysis $script:Analysis -Review $script:Reviews `
            -ChangeSet $script:Changes -RepositoryRoot $script:Repo -MinimumConfirmations 3)
        $script:BugPlan = New-QaFoundryProductBugPlan -Defects $confirmed -RunId run
        $script:Receipt = [pscustomobject]@{ runId = 'run'; status = 'completed'; dryRun = $false; actions = @([pscustomobject]@{
            sourceRef = 'product-defect:' + $script:Cases[0].sourceRef; status = 'duplicate'; externalId = '12345'
        }) }
        function Save-Artifact {
            param([string]$Name, [object]$Value, [switch]$Raw)
            $path = Join-Path $script:Run $Name
            $body = if ($Raw) { [string]$Value } else { $Value | ConvertTo-Json -Depth 100 }
            [IO.File]::WriteAllText($path, $body)
            return [pscustomobject]@{ name = $Name; relativePath = $Name; sha256 = (Get-FileHash $path).Hash }
        }
        function Save-Proof {
            $changeRecord = Save-Artifact 'change-set.json' $script:Changes
            $logRecord = Save-Artifact 'command-003.log' $script:Text -Raw
            $script:Verification = [pscustomobject]@{ runId = 'run'; outcome = 'verified'; projects = @([pscustomobject]@{
                projectPath = 'automation/api'; ecosystem = 'nuget'; outcome = 'verified'; testsDiscovered = 10; testsFailed = 1
                negativeProbe = [pscustomobject]@{ attempted = $true; failedAsExpected = $true }
                steps = @([pscustomobject]@{ name = 'test'; status = 'failed'; detail = "Full output: commands/command-003.log [sha256: $($logRecord.sha256.ToLowerInvariant())]" })
            }) }
            $records = @($logRecord, (Save-Artifact 'framework-verification.json' $script:Verification),
                (Save-Artifact 'product-defect-analysis.json' $script:Analysis),
                (Save-Artifact 'product-defect-review-1.json' $script:Reviews[0]),
                (Save-Artifact 'product-defect-review-2.json' $script:Reviews[1]),
                (Save-Artifact 'product-defect-plan.json' $script:BugPlan),
                (Save-Artifact 'product-defect-bugs.json' $script:Receipt))
            $script:State = [pscustomobject]@{ runId = 'run'; status = 'completed'; stages = @(
                [pscustomobject]@{ id = 'bootstrap-change-materialization'; attempts = @([pscustomobject]@{
                    status = 'completed'; completedAt = '2026-09-14T10:00:00Z'; artifacts = @($changeRecord)
                }) },
                [pscustomobject]@{ id = 'framework-verification'; attempts = @([pscustomobject]@{
                    status = 'completed'; startedAt = '2026-09-14T10:01:00Z'; artifacts = $records
                }) }
            ) }
            $script:State | ConvertTo-Json -Depth 100 | Set-Content "$script:Run/workflow-state.json"
        }
        function Read-Context {
            Get-QaFoundryQualityProductDefectContext -RunRoot $script:Run -ChangeSetPath "$script:Run/change-set.json" -RepositoryRoot $script:Repo
        }
        function Match-Bugs {
            param([object]$Context, [string]$Output = $script:Text)
            @(Get-QaFoundryQualityProductBugIds -Context $Context -ProjectPath automation/api -Ecosystem nuget -Output $Output -ExitCode 2)
        }
        Save-Proof
    }

    It 'selects MTP after build output appears, independent of the process working directory' {
        $manifest = "$script:Repo/automation/api/Test.csproj"
        Set-Content $manifest '<Project Sdk="Microsoft.NET.Sdk" />'
        $adapter = Get-QaFoundryEcosystemAdapter nuget
        $before = @(New-QaFoundryAutomationGateCommands -Adapter $adapter -ManifestPath $manifest -ProjectPath automation/api)
        $before[-1].arguments[0] | Should -Be test
        New-Item -ItemType Directory "$script:Repo/automation/api/obj/Release/net10.0" -Force | Out-Null
        Set-Content "$script:Repo/automation/api/obj/Release/net10.0/MicrosoftTestingPlatformEntryPoint.cs" '// generated entry point'
        $after = @(New-QaFoundryAutomationGateCommands -Adapter $adapter -ManifestPath $manifest -ProjectPath automation/api)
        $after[-1].arguments[0] | Should -Be run
        $after[-1].workingDirectory | Should -Be 'automation/api'
    }
    It 'recognizes the same failed assertion with changed duration and stack path' {
        $context = Read-Context
        $observed = $script:Text.Replace('(14ms)', '(51ms)').Replace('/work/', 'C:\build\')
        (Match-Bugs $context $observed) | Should -Be @('12345')
    }
    It 'does not accept <Case>' -ForEach @(
        @{ Case = 'another assertion in the same test'; Old = 'actual: 200'; New = 'actual: 500' },
        @{ Case = 'another test with the same failure count'; Old = 'RejectsEmptyName'; New = 'OtherTest' },
        @{ Case = 'missing tests'; Old = 'total: 10'; New = 'total: 9' },
        @{ Case = 'an additional failure'; Old = 'failed: 1'; New = 'failed: 2' },
        @{ Case = 'skipped tests'; Old = 'skipped: 0'; New = 'skipped: 1' }
    ) {
        @(Match-Bugs (Read-Context) ($script:Text.Replace($Old,$New))).Count | Should -Be 0
    }
    It 'does not confuse runner startup failure with a product defect' {
        @(Match-Bugs (Read-Context) 'Testing with VSTest target is no longer supported').Count | Should -Be 0
    }
    It 'rejects modified installed test code' {
        Add-Content "$script:Repo/automation/api/ProductTests.cs" '// changed'
        { Read-Context } | Should -Throw '*Installed source differs*'
    }
    It 'rejects a modified recorded artifact' {
        Add-Content "$script:Run/product-defect-analysis.json" ' '
        { Read-Context } | Should -Throw '*changed*'
    }
    It 'rejects a dry-run Bug receipt' {
        $script:Receipt.dryRun = $true; Save-Proof
        { Read-Context } | Should -Throw '*real completed write*'
    }
    It 'does not accept changed product requirements' {
        Set-Content "$script:Repo/requirements.md" 'Empty names are valid.'
        @( (Read-Context).projects ).Count | Should -Be 0
    }
    It 'does not accept fewer than three independent confirmations' {
        $script:Reviews[1].agentId = $script:Reviews[0].agentId; Save-Proof
        @( (Read-Context).projects ).Count | Should -Be 0
    }
    It 'does not accept an absent real Bug id' {
        $script:Receipt.actions[0].externalId = ''; Save-Proof
        @( (Read-Context).projects ).Count | Should -Be 0
    }
    It 'rejects verification predating the delivered materialization' {
        $script:State.stages[1].attempts[0].startedAt = '2026-09-14T09:00:00Z'
        $script:State | ConvertTo-Json -Depth 100 | Set-Content "$script:Run/workflow-state.json"
        { Read-Context } | Should -Throw '*must follow*'
    }
}

Describe 'Secret scanning distinguishes credentials from source and fixture data' {
    It 'does not block <Case>' -ForEach @(
        @{ Case = 'a package hash'; Path = 'packages.lock.json'; Line = '"contentHash": "FnASiAaTGSmB4SaSroIwnK4ph9noFIXZpPOMezDqWw5S/TNakzSnawPeM7u0Auq1/EqJXeqG4s6UjfrGBH33Ow=="' },
        @{ Case = 'an environment variable constant'; Path = 'Config.cs'; Line = 'private const string ReaderSecret = "APP_AUTH_READER_SECRET";' },
        @{ Case = 'an empty string expression'; Path = 'Config.cs'; Line = 'Password = string.Empty' },
        @{ Case = 'a property access'; Path = 'Config.cs'; Line = 'Password = options.Password' },
        @{ Case = 'a function call'; Path = 'test.ts'; Line = 'const password = symbolicSecret();' },
        @{ Case = 'secure input'; Path = 'README.md'; Line = '$password = Read-Host -AsSecureString' },
        @{ Case = 'an explicitly symbolic test password'; Path = 'tests/config.spec.ts'; Line = 'APP_PASSWORD: ''LocalSymbolicPassword123!'',' },
        @{ Case = 'redaction fixture values'; Path = 'tests/redaction.spec.ts'; Line = 'token: ''raw-token-value'', password: ''row-one-password''' }
    ) {
        $rules = @(Get-QaFoundrySecretRules | Where-Object { -not $_.PSObject.Properties['failsBuild'] -or $_.failsBuild })
        @(Get-QaFoundrySecretLineFindings -Line $Line -Path $Path -Rules $rules | Where-Object { -not $_.ignored }).Count | Should -Be 0
    }
    It 'still blocks <Case>' -ForEach @(
        @{ Case = 'a real-shaped AWS key'; Path = 'config.json'; Line = '"accessKey": "AKIA1234567890ABCDEF"' },
        @{ Case = 'a generic key in a hidden file'; Path = '.env'; Line = 'api_key = "0123456789abcdef"' },
        @{ Case = 'a generic key inside a test'; Path = 'tests/auth.spec.ts'; Line = 'token: "0123456789abcdef"' },
        @{ Case = 'a symbolic-looking value in production configuration'; Path = 'config.json'; Line = '"password": "LocalSymbolicPassword123!"' },
        @{ Case = 'a connection string'; Path = 'Config.cs'; Line = 'const string Connection = "Server=local;Password=RealPassword42!;";' }
    ) {
        $rules = @(Get-QaFoundrySecretRules | Where-Object { -not $_.PSObject.Properties['failsBuild'] -or $_.failsBuild })
        @(Get-QaFoundrySecretLineFindings -Line $Line -Path $Path -Rules $rules | Where-Object { -not $_.ignored }).Count | Should -BeGreaterThan 0
    }
}

Describe 'Installation secret scan covers the complete delivery' {
    BeforeEach {
        $script:ScanRepo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $script:ScanRepo | Out-Null
        & git -C $script:ScanRepo init -q
        Set-Content "$script:ScanRepo/old.env" 'api_key = "0123456789abcdef"'
        Set-Content "$script:ScanRepo/new.txt" 'safe content'
        $script:ScanConfig = [pscustomobject]@{ quality = [pscustomobject]@{
            auto_detect = $false; fail_on_required_failure = $true; commands = @()
            security = [pscustomobject]@{ secret_scan = $true; dependency_audit = $false; max_file_bytes = 1048576 }
        } }
        $script:ScanPlan = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
        @{ runId = 'delivery'; changes = @(@{ path = 'new.txt'; operation = 'create' }) } |
            ConvertTo-Json -Depth 10 | Set-Content $script:ScanPlan
        function Invoke-Scan {
            & (Join-Path $script:Root 'scripts/collectors/Collect-QualityEvidence.ps1') -RunId delivery `
                -Config $script:ScanConfig -Policy ([pscustomobject]@{}) -RepositoryRoot $script:ScanRepo `
                -OutputPath (Join-Path $TestDrive 'scan-result.json') -InstallationChangeSetPath $script:ScanPlan
        }
    }
    It 'does not attribute an unchanged repository secret to this delivery' {
        $result = Invoke-Scan
        $result.summary.secretFindingCount | Should -Be 0
        ($result.warnings -join ' ') | Should -Match 'covers 1 delivered file'
    }
    It 'blocks a credential in an untracked delivered file' {
        Set-Content "$script:ScanRepo/new.txt" 'api_key = "0123456789abcdef"'
        { Invoke-Scan } | Should -Throw '*Secret scan found 1*'
    }
    It 'refuses an installation scope from another run' {
        @{ runId = 'other'; changes = @() } | ConvertTo-Json | Set-Content $script:ScanPlan
        { Invoke-Scan } | Should -Throw '*different run*'
    }
    It 'refuses a delivery whose file is absent' {
        @{ runId = 'delivery'; changes = @(@{ path = 'missing.txt'; operation = 'create' }) } |
            ConvertTo-Json -Depth 10 | Set-Content $script:ScanPlan
        { Invoke-Scan } | Should -Throw '*Delivered file is missing*'
    }
}
