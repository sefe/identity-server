BeforeAll {
    $script:RationaleCheck = Join-Path $PSScriptRoot '../../scripts/Test-ProjectRationale.ps1'
}

Describe 'Project rationale follows the approved blueprint' {
    BeforeEach {
        $projects = @(
            [pscustomobject]@{ name = 'api'; path = 'automation/api' }
            [pscustomobject]@{ name = 'ui'; path = 'automation/ui' }
        )
        $files = @(
            [pscustomobject]@{ path = 'automation/api/technology-choices.md'; project = 'api'; operation = 'create' }
            [pscustomobject]@{ path = 'automation/ui/technology-choices.md'; project = 'ui'; operation = 'create' }
            [pscustomobject]@{ path = 'automation/Directory.Packages.props'; project = 'shared'; operation = 'create' }
            [pscustomobject]@{ path = '.github/workflows/api.yml'; project = 'ci'; operation = 'create' }
        )
    }

    It 'does not invent shared and ci projects from inventory labels' {
        $findings = @(& $script:RationaleCheck -PlannedFiles $files -DocumentName 'technology-choices.md' -AutomationProjects $projects)
        $findings.Count | Should -Be 0
    }

    It 'still requires documentation for a real project named shared' {
        $projects += [pscustomobject]@{ name = 'shared'; path = 'automation/shared' }
        $findings = @(& $script:RationaleCheck -PlannedFiles $files -DocumentName 'technology-choices.md' -AutomationProjects $projects)
        $findings.Count | Should -Be 1
        $findings[0] | Should -Match 'automation/shared/technology-choices.md'
    }

    It 'detects a project omitted entirely from the inventory' {
        $files = @($files | Where-Object project -ne 'ui')
        $findings = @(& $script:RationaleCheck -PlannedFiles $files -DocumentName 'technology-choices.md' -AutomationProjects $projects)
        $findings.Count | Should -Be 1
        $findings[0] | Should -Match 'automation/ui/technology-choices.md'
    }

    It 'does not accept a shared document or a nested document instead of the project root document' {
        $files[0].path = 'automation/technology-choices.md'
        $files[1].path = 'automation/ui/docs/technology-choices.md'
        $findings = @(& $script:RationaleCheck -PlannedFiles $files -DocumentName 'technology-choices.md' -AutomationProjects $projects)
        $findings.Count | Should -Be 2
    }

    It 'matches paths case-sensitively for Linux runners' {
        $files[0].path = 'automation/api/TECHNOLOGY-CHOICES.md'
        $findings = @(& $script:RationaleCheck -PlannedFiles $files -DocumentName 'technology-choices.md' -AutomationProjects $projects)
        $findings.Count | Should -Be 1
    }

    It 'does not count a document scheduled for deletion' {
        $files[0].operation = 'delete'
        $findings = @(& $script:RationaleCheck -PlannedFiles $files -DocumentName 'technology-choices.md' -AutomationProjects $projects)
        $findings.Count | Should -Be 1
    }

    It 'uses root paths even when the agent labels a real project file shared' {
        $files[0].project = 'shared'
        $projects[1].path = 'automation\ui\'
        $files[1].path = 'automation\ui\technology-choices.md'
        $findings = @(& $script:RationaleCheck -PlannedFiles $files -DocumentName 'technology-choices.md' -AutomationProjects $projects)
        $findings.Count | Should -Be 0
    }

    It 'retains validation for legacy callers without blueprint metadata' {
        $findings = @(& $script:RationaleCheck -PlannedFiles @($files[0], $files[1]) -DocumentName 'technology-choices.md')
        $findings.Count | Should -Be 0
        $files[1].path = 'automation/ui/test.cs'
        $findings = @(& $script:RationaleCheck -PlannedFiles @($files[0], $files[1]) -DocumentName 'technology-choices.md')
        $findings.Count | Should -Be 1
    }

    It 'passes selected blueprint projects through agent validation when resuming an artifact' {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        . (Join-Path $root 'scripts/Common.ps1')
        $config = Import-QaFoundryYaml -Path (Join-Path $root 'tests/fixtures/sample-project-config.yaml') -Root $root
        $profile = & (Join-Path $root 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach ($property in $profile.PSObject.Properties) {
            if ($property.Name -notin @('name', 'required_secret_env', 'secret_env')) {
                $config.ai | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
            }
        }
        $config.automation | Add-Member -NotePropertyName rationale_document -NotePropertyValue 'technology-choices.md' -Force
        $output = Join-Path $TestDrive 'agent/framework-implementation.json'
        $invoke = @{
            AgentId = 'framework-implementation'; StageId = 'implementation'; RunId = 'rationale-regression'
            PromptPath = Join-Path $root 'prompts/implementation/framework-implementation.md'
            SchemaPath = Join-Path $root 'schemas/implementation/implementation-result.schema.json'
            OutputPath = $output; Config = $config; ContextPaths = @()
        }
        $artifact = & (Join-Path $root 'scripts/Invoke-Agent.ps1') @invoke
        $artifact.plannedFiles += [pscustomobject]@{
            path = 'automation/shared/README.md'; project = 'shared'; operation = 'create'
            purpose = 'Document shared configuration.'; contentContract = 'Explain configuration shared by the projects.'
        }
        $artifact | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $output -Encoding utf8
        $blueprint = Join-Path $TestDrive 'automation-blueprint.json'
        @{ details = @{ automationProjects = @(@{ name = 'automation-api'; path = 'automation' }) } } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $blueprint -Encoding utf8
        $invoke.ContextPaths = @($blueprint)
        $resumed = & (Join-Path $root 'scripts/Invoke-Agent.ps1') @invoke -AllowExistingArtifact -EnforceProjectRationale
        @($resumed.plannedFiles | Where-Object project -eq 'shared').Count | Should -Be 1
    }
}
