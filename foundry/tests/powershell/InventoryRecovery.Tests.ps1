BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
    . (Join-Path $script:Root 'scripts/RunInputs.ps1')
    $script:Schema = Join-Path $script:Root 'schemas/implementation/implementation-result.schema.json'
    function Save-Inventory($Path, $Files) {
        @{agentId='framework-implementation';stageId='implementation';runId='run';status='completed';
          summary='Inventory fixture';evidence=@();assumptions=@();warnings=@();risks=@();unknowns=@();details=@{};
          plannedFiles=@($Files);commandsProposed=@()} | ConvertTo-Json -Depth 30 | Set-Content $Path
    }
    function New-File($Name) {
        @{path="automation/$Name.cs";operation='create';purpose='Test support';contentContract='Real assertions';dependsOn=@()}
    }
    function Test-Inventory($Path) {
        & (Join-Path $script:Root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $Path -SchemaPath $script:Schema
    }
}

Describe 'Recovery inventory grows independently of one response' {
    It 'merges eight revised contracts with 38 previous files into 41 and retains unchanged contracts' {
        $base=Join-Path $TestDrive base.json
        $delta=Join-Path $TestDrive delta.json
        Save-Inventory $base @(1..38 | ForEach-Object { New-File $_ })
        Save-Inventory $delta @(@(1..5)+@(39..41) | ForEach-Object { New-File $_ })
        $null=Test-Inventory $delta
        $result=& (Join-Path $script:Root 'scripts/Merge-IncrementalInventory.ps1') -ArtifactPath $delta -PreviousArtifactPath $base
        $result.carriedOver | Should -Be 33
        $null=Test-Inventory $delta
        $merged=Get-Content $delta -Raw | ConvertFrom-Json
        $merged.plannedFiles.Count | Should -Be 41
        ($merged.plannedFiles | Where-Object path -eq automation/38.cs).contentContract | Should -Be 'Real assertions'
        $split=& (Join-Path $script:Root 'scripts/New-ChangeSetBatches.ps1') -InventoryPaths $delta
        @($split.approvedFiles).Count | Should -Be 41
        # A resumed already-merged artifact follows the same validation path.
        $null=& (Join-Path $script:Root 'scripts/Merge-IncrementalInventory.ps1') -ArtifactPath $delta -PreviousArtifactPath $base
        $null=Test-Inventory $delta
    }

    It 'still rejects a malformed contract beyond the former limit' {
        $path=Join-Path $TestDrive invalid.json
        $files=@(1..41 | ForEach-Object { New-File $_ })
        $files[40].Remove('contentContract')
        Save-Inventory $path $files
        { Test-Inventory $path } | Should -Throw '*contentContract*'
    }
}

Describe 'Inventory schema compatibility is an exact additive transition' {
    It 'matches the four removed limits and accepts no other schema edits' {
        $after=[IO.File]::ReadAllText($script:Schema).Replace("`r`n","`n")
        $before=$after
        foreach($entry in @(@('plannedFiles',40),@('unchangedFiles',40),@('removedFiles',40),@('mergedRemovals',200))) {
            $pattern='("'+$entry[0]+'": \{\n          "type": "array",\n)'
            $before=[regex]::Replace($before,$pattern,('$1          "maxItems": '+$entry[1]+",`n"))
        }
        (Get-QaFoundryInputHash $before) | Should -Be '86f53eac45da919469d82419d76b00ebe91f69e9cdf44e15fd76dbfb6528333f'
        $oldContracts=[ordered]@{'prompts/a.md'='unchanged';'schemas/implementation/implementation-result.schema.json'=(Get-QaFoundryInputHash $before)}
        $recorded=[pscustomobject]@{version=1;hashes=[pscustomobject]@{source='source';contracts=(Get-QaFoundryInputHash ($oldContracts|ConvertTo-Json -Compress))}}
        $contracts=[ordered]@{'prompts/a.md'='unchanged';'schemas/implementation/implementation-result.schema.json'=(Get-QaFoundryInputHash $after)}
        $current=[pscustomobject]@{version=1;hashes=[pscustomobject]@{source='source';contracts='new'};compatibleContractHashes=@(Get-QaFoundryCompatibleContractHash $contracts)}
        { Assert-QaFoundryRunInputs $recorded $current } | Should -Not -Throw
        $current.hashes.source='changed'
        { Assert-QaFoundryRunInputs $recorded $current } | Should -Throw '*source*'
        $current.hashes.source='source'
        $contracts['prompts/a.md']='changed'
        $current.compatibleContractHashes=@(Get-QaFoundryCompatibleContractHash $contracts)
        { Assert-QaFoundryRunInputs $recorded $current } | Should -Throw '*contracts*'
        $contracts['schemas/implementation/implementation-result.schema.json']='different-schema'
        @(Get-QaFoundryCompatibleContractHash $contracts).Count | Should -Be 0
    }
}
