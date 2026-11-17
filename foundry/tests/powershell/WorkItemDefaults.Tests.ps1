BeforeAll {
    . (Join-Path $PSScriptRoot '../../scripts/WorkItemDefaults.ps1')
}
Describe 'Work-item defaults are scoped to the process and authenticated user' {
    BeforeEach {
        $script:Path = Join-Path $TestDrive defaults.json
        @{ targets = @(@{
            organization_url = 'https://dev.azure.com/example'; project = 'Product'; work_item_type = 'Bug'
            fields = @{ 'Custom.RequestedBy' = '@authenticated-user'; 'Custom.Environment' = 'Development' }
        }) } | ConvertTo-Json -Depth 20 | Set-Content $script:Path
        $script:Settings = [pscustomobject]@{organization_url='https://dev.azure.com/example/';project='Product'}
    }
    It 'uses the current PAT identity and retains explicit process defaults' {
        $fields = Get-QaFoundryWorkItemDefaults -Settings $script:Settings -Type Bug -UserEmail owner@example.invalid -Path $script:Path
        $fields['Custom.RequestedBy'] | Should -Be owner@example.invalid
        $fields['Custom.Environment'] | Should -Be Development
    }
    It 'does not apply one projects defaults to other organizations, projects or item types' {
        (Get-QaFoundryWorkItemDefaults -Settings $script:Settings -Type Task -UserEmail owner@example.invalid -Path $script:Path).Count | Should -Be 0
        $script:Settings.project = 'Other'
        (Get-QaFoundryWorkItemDefaults -Settings $script:Settings -Type Bug -UserEmail owner@example.invalid -Path $script:Path).Count | Should -Be 0
        $script:Settings.project = 'Product'; $script:Settings.organization_url = 'https://dev.azure.com/other'
        (Get-QaFoundryWorkItemDefaults -Settings $script:Settings -Type Bug -UserEmail owner@example.invalid -Path $script:Path).Count | Should -Be 0
    }
    It 'rejects an unresolved required identity' {
        { Get-QaFoundryWorkItemDefaults -Settings $script:Settings -Type Bug -UserEmail '' -Path $script:Path } | Should -Throw '*nonempty scalar*'
    }
}
