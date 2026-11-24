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
}
