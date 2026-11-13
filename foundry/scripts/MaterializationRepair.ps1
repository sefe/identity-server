# Recover resolver instructions, never generated lock-file contents. The caller
# still validates these recipes against the current blueprint and toolchain.
function Get-QaFoundryCarriedMaterializations {
    param([object]$Plan, [string]$RunRoot, [string]$RunId)

    $recipes = [System.Collections.Generic.List[object]]::new()
    if ('materializations' -in @($Plan.PSObject.Properties.Name)) {
        foreach ($recipe in @($Plan.materializations)) { if ($null -ne $recipe) { $recipes.Add($recipe) } }
    }
    $sources = [System.Collections.Generic.List[object]]::new()
    $cursor = $Plan
    $visited = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($RunRoot -and 'details' -in @($cursor.PSObject.Properties.Name) -and
        $null -ne $cursor.details -and 'carriedForward' -in @($cursor.details.PSObject.Properties.Name) -and
        $null -ne $cursor.details.carriedForward) {
        $provenance = $cursor.details.carriedForward
        $hash = [string]$provenance.sha256
        $name = [string]$provenance.plan
        if ($hash -notmatch '^[a-fA-F0-9]{64}$' -or $name -notmatch '^[\w.-]+\.json$') {
            throw 'Carried materialization provenance has no valid plan name and SHA256.'
        }
        if (-not $visited.Add($hash)) { throw 'Carried materialization provenance contains a cycle.' }
        $matching = @(Get-ChildItem -LiteralPath $RunRoot -Recurse -File -Filter $name | Where-Object {
            (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -eq $hash
        })
        if ($matching.Count -eq 0) { throw "The hash-bound carried plan '$name' is missing or changed." }
        $sourcePath = $matching[0].FullName
        $schemaRoot = Join-Path $PSScriptRoot '../schemas'
        $null = & (Join-Path $PSScriptRoot 'Validate-JsonArtifact.ps1') -ArtifactPath $sourcePath `
            -SchemaPath (Join-Path $schemaRoot 'actions/change-set-plan.schema.json') -SchemaRoot $schemaRoot
        $source = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json -Depth 100
        if ([string]$source.runId -cne $RunId -or $source.status -ne 'completed') {
            throw 'The carried materialization plan is not a completed plan from this run.'
        }
        $sourceRecipes = @(if ('materializations' -in @($source.PSObject.Properties.Name)) { $source.materializations })
        foreach ($recipe in $sourceRecipes) {
            if ($null -eq $recipe) { continue }
            $manifest = [string]$recipe.manifestPath
            if (@($recipes | Where-Object { [string]$_.manifestPath -ceq $manifest }).Count -gt 0) { continue }
            $before = @($source.changes | Where-Object { [string]$_.path -ceq $manifest })
            $after = @($Plan.changes | Where-Object { [string]$_.path -ceq $manifest })
            if ($before.Count -ne 1 -or $after.Count -ne 1 -or
                $after[0].operation -notin @('create', 'update') -or
                [string]$before[0].operation -cne [string]$after[0].operation -or
                [string]$before[0].content -cne [string]$after[0].content -or
                [string]$before[0].expectedSha256 -cne [string]$after[0].expectedSha256) { continue }
            $recipes.Add($recipe)
            $sources.Add([ordered]@{ plan = [IO.Path]::GetRelativePath($RunRoot, $sourcePath).Replace('\', '/')
                sha256 = $hash; manifestPath = $manifest })
        }
        # A nonempty source already has its own resolver instructions. Only an
        # empty intermediate repair plan needs another hop through provenance.
        if ($sourceRecipes.Count -gt 0) { break }
        $cursor = $source
    }
    return [pscustomobject]@{ materializations = @($recipes.ToArray()); sources = @($sources.ToArray()) }
}
