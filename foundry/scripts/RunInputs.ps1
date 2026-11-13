function Get-QaFoundryInputHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes($Text.Replace("`r`n", "`n")))).ToLowerInvariant()
}

function Get-QaFoundryCompatibleContractHash {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Contracts)
    # Exact, additive migration: only the four inventory membership limits were
    # removed. All item contracts, required fields and other schemas are intact.
    # Reconstruct the OLD whole-contract fingerprint from CURRENT inputs, so a
    # simultaneous prompt/schema edit cannot be hidden by this compatibility.
    $path = 'schemas/implementation/implementation-result.schema.json'
    $before = '86f53eac45da919469d82419d76b00ebe91f69e9cdf44e15fd76dbfb6528333f'
    $after = '5f3f39d04eb3e04c4da09f613545ce4e1fd8d75585fd71c0f7ab5f05c1a8da44'
    if (-not $Contracts.Contains($path) -or $Contracts[$path] -cne $after) { return }
    $legacy = [ordered]@{}
    foreach ($key in $Contracts.Keys) {
        $legacy[$key] = if ($key -ceq $path) { $before } else { $Contracts[$key] }
    }
    return Get-QaFoundryInputHash -Text (ConvertTo-Json -InputObject $legacy -Depth 10 -Compress)
}

function Get-QaFoundryRunInputs {
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)][string]$FrameworkRoot,
        [Parameter(Mandatory)][object]$Config, [Parameter(Mandatory)][object]$Workflow,
        [Parameter(Mandatory)][object]$Policy, [string[]]$InputPaths = @())
    $configuration = $Config | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
    # These controls change how much work may run, not what its outputs mean.
    if ($configuration.ContainsKey('runtime')) {
        foreach ($key in @('relay', 'progress', 'max_stage_iterations', 'artifacts_root')) { $configuration.runtime.Remove($key) }
    }
    if ($configuration.ContainsKey('ai')) { $configuration.ai.Remove('run_budget') }
    $source = [ordered]@{}
    $configuredArtifactsRelative = ''
    if ($Config.PSObject.Properties['runtime'] -and $Config.runtime.PSObject.Properties['artifacts_root']) {
        $configuredArtifacts = [IO.Path]::GetFullPath([string]$Config.runtime.artifacts_root, $RepositoryRoot)
        $relativeArtifacts = [IO.Path]::GetRelativePath($RepositoryRoot, $configuredArtifacts).Replace('\', '/')
        if ($relativeArtifacts -ne '.' -and $relativeArtifacts -ne '..' -and -not $relativeArtifacts.StartsWith('../') -and
            -not [IO.Path]::IsPathRooted($relativeArtifacts)) {
            $configuredArtifactsRelative = $relativeArtifacts.TrimEnd('/') + '/'
        }
    }
    $tracked = @(& git -C $RepositoryRoot -c core.quotepath=false ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot fingerprint the target repository; git ls-files failed.' }
    $frameworkRelative = [IO.Path]::GetRelativePath($RepositoryRoot, $FrameworkRoot).Replace('\', '/').TrimEnd('/') + '/'
    foreach ($relative in @($tracked | Sort-Object -Unique -CaseSensitive)) {
        if ($configuredArtifactsRelative -and $relative.StartsWith($configuredArtifactsRelative,
            $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }))) { continue }
        if ($relative.StartsWith($frameworkRelative) -or $relative -eq 'foundry-report.html' -or $relative -match '^(\.qa-foundry-artifacts|\.sdlc-foundry)/') { continue }
        $path = Join-Path $RepositoryRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $source[$relative] = 'deleted'; continue }
        $bytes = [IO.File]::ReadAllBytes($path)
        try {
            $content = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
            $source[$relative] = Get-QaFoundryInputHash -Text $content
        } catch [Text.DecoderFallbackException] {
            $source[$relative] = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        }
    }
    $contracts = [ordered]@{}
    foreach ($directory in @('prompts', 'schemas')) {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $FrameworkRoot $directory) -File -Recurse | Sort-Object FullName) {
            $relative = [IO.Path]::GetRelativePath($FrameworkRoot, $file.FullName).Replace('\', '/')
            $contracts[$relative] = Get-QaFoundryInputHash -Text ([IO.File]::ReadAllText($file.FullName))
        }
    }
    $external = [ordered]@{}
    for ($index = 0; $index -lt $InputPaths.Count; $index++) {
        $inputPath = $InputPaths[$index]
        foreach ($file in Get-ChildItem -LiteralPath $inputPath -File -Recurse | Sort-Object FullName) {
            $bytes = [IO.File]::ReadAllBytes($file.FullName)
            if ($file.Extension.ToLowerInvariant() -in @('.pdf', '.docx', '.pptx', '.xlsx', '.png', '.jpg', '.jpeg', '.webp', '.tif', '.tiff')) {
                $fingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            }
            else {
                try {
                    $content = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
                    $fingerprint = Get-QaFoundryInputHash -Text $content
                } catch [Text.DecoderFallbackException] {
                    $fingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
                }
            }
            $external["$index/" + [IO.Path]::GetRelativePath($inputPath, $file.FullName).Replace('\', '/')] = $fingerprint
        }
    }
    $configText = ConvertTo-Json -InputObject $configuration -Depth 100 -Compress
    # Checkouts may have different absolute locations on different agents.
    foreach ($prefix in @($RepositoryRoot, $FrameworkRoot)) {
        $escaped = (ConvertTo-Json -InputObject $prefix -Compress).Trim('"')
        $configText = $configText.Replace($escaped, '<checkout>')
    }
    $hashes = [ordered]@{
        source = Get-QaFoundryInputHash -Text (ConvertTo-Json -InputObject $source -Depth 10 -Compress)
        contracts = Get-QaFoundryInputHash -Text (ConvertTo-Json -InputObject $contracts -Depth 10 -Compress)
        config = Get-QaFoundryInputHash -Text $configText
        workflow = Get-QaFoundryInputHash -Text (ConvertTo-Json -InputObject $Workflow -Depth 100 -Compress)
        policy = Get-QaFoundryInputHash -Text (ConvertTo-Json -InputObject $Policy -Depth 100 -Compress)
        analysisInputs = Get-QaFoundryInputHash -Text (ConvertTo-Json -InputObject $external -Depth 10 -Compress)
    }
    return [pscustomobject]@{
        version = 1
        sourceCommit = [string](& git -C $RepositoryRoot rev-parse HEAD)
        hashes = [pscustomobject]$hashes
        compatibleContractHashes = @(Get-QaFoundryCompatibleContractHash -Contracts $contracts)
    }
}

function Assert-QaFoundryRunInputs {
    param([Parameter(Mandatory)][object]$Recorded, [Parameter(Mandatory)][object]$Current)
    if ($Recorded.version -ne 1) { throw 'Unsupported run input manifest.' }
    $changed = @($Current.hashes.PSObject.Properties | Where-Object {
        $name = $_.Name
        $compatibleContracts = $name -eq 'contracts' -and
            $Current.PSObject.Properties['compatibleContractHashes'] -and
            $Recorded.hashes.PSObject.Properties['contracts'] -and
            [string]$Recorded.hashes.contracts -cin @($Current.compatibleContractHashes)
        -not $compatibleContracts -and (
            -not $Recorded.hashes.PSObject.Properties[$name] -or [string]$Recorded.hashes.$name -ne [string]$_.Value)
    } | ForEach-Object Name)
    if ($changed.Count) {
        throw "Saved run inputs changed: $($changed -join ', '). Restart from the first stage to recollect context; downstream artifacts cannot be reused."
    }
}
