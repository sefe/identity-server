BeforeAll {
    $script:Framework = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Framework 'scripts/Common.ps1')
    . (Join-Path $script:Framework 'scripts/RunInputs.ps1')
}

Describe 'Foundry reporting and documentation integration' {
    It 'does not report missing evidence as a successful zero-artifact validation' {
        { & (Join-Path $script:Framework 'scripts/Test-RunArtifacts.ps1') -RunRoot (Join-Path $TestDrive 'missing-run') } |
            Should -Throw '*does not exist*'
    }
    It 'keeps technical diagnostics while showing business progress and failures' {
        $beforeStyle = $env:FOUNDRY_LOG_STYLE
        $beforeDirectory = $env:FOUNDRY_DIAGNOSTICS_DIRECTORY
        try {
            $env:FOUNDRY_LOG_STYLE = 'summary'
            $env:FOUNDRY_DIAGNOSTICS_DIRECTORY = Join-Path $TestDrive 'logs'
            $messages = @(& {
                Write-QaFoundryLog -Message 'Request bytes: 1234' -Scope agent
                Write-QaFoundryLog -Level step -Message 'Discovery started.'
                Write-QaFoundryLog -Audience business -Message 'Two application components found.'
                Write-QaFoundryLog -Level error -Message 'Source access denied.'
            } 6>&1 | ForEach-Object { [string]$_ })
            ($messages -join ' ') | Should -Not -Match 'Request bytes'
            ($messages -join ' ') | Should -Match 'Discovery started.*Two application.*Source access denied'
            $records = @(Get-ChildItem $env:FOUNDRY_DIAGNOSTICS_DIRECTORY -Filter '*.jsonl' | Get-Content | ConvertFrom-Json)
            $records.Count | Should -Be 4
            $records.message | Should -Contain 'Request bytes: 1234'
        }
        finally {
            $env:FOUNDRY_LOG_STYLE = $beforeStyle
            $env:FOUNDRY_DIAGNOSTICS_DIRECTORY = $beforeDirectory
        }
    }

    It 'reads an explicitly supplied Office document using the extracted text budget' {
        $repo = Join-Path $TestDrive 'product'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        $document = Join-Path $TestDrive 'requirements.docx'
        $zip = [IO.Compression.ZipFile]::Open($document, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry = $zip.CreateEntry('word/document.xml', [IO.Compression.CompressionLevel]::NoCompression)
            $writer = [IO.StreamWriter]::new($entry.Open())
            try { $writer.Write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>' + ('Project requirement. ' * 100) + '</w:t></w:r></w:p></w:body></w:document>') }
            finally { $writer.Dispose() }
        } finally { $zip.Dispose() }
        $context = & (Join-Path $script:Framework 'scripts/Collect-RepositoryContext.ps1') -RepositoryRoot $repo `
            -OutputPath (Join-Path $TestDrive 'repository.json') -RunId report-fixture `
            -DocumentationPaths @($document) -MaxFileBytes 256 -MaxTotalBytes 16384
        $context.analysisInputs[0].included | Should -BeTrue
        $context.analysisInputs[0].content | Should -Match 'Project requirement'
    }

    It 'fingerprints binary document contents without UTF8 replacement collisions' {
        $repo = Join-Path $TestDrive 'fingerprint'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        & git init -q $repo
        & git -C $repo -c user.email=fixture@example.invalid -c user.name=Fixture commit -q --allow-empty -m fixture
        $inputFile = Join-Path $TestDrive 'diagram.png'
        [IO.File]::WriteAllBytes($inputFile, [byte[]]@(255, 0, 1))
        $parameters = @{RepositoryRoot=$repo;FrameworkRoot=$script:Framework;Config=[pscustomobject]@{};Workflow=[pscustomobject]@{};Policy=[pscustomobject]@{};InputPaths=@($inputFile)}
        $first = Get-QaFoundryRunInputs @parameters
        [IO.File]::WriteAllBytes($inputFile, [byte[]]@(254, 0, 1))
        $second = Get-QaFoundryRunInputs @parameters
        $first.hashes.analysisInputs | Should -Not -Be $second.hashes.analysisInputs
        $pdf = Join-Path $TestDrive 'ascii.pdf'
        $parameters.InputPaths = @($pdf)
        [IO.File]::WriteAllText($pdf, "%PDF-1.4`r`nOffset-sensitive bytes`r`n")
        $firstPdf = Get-QaFoundryRunInputs @parameters
        [IO.File]::WriteAllText($pdf, "%PDF-1.4`nOffset-sensitive bytes`n")
        $secondPdf = Get-QaFoundryRunInputs @parameters
        $firstPdf.hashes.analysisInputs | Should -Not -Be $secondPdf.hashes.analysisInputs
    }

    It 'keeps configurable run evidence out of product fingerprints' {
        $repo = Join-Path $TestDrive 'custom-artifacts'
        New-Item -ItemType Directory -Path (Join-Path $repo 'evidence') -Force | Out-Null
        & git init -q $repo
        & git -C $repo -c user.email=fixture@example.invalid -c user.name=Fixture commit -q --allow-empty -m fixture
        $parameters = @{RepositoryRoot=$repo;FrameworkRoot=$script:Framework;Config=[pscustomobject]@{runtime=[pscustomobject]@{artifacts_root='evidence'}};Workflow=[pscustomobject]@{};Policy=[pscustomobject]@{}}
        $first = Get-QaFoundryRunInputs @parameters
        Set-Content -LiteralPath (Join-Path $repo 'evidence/report.html') -Value 'A new run report.'
        $second = Get-QaFoundryRunInputs @parameters
        $first.hashes.source | Should -Be $second.hashes.source
        Set-Content -LiteralPath (Join-Path $repo 'app.cs') -Value 'Changed product source.'
        $third = Get-QaFoundryRunInputs @parameters
        $first.hashes.source | Should -Not -Be $third.hashes.source
    }
}
