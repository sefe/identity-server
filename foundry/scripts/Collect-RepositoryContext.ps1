[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$RunId,
    [string[]]$DocumentationPaths = @(),
    [string[]]$RequirementsPaths = @(),
    [string[]]$ArchitecturePaths = @(),
    [string[]]$AdditionalContextPaths = @(),
    [string[]]$AllowedReadPaths = @("."),
    [int64]$MaxFileBytes = 262144,
    [int64]$MaxTotalBytes = 4194304,
    [string[]]$ExcludedDirectories = @()
)

. (Join-Path $PSScriptRoot "Common.ps1")
$defaultExcludedSegments = @(
    ".git", "node_modules", ".qa-foundry-artifacts", ".sdlc-foundry",
    "bin", "obj", ".vs", ".idea", "packages", "TestResults",
    "dist", "build", "out", "target", "coverage",
    ".gradle", ".terraform", "vendor",
    ".venv", "venv", "__pycache__", ".pytest_cache", ".mypy_cache",
    ".next", ".nuxt", ".svelte-kit", ".angular", ".turbo", ".parcel-cache"
)
$excludedSegments = @($defaultExcludedSegments)
foreach ($segment in $ExcludedDirectories) {
    if (-not [string]::IsNullOrWhiteSpace($segment) -and $segment -notin $excludedSegments) {
        $excludedSegments += $segment.Trim()
    }
}
$textExtensions = @(
    ".md", ".txt", ".json", ".yaml", ".yml", ".toml", ".xml", ".html",
    ".htm", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx", ".py", ".cs",
    ".java", ".kt", ".go", ".rs", ".rb", ".php", ".ps1", ".psm1", ".sh",
    ".sln", ".csproj", ".fsproj", ".vbproj", ".props", ".targets", ".feature",
    ".graphql", ".gql", ".puml", ".mmd", ".svg", ".drawio"
)
$documentExtensions = @(".docx", ".pptx", ".xlsx", ".pdf")
$imageExtensions = @(".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff")

function Test-ExcludedPath {
    param([Parameter(Mandatory)][string]$Path)
    $relative = [System.IO.Path]::GetRelativePath($RepositoryRoot, $Path)
    if ($relative -eq 'foundry-report.html') { return $true }
    $segments = @($relative -split "[\\/]")
    return @($excludedSegments | Where-Object { $_ -in $segments }).Count -gt 0
}

function Test-SecretLikeName {
    param([Parameter(Mandatory)][string]$Path)
    $name = [System.IO.Path]::GetFileName($Path)
    return $name -match "(?i)^\.env($|\.)|(^|[._-])(secret|credential|token|private[-_]?key)([._-]|$)"
}

function Get-OpenXmlText {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Extension)
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $patterns = switch ($Extension) {
            ".docx" { @("word/document.xml", "word/header", "word/footer", "word/footnotes.xml") }
            ".pptx" { @("ppt/slides/slide", "ppt/notesSlides/notesSlide") }
            ".xlsx" { @("xl/sharedStrings.xml", "xl/worksheets/sheet") }
        }
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in @($archive.Entries | Sort-Object FullName)) {
            if (@($patterns | Where-Object { $entry.FullName.StartsWith($_) }).Count -eq 0 -or
                -not $entry.FullName.EndsWith(".xml")) { continue }
            $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8, $true)
            try { $xmlText = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $plain = [Net.WebUtility]::HtmlDecode([regex]::Replace($xmlText, "<[^>]+>", " "))
            $plain = [regex]::Replace($plain, "\s+", " ").Trim()
            if ($plain) { $parts.Add($plain) }
        }
        return @($parts) -join [Environment]::NewLine
    }
    finally { $archive.Dispose() }
}

function Invoke-BoundedTextExtractor {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30
    )
    $command = Resolve-QaFoundryExecutable -Name $Executable
    if ($null -eq $command) {
        return [pscustomobject]@{ available = $false; content = "" }
    }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $command
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        $process.WaitForExit()
        return [pscustomobject]@{ available = $true; content = ""; failed = $true }
    }
    $content = $stdoutTask.GetAwaiter().GetResult()
    $null = $stderrTask.GetAwaiter().GetResult()
    return [pscustomobject]@{
        available = $true
        content = $content
        failed = $process.ExitCode -ne 0
    }
}

function Get-DocumentText {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Extension)
    if ($Extension -in @(".docx", ".pptx", ".xlsx")) {
        return [pscustomobject]@{
            available = $true
            failed = $false
            content = Get-OpenXmlText -Path $Path -Extension $Extension
        }
    }
    if ($Extension -eq ".pdf") {
        return Invoke-BoundedTextExtractor -Executable "pdftotext" -Arguments @("-layout", $Path, "-")
    }
    if ($Extension -in $imageExtensions) {
        return Invoke-BoundedTextExtractor -Executable "tesseract" -Arguments @($Path, "stdout")
    }
    return [pscustomobject]@{ available = $false; failed = $false; content = "" }
}

function Expand-InputPath {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Configured analysis input does not exist: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        return @(Get-ChildItem -LiteralPath $item.FullName -File -Recurse |
            Where-Object { -not (Test-ExcludedPath -Path $_.FullName) } |
            Sort-Object FullName)
    }
    return @($item)
}

$repositoryFileSet = [System.Collections.Generic.Dictionary[string, object]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($allowedReadPath in @($AllowedReadPaths)) {
    $readRoot = Resolve-QaFoundryPath -Root $RepositoryRoot -Path ([string]$allowedReadPath)
    if (-not (Test-PathWithinRoot -Candidate $readRoot -Root $RepositoryRoot)) {
        throw "allowed_read_paths cannot escape the target repository: $allowedReadPath"
    }
    if (-not (Test-Path $readRoot)) {
        throw "Configured allowed read path does not exist: $readRoot"
    }
    # An allowed read path may name a dot-prefixed file or folder, which the
    # provider treats as hidden on Linux and withholds unless it is forced.
    $readItem = Get-Item -LiteralPath $readRoot -Force
    $readFiles = if ($readItem.PSIsContainer) {
        @(Get-ChildItem -LiteralPath $readRoot -File -Recurse)
    }
    else {
        @($readItem)
    }
    foreach ($readFile in $readFiles) {
        if (-not (Test-ExcludedPath -Path $readFile.FullName)) {
            $repositoryFileSet[$readFile.FullName] = $readFile
        }
    }
}
$repositoryFiles = @($repositoryFileSet.Values | Sort-Object FullName)
$files = @($repositoryFiles | ForEach-Object {
    $relative = [System.IO.Path]::GetRelativePath($RepositoryRoot, $_.FullName)
    [ordered]@{
        path = $relative.Replace("\", "/")
        extension = $_.Extension.ToLowerInvariant()
        sizeBytes = $_.Length
    }
})

function Get-ComponentInterleavedOrder {
    # The content budget is spent in the order files are offered, so that order
    # decides which parts of a repository an agent gets to read. Offered
    # alphabetically, a repository whose backend projects sort before its user
    # interface spends the whole budget before reaching the interface, and the
    # agent asked to test that interface is handed nothing but paths and sizes.
    # Taking one file from each top-level component in turn costs nothing and
    # leaves every component represented.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Files,
        [Parameter(Mandatory)][string]$Root
    )
    $byComponent = [ordered]@{}
    foreach ($file in @($Files)) {
        $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace("\", "/")
        $component = if ($relative.Contains("/")) { $relative.Split("/")[0] } else { "" }
        if (-not $byComponent.Contains($component)) {
            $byComponent[$component] = [System.Collections.Generic.List[object]]::new()
        }
        $byComponent[$component].Add($file)
    }
    $componentNames = @($byComponent.Keys | Sort-Object)
    $longest = 0
    foreach ($name in $componentNames) {
        if ($byComponent[$name].Count -gt $longest) { $longest = $byComponent[$name].Count }
    }
    $ordered = [System.Collections.Generic.List[object]]::new()
    for ($round = 0; $round -lt $longest; $round++) {
        foreach ($name in $componentNames) {
            $bucket = $byComponent[$name]
            if ($round -lt $bucket.Count) { $ordered.Add($bucket[$round]) }
        }
    }
    return @($ordered)
}

$offeredRepositoryFiles = Get-ComponentInterleavedOrder `
    -Files $repositoryFiles -Root $RepositoryRoot

$extensionGroups = $files |
    Group-Object extension |
    Sort-Object Count -Descending |
    ForEach-Object {
        [ordered]@{ extension = $_.Name; count = $_.Count }
    }

$candidateGroups = @(
    [pscustomobject]@{ category = "requirements"; paths = @($RequirementsPaths) },
    [pscustomobject]@{ category = "architecture"; paths = @($ArchitecturePaths) },
    [pscustomobject]@{ category = "documentation"; paths = @($DocumentationPaths) },
    [pscustomobject]@{ category = "additional"; paths = @($AdditionalContextPaths) },
    [pscustomobject]@{
        category = "repository"
        paths = @($offeredRepositoryFiles | Select-Object -ExpandProperty FullName)
    }
)
$seen = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
$analysisInputs = @()
$totalIncludedBytes = [int64]0
foreach ($group in $candidateGroups) {
    foreach ($configuredPath in @($group.paths)) {
        if ([string]::IsNullOrWhiteSpace([string]$configuredPath)) {
            continue
        }
        foreach ($file in @(Expand-InputPath -Path ([string]$configuredPath))) {
            $fullPath = [System.IO.Path]::GetFullPath($file.FullName)
            if (-not $seen.Add($fullPath)) {
                continue
            }
            if (Test-SecretLikeName -Path $fullPath) {
                if ($group.category -ne "repository") {
                    throw "Secret-like file cannot be used as analysis context: $fullPath"
                }
                continue
            }
            $relative = if (Test-PathWithinRoot -Candidate $fullPath -Root $RepositoryRoot) {
                [System.IO.Path]::GetRelativePath($RepositoryRoot, $fullPath).Replace("\", "/")
            }
            else {
                $fullPath
            }
            $extension = $file.Extension.ToLowerInvariant()
            $included = $false
            $skipReason = ""
            $content = ""
            $redactions = @()
            $isPlainText = $extension -in $textExtensions -or
                $file.Name -in @("Dockerfile", "Makefile", "Jenkinsfile")
            $isExplicitExtractable = $group.category -ne "repository" -and
                ($extension -in $documentExtensions -or $extension -in $imageExtensions)
            if (-not $isPlainText -and -not $isExplicitExtractable) {
                $skipReason = "unsupported_text_format"
            }
            elseif ($file.Length -gt $(if ($isExplicitExtractable) { 16777216 } else { $MaxFileBytes })) {
                $skipReason = "file_size_limit"
            }
            elseif (-not $isExplicitExtractable -and ($totalIncludedBytes + $file.Length) -gt $MaxTotalBytes) {
                $skipReason = "total_context_limit"
            }
            else {
                try {
                    if ($isPlainText) {
                        $raw = Get-Content -LiteralPath $fullPath -Raw -ErrorAction Stop
                        $content = if ($null -eq $raw) { "" } else { [string]$raw }
                    }
                    else {
                        $extracted = Get-DocumentText -Path $fullPath -Extension $extension
                        if (-not $extracted.available) {
                            $skipReason = "extractor_unavailable"
                        }
                        elseif ($extracted.failed) {
                            $skipReason = "extractor_error"
                        }
                        else { $content = [string]$extracted.content }
                    }
                    if (-not $skipReason) {
                        # Excluding files whose names look like secrets was
                        # never the whole job: an ordinary appsettings.json
                        # carries a connection string with a password in it, and
                        # this content is about to be sent to a model provider.
                        # The secret scan that fails a build runs long after
                        # that, on the same rules, which is why the rules are
                        # shared rather than repeated.
                        $protected = Protect-QaFoundrySecretText -Text $content
                        $redactions = @($protected.redactions)
                        $content = [string]$protected.text
                        $contentBytes = [Text.Encoding]::UTF8.GetByteCount($content)
                        if (($totalIncludedBytes + $contentBytes) -gt $MaxTotalBytes) {
                            $skipReason = "total_context_limit"
                            $content = ""
                        }
                        else {
                            $included = $true
                            $totalIncludedBytes += $contentBytes
                        }
                    }
                }
                catch {
                    $skipReason = "read_error"
                }
            }
            $fileHash = Get-FileSha256Safe -Path $fullPath
            if (-not $fileHash) {
                continue
            }
            $analysisInputs += [ordered]@{
                category = [string]$group.category
                path = $relative
                sizeBytes = $file.Length
                sha256 = $fileHash
                included = $included
                skipReason = $skipReason
                redactions = @($redactions)
                content = $content
            }
        }
    }
}

$context = [ordered]@{
    runId = $RunId
    collectedAt = Get-UtcTimestamp
    repositoryRoot = $RepositoryRoot
    fileCount = @($files).Count
    files = @($files)
    extensionSummary = @($extensionGroups)
    analysisInputs = @($analysisInputs)
    contextBytes = $totalIncludedBytes
    limits = [ordered]@{
        maxFileBytes = $MaxFileBytes
        maxTotalBytes = $MaxTotalBytes
    }
    notes = @(
        "The files list is an index of what this run may read, not its content: every entry is a real file on disk under repositoryRoot, and an agent with a file-view tool should open the ones that answer its question.",
        "Repository content is offered one file per top-level component in turn, so that the context budget leaves every component represented rather than being spent on whichever sorts first.",
        "Explicit requirements and architecture inputs take priority over repository files.",
        "Secret-like files, dependency directories, artifacts, and Git metadata are excluded.",
        "Secret values inside ordinary files are replaced before this context is assembled; each input records which rules fired.",
        "Explicit DOCX, PPTX, and XLSX inputs are extracted locally; PDF and image inputs use pdftotext or tesseract when installed.",
        "Every included input is content-hashed for evidence traceability."
    )
}

$parent = Split-Path $OutputPath -Parent
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$context | ConvertTo-Json -Depth 30 | Set-Content -Path $OutputPath -Encoding utf8
return $context
