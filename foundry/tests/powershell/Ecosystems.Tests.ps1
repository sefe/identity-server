Describe "Starting the tools a toolchain names" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        . (Join-Path $script:Root "scripts/Common.ps1")
    }

    # Every child process in this runtime is started with the shell out of the
    # way, so a name has to resolve to a file the operating system will execute
    # on its own. On Windows 'npm' on PATH is a shell script beside npm.cmd, and
    # PowerShell's own resolution answers with npm.ps1; both fail to start with
    # "%1 is not a valid Win32 application", which the verification stage read as
    # the chosen framework being broken and sent back for repair three times.
    It "resolves a tool to something the operating system can start" {
        $resolved = Resolve-QaFoundryExecutablePath -Name "git"
        $resolved | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $resolved -PathType Leaf | Should -BeTrue
        if ($IsWindows) {
            [IO.Path]::GetExtension($resolved).ToLowerInvariant() |
                Should -BeIn @(".com", ".exe", ".bat", ".cmd")
        }
        # Resolved or not, the answer has to be startable, which is the only
        # claim this function makes.
        $probe = Start-Process -FilePath $resolved -ArgumentList "--version" `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput ([IO.Path]::GetTempFileName()) `
            -RedirectStandardError ([IO.Path]::GetTempFileName())
        $probe.ExitCode | Should -Be 0
    }

    It "never answers with a script the process API cannot launch" {
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because "only Windows ships PowerShell and shell-script shims on PATH"
            return
        }
        foreach ($name in @("npm", "npx")) {
            $resolved = Resolve-QaFoundryExecutablePath -Name $name
            if ([string]::IsNullOrWhiteSpace($resolved)) { continue }
            [IO.Path]::GetExtension($resolved).ToLowerInvariant() |
                Should -BeIn @(".com", ".exe", ".bat", ".cmd") -Because "$name must be startable without a shell"
        }
    }

    It "says a tool is absent rather than naming something that will not run" {
        Resolve-QaFoundryExecutablePath -Name "qa-foundry-tool-that-is-not-installed" |
            Should -BeNullOrEmpty
        Resolve-QaFoundryExecutablePath -Name "" | Should -BeNullOrEmpty
        Test-QaFoundryExecutableAvailable -Name "qa-foundry-tool-that-is-not-installed" |
            Should -BeFalse
        # The older spelling answers $null, and its callers branch on that.
        Resolve-QaFoundryExecutable -Name "qa-foundry-tool-that-is-not-installed" |
            Should -BeNullOrEmpty
    }

    It "answers from the location a caller named, never from PATH" {
        $directory = Join-Path ([IO.Path]::GetTempPath()) ("foundry-exe-" + [guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        try {
            Resolve-QaFoundryExecutablePath -Name (Join-Path $directory "git") |
                Should -BeNullOrEmpty -Because "a named location that holds nothing resolves to nothing"
        }
        finally {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Package ecosystem adapters" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        . (Join-Path $script:Root "scripts/Common.ps1")
    }

    It "loads an adapter for every ecosystem this installation ships" {
        foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
            $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $id
            $adapter.id | Should -Be $id
            foreach ($member in @(
                    "manifestPattern", "lockFilePattern", "requiredRuntimeKeys",
                    "GetManifestFileName", "ReadRuntime", "NewManifestContent",
                    "ReadManifestDependencies", "NormalizePackageName",
                    "GetPublishedVersions", "SelectVersion", "GetRuntimeRequirements",
                    "GetInstallCommand", "GetBuildCommand", "GetTestCommand",
                    "ReadTestRunSummary", "NewNegativeProbe", "lockEnforcement",
                    "manifestExpressesDependencyScope", "ReadWorkspaceMembers",
                    "TestVersionRange")) {
                @(Get-QaFoundryPropertyNames -InputObject $adapter) |
                    Should -Contain $member -Because "$id must answer for $member"
            }
        }
    }

    # A run that decides which packages are only for building and testing, and
    # then reads that decision back out of a manifest whose format cannot state
    # it, is comparing its own answer with a default. It refuses a project that
    # is entirely correct, and no author can fix it, because the file has
    # nowhere to write what is being asked for.
    It "says for every ecosystem whether its manifest can state a development scope" {
        foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
            $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $id
            $adapter.manifestExpressesDependencyScope | Should -BeOfType [bool] `
                -Because "$id must answer yes or no, not leave it to be guessed"
        }
        # Named outright rather than derived, so that adding an ecosystem forces
        # somebody to look at its manifest format and answer for it.
        (Get-QaFoundryEcosystemAdapter -Ecosystem "nuget").manifestExpressesDependencyScope |
            Should -BeFalse -Because "a PackageReference has no development section"
        (Get-QaFoundryEcosystemAdapter -Ecosystem "go").manifestExpressesDependencyScope |
            Should -BeFalse -Because "go.mod says what is needed, not what it is needed for"
        (Get-QaFoundryEcosystemAdapter -Ecosystem "pypi").manifestExpressesDependencyScope |
            Should -BeFalse -Because "a requirements file is a flat list"
        (Get-QaFoundryEcosystemAdapter -Ecosystem "npm").manifestExpressesDependencyScope |
            Should -BeTrue -Because "devDependencies is a section of its own"
        (Get-QaFoundryEcosystemAdapter -Ecosystem "composer").manifestExpressesDependencyScope |
            Should -BeTrue -Because "require-dev is a section of its own"
        (Get-QaFoundryEcosystemAdapter -Ecosystem "maven").manifestExpressesDependencyScope |
            Should -BeTrue -Because "a dependency carries its own scope element"
        (Get-QaFoundryEcosystemAdapter -Ecosystem "rubygems").manifestExpressesDependencyScope |
            Should -BeTrue -Because "a Gemfile group says what a gem is for"
    }

    # Build 973307 blocked the materialisation of a manifest that was correct.
    # An author who declares '"dependencies": {}' is saying that nothing runs in
    # production - which is true of a test project, and which npm itself writes
    # - and reading that empty section threw "the property 'Name' cannot be
    # found on this object". Member enumeration over an empty property
    # collection is an error under the strict mode this runtime sets, so the
    # emptier the manifest the surer the crash.
    It "reads a manifest whose dependency sections are present but empty" {
        $manifest = @'
{
  "name": "commoditypricingservice-automation-ui",
  "version": "1.0.0",
  "private": true,
  "dependencies": {},
  "devDependencies": {
    "@playwright/test": "1.63.0",
    "typescript": "5.9.3"
  }
}
'@
        $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem "npm"
        $declared = @(& $adapter.ReadManifestDependencies $manifest)

        @($declared).Count | Should -Be 2
        @($declared | Where-Object { $_.scope -eq "runtime" }).Count | Should -Be 0
        @($declared | ForEach-Object { [string]$_.name }) | Should -Contain "typescript"
        (& $adapter.ReadManifestIdentity $manifest).name |
            Should -Be "commoditypricingservice-automation-ui"
    }

    It "reads a manifest that declares nothing at all, in every ecosystem" {
        # Written by each adapter from a toolchain that pins no package, so the
        # emptiest manifest an ecosystem can produce is the one it is asked to
        # read back. An adapter that cannot read its own output would fail the
        # same way npm did, at materialisation, an hour into a run.
        $runtime = [pscustomobject]@{
            nodeMajor = 22; npmVersion = "10.9.4"; lockfileVersion = 3
            sdkMajor = 10; targetFramework = "net10.0"
            phpVersion = "8.3"; composerVersion = "2.7"
            goVersion = "1.23"; modulePath = "example.invalid/automation"
            javaVersion = "21"; mavenVersion = "3.9"
            pythonVersion = "3.12"
            rubyVersion = "3.3"; bundlerVersion = "2.5"
        }
        foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
            $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $id
            $toolchain = [pscustomobject]@{
                ecosystem = $id
                packages = @()
                runtime = $runtime
                source = [pscustomobject]@{ registry = "https://example.invalid/feed" }
            }
            $content = [string](& $adapter.NewManifestContent $toolchain "empty-project" "1.0.0")
            $content | Should -Not -BeNullOrEmpty -Because "$id must write something"
            { & $adapter.ReadManifestDependencies $content } |
                Should -Not -Throw -Because "$id must read the manifest it just wrote"
            @(& $adapter.ReadManifestDependencies $content).Count |
                Should -Be 0 -Because "$id was given no package to declare"
        }
    }

    # Build 972137 died here. The architect designed a .NET half and an npm
    # half, wrote NuGet's interval notation for both, and '[1.49.0,2.0.0)' -
    # which '^1.49.0' would have expressed - matched nothing npm publishes. The
    # feed was fine, the package was fine, and a two-hour run ended on a
    # spelling mistake nobody read the range for.
    It "tells a range written in another ecosystem's notation from one nothing satisfies" {
        $verdict = Test-QaFoundryVersionRange -Ecosystem "npm" -Range "[1.49.0,2.0.0)"
        $verdict.valid | Should -BeFalse
        $verdict.reason | Should -Match "interval notation"
        $verdict.reason | Should -Match "\^1\.49\.0" -Because "saying what to write instead is the point"
        # The mirror image, so the check is not just 'npm dislikes brackets'.
        (Test-QaFoundryVersionRange -Ecosystem "nuget" -Range "^1.49.0").valid |
            Should -BeFalse -Because "NuGet has no caret"
        (Test-QaFoundryVersionRange -Ecosystem "npm" -Range "^1.49.0").valid | Should -BeTrue
        (Test-QaFoundryVersionRange -Ecosystem "nuget" -Range "[1.49.0,2.0.0)").valid |
            Should -BeTrue
    }

    # Every adapter answers for its own notation, and the answer has to agree
    # with the selector that will read the same string later: a range this check
    # accepts and the selector then cannot use is worse than no check, because
    # it fails further from the cause.
    It "accepts exactly the ranges its own selector can resolve" {
        $accepted = @{
            npm = @("^1.49.0", "~1.49.0", ">=1.49.0", "1.49.x", "1.49.0", "latest", "*")
            nuget = @("[1.49.0,2.0.0)", "[1.49.0]", "1.49.0", "(1.0,2.0]")
            maven = @("[1.49.0,2.0.0)", "1.49.0", "RELEASE", "LATEST")
            pypi = @(">=1.49.0,<2.0.0", "==1.49.0", "~=1.49.0", "!=1.49.0", "==1.49.*")
            rubygems = @("~> 1.49", ">= 1.4, < 2.0", "= 1.49.0")
            composer = @("^1.49.0 || ^2.0", "~1.49", ">=1.49.0", "v1.49.0")
            go = @("v1.49.0", "1.49.0")
        }
        $rejected = @{
            npm = @("[1.49.0,2.0.0)", "~> 1.4", ">=1.49.0 <2.0.0")
            nuget = @("^1.49.0", "~> 1.4")
            maven = @("^1.0", "~1.0")
            pypi = @("^1.49.0", "[1,2)", "~> 1.4")
            rubygems = @("^1.49", "[1,2)")
            composer = @("[1,2)", "~> 1.4")
            go = @("^1.49.0", ">=1.49.0", "[1.49.0,2.0.0)")
        }
        foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
            $accepted.Keys | Should -Contain $id `
                -Because "a new ecosystem must say which ranges it takes"
            foreach ($range in @($accepted[$id])) {
                (Test-QaFoundryVersionRange -Ecosystem $id -Range $range).valid |
                    Should -BeTrue -Because "$id writes ranges like '$range'"
            }
            foreach ($range in @($rejected[$id])) {
                $verdict = Test-QaFoundryVersionRange -Ecosystem $id -Range $range
                $verdict.valid | Should -BeFalse -Because "$id does not write '$range'"
                $verdict.reason | Should -Not -BeNullOrEmpty `
                    -Because "a refusal an architect cannot act on is a dead end"
            }
        }
    }

    # The pair that stopped the first live bootstrap, kept as a fixture: the
    # decision called MSTest a development dependency, and the project file an
    # author would write says nothing either way. Both are right. Comparing them
    # on that field is what was wrong.
    It "reads a hand-written test project without inventing a development scope" {
        $csproj = @(
            '<Project Sdk="Microsoft.NET.Sdk">',
            '  <PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup>',
            '  <ItemGroup>',
            '    <PackageReference Include="MSTest" Version="4.4.0" />',
            '    <PackageReference Include="NSubstitute" Version="5.3.0" />',
            '  </ItemGroup>',
            '</Project>'
        ) -join "`n"
        $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem "nuget"
        $declared = @(& $adapter.ReadManifestDependencies $csproj)
        @($declared).Count | Should -Be 2
        @($declared | ForEach-Object { [string]$_.scope }) | Should -Be @("runtime", "runtime")
        # Which is exactly why the ecosystem must not have that field compared:
        # no author can write anything here that would satisfy a decision of
        # 'dev', short of an attribute that means something else entirely.
        $adapter.manifestExpressesDependencyScope | Should -BeFalse
    }

    # The lock a resolution writes is only worth reading if something refuses to    # install around it. Most installers do that themselves; the one that does
    # not had a lock delivered into the change set and never consulted, which is
    # a lock in name only. Declaring which of the two an adapter relies on makes
    # the omission impossible to repeat quietly.
    It "says for every ecosystem how the approved lock is enforced when it installs" {
        foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
            $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $id
            [string]$adapter.lockEnforcement |
                Should -BeIn @("install", "verified-after-install") `
                -Because "$id must say whether its installer reads the lock or whether the run must check afterwards"
            if ([string]$adapter.lockEnforcement -eq "verified-after-install") {
                @(Get-QaFoundryPropertyNames -InputObject $adapter) |
                    Should -Contain "GetInstalledArtefactFindings" `
                    -Because "$id installs without reading the lock, so it must supply the comparison"
                [string]$adapter.lockFileName | Should -Not -BeNullOrEmpty `
                    -Because "$id must name the file the comparison reads"
            }
        }
    }

    # Checking that an adapter *has* a SelectVersion is not the same as checking
    # that it can run one. An adapter whose private helpers were loaded into a
    # scope that no longer exists still answers for every member here and then
    # fails on the first call, so every shipped adapter is actually invoked.
    It "resolves a requested range against a feed for every ecosystem it ships" {
        $samples = @{
            npm      = @{ Requested = "^1.2.0";          Published = @("1.0.0", "1.2.0", "1.3.4", "2.0.0"); Expected = "1.3.4" }
            nuget    = @{ Requested = "1.2.0";           Published = @("1.0.0", "1.2.0", "2.0.0");          Expected = "1.2.0" }
            pypi     = @{ Requested = ">=1.2.0,<2.0.0";  Published = @("1.0.0", "1.2.0", "1.9.1", "2.0.0"); Expected = "1.9.1" }
            maven    = @{ Requested = "1.2.0";           Published = @("1.0.0", "1.2.0", "2.0.0");          Expected = "1.2.0" }
            rubygems = @{ Requested = "~> 1.2";          Published = @("1.0.0", "1.2.0", "1.9.1", "2.0.0"); Expected = "1.9.1" }
            go       = @{ Requested = "v1.2.0";          Published = @("v1.0.0", "v1.2.0", "v2.0.0");       Expected = "v1.2.0" }
            composer = @{ Requested = "^1.2";            Published = @("1.0.0", "1.2.0", "1.9.1", "2.0.0"); Expected = "1.9.1" }
        }
        foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
            # A new adapter has to arrive with a case here, or it ships untried.
            $samples.ContainsKey($id) |
                Should -BeTrue -Because "$id ships without a version-selection case"
            $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $id
            $sample = $samples[$id]
            $selected = & $adapter.SelectVersion -Requested $sample.Requested `
                -Published $sample.Published -AllowPrerelease $false
            [string]$selected |
                Should -BeExactly ([string]$sample.Expected) -Because "$id must resolve $($sample.Requested)"
        }
    }

    # An adapter that named a manifest its own pattern rejects would write a file
    # the runtime then refuses to recognise as the manifest it just wrote.
    It "names a manifest file that matches its own manifest pattern" {
        foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
            $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $id
            foreach ($projectName in @("automation", "Contoso.Api.Tests", "a b/../c", "")) {
                $fileName = [string](& $adapter.GetManifestFileName $projectName)
                $fileName | Should -Not -BeNullOrEmpty -Because "$id must name its manifest"
                $fileName | Should -Not -Match "[\\/]" -Because "$id must name a file, not a path"
                "automation/$fileName" |
                    Should -Match ([string]$adapter.manifestPattern) -Because "$id must recognise the manifest it names"
            }
        }
    }

    It "ships adapters for npm and NuGet" {
        @(Get-QaFoundryEcosystemAdapterNames) | Should -Contain "npm"
        @(Get-QaFoundryEcosystemAdapterNames) | Should -Contain "nuget"
    }

    # Whether "Newtonsoft.JSON" is the package that was approved as
    # "Newtonsoft.Json" is a question with a different answer per registry, and
    # PowerShell answers "yes" for all of them. Every ecosystem states its own
    # rule, so a name that survives a comparison is one the feed would serve.
    It "decides package identity by each registry's own rule" {
        $expectations = @{
            # Published names are kept as they were published.
            npm      = @{ Same = @(); Different = @(, @("JSON5", "json5")) }
            rubygems = @{ Same = @(); Different = @(, @("Ascii85", "ascii85")) }
            maven    = @{ Same = @(); Different = @(, @("com.example:Widget", "com.example:widget")) }
            go       = @{ Same = @(); Different = @(, @("github.com/Sirupsen/logrus", "github.com/sirupsen/logrus")) }
            # Case is folded by the registry itself.
            nuget    = @{ Same = @(, @("Newtonsoft.Json", "newtonsoft.JSON")); Different = @(, @("Newtonsoft.Json", "Newtonsoft.Bson")) }
            composer = @{ Same = @(, @("Monolog/Monolog", "monolog/monolog")); Different = @(, @("monolog/monolog", "monolog/mono")) }
            # PEP 503 folds case and collapses runs of - _ and . alike.
            pypi     = @{ Same = @(@("Flask_SQLAlchemy", "flask-sqlalchemy"), @("zope.interface", "zope-interface")); Different = @(, @("flask", "flask-cors")) }
        }
        foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
            # A new adapter has to arrive with a case here, or it ships with an
            # unstated opinion about what counts as the same package.
            $expectations.ContainsKey($id) |
                Should -BeTrue -Because "$id ships without a package-identity case"
            foreach ($pair in @($expectations[$id].Same)) {
                Test-QaFoundrySamePackageName -Ecosystem $id -Left $pair[0] -Right $pair[1] |
                    Should -BeTrue -Because "$id treats $($pair[0]) and $($pair[1]) as one package"
            }
            foreach ($pair in @($expectations[$id].Different)) {
                Test-QaFoundrySamePackageName -Ecosystem $id -Left $pair[0] -Right $pair[1] |
                    Should -BeFalse -Because "$id treats $($pair[0]) and $($pair[1]) as two packages"
            }
            # Whatever the rule, it has to be a rule: the same name twice is the
            # same package, and surrounding whitespace is not part of a name.
            Test-QaFoundrySamePackageName -Ecosystem $id -Left "example.package" -Right " example.package " |
                Should -BeTrue -Because "$id must ignore whitespace around a name"
        }
    }

    # The whole point of refusing loudly: a run that quietly substituted a
    # supported ecosystem would deliver automation in a language nobody chose.
    It "refuses an ecosystem it has no adapter for and names the ones it has" {
        $absent = @("cocoapods", "cargo", "hex", "cpan") |
            Where-Object { $_ -notin @(Get-QaFoundryEcosystemAdapterNames) } |
            Select-Object -First 1
        $absent | Should -Not -BeNullOrEmpty
        { Get-QaFoundryEcosystemAdapter -Ecosystem $absent } |
            Should -Throw "*no adapter for the '$absent' package ecosystem*"
        { Get-QaFoundryEcosystemAdapter -Ecosystem $absent } | Should -Throw "*npm*"
    }

    It "refuses an ecosystem name that could escape the adapter directory" {
        { Get-QaFoundryEcosystemAdapter -Ecosystem "../../Common" } | Should -Throw "*not a package ecosystem name*"
        { Get-QaFoundryEcosystemAdapter -Ecosystem "" } | Should -Throw "*No package ecosystem was named*"
    }

    It "matches each ecosystem's own manifest and lock names" {
        $npm = Get-QaFoundryEcosystemAdapter -Ecosystem "npm"
        "automation/api/package.json" | Should -Match ([string]$npm.manifestPattern)
        "automation/api/package-lock.json" | Should -Match ([string]$npm.lockFilePattern)
        "automation/api/Api.csproj" | Should -Not -Match ([string]$npm.manifestPattern)

        $nuget = Get-QaFoundryEcosystemAdapter -Ecosystem "nuget"
        "automation/api/Contoso.Api.Tests.csproj" | Should -Match ([string]$nuget.manifestPattern)
        "automation/api/packages.lock.json" | Should -Match ([string]$nuget.lockFilePattern)
        "automation/api/package.json" | Should -Not -Match ([string]$nuget.manifestPattern)
    }
}

Describe "Reading a package hash" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        . (Join-Path $script:Root "scripts/Common.ps1")
    }

    # NuGet writes a content hash as padded base64 with no algorithm in front of
    # it. When the 86 characters before the padding happen to contain neither
    # "+" nor "/" - about one hash in fifteen - the whole value is alphanumeric
    # up to a trailing "=", which is one of the separators the prefixed spelling
    # uses. Build 973302 blocked on exactly this: two real packages out of
    # thirty were called unhashed, and a rerun would have picked two others.
    It "accepts a NuGet content hash whose padding looks like a separator" {
        $hash = "go1cdBdN47PLsCcmMnp5tUFGTI3qpIbWJJPPvqXSat0EqCSpMfI3X3qDK6EzXt6rkCKQh4XiXFLic8sROgIrLw=="
        $hash | Should -Not -Match "[+/]" -Because "the whole point is a value with no base64 specials"
        Test-QaFoundryPackageDigest -Value $hash | Should -BeTrue
    }

    It "accepts every padded hash length an ecosystem writes bare" {
        $sha = [System.Security.Cryptography.SHA512]::Create()
        try {
            $seed = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("qa-foundry"))
            foreach ($length in @(16, 20, 32, 48, 64)) {
                $value = [Convert]::ToBase64String($seed[0..($length - 1)])
                Test-QaFoundryPackageDigest -Value $value |
                    Should -BeTrue -Because "$length bytes of base64 is a hash somebody writes"
            }
        }
        finally { $sha.Dispose() }
    }

    It "still refuses a named algorithm carrying the wrong number of bytes" {
        Test-QaFoundryPackageDigest -Value "sha512-YQ==" | Should -BeFalse
        Test-QaFoundryPackageDigest -Value "sha256:abcd" | Should -BeFalse
        Test-QaFoundryPackageDigest -Value "trust-me" | Should -BeFalse
    }

    It "still reads the spellings the other ecosystems use" {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("qa-foundry"))
            $base64 = [Convert]::ToBase64String($bytes)
            $hex = -join ($bytes | ForEach-Object { $_.ToString("x2") })
            Test-QaFoundryPackageDigest -Value "sha256-$base64" | Should -BeTrue
            Test-QaFoundryPackageDigest -Value "sha256:$hex" | Should -BeTrue
            Test-QaFoundryPackageDigest -Value "sha256=$hex" | Should -BeTrue
            Test-QaFoundryPackageDigest -Value "h1:$base64" | Should -BeTrue
            Test-QaFoundryPackageDigest -Value $hex | Should -BeTrue
        }
        finally { $sha.Dispose() }
    }
}

Describe "Resolving a proposed version against a feed" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        . (Join-Path $script:Root "scripts/Common.ps1")
        $script:Published = @("1.2.2", "1.2.9", "1.3.0", "1.9.0", "1.10.0", "2.0.0", "2.1.0-beta.1")
    }

    It "reads a caret range the way npm does" {
        Select-QaFoundryNodeStyleVersion -Requested "^1.2.3" -Published $script:Published `
            -AllowPrerelease $false | Should -Be "1.10.0"
    }

    # Sort-Object would put 1.9.0 above 1.10.0, which is the single most common
    # way a resolver pins a version older than the one it was asked for.
    It "orders versions numerically rather than as text" {
        Get-QaFoundryHighestVersion -Versions @("1.9.0", "1.10.0") | Should -Be "1.10.0"
        Compare-QaFoundryVersion -Left "1.10.0" -Right "1.9.0" | Should -BeGreaterThan 0
    }

    It "honours an exact npm version" {
        Select-QaFoundryNodeStyleVersion -Requested "1.2.9" -Published $script:Published `
            -AllowPrerelease $false | Should -Be "1.2.9"
    }

    It "keeps pre-releases out unless they are allowed" {
        Select-QaFoundryNodeStyleVersion -Requested "^2.0.0" -Published $script:Published `
            -AllowPrerelease $false | Should -Be "2.0.0"
        Select-QaFoundryNodeStyleVersion -Requested "^2.0.0" -Published $script:Published `
            -AllowPrerelease $true | Should -Be "2.1.0-beta.1"
    }

    It "reads NuGet interval notation rather than npm ranges" {
        Select-QaFoundryNuGetVersion -Requested "[1.2.9]" -Published $script:Published `
            -AllowPrerelease $false | Should -Be "1.2.9"
        Select-QaFoundryNuGetVersion -Requested "[1.2.2,1.10.0)" -Published $script:Published `
            -AllowPrerelease $false | Should -Be "1.9.0"
    }

    It "returns nothing when no published version satisfies the request" {
        Select-QaFoundryNodeStyleVersion -Requested "^9.0.0" -Published $script:Published `
            -AllowPrerelease $false | Should -BeNullOrEmpty
    }
}

# PEP 440 is not semantic versioning spelled differently, and reading it as such
# selected distributions the request had ruled out.
Describe "Reading a Python version the way PEP 440 defines one" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        . (Join-Path $script:Root "scripts/ecosystems/pypi.Ecosystem.ps1")
    }

    It "orders a development release below a pre-release, and a post-release above the release" {
        $order = @("1.0.dev1", "1.0a1", "1.0a2", "1.0b1", "1.0rc1", "1.0", "1.0.post1", "1.0.post2")
        for ($i = 1; $i -lt $order.Count; $i++) {
            $left = ConvertTo-QaFoundryPythonVersion -Version $order[$i - 1]
            $right = ConvertTo-QaFoundryPythonVersion -Version $order[$i]
            Compare-QaFoundryPythonVersion -Left $left -Right $right |
                Should -BeLessThan 0 -Because "$($order[$i - 1]) precedes $($order[$i])"
        }
    }

    It "orders an epoch above every version without one" {
        $left = ConvertTo-QaFoundryPythonVersion -Version "99.9"
        $right = ConvertTo-QaFoundryPythonVersion -Version "1!0.1"
        Compare-QaFoundryPythonVersion -Left $left -Right $right | Should -BeLessThan 0
    }

    It "reads 1.0 and 1.0.0 as the same version" {
        $left = ConvertTo-QaFoundryPythonVersion -Version "1.0"
        $right = ConvertTo-QaFoundryPythonVersion -Version "1.0.0"
        Compare-QaFoundryPythonVersion -Left $left -Right $right | Should -Be 0
    }

    # The defect this replaces: a post-release was rewritten to the release it
    # follows, so a request for one was answered with a different distribution.
    It "keeps a post-release distinct from the release it follows" {
        Select-QaFoundryPythonVersion -Requested "==1.2.3.post1" `
            -Published ([string[]]@("1.2.3", "1.2.3.post1")) -AllowPrerelease $false |
            Should -Be "1.2.3.post1"
        Select-QaFoundryPythonVersion -Requested "==1.2.3" `
            -Published ([string[]]@("1.2.3", "1.2.3.post1")) -AllowPrerelease $false |
            Should -Be "1.2.3"
    }

    It "excludes a whole release series with a wildcard exclusion" {
        Select-QaFoundryPythonVersion -Requested "!=1.5.*" `
            -Published ([string[]]@("1.4.9", "1.5.9")) -AllowPrerelease $false | Should -Be "1.4.9"
    }

    It "matches a release series by the segments the request names, not by major and minor" {
        Select-QaFoundryPythonVersion -Requested "==1.5.0.*" `
            -Published ([string[]]@("1.5.0.9", "1.5.1")) -AllowPrerelease $false | Should -Be "1.5.0.9"
        Select-QaFoundryPythonVersion -Requested "==1.5.*" `
            -Published ([string[]]@("1.4.9", "1.5.9", "1.6.0")) -AllowPrerelease $false | Should -Be "1.5.9"
    }

    It "reads a compatible release against the last segment the request named" {
        Select-QaFoundryPythonVersion -Requested "~=1.4.2" `
            -Published ([string[]]@("1.4.1", "1.4.9", "1.5.0")) -AllowPrerelease $false | Should -Be "1.4.9"
        Select-QaFoundryPythonVersion -Requested "~=1.4" `
            -Published ([string[]]@("1.4.0", "1.9.9", "2.0.0")) -AllowPrerelease $false | Should -Be "1.9.9"
    }

    # An exclusive bound is written about the release, so it rules out the
    # post-releases and pre-releases that the ordering places on the other side.
    It "refuses a post-release of an excluded lower bound and a pre-release of an excluded upper one" {
        Select-QaFoundryPythonVersion -Requested ">1.5" `
            -Published ([string[]]@("1.5", "1.5.post1")) -AllowPrerelease $false | Should -BeNullOrEmpty
        Select-QaFoundryPythonVersion -Requested "<1.5" `
            -Published ([string[]]@("1.5a1", "1.5")) -AllowPrerelease $true | Should -BeNullOrEmpty
    }

    It "reads every clause of a comma-separated specifier" {
        Select-QaFoundryPythonVersion -Requested ">=1.0,<2.0" `
            -Published ([string[]]@("0.9", "1.9.1", "2.0")) -AllowPrerelease $false | Should -Be "1.9.1"
    }

    It "compares an arbitrary equality against the version as published" {
        Select-QaFoundryPythonVersion -Requested "===1.2.3" `
            -Published ([string[]]@("1.2.3.0", "1.2.3")) -AllowPrerelease $false | Should -Be "1.2.3"
        Select-QaFoundryPythonVersion -Requested "===1.2.3" `
            -Published ([string[]]@("1.2.3.0")) -AllowPrerelease $false | Should -BeNullOrEmpty
    }

    It "leaves pre-releases out unless the run allows them, and never counts a post-release as one" {
        Select-QaFoundryPythonVersion -Requested "" -Published ([string[]]@("1.9", "2.0b1")) `
            -AllowPrerelease $false | Should -Be "1.9"
        Select-QaFoundryPythonVersion -Requested "" -Published ([string[]]@("1.9", "2.0b1")) `
            -AllowPrerelease $true | Should -Be "2.0b1"
        Select-QaFoundryPythonVersion -Requested "" -Published ([string[]]@("1.0", "1.0.post2")) `
            -AllowPrerelease $false | Should -Be "1.0.post2"
    }

    # Python 3.11 and 3.12 are different runtimes with different wheels, so a
    # lock resolved against one proves nothing about the other.
    It "holds the agent to the named Python minor version, not merely to Python 3" {
        $adapter = & (Get-Command New-QaFoundryPypiEcosystemAdapter)
        $tools = @(& $adapter.GetResolverTools ([pscustomobject]@{
            runtime = [pscustomobject]@{ pythonVersion = "3.12" }
        }))
        $python = @($tools | Where-Object { $_.key -eq "python" })
        $python.Count | Should -Be 1
        $python[0].match | Should -Be "minor"
    }
}

Describe "Proving the chosen framework by running it" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        $script:Verifier = Join-Path $script:Root "scripts/actions/Test-MaterializedFramework.ps1"
        . (Join-Path $script:Root "scripts/Common.ps1")

        function New-VerificationInputs {
            param(
                [Parameter(Mandatory)][string]$Directory,
                [string]$RunId = "run-verify",
                # Lets a test write a runtime block that a resolver would never
                # have written, which is the only way to check the refusal.
                [System.Collections.IDictionary]$Runtime = $null,
                # Lets a test materialise a framework of its own, which is how
                # the container sequence is proved against real commands rather
                # than against the arguments they were built from.
                [object[]]$Changes = @()
            )
            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
            $changeSet = [ordered]@{
                agentId = "materialize-change-set"
                stageId = "bootstrap-change-materialization"
                runId = $RunId
                status = "completed"
                summary = "Resolved change set."
                evidence = @()
                assumptions = @()
                unknowns = @()
                warnings = @()
                details = [ordered]@{
                    planPath = "plan.json"
                    materializationCount = 1
                    materializations = @([ordered]@{
                        toolchainId = "npm-automation"
                        ecosystem = "npm"
                        manifestPath = "automation/api/package.json"
                        lockPath = "automation/api/package-lock.json"
                        projectPaths = @("automation/api")
                    })
                }
                outcome = "proposed"
                changes = @(
                    [ordered]@{
                        operation = "create"
                        path = "automation/api/package.json"
                        expectedSha256 = ""
                        content = '{"name":"api","version":"1.0.0","devDependencies":{"playwright":"1.49.0"}}'
                        reason = "Automation manifest."
                        sourceRefs = @("automation-blueprint.json")
                    },
                    [ordered]@{
                        operation = "create"
                        path = "automation/api/package-lock.json"
                        expectedSha256 = ""
                        content = '{"lockfileVersion":3}'
                        reason = "Resolved lock."
                        sourceRefs = @("automation-blueprint.json")
                    }
                )
            }
            $changeSetPath = Join-Path $Directory "change-set.json"
            if (@($Changes).Count -gt 0) { $changeSet.changes = @($Changes) }
            $changeSet | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $changeSetPath -Encoding utf8

            $lock = [ordered]@{
                runId = $RunId
                stageId = "toolchain-resolution"
                blueprintSha256 = ("a" * 64)
                resolvedAt = (Get-Date).ToUniversalTime().ToString("o")
                toolchains = @(
                    [ordered]@{
                        id = "npm-automation"
                        revision = 1
                        ecosystem = "npm"
                        recipe = "npm-package-lock"
                        language = "TypeScript"
                        testFramework = "playwright"
                        source = [ordered]@{
                            id = "npm-public"
                            registry = "https://registry.npmjs.org/"
                            authentication = "none"
                        }
                        runtime = [ordered]@{
                            # The canonical names a resolver writes, which is
                            # what a lock read back from disk actually carries.
                            # The config's snake_case spelling is translated
                            # once, where the toolchain is recorded, and a
                            # fixture that keeps the config spelling tests a
                            # document this runtime never produces.
                            nodeMajor = 20
                            npmVersion = "10.8.2"
                            lockfileVersion = 3
                        }
                        packages = @(
                            [ordered]@{
                                key = "playwright"
                                name = "playwright"
                                version = "1.49.0"
                                scope = "dev"
                                requested = "^1.49.0"
                            }
                        )
                        decidedFor = @("Contoso.Automation.Api")
                        sha256 = ("b" * 64)
                    }
                )
            }
            $lockPath = Join-Path $Directory "toolchain-lock.json"
            if ($null -ne $Runtime) { $lock.toolchains[0].runtime = $Runtime }
            $lock | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $lockPath -Encoding utf8

            return [pscustomobject]@{
                ChangeSetPath = $changeSetPath
                LockPath = $lockPath
                RunId = $RunId
            }
        }

        # A runner stands in for npm. The verification is about what the runtime
        # concludes from a run, not about whether this machine has node.
        function New-Runner {
            param(
                [int]$InstallExit = 0,
                [int]$BuildExit = 0,
                [string]$TestOutput = "# pass 4`n# fail 0",
                [int]$TestExit = 0,
                # The probe adds one deliberately failing test, so a suite that
                # ran four tests must now run five and report one of them red.
                [string]$ProbeOutput = "# pass 4`n# fail 1",
                [int]$ProbeExit = 1
            )
            # The verifier runs each project in its own working directory, and a
            # counter shared across projects would hand the second project the
            # probe's failing output as its first test run.
            $state = @{}
            return {
                param($Executable, $Arguments, $WorkingDirectory)
                $joined = (@($Arguments) -join " ")
                if ($joined -like "*ci*" -or $joined -like "*install*") {
                    return [pscustomobject]@{ exitCode = $InstallExit; output = "installed"; durationMs = 1 }
                }
                if ($joined -like "*build*") {
                    return [pscustomobject]@{ exitCode = $BuildExit; output = "built"; durationMs = 1 }
                }
                $key = [string]$WorkingDirectory
                if (-not $state.ContainsKey($key)) { $state[$key] = 0 }
                $state[$key]++
                if ($state[$key] -eq 1) {
                    return [pscustomobject]@{ exitCode = $TestExit; output = $TestOutput; durationMs = 1 }
                }
                return [pscustomobject]@{ exitCode = $ProbeExit; output = $ProbeOutput; durationMs = 1 }
            }.GetNewClosure()
        }

        function Invoke-Verification {
            param(
                [Parameter(Mandatory)][string]$Directory,
                [Parameter(Mandatory)][scriptblock]$Runner
            )
            $inputs = New-VerificationInputs -Directory $Directory
            $outputPath = Join-Path $Directory "framework-verification.json"
            $result = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
                -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
                -StageId "framework-verification" -OutputPath $outputPath `
                -WorkRoot (Join-Path $Directory "work") -CommandRunner $Runner
            return [pscustomobject]@{
                Result = $result
                Verification = (Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40)
            }
        }

        # Maven is the one ecosystem here whose installer does not read a lock,
        # so the comparison this runtime makes afterwards is the only thing
        # standing between an approved lock and an install that ignored it.
        # Proving it needs a change set that ends in a real dependency-lock.txt
        # and a runner that leaves real artefacts behind.
        $script:JarBytes = "locked-artefact-bytes"
        $script:JarDigest = ([BitConverter]::ToString(
            [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($script:JarBytes))
        ) -replace "-", "").ToLowerInvariant()

        function New-MavenVerificationInputs {
            param([Parameter(Mandatory)][string]$Directory, [string]$LockContent, [switch]$NoLock)
            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
            if ([string]::IsNullOrEmpty($LockContent)) {
                $LockContent = ("# Generated from the locked toolchain. Do not edit by hand.`n" +
                    "org.junit.jupiter:junit-jupiter:5.11.3 sha256:$script:JarDigest " +
                    "https://repo.maven.apache.org/maven2/org/junit/jupiter/junit-jupiter/5.11.3/junit-jupiter-5.11.3.jar`n")
            }
            $changeSet = [ordered]@{
                agentId = "materialize-change-set"
                stageId = "bootstrap-change-materialization"
                runId = "run-verify-maven"
                status = "completed"
                summary = "Resolved change set."
                evidence = @(); assumptions = @(); unknowns = @(); warnings = @()
                details = [ordered]@{
                    planPath = "plan.json"
                    materializationCount = 1
                    materializations = @([ordered]@{
                        toolchainId = "maven-junit"
                        ecosystem = "maven"
                        manifestPath = "automation/pom.xml"
                        lockPath = "automation/dependency-lock.txt"
                        projectPaths = @("automation")
                    })
                }
                outcome = "proposed"
                changes = @(
                    [ordered]@{
                        operation = "create"; path = "automation/pom.xml"; expectedSha256 = ""
                        content = "<project><artifactId>automation</artifactId></project>"
                        reason = "Automation manifest."; sourceRefs = @("automation-blueprint.json")
                    },
                    [ordered]@{
                        operation = "create"; path = "automation/dependency-lock.txt"; expectedSha256 = ""
                        content = $LockContent
                        reason = "Resolved lock."; sourceRefs = @("automation-blueprint.json")
                    }
                )
            }
            if ($NoLock) {
                $changeSet.changes = @($changeSet.changes[0])
            }
            $changeSetPath = Join-Path $Directory "change-set-maven.json"
            $changeSet | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $changeSetPath -Encoding utf8

            $lock = [ordered]@{
                runId = "run-verify-maven"
                stageId = "toolchain-resolution"
                blueprintSha256 = ("a" * 64)
                resolvedAt = (Get-Date).ToUniversalTime().ToString("o")
                toolchains = @([ordered]@{
                    id = "maven-junit"; revision = 1; ecosystem = "maven"; recipe = "maven-surefire"
                    language = "Java"; testFramework = "junit5"
                    source = [ordered]@{
                        id = "maven-central"; registry = "https://repo.maven.apache.org/maven2"
                        authentication = "none"
                    }
                    runtime = [ordered]@{ javaVersion = "21"; mavenVersion = "3.9.9" }
                    packages = @([ordered]@{
                        key = "org-junit-jupiter-junit-jupiter"; name = "org.junit.jupiter:junit-jupiter"
                        version = "5.11.3"; scope = "dev"; requested = "5.11.3"
                    })
                    decidedFor = @("Contoso.Automation.Api"); sha256 = ("b" * 64)
                })
            }
            $lockPath = Join-Path $Directory "toolchain-lock-maven.json"
            $lock | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $lockPath -Encoding utf8
            return [pscustomobject]@{ ChangeSetPath = $changeSetPath; LockPath = $lockPath }
        }

        # Stands in for mvn. The install leaves whatever artefacts the test asks
        # it to leave, which is how an install that fetched something other than
        # the locked set is described here.
        function New-MavenRunner {
            param([hashtable]$Fetched = $null)
            if ($null -eq $Fetched) {
                $Fetched = @{ "org/junit/jupiter/junit-jupiter/5.11.3/junit-jupiter-5.11.3.jar" = $script:JarBytes }
            }
            $state = [ordered]@{ testRuns = 0 }
            return {
                param($Executable, $Arguments, $WorkingDirectory)
                $joined = (@($Arguments) -join " ")
                if ($Executable -eq 'pwsh' -and $joined -like '*-EncodedCommand*') {
                    foreach ($relative in @($Fetched.Keys)) {
                        $target = Join-Path (Join-Path $WorkingDirectory ".m2-repo") ($relative -replace "/", "\")
                        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
                        Set-Content -LiteralPath $target -Value ([string]$Fetched[$relative]) -Encoding utf8 -NoNewline
                    }
                    return [pscustomobject]@{ exitCode = 0; output = "installed"; durationMs = 1 }
                }
                if ($joined -like "*test-compile*") {
                    return [pscustomobject]@{ exitCode = 0; output = "built"; durationMs = 1 }
                }
                $state.testRuns++
                if ($state.testRuns -eq 1) {
                    return [pscustomobject]@{
                        exitCode = 0; output = "Tests run: 4, Failures: 0, Errors: 0, Skipped: 0"; durationMs = 1
                    }
                }
                return [pscustomobject]@{
                    exitCode = 1; output = "Tests run: 5, Failures: 1, Errors: 0, Skipped: 0"; durationMs = 1
                }
            }.GetNewClosure()
        }

        function Invoke-MavenVerification {
            param(
                [Parameter(Mandatory)][string]$Directory,
                [Parameter(Mandatory)][scriptblock]$Runner,
                [string]$LockContent,
                [switch]$NoLock
            )
            $inputs = New-MavenVerificationInputs -Directory $Directory -LockContent $LockContent -NoLock:$NoLock
            $outputPath = Join-Path $Directory "framework-verification.json"
            $result = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
                -ToolchainLockPath $inputs.LockPath -RunId "run-verify-maven" `
                -StageId "framework-verification" -OutputPath $outputPath `
                -WorkRoot (Join-Path $Directory "work") -CommandRunner $Runner
            return [pscustomobject]@{
                Result = $result
                Verification = (Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40)
            }
        }
    }

    BeforeEach {
        $script:Work = Join-Path ([IO.Path]::GetTempPath()) ("foundry-verify-" + [guid]::NewGuid().ToString("n"))
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "accepts a framework that installs, builds, runs tests and can still fail" {
        $outcome = Invoke-Verification -Directory $script:Work -Runner (New-Runner)
        $outcome.Result.status | Should -Be "completed"
        $outcome.Result.handler | Should -Be "verify_framework"
        $outcome.Verification.outcome | Should -Be "verified"
        @($outcome.Verification.projects).Count | Should -Be 1
        $outcome.Verification.projects[0].testsDiscovered | Should -Be 4
        $outcome.Verification.projects[0].negativeProbe.attempted | Should -BeTrue
        $outcome.Verification.projects[0].negativeProbe.failedAsExpected | Should -BeTrue
    }

    # npm ci, dotnet restore --locked-mode and pip --require-hashes refuse on
    # their own. Maven resolves from the POM and never opens the lock the review
    # approved, so the run has to hold it to it afterwards.
    It "accepts a Maven install that fetched exactly the artefacts the lock pins" {
        $outcome = Invoke-MavenVerification -Directory $script:Work -Runner (New-MavenRunner)
        $outcome.Verification.outcome | Should -Be "verified"
        $step = @($outcome.Verification.projects[0].steps | Where-Object { $_.name -eq "install_lock" })
        $step.Count | Should -Be 1
        $step[0].status | Should -Be "passed"
    }

    It "refuses a Maven install that fetched an artefact the lock does not pin" {
        $runner = New-MavenRunner -Fetched @{
            "org/junit/jupiter/junit-jupiter/5.11.3/junit-jupiter-5.11.3.jar" = $script:JarBytes
            "com/evil/backdoor/1.0.0/backdoor-1.0.0.jar" = "arrived without being resolved"
        }
        $outcome = Invoke-MavenVerification -Directory $script:Work -Runner $runner
        $outcome.Verification.outcome | Should -Be "toolchain_defect"
        $step = @($outcome.Verification.projects[0].steps | Where-Object { $_.name -eq "install_lock" })
        $step[0].status | Should -Be "failed"
        $step[0].detail | Should -BeLike "*com.evil:backdoor:1.0.0*"
        # The framework is not run once the bytes underneath it are in doubt.
        @($outcome.Verification.projects[0].steps | Where-Object { $_.name -eq "test" }).Count | Should -Be 0
    }

    It "refuses a Maven install whose artefact is not the bytes the lock pins" {
        $runner = New-MavenRunner -Fetched @{
            "org/junit/jupiter/junit-jupiter/5.11.3/junit-jupiter-5.11.3.jar" = "different bytes entirely"
        }
        $outcome = Invoke-MavenVerification -Directory $script:Work -Runner $runner
        $outcome.Verification.outcome | Should -Be "toolchain_defect"
        $step = @($outcome.Verification.projects[0].steps | Where-Object { $_.name -eq "install_lock" })
        $step[0].detail | Should -BeLike "*lock file pins*"
    }

    It "refuses a Maven change set that carries no lock at all" {
        $outcome = Invoke-MavenVerification -Directory $script:Work -Runner (New-MavenRunner) -NoLock
        $outcome.Verification.outcome | Should -Be "toolchain_defect"
        $step = @($outcome.Verification.projects[0].steps | Where-Object { $_.name -eq "install_lock" })
        $step[0].detail | Should -BeLike "*no dependency-lock.txt*"
    }

    # An ecosystem whose installer enforces its own lock is not asked to prove
    # it twice, and a step that always passes is a step nobody reads.
    It "does not add a lock comparison for an ecosystem whose installer enforces one" {
        $outcome = Invoke-Verification -Directory $script:Work -Runner (New-Runner)
        @($outcome.Verification.projects[0].steps | Where-Object { $_.name -eq "install_lock" }).Count |
            Should -Be 0
    }

    # Two decisions in one ecosystem is the ordinary case - one project on
    # Playwright, another on Vitest - and matching manifests by ecosystem tested
    # both against whichever the lock happened to list first.
    It "verifies every locked toolchain, including a second one in the same ecosystem" {
        $inputs = New-VerificationInputs -Directory $script:Work
        $changeSet = Get-Content -LiteralPath $inputs.ChangeSetPath -Raw | ConvertFrom-Json -Depth 40
        $changeSet.changes += @(
            [pscustomobject]@{
                operation = "create"; path = "automation/ui/package.json"; expectedSha256 = ""
                content = '{"name":"ui","version":"1.0.0","devDependencies":{"vitest":"3.2.4"}}'
                reason = "Automation manifest."; sourceRefs = @("automation-blueprint.json")
            },
            [pscustomobject]@{
                operation = "create"; path = "automation/ui/package-lock.json"; expectedSha256 = ""
                content = '{"lockfileVersion":3}'
                reason = "Resolved lock."; sourceRefs = @("automation-blueprint.json")
            }
        )
        $changeSet.details.materializationCount = 2
        $changeSet.details.materializations += @([pscustomobject]@{
            toolchainId = "npm-ui"; ecosystem = "npm"
            manifestPath = "automation/ui/package.json"
            lockPath = "automation/ui/package-lock.json"
            projectPaths = @("automation/ui")
        })
        $changeSet | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $inputs.ChangeSetPath -Encoding utf8

        $lock = Get-Content -LiteralPath $inputs.LockPath -Raw | ConvertFrom-Json -Depth 40
        $second = $lock.toolchains[0] | ConvertTo-Json -Depth 40 | ConvertFrom-Json -Depth 40
        $second.id = "npm-ui"
        $second.testFramework = "vitest"
        $second.decidedFor = @("Contoso.Automation.Ui")
        $lock.toolchains += @($second)
        $lock | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $inputs.LockPath -Encoding utf8

        $outputPath = Join-Path $script:Work "framework-verification.json"
        $null = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
            -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
            -StageId "framework-verification" -OutputPath $outputPath `
            -WorkRoot (Join-Path $script:Work "work") -CommandRunner (New-Runner)
        $verification = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40

        $verification.outcome | Should -Be "verified"
        @($verification.projects).Count | Should -Be 2
        @($verification.projects | ForEach-Object { [string]$_.toolchainId } | Sort-Object) |
            Should -Be @("npm-automation", "npm-ui")
    }

    It "refuses a change set that materialises nothing for a locked toolchain" {
        $inputs = New-VerificationInputs -Directory $script:Work
        $lock = Get-Content -LiteralPath $inputs.LockPath -Raw | ConvertFrom-Json -Depth 40
        $second = $lock.toolchains[0] | ConvertTo-Json -Depth 40 | ConvertFrom-Json -Depth 40
        $second.id = "npm-ui"
        $second.decidedFor = @("Contoso.Automation.Ui")
        $lock.toolchains += @($second)
        $lock | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $inputs.LockPath -Encoding utf8

        $outputPath = Join-Path $script:Work "framework-verification.json"
        $null = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
            -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
            -StageId "framework-verification" -OutputPath $outputPath `
            -WorkRoot (Join-Path $script:Work "work") -CommandRunner (New-Runner)
        $verification = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40
        $verification.outcome | Should -Be "toolchain_defect"
        (@($verification.findings | ForEach-Object { [string]$_.message }) -join " ") |
            Should -BeLike "*npm-ui*unproved*"
    }

    It "refuses a manifest the change set attributes to no locked toolchain" {
        $inputs = New-VerificationInputs -Directory $script:Work
        $changeSet = Get-Content -LiteralPath $inputs.ChangeSetPath -Raw | ConvertFrom-Json -Depth 40
        $changeSet.changes += @([pscustomobject]@{
            operation = "create"; path = "automation/stowaway/package.json"; expectedSha256 = ""
            content = '{"name":"stowaway","version":"1.0.0"}'
            reason = "Automation manifest."; sourceRefs = @("automation-blueprint.json")
        })
        $changeSet | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $inputs.ChangeSetPath -Encoding utf8

        $outputPath = Join-Path $script:Work "framework-verification.json"
        $null = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
            -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
            -StageId "framework-verification" -OutputPath $outputPath `
            -WorkRoot (Join-Path $script:Work "work") -CommandRunner (New-Runner)
        $verification = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40
        $verification.outcome | Should -Be "toolchain_defect"
        (@($verification.findings | ForEach-Object { [string]$_.message }) -join " ") |
            Should -BeLike "*stowaway*attributes it to no locked toolchain*"
    }

    # The defect this replaces: a probe that would not compile exits non-zero
    # and prints no summary, and that was read as the suite going red on
    # purpose. Every framework in the world can fail to compile.
    It "refuses a negative probe whose run produced no readable summary" {
        $runner = New-Runner -ProbeOutput "error TS2304: cannot find name 'expect'" -ProbeExit 1
        $outcome = Invoke-Verification -Directory $script:Work -Runner $runner
        $outcome.Verification.outcome | Should -Be "toolchain_defect"
        $outcome.Verification.projects[0].negativeProbe.failedAsExpected | Should -BeFalse
        $outcome.Verification.projects[0].negativeProbe.detail | Should -BeLike "*no summary*"
    }

    It "refuses a negative probe that did not add a failing test to the suite" {
        # The suite ran four tests before the probe and four after it, so
        # whatever failed, it was not the test this stage wrote.
        $runner = New-Runner -ProbeOutput "# pass 3`n# fail 1" -ProbeExit 1
        $outcome = Invoke-Verification -Directory $script:Work -Runner $runner
        $outcome.Verification.outcome | Should -Be "toolchain_defect"
        $outcome.Verification.projects[0].negativeProbe.detail | Should -BeLike "*not the one that ran*"
    }

    It "refuses a runner that reports failed tests and still exits zero" {
        $runner = New-Runner -ProbeOutput "# pass 4`n# fail 1" -ProbeExit 0
        $outcome = Invoke-Verification -Directory $script:Work -Runner $runner
        $outcome.Verification.outcome | Should -Be "toolchain_defect"
        $outcome.Verification.projects[0].negativeProbe.detail | Should -BeLike "*exited zero*"
    }

    # A runner exits zero when everything passed and when it found nothing to
    # run. Reading the second as success is how an empty framework is delivered
    # as a verified one.
    It "refuses a run that discovered no tests" {
        $outcome = Invoke-Verification -Directory $script:Work `
            -Runner (New-Runner -TestOutput "# pass 0`n# fail 0")
        $outcome.Result.status | Should -Be "revision_required"
        $outcome.Verification.outcome | Should -Be "toolchain_defect"
        $outcome.Verification.projects[0].testsDiscovered | Should -Be 0
        @($outcome.Verification.findings.message) | Should -Contain "automation/api: the framework discovered no tests."
    }

    It "refuses a run whose summary it cannot read" {
        $outcome = Invoke-Verification -Directory $script:Work `
            -Runner (New-Runner -TestOutput "everything is fine, probably")
        $outcome.Result.status | Should -Be "revision_required"
        $outcome.Verification.outcome | Should -Be "toolchain_defect"
    }

    It 'preserves the npm startup error when no test summary was produced' {
        $outcome = Invoke-Verification -Directory $script:Work `
            -Runner (New-Runner -TestOutput 'npm error Missing script: "test"' -TestExit 1)
        $outcome.Result.status | Should -Be 'revision_required'
        $step = @($outcome.Verification.projects[0].steps | Where-Object name -eq 'test')[0]
        $step.detail | Should -Match 'Missing script: "test"'
    }

    It 'publishes the complete failing command output with a verifiable reference' {
        $output = "first failure in another file`n" + ('diagnostic line' * 400) + "`nlast failure"
        $outcome = Invoke-Verification -Directory $script:Work `
            -Runner (New-Runner -TestOutput $output -TestExit 1)
        $step = @($outcome.Verification.projects[0].steps | Where-Object name -eq 'test')[0]
        $step.detail | Should -Match 'Full output: (commands/[\w.-]+\.log) \[sha256: ([a-f0-9]{64})\]'
        $match = [regex]::Match($step.detail, 'Full output: (commands/[\w.-]+\.log) \[sha256: ([a-f0-9]{64})\]')
        $path = Join-Path $script:Work $match.Groups[1].Value
        (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() | Should -Be $match.Groups[2].Value
        Get-Content -LiteralPath $path -Raw | Should -BeExactly $output
        $outcome.Result.evidence | Should -Contain $path
        $outcome.Result.status | Should -Be 'revision_required'
    }

    # A suite that stays green against a deliberately broken expectation would
    # stay green against a real defect too.
    It "refuses a suite that cannot go red" {
        $outcome = Invoke-Verification -Directory $script:Work `
            -Runner (New-Runner -ProbeOutput "# pass 5`n# fail 0" -ProbeExit 0)
        $outcome.Result.status | Should -Be "revision_required"
        $outcome.Verification.outcome | Should -Be "toolchain_defect"
        $outcome.Verification.projects[0].negativeProbe.attempted | Should -BeTrue
        $outcome.Verification.projects[0].negativeProbe.failedAsExpected | Should -BeFalse
    }

    It 'proves one additional failing assertion without erasing pre-existing product failures' {
        $baseline = "  1) [local] › tests/product.spec.ts:12:3 › rejects bad input ─────`n# pass 4`n# fail 1"
        $probe = "  1) [local] › tests/product.spec.ts:12:3 › rejects bad input ─────`n  2) [local] › tests/probe.spec.ts:1:1 › injected failure ─────`n# pass 4`n# fail 2"
        $outcome = Invoke-Verification -Directory $script:Work -Runner (New-Runner -TestOutput $baseline -TestExit 1 -ProbeOutput $probe)
        $outcome.Verification.projects[0].negativeProbe.attempted | Should -BeTrue
        $outcome.Verification.projects[0].negativeProbe.failedAsExpected | Should -BeTrue
        $outcome.Verification.projects[0].testsFailed | Should -Be 1
        $outcome.Verification.outcome | Should -Be toolchain_defect
    }

    It 'rejects a negative probe when one baseline failure silently disappears' {
        $baseline = "  1) [local] › tests/product.spec.ts:12:3 › rejects bad input ─────`n# pass 4`n# fail 1"
        $probe = "  1) [local] › tests/other.spec.ts:12:3 › unrelated failure ─────`n  2) [local] › tests/probe.spec.ts:1:1 › injected failure ─────`n# pass 4`n# fail 2"
        $outcome = Invoke-Verification -Directory $script:Work -Runner (New-Runner -TestOutput $baseline -TestExit 1 -ProbeOutput $probe)
        $outcome.Verification.projects[0].negativeProbe.failedAsExpected | Should -BeFalse
        $outcome.Verification.projects[0].negativeProbe.detail | Should -Match 'baseline failed tests changed'
    }

    It "sends a build that does not compile back for repair" {
        $outcome = Invoke-Verification -Directory $script:Work -Runner (New-Runner -BuildExit 2)
        $outcome.Result.status | Should -Be "revision_required"
        $outcome.Verification.outcome | Should -Be "toolchain_defect"
        @($outcome.Verification.projects[0].steps | Where-Object { $_.name -eq "build" })[0].status |
            Should -Be "failed"
    }

    # An agent that could not reach a registry has not shown the design to be
    # wrong. Redesigning over it would spend the repair budget answering a
    # question nobody asked.
    It "separates an unreachable feed from a defect in the chosen technology" {
        $runner = {
            param($Executable, $Arguments, $WorkingDirectory)
            return [pscustomobject]@{
                exitCode = 1
                output = "npm error code ENOTFOUND`nnpm error request to https://registry.npmjs.org/ failed"
                durationMs = 1
            }
        }
        $outcome = Invoke-Verification -Directory $script:Work -Runner $runner
        $outcome.Result.status | Should -Be "blocked"
        $outcome.Verification.outcome | Should -Be "infrastructure_unavailable"
    }

    It 'does not regenerate tests when the filesystem prevents an installed runner from executing' {
        $runner = {
            param($Executable, $Arguments, $WorkingDirectory)
            if ($Arguments -contains 'ci') { return [pscustomobject]@{ exitCode = 0; output = ''; durationMs = 1 } }
            return [pscustomobject]@{ exitCode = 126; output = 'sh: /tmp/qaf/automation/node_modules/.bin/tsc: Permission denied'; durationMs = 1 }
        }
        $outcome = Invoke-Verification -Directory $script:Work -Runner $runner
        $outcome.Result.status | Should -Be blocked
        $outcome.Verification.outcome | Should -Be infrastructure_unavailable
        $outcome.Verification.projects[0].negativeProbe.attempted | Should -BeFalse
    }

    It "refuses a change set that carries no manifest for any locked ecosystem" {
        $directory = $script:Work
        $inputs = New-VerificationInputs -Directory $directory
        $changeSet = Get-Content -LiteralPath $inputs.ChangeSetPath -Raw | ConvertFrom-Json -Depth 40
        $changeSet.changes = @($changeSet.changes[0])
        $changeSet.changes[0].path = "automation/api/readme.md"
        $changeSet | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $inputs.ChangeSetPath -Encoding utf8

        $outputPath = Join-Path $directory "framework-verification.json"
        $result = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
            -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
            -StageId "framework-verification" -OutputPath $outputPath `
            -WorkRoot (Join-Path $directory "work") -CommandRunner (New-Runner)
        $result.status | Should -Be "revision_required"
    }

    It "refuses inputs that belong to a different run" {
        $inputs = New-VerificationInputs -Directory $script:Work
        $outputPath = Join-Path $script:Work "framework-verification.json"
        $result = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
            -ToolchainLockPath $inputs.LockPath -RunId "some-other-run" `
            -StageId "framework-verification" -OutputPath $outputPath `
            -WorkRoot (Join-Path $script:Work "work") -CommandRunner (New-Runner)
        $result.status | Should -Be "blocked"
        (Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40).outcome |
            Should -Be "not_attempted"
    }

    It "refuses a lock whose runtime block was never translated to canonical names" {
        # The config spells these node_major and npm_version; a recorded
        # toolchain spells them nodeMajor and npmVersion, because the
        # translation happens once, where the lock is written. A verification
        # that translated a second time read every pin as absent and still
        # reported the framework as verified against "Node.js 0.x". Reading a
        # pin as zero is worse than refusing to read it.
        $inputs = New-VerificationInputs -Directory $script:Work -Runtime ([ordered]@{
            node_major = 20
            npm_version = "10.8.2"
            lockfile_version = 3
        })
        $outputPath = Join-Path $script:Work "framework-verification.json"
        $result = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
            -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
            -StageId "framework-verification" -OutputPath $outputPath `
            -WorkRoot (Join-Path $script:Work "work") -CommandRunner {
                param($Executable, $Arguments, $WorkingDirectory)
                throw "Nothing may be run against a toolchain whose pins could not be read."
            }
        $result.status | Should -Be "revision_required"
        $verification = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40
        $verification.outcome | Should -Be "toolchain_defect"
        @($verification.findings.message) -join " " | Should -Match "nodeMajor"
        @($verification.projects[0].steps | Where-Object { $_.name -eq "runtime" })[0].status |
            Should -Be "failed"
    }

    It "installs nothing and executes nothing in a rehearsal, and says it proved nothing" {
        # Verification reaches a package registry and then runs code this run
        # wrote minutes earlier. A rehearsal suppresses that exactly as it
        # suppresses pushing a branch, and the artifact has to say so rather
        # than report a framework nobody executed as verified.
        $inputs = New-VerificationInputs -Directory $script:Work
        $outputPath = Join-Path $script:Work "framework-verification.json"
        $result = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
            -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
            -StageId "framework-verification" -OutputPath $outputPath `
            -WorkRoot (Join-Path $script:Work "work") -DryRun -CommandRunner {
                param($Executable, $Arguments, $WorkingDirectory)
                throw "A rehearsal must not run '$Executable'."
            }
        $result.status | Should -Be "completed"
        $result.dryRun | Should -BeTrue
        $verification = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40
        $verification.outcome | Should -Be "not_attempted"
        @($verification.projects).Count | Should -Be 0
        @($verification.findings.message) -join " " | Should -Match "rehearsal"
        # The layout directory is the first thing a real run creates, so its
        # absence is the plainest evidence that nothing was laid out or run.
        Test-Path -LiteralPath (Join-Path $script:Work "work") | Should -BeFalse
    }

    It 'delivers deferred verification without executing commands or claiming tests passed' {
        $inputs = New-VerificationInputs -Directory $script:Work
        $outputPath = Join-Path $script:Work 'framework-verification.json'
        $result = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
            -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
            -StageId framework-verification -OutputPath $outputPath `
            -WorkRoot (Join-Path $script:Work 'work') -DeferExecution -CommandRunner {
                throw 'Deferred bootstrap must not execute any command.'
            }
        $result.status | Should -Be completed
        $result.dryRun | Should -BeFalse
        $verification = Get-Content $outputPath -Raw | ConvertFrom-Json -Depth 40
        $verification.outcome | Should -Be not_attempted
        $verification.projects.Count | Should -Be 0
        ($verification.findings.message -join ' ') | Should -Match 'after delivery'
        Test-Path (Join-Path $script:Work 'work') | Should -BeFalse
    }

    It 'does not accept missing verification inputs even when execution is deferred' {
        $inputs = New-VerificationInputs -Directory $script:Work
        $result = & $script:Verifier -ChangeSetPath (Join-Path $script:Work 'missing.json') `
            -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
            -StageId framework-verification -OutputPath (Join-Path $script:Work 'framework-verification.json') `
            -WorkRoot (Join-Path $script:Work 'work') -DeferExecution -CommandRunner {
                throw 'Missing input must not execute any command.'
            }
        $result.status | Should -Be blocked
    }

    # A suite of nothing but skipped tests exits zero, and .NET prints
    # "Passed: 0, Skipped: 4, Total: 4" for it. Reading the total as the number
    # that ran turns four tests nobody executed into four passing ones.
    It "counts a skipped test as skipped rather than as one that ran" {
        $adapter = & (Get-Command New-QaFoundryNugetEcosystemAdapter)
        $summary = & $adapter.ReadTestRunSummary `
            "Skipped! - Failed: 0, Passed: 0, Skipped: 4, Total: 4 - Contoso.Tests.dll" 0
        $summary.parsed | Should -BeTrue
        $summary.total | Should -Be 4
        $summary.failed | Should -Be 0
        $summary.skipped | Should -Be 4
    }

    It "refuses a suite whose every test was skipped" {
        $outcome = Invoke-Verification -Directory $script:Work `
            -Runner (New-Runner -TestOutput "# pass 0`n# fail 0`n# skipped 4")
        $outcome.Result.status | Should -Be "revision_required"
        $outcome.Verification.outcome | Should -Be "toolchain_defect"
        # Four were found, none of them ran, and the artifact says both.
        $outcome.Verification.projects[0].testsDiscovered | Should -Be 4
        @($outcome.Verification.findings.message) -join " " | Should -Match "skipped"
    }

    # The probe is a source file written after the build step ran. Running the
    # binary built before it existed reports the same suite as a moment ago, and
    # a sound framework is sent back to be rewritten.
    It "compiles the .NET negative probe before running it" {
        $adapter = & (Get-Command New-QaFoundryNugetEcosystemAdapter)
        $toolchain = [pscustomobject]@{
            runtime = [pscustomobject]@{ sdkMajor = 10; targetFramework = "net8.0" }
            packages = @([pscustomobject]@{ name = "xunit"; version = "2.9.2" })
        }
        $probe = & $adapter.GetNegativeProbeTestCommand $toolchain "C:\work\automation"
        @($probe.arguments) | Should -Not -Contain "--no-build"
        # Restore is still skipped: the lock this project was installed under
        # stands, and the probe adds a file, not a dependency.
        @($probe.arguments) | Should -Contain "--no-restore"

        # The ordinary run is the opposite case: the build step ran moments ago
        # and rebuilding it would only cost time.
        $test = & $adapter.GetTestCommand $toolchain "C:\work\automation"
        @($test.arguments) | Should -Contain "--no-build"
    }

    # Microsoft.Testing.Platform - the runner every new .NET template uses -
    # prints its counts one per line instead of on the single "Passed! - Failed:"
    # line the old VSTest runner wrote. A reader that only knows the old shape
    # sees no numbers at all and has to decide what a zero-exit run with no
    # counts meant.
    It "reads the counts the new .NET test platform prints one per line" {
        $adapter = & (Get-Command New-QaFoundryNugetEcosystemAdapter)
        $output = @(
            "Test run summary: Passed! - Contoso.Tests.dll (net8.0|x64)",
            "  total: 12",
            "  failed: 0",
            "  succeeded: 9",
            "  skipped: 3",
            "  duration: 1s"
        ) -join "`n"
        $summary = & $adapter.ReadTestRunSummary $output 0
        $summary.parsed | Should -BeTrue
        $summary.total | Should -Be 12
        $summary.failed | Should -Be 0
        $summary.skipped | Should -Be 3
    }

    # -match replaces $Matches wholesale. Reading the totals out of it after
    # matching the pending line reports whatever that line captured, so a suite
    # with one pending example was read as a suite of one test.
    It "keeps the RSpec totals when the run also reports pending examples" {
        $adapter = & (Get-Command New-QaFoundryRubygemsEcosystemAdapter)
        $output = @(
            "Pending: (Failures listed here are expected and do not affect your suite's status)",
            "  1) Widget is not written yet",
            "",
            "31 examples, 0 failures, 2 pending"
        ) -join "`n"
        $summary = & $adapter.ReadTestRunSummary $output 0
        $summary.parsed | Should -BeTrue
        $summary.total | Should -Be 31
        $summary.failed | Should -Be 0
        $summary.skipped | Should -Be 2
    }

    # The one place in this runtime that executes code an agent wrote minutes
    # ago. A child that inherits this process's environment inherits the run's
    # delivery credentials with it.
    It "hides the run's credentials from the code it was asked to prove" {
        $inputs = New-VerificationInputs -Directory $script:Work
        $workRoot = Join-Path $script:Work "isolation-work"
        $previous = [Environment]::GetEnvironmentVariable("SYSTEM_ACCESSTOKEN")
        try {
            [Environment]::SetEnvironmentVariable("SYSTEM_ACCESSTOKEN", "ado-delivery-token")

            # Dot-sourced so the real function is exercised rather than a copy of
            # it. The rehearsal switch makes the load itself install and run
            # nothing.
            . $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
                -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
                -StageId "framework-verification" `
                -OutputPath (Join-Path $script:Work "isolation-verification.json") `
                -WorkRoot $workRoot -DryRun | Out-Null

            # Populated from this process by default, which is exactly the
            # inheritance being closed.
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.EnvironmentVariables.ContainsKey("SYSTEM_ACCESSTOKEN") | Should -BeTrue

            Set-VerificationEnvironment -StartInfo $startInfo -Command ([pscustomobject]@{
                environment = [pscustomobject]@{
                    PLAYWRIGHT_BROWSERS_PATH = "browsers"
                    # An ecosystem must not be able to undo the isolation by
                    # naming a variable this function already set.
                    HOME = "C:\the-agents-real-profile"
                    NUGET_PACKAGES = "C:\the-agents-real-profile\.nuget\packages"
                }
            })

            $startInfo.EnvironmentVariables.ContainsKey("SYSTEM_ACCESSTOKEN") | Should -BeFalse
            $startInfo.EnvironmentVariables["HOME"] | Should -BeLike "$workRoot*"
            $startInfo.EnvironmentVariables["USERPROFILE"] | Should -BeLike "$workRoot*"
            $startInfo.EnvironmentVariables["TEMP"] | Should -BeLike "$workRoot*"
            $startInfo.EnvironmentVariables["CI"] | Should -Be "true"
            # What a compiler genuinely needs still arrives, or nothing would run.
            $startInfo.EnvironmentVariables["PATH"] | Should -Not -BeNullOrEmpty
            $startInfo.EnvironmentVariables["PLAYWRIGHT_BROWSERS_PATH"] | Should -Be "browsers"
            # Where a package manager keeps what it downloaded is the isolation's
            # to decide, not an ecosystem's: a cache in the agent's profile sits
            # beside the credentials all of this exists to keep out of reach, and
            # in container mode it would not survive to the next command either.
            $startInfo.EnvironmentVariables["NUGET_PACKAGES"] | Should -BeLike "$workRoot*"
            foreach ($name in @("npm_config_cache", "PIP_CACHE_DIR", "GRADLE_USER_HOME",
                "GOPATH", "GOMODCACHE", "GOCACHE", "CARGO_HOME")) {
                $startInfo.EnvironmentVariables[$name] | Should -BeLike "$workRoot*" `
                    -Because "$name has to stay inside the work root"
            }
            # Emptying the environment leaves the credentials that live in files.
            # Each tool that reads one is pointed at a path inside the isolated
            # home, which holds nothing.
            foreach ($name in @(
                "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "NETRC",
                "npm_config_userconfig", "npm_config_globalconfig",
                "COMPOSER_HOME", "BUNDLE_USER_HOME", "DOTNET_CLI_HOME",
                "APPDATA", "LOCALAPPDATA", "XDG_CONFIG_HOME")) {
                $startInfo.EnvironmentVariables[$name] | Should -BeLike "$workRoot*" `
                    -Because "$name would otherwise resolve against the agent's own profile"
            }
            Test-Path $startInfo.EnvironmentVariables["GIT_CONFIG_GLOBAL"] | Should -BeFalse
            $startInfo.EnvironmentVariables["GIT_TERMINAL_PROMPT"] | Should -Be "0"
            # pip treats a configuration file that does not exist as no
            # instruction at all and reads the global, user and site files
            # anyway. Only the null device stops it.
            $startInfo.EnvironmentVariables["PIP_CONFIG_FILE"] |
                Should -Be $(if ($IsWindows) { "NUL" } else { "/dev/null" })
            # Maven finds '~/.m2/settings.xml' through the JVM's user.home, which
            # HOME does not move on Windows.
            $startInfo.EnvironmentVariables["MAVEN_OPTS"] | Should -Match "user\.home"
            $startInfo.EnvironmentVariables["MAVEN_OPTS"] | Should -Match ([regex]::Escape($workRoot))
        }
        finally {
            [Environment]::SetEnvironmentVariable("SYSTEM_ACCESSTOKEN", $previous)
        }
    }

    Context "and saying what that isolation does not cover" {
        # The environment is built rather than inherited, which closes every path
        # a package manager takes by default. It does not change who the child
        # runs as, and a boundary described as complete is the one nobody checks
        # - so the run states in its own evidence which of the two it got.
        It "records that a child process shares this run's user and says so plainly" {
            $directory = Join-Path $script:Work "isolation-recorded"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $inputs = New-VerificationInputs -Directory $directory
            $outputPath = Join-Path $directory "framework-verification.json"

            $null = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
                -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
                -StageId "framework-verification" -OutputPath $outputPath `
                -WorkRoot (Join-Path $directory "work") -CommandRunner (New-Runner)

            $verification = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40
            [string]$verification.isolation.mode | Should -Be "process"
            (@($verification.isolation.limitations) -join " ") |
                Should -Match "same operating system user"
            (@($verification.isolation.limitations) -join " ") | Should -Match "container"
            # The artifact has to satisfy its own schema, which is where a field
            # the writer always produces and the contract forbids gets caught.
            {
                & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                    -ArtifactPath $outputPath `
                    -SchemaPath (Join-Path $script:Root "schemas/runtime/framework-verification.schema.json") `
                    -SchemaRoot (Join-Path $script:Root "schemas")
            } | Should -Not -Throw
        }

        It "stops rather than run unisolated when a container was asked for and there is none" {
            # No fallback on purpose. A run that believes it is isolated and is
            # not is worse than one that refuses: the setting exists because
            # somebody decided this code is not to be trusted with the machine.
            $directory = Join-Path $script:Work "isolation-missing-runtime"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $inputs = New-VerificationInputs -Directory $directory

            {
                & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
                    -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
                    -StageId "framework-verification" `
                    -OutputPath (Join-Path $directory "framework-verification.json") `
                    -WorkRoot (Join-Path $directory "work") -CommandRunner (New-Runner) `
                    -Isolation ([pscustomobject]@{
                        mode = "container"
                        container = [pscustomobject]@{
                            executable = "no-such-container-runtime"; image = "example/image:1"
                        }
                    })
            } | Should -Throw "*is not installed on this agent*"
        }

        It "refuses a container that names no image rather than choosing one" {
            $directory = Join-Path $script:Work "isolation-no-image"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $inputs = New-VerificationInputs -Directory $directory

            {
                & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
                    -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
                    -StageId "framework-verification" `
                    -OutputPath (Join-Path $directory "framework-verification.json") `
                    -WorkRoot (Join-Path $directory "work") -CommandRunner (New-Runner) `
                    -Isolation ([pscustomobject]@{
                        mode = "container"
                        container = [pscustomobject]@{ executable = "docker"; image = "" }
                    })
            } | Should -Throw "*Neither can be guessed*"
        }

        It "refuses an isolation mode this runtime does not implement" {            $directory = Join-Path $script:Work "isolation-unknown-mode"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $inputs = New-VerificationInputs -Directory $directory

            {
                & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
                    -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
                    -StageId "framework-verification" `
                    -OutputPath (Join-Path $directory "framework-verification.json") `
                    -WorkRoot (Join-Path $directory "work") -CommandRunner (New-Runner) `
                    -Isolation ([pscustomobject]@{ mode = "chroot" })
            } | Should -Throw "*is not one this runtime implements*"
        }

        It "runs the framework in the container, mounting the work root and nothing else" {
            # 'node' stands in for a container runtime here only because it is
            # certainly installed: what is under test is the command this builds,
            # not what a daemon does with it.
            $directory = Join-Path $script:Work "isolation-container-command"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $inputs = New-VerificationInputs -Directory $directory
            $workRoot = Join-Path $directory "work"
            $outputPath = Join-Path $directory "framework-verification.json"
            $global:ContainerInvocations = [System.Collections.Generic.List[string]]::new()

            $null = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
                -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
                -StageId "framework-verification" -OutputPath $outputPath `
                -WorkRoot $workRoot `
                -Isolation ([pscustomobject]@{
                    mode = "container"
                    container = [pscustomobject]@{
                        executable = "node"; image = "example/sdk:1"; network = "none"
                        extra_args = @("--read-only")
                    }
                }) `
                -CommandRunner {
                    param($Executable, $Arguments, $WorkingDirectory)
                    $global:ContainerInvocations.Add(
                        "$Executable " + (@($Arguments) -join " "))
                    return [pscustomobject]@{ exitCode = 0; output = "# pass 3`n# fail 0"; durationMs = 1 }
                }

            $first = $global:ContainerInvocations[0]
            $first | Should -Match "run --rm --name qa-foundry-verify-[0-9a-f]{12} --network none --volume "
            $first | Should -BeLike "*:/qa-foundry/work --workdir /qa-foundry/work*"
            # Everything an ecosystem asked for still reaches the container, by
            # name rather than by inheritance.
            $first | Should -Match "--env CI=true"
            # The host's own paths would be wrong inside the image, which brings
            # its own, so they are the ones not forwarded.
            $first | Should -Not -Match "--env PATH="
            $first | Should -Not -Match "--env HOME="
            # Site arguments are added last of all, after the mount and the
            # environment, so they cannot remove either.
            $first | Should -Match "--read-only example/sdk:1 "

            $verification = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40
            [string]$verification.isolation.mode | Should -Be "container"
            (@($verification.isolation.limitations) -join " ") | Should -Match "Only the work root is mounted"
            {
                & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                    -ArtifactPath $outputPath `
                    -SchemaPath (Join-Path $script:Root "schemas/runtime/framework-verification.schema.json") `
                    -SchemaRoot (Join-Path $script:Root "schemas")
            } | Should -Not -Throw
            Remove-Variable -Name ContainerInvocations -Scope Global -ErrorAction SilentlyContinue
        }

        It "removes the container when the run it started had to be killed" {
            # Killing 'docker run' ends the client. The daemon goes on running
            # what it started, still holding the work directory the next attempt
            # writes into, and '--rm' does not fire because the container never
            # exited. This runs the real process path - no command seam - against
            # a client that hangs, so the kill is a real kill.
            $directory = Join-Path $script:Work "isolation-container-timeout"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $inputs = New-VerificationInputs -Directory $directory
            $outputPath = Join-Path $directory "framework-verification.json"
            $clientName = if ($IsWindows) { "hanging-client.cmd" } else { "hanging-client.sh" }
            $hangingClient = Join-Path $directory $clientName
            if ($IsWindows) {
                "@echo off`r`nping -n 60 127.0.0.1 > nul" |
                    Set-Content -LiteralPath $hangingClient -Encoding ascii
            }
            else {
                "#!/bin/sh`nsleep 60" | Set-Content -LiteralPath $hangingClient -Encoding ascii
                & chmod +x $hangingClient
            }
            $global:RemovedContainers = [System.Collections.Generic.List[string]]::new()

            $null = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
                -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
                -StageId "framework-verification" -OutputPath $outputPath `
                -WorkRoot (Join-Path $directory "work") `
                -Deadline ([datetime]::UtcNow.AddSeconds(123)) `
                -Isolation ([pscustomobject]@{
                    mode = "container"
                    container = [pscustomobject]@{
                        executable = $hangingClient; image = "example/sdk:1"; network = "none"
                    }
                }) `
                -ContainerRemover {
                    param($Executable, $Name)
                    $global:RemovedContainers.Add("$Executable rm --force $Name")
                    return " The container '$Name' was removed."
                }

            @($global:RemovedContainers).Count | Should -BeGreaterThan 0
            # The name it removes is the name it started the container under,
            # which is the only handle a killed client leaves behind.
            $global:RemovedContainers[0] |
                Should -Match "rm --force qa-foundry-verify-[0-9a-f]{12}$"

            $verification = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40
            [string]$verification.outcome | Should -Not -Be "verified"
            $reported = (@($verification.projects[0].steps) |
                ForEach-Object { [string]$_.detail }) -join " "
            $reported | Should -Match "was removed"
            Remove-Variable -Name RemovedContainers -Scope Global -ErrorAction SilentlyContinue
        }

        It "refuses to start a command once the stage deadline has passed" {
            # The other half of the same comparison. It is asserted with a UTC
            # deadline because that is what the runtime builds, and reading it
            # against local time is what made this stage refuse every command on
            # an agent that was not set to UTC.
            $directory = Join-Path $script:Work "isolation-deadline-passed"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $inputs = New-VerificationInputs -Directory $directory
            $outputPath = Join-Path $directory "framework-verification.json"

            {
                & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
                    -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
                    -StageId "framework-verification" -OutputPath $outputPath `
                    -WorkRoot (Join-Path $directory "work") `
                    -Deadline ([datetime]::UtcNow.AddMinutes(-1)) `
                    -CommandRunner {
                        param($Executable, $Arguments, $WorkingDirectory)
                        return [pscustomobject]@{ exitCode = 0; output = ""; durationMs = 1 }
                    }
            } | Should -Throw "*deadline passed*"
        }

        It "keeps what one command downloaded for the command that comes after it" {
            # Reading the arguments proves the arguments were built. It does not
            # prove a package manager can do anything with them, and that is
            # where container mode failed: every path in the environment named a
            # place on the agent, and every command was its own throwaway
            # container, so whatever the install step downloaded was gone by the
            # time the build step - told not to fetch anything again - looked for
            # it. So this runs the real sequence, install then build then test
            # then the negative probe, through a runtime that refuses a host path
            # and discards everything outside the mount, exactly as '--rm' does.
            $directory = Join-Path $script:Work "isolation-container-sequence"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $manifest = @(
                '{"name":"api","version":"1.0.0","private":true,"scripts":{',
                '"build":"node tools/seed-cache.mjs","test":"node --test --test-reporter=tap"}}'
            ) -join ""
            $lock = @(
                '{"name":"api","version":"1.0.0","lockfileVersion":3,"requires":true,',
                '"packages":{"":{"name":"api","version":"1.0.0"}}}'
            ) -join ""
            # Stands in for a restore: it writes into the package cache the
            # environment names, which is the thing a throwaway container loses.
            $seed = @(
                'import { mkdirSync, writeFileSync } from "node:fs";',
                'import { join } from "node:path";',
                'const cache = process.env.npm_config_cache;',
                'if (!cache) { console.error("npm_config_cache was not set"); process.exit(2); }',
                'mkdirSync(cache, { recursive: true });',
                'writeFileSync(join(cache, "foundry-marker.txt"), "downloaded");'
            ) -join "`n"
            $suite = @(
                'import assert from "node:assert/strict";',
                'import { existsSync } from "node:fs";',
                'import { join } from "node:path";',
                'import { test } from "node:test";',
                'test("the package cache outlived the command that filled it", () => {',
                '  const cache = process.env.npm_config_cache;',
                '  assert.ok(cache, "npm_config_cache was not set");',
                '  assert.ok(existsSync(join(cache, "foundry-marker.txt")),',
                '    `the cache at ${cache} lost what an earlier command put there`);',
                '});'
            ) -join "`n"
            $newChange = {
                param([string]$Path, [string]$Content)
                return [ordered]@{
                    operation = "create"; path = $Path; expectedSha256 = ""; content = $Content
                    reason = "Container sequence fixture."; sourceRefs = @("automation-blueprint.json")
                }
            }
            $inputs = New-VerificationInputs -Directory $directory -Changes @(
                (& $newChange "automation/api/package.json" $manifest),
                (& $newChange "automation/api/package-lock.json" $lock),
                (& $newChange "automation/api/tools/seed-cache.mjs" $seed),
                (& $newChange "automation/api/tests/cache.test.mjs" $suite)
            )
            $outputPath = Join-Path $directory "framework-verification.json"
            $global:FakeContainer = (Resolve-Path (
                Join-Path $script:Root "tests/fixtures/fake-container.mjs")).Path

            $null = & $script:Verifier -ChangeSetPath $inputs.ChangeSetPath `
                -ToolchainLockPath $inputs.LockPath -RunId $inputs.RunId `
                -StageId "framework-verification" -OutputPath $outputPath `
                -WorkRoot (Join-Path $directory "work") `
                -Isolation ([pscustomobject]@{
                    mode = "container"
                    container = [pscustomobject]@{
                        executable = "node"; image = "example/sdk:1"; network = "none"
                    }
                }) `
                -CommandRunner {
                    param($Executable, $Arguments, $WorkingDirectory)
                    # The seam stands for starting the process, and what it
                    # starts is the command that was built, unchanged. Only the
                    # runtime that would receive it is the fixture.
                    $text = (& node $global:FakeContainer @Arguments 2>&1 | Out-String)
                    return [pscustomobject]@{
                        exitCode = $LASTEXITCODE; output = $text; durationMs = 1
                    }
                }

            $verification = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 40
            $steps = @($verification.projects[0].steps)
            $named = @{}
            foreach ($step in $steps) { $named[[string]$step.name] = $step }
            # Named one at a time: a sequence asserted only on its outcome says
            # nothing about which command was the one that could not run.
            foreach ($name in @("install", "build", "test", "negative_probe")) {
                $named.ContainsKey($name) | Should -BeTrue -Because "$name has to have run"
                [string]$named[$name].status | Should -Be "passed" -Because (
                    "$name reported: $([string]$named[$name].detail)")
            }
            [string]$verification.outcome | Should -Be "verified"
            [string]$verification.isolation.mode | Should -Be "container"
            Remove-Variable -Name FakeContainer -Scope Global -ErrorAction SilentlyContinue
        }
    }
}

Describe "Reading the runtime a design was written for" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        . (Join-Path $script:Root "scripts/Common.ps1")
    }

    It 'keeps the primary runtime version ahead of tool annotations: <Version>' -ForEach @(
        @{Version='22 (npm 10.9.4)'; Expected='22'},
        @{Version='Node.js 22 with npm 10.9.4'; Expected='22'},
        @{Version='22.18.0 (npm 10.9.4)'; Expected='22.18.0'},
        @{Version='net8.0 on SDK 10'; Expected='8.0'},
        @{Version='3.12 (pip 25.1)'; Expected='3.12'},
        @{Version='JDK 21 with Maven 3.9.9'; Expected='21'}
    ) {
        Get-QaFoundryProposedRuntimeVersion -Name runtime -Version $Version | Should -Be $Expected
    }

    It 'accepts Node 22 with an npm annotation without accepting a different Node major' {
        $npm = Get-QaFoundryEcosystemAdapter -Ecosystem npm
        $canonical = @{nodeMajor=22; npmVersion='10.9.4'}
        $resolved = & $npm.ResolveProposedRuntime $null $canonical 'Node.js' '22 (npm 10.9.4)'
        $resolved.nodeMajor | Should -Be 22
        $resolved.npmVersion | Should -Be '10.9.4'
        { & $npm.ResolveProposedRuntime $null $canonical 'Node.js' '24 (npm 10.9.4)' } |
            Should -Throw '*written for Node 24*'
    }

    # 'LTS', 'current' and 'latest' name a moving target. Read as "no version
    # stated", the configured one stood in for it and the run reported a design
    # verified against a runtime nobody had asked for.
    It "refuses a runtime version it cannot check against the installed one" {
        $npm = Get-QaFoundryEcosystemAdapter -Ecosystem "npm"
        $canonical = @{ nodeMajor = 22; npmVersion = "10.9.4" }
        foreach ($unreadable in @("LTS", "current", "latest")) {
            { & $npm.ResolveProposedRuntime $null $canonical "Node.js" $unreadable } |
                Should -Throw "*names no version this runtime can check*"
        }

        $nuget = Get-QaFoundryEcosystemAdapter -Ecosystem "nuget"
        { & $nuget.ResolveProposedRuntime $null @{ sdkMajor = 10; targetFramework = "net10.0" } `
            ".NET" "latest" } | Should -Throw "*names no version this runtime can check*"
    }

    # A stated version decides on its own. Reading the name when the version
    # could not be parsed accepted 'latest' as Node 22 whenever the name happened
    # to carry a number - a version nobody stated and nothing checked.
    It "does not read a version out of the runtime's name when one was stated" {
        Get-QaFoundryProposedRuntimeVersion -Name "Node.js 22" -Version "latest" |
            Should -BeNullOrEmpty
        # With no version stated the name is still where the number comes from,
        # which is how 'net10.0' has always been read.
        Get-QaFoundryProposedRuntimeVersion -Name "net10.0" -Version "" | Should -Be "10.0"

        $npm = Get-QaFoundryEcosystemAdapter -Ecosystem "npm"
        { & $npm.ResolveProposedRuntime $null @{ nodeMajor = 22; npmVersion = "10.9.4" } `
            "Node.js 22" "latest" } | Should -Throw "*names no version this runtime can check*"
    }

    # The runtime's own name states an identity, not a version, so a design that
    # names 'node' and no number has asked for nothing that needs checking.
    It "accepts a design that names the runtime without pinning a version" {
        $npm = Get-QaFoundryEcosystemAdapter -Ecosystem "npm"
        $canonical = @{ nodeMajor = 22; npmVersion = "10.9.4" }
        $resolved = & $npm.ResolveProposedRuntime $null $canonical "node" ""
        [int]$resolved["nodeMajor"] | Should -Be 22
    }

    It "still refuses a design written for a different major version" {
        $npm = Get-QaFoundryEcosystemAdapter -Ecosystem "npm"
        { & $npm.ResolveProposedRuntime $null @{ nodeMajor = 22; npmVersion = "10.9.4" } `
            "Node.js" "24" } | Should -Throw "*written for Node 24*"
    }
}

Describe "Carrying the technology decision out of the run" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        . (Join-Path $script:Root "scripts/Common.ps1")

        function New-BlueprintRun {
            param(
                [Parameter(Mandatory)][string]$Directory,
                [bool]$Deviates = $false,
                [string]$Status = "completed"
            )
            $stageDirectory = Join-Path $Directory "architecture"
            New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
            $toolchain = [ordered]@{
                detectedStack = [ordered]@{
                    language = "C#"
                    runtime = "net8.0"
                    buildSystem = "dotnet"
                    evidence = @("src/Api/Api.csproj", "global.json")
                }
                ecosystem = "nuget"
                language = "C#"
                runtime = [ordered]@{ name = "dotnet"; version = "8.0" }
                testFramework = "xunit"
                packages = @()
                coverageFit = @()
                alternativesRejected = @(
                    [ordered]@{ option = "TypeScript and Playwright"; reason = "No capability the .NET stack lacks." }
                )
                ciRequirements = @(".NET SDK 8 on the agent")
                deviatesFromDetectedStack = $Deviates
            }
            if ($Deviates) { $toolchain["deviationReason"] = "The product has no HTTP/2 client." }
            $blueprint = [ordered]@{
                agentId = "automation-architect"
                stageId = "architecture"
                runId = "run-narrative"
                status = $Status
                summary = "Blueprint."
                evidence = @()
                assumptions = @()
                unknowns = @()
                warnings = @()
                details = [ordered]@{
                    automationProjects = @(
                        [ordered]@{
                            name = "Contoso.Automation.Api"
                            path = "automation/api"
                            purpose = "API coverage."
                            toolchain = $toolchain
                        }
                    )
                }
            }
            $blueprint | ConvertTo-Json -Depth 40 |
                Set-Content -LiteralPath (Join-Path $stageDirectory "automation-blueprint.json") -Encoding utf8
        }
    }

    BeforeEach {
        $script:RunRoot = Join-Path ([IO.Path]::GetTempPath()) ("foundry-narrative-" + [guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Path $script:RunRoot -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:RunRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "renders the decision with the evidence it was made from" {
        New-BlueprintRun -Directory $script:RunRoot
        $narrative = @(Get-QaFoundryToolchainNarrative -RunRoot $script:RunRoot) -join "`n"
        $narrative | Should -Match "Why this technology"
        $narrative | Should -Match "Contoso\.Automation\.Api"
        $narrative | Should -Match "src/Api/Api\.csproj"
        $narrative | Should -Match "Rejected TypeScript and Playwright"
    }

    It "says out loud when the automation is not in the product's technology" {
        New-BlueprintRun -Directory $script:RunRoot -Deviates $true
        $narrative = @(Get-QaFoundryToolchainNarrative -RunRoot $script:RunRoot) -join "`n"
        $narrative | Should -Match "Deviates from the product's stack"
        $narrative | Should -Match "no HTTP/2 client"
    }

    # A rejected revision left on disk would put a rationale nobody accepted in
    # front of the person reviewing the pull request.
    It "ignores a blueprint that was never approved" {
        New-BlueprintRun -Directory $script:RunRoot -Status "blocked"
        @(Get-QaFoundryToolchainNarrative -RunRoot $script:RunRoot).Count | Should -Be 0
    }
}

Describe "Applying the programme's refusals to everything that would be installed" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        . (Join-Path $script:Root "scripts/Common.ps1")
        $script:VerifyLock = Join-Path $script:Root "scripts/actions/Test-EcosystemLock.ps1"
        $script:Registry = "https://registry.npmjs.org"

        $script:NpmToolchain = [pscustomobject]@{
            id = "npm-vitest"
            ecosystem = "npm"
            source = [pscustomobject]@{ id = "npm-public"; registry = $script:Registry; authentication = "none" }
            runtime = [pscustomobject]@{ nodeMajor = 22; npmVersion = "10.9.4"; lockfileVersion = 3 }
            packages = @([pscustomobject]@{
                key = "vitest"; name = "vitest"; version = "3.2.4"; scope = "dev"; requested = "^3.2.0"
            })
        }

        # One approved direct package and one package it drags in. The refused
        # thing is always the second kind, because that is how a dependency
        # nobody chose actually arrives.
        function script:New-NpmLockJson {
            param([hashtable]$TransitiveOverride = @{}, [hashtable]$DirectOverride = @{})
            $direct = [ordered]@{
                version = "3.2.4"
                resolved = "$script:Registry/vitest/-/vitest-3.2.4.tgz"
                integrity = "sha512-" + ("a" * 86) + "=="
                license = "MIT"
            }
            foreach ($key in $DirectOverride.Keys) {
                if ($null -eq $DirectOverride[$key]) { $direct.Remove($key) } else { $direct[$key] = $DirectOverride[$key] }
            }
            $transitive = [ordered]@{
                version = "2.0.0"
                resolved = "$script:Registry/tinyrainbow/-/tinyrainbow-2.0.0.tgz"
                integrity = "sha512-" + ("b" * 86) + "=="
                license = "MIT"
            }
            foreach ($key in $TransitiveOverride.Keys) {
                if ($null -eq $TransitiveOverride[$key]) { $transitive.Remove($key) } else { $transitive[$key] = $TransitiveOverride[$key] }
            }
            return ([ordered]@{
                name = "automation"
                version = "0.0.0"
                lockfileVersion = 3
                requires = $true
                packages = [ordered]@{
                    "" = [ordered]@{
                        name = "automation"; version = "0.0.0"
                        devDependencies = [ordered]@{ vitest = "3.2.4" }
                    }
                    "node_modules/vitest" = $direct
                    "node_modules/tinyrainbow" = $transitive
                }
            } | ConvertTo-Json -Depth 30)
        }

        function script:Invoke-LockVerification {
            param(
                [string]$LockJson,
                [AllowNull()]$Policy,
                $Toolchain = $script:NpmToolchain,
                [string]$ManifestName = "automation",
                [string]$ManifestVersion = "0.0.0"
            )
            return & $script:VerifyLock -LockJson $LockJson -Toolchain $Toolchain `
                -ManifestName $ManifestName -ManifestVersion $ManifestVersion -PackagePolicy $Policy
        }

        function script:New-Policy {
            param([string[]]$DeniedPackages = @(), [string[]]$DeniedLicenses = @())
            return [pscustomobject]@{
                maxDirectPackages = 12
                allowPrerelease = $false
                deniedPackages = @($DeniedPackages)
                deniedLicenses = @($DeniedLicenses)
            }
        }
    }

    It "accepts a lock that breaks no rule" {
        $verdict = Invoke-LockVerification -LockJson (New-NpmLockJson) -Policy (New-Policy)
        @($verdict.findings) | Should -BeNullOrEmpty
        $verdict.accepted | Should -BeTrue
    }

    # The check used to run only where an agent named a package, so a refused
    # package arriving as somebody else's dependency was installed anyway.
    It "refuses a package the programme forbids even when nobody asked for it" {
        $verdict = Invoke-LockVerification -LockJson (New-NpmLockJson) `
            -Policy (New-Policy -DeniedPackages @("tinyrainbow"))
        $verdict.accepted | Should -BeFalse
        (@($verdict.findings) -join " ") | Should -Match "tinyrainbow 2\.0\.0"
        (@($verdict.findings) -join " ") | Should -Match "chosen directly or pulled in by something else"
    }

    It "reads a refused name by the registry's own rule about identity" {
        # npm serves a name as published, so the refusal of "TinyRainbow" is a
        # refusal of a package this lock does not contain.
        $verdict = Invoke-LockVerification -LockJson (New-NpmLockJson) `
            -Policy (New-Policy -DeniedPackages @("TinyRainbow"))
        $verdict.accepted | Should -BeTrue
    }

    It "refuses a transitive package under a licence the programme forbids" {
        $lock = New-NpmLockJson -TransitiveOverride @{ license = "AGPL-3.0-or-later" }
        $verdict = Invoke-LockVerification -LockJson $lock `
            -Policy (New-Policy -DeniedLicenses @("AGPL-3.0-or-later"))
        $verdict.accepted | Should -BeFalse
        (@($verdict.findings) -join " ") | Should -Match "tinyrainbow \(AGPL-3\.0-or-later\)"
    }

    It "reads a refused licence out of a choice of licences" {
        $lock = New-NpmLockJson -TransitiveOverride @{ license = "(MIT OR GPL-3.0-only)" }
        $verdict = Invoke-LockVerification -LockJson $lock `
            -Policy (New-Policy -DeniedLicenses @("GPL-3.0-only"))
        $verdict.accepted | Should -BeFalse
        (@($verdict.findings) -join " ") | Should -Match "GPL-3\.0-only"
    }

    It "compares licence identifiers rather than searching for the text of one" {
        # "GPL-3.0-only" is a substring of "LGPL-3.0-only" and a different
        # licence, so a refusal of the first must not catch the second.
        $lock = New-NpmLockJson -TransitiveOverride @{ license = "LGPL-3.0-only" }
        $verdict = Invoke-LockVerification -LockJson $lock `
            -Policy (New-Policy -DeniedLicenses @("GPL-3.0-only"))
        $verdict.accepted | Should -BeTrue
    }

    # A package whose licence the lock does not state is one whose terms nobody
    # has read. With a policy in force that is a gap, not a pass.
    It "refuses to conclude anything about a package that states no licence" {
        $lock = New-NpmLockJson -TransitiveOverride @{ license = $null }
        $verdict = Invoke-LockVerification -LockJson $lock `
            -Policy (New-Policy -DeniedLicenses @("AGPL-3.0-or-later"))
        $verdict.accepted | Should -BeFalse
        (@($verdict.findings) -join " ") | Should -Match "states no licence for tinyrainbow"
    }

    It "says nothing about licences when the programme refuses none" {
        $lock = New-NpmLockJson -TransitiveOverride @{ license = $null }
        $verdict = Invoke-LockVerification -LockJson $lock -Policy (New-Policy)
        $verdict.accepted | Should -BeTrue
    }

    # NuGet's lock records no licence and there is nowhere else in the run to
    # learn one from. Reporting "nothing refused" would be the one reading that
    # is certainly wrong.
    It "fails closed where the lock format records no licence at all" {
        $nugetToolchain = [pscustomobject]@{
            id = "nuget-xunit"
            ecosystem = "nuget"
            source = [pscustomobject]@{ id = "nuget-public"; registry = "https://api.nuget.org/v3/index.json"; authentication = "none" }
            runtime = [pscustomobject]@{ sdkMajor = 8; targetFramework = "net8.0" }
            packages = @([pscustomobject]@{ key = "xunit"; name = "xunit"; version = "2.9.2"; scope = "runtime"; requested = "2.9.2" })
        }
        $contentHash = [Convert]::ToBase64String((1..64 | ForEach-Object { [byte]($_ % 256) }))
        $lock = ([ordered]@{
            version = 1
            dependencies = [ordered]@{
                "net8.0" = [ordered]@{
                    xunit = [ordered]@{
                        type = "Direct"; requested = "[2.9.2, )"; resolved = "2.9.2"; contentHash = $contentHash
                    }
                }
            }
        } | ConvertTo-Json -Depth 30)

        # A NuGet lock records no project identity of its own, so nothing is
        # claimed about one here.
        $permitted = Invoke-LockVerification -LockJson $lock -Policy (New-Policy) `
            -Toolchain $nugetToolchain -ManifestName "" -ManifestVersion ""
        $permitted.accepted | Should -BeTrue

        $refused = Invoke-LockVerification -LockJson $lock `
            -Policy (New-Policy -DeniedLicenses @("AGPL-3.0-or-later")) -Toolchain $nugetToolchain `
            -ManifestName "" -ManifestVersion ""
        $refused.accepted | Should -BeFalse
        (@($refused.findings) -join " ") | Should -Match "records no licence for the packages it pins"
        (@($refused.findings) -join " ") | Should -Match "guessing is not one of the options"
    }

    It "still verifies a lock when no policy is handed to it" {
        $verdict = & $script:VerifyLock -LockJson (New-NpmLockJson) -Toolchain $script:NpmToolchain `
            -ManifestName "automation" -ManifestVersion "0.0.0"
        $verdict.accepted | Should -BeTrue
    }
}

Describe "Holding an install to the lock when the installer will not" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        . (Join-Path $script:Root "scripts/Common.ps1")
        $script:Maven = Get-QaFoundryEcosystemAdapter -Ecosystem "maven"

        # A repository laid out the way Maven lays one out, so the coordinate can
        # be read back off the path exactly as the lock writer read it.
        function script:New-Artefact {
            param(
                [string]$ProjectPath,
                [string]$GroupId,
                [string]$ArtifactId,
                [string]$Version,
                [string]$Content
            )
            $directory = Join-Path (Join-Path $ProjectPath ".m2-repo") (
                ((($GroupId -split "\.") + @($ArtifactId, $Version)) -join [IO.Path]::DirectorySeparatorChar))
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $jar = Join-Path $directory "$ArtifactId-$Version.jar"
            Set-Content -LiteralPath $jar -Value $Content -Encoding utf8 -NoNewline
            return $jar
        }

        function script:New-Project {
            param([switch]$WithoutRepository)
            $path = Join-Path ([IO.Path]::GetTempPath()) ("qaf-maven-" + [guid]::NewGuid().ToString("n"))
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            if (-not $WithoutRepository) {
                New-Item -ItemType Directory -Path (Join-Path $path ".m2-repo") -Force | Out-Null
            }
            return $path
        }

        function script:New-LockLine {
            param([string]$Coordinate, [string]$JarPath, [string]$Algorithm = "SHA256")
            $digest = (Get-FileHash -LiteralPath $JarPath -Algorithm $Algorithm).Hash.ToLowerInvariant()
            return "$Coordinate $($Algorithm.ToLowerInvariant()):$digest https://repo.example/$Coordinate"
        }

        $script:Header = "# Generated from the locked toolchain. Do not edit by hand."
    }

    It "accepts an install that fetched exactly the artefacts the lock pins" {
        $project = New-Project
        try {
            $jar = New-Artefact -ProjectPath $project -GroupId "org.junit.jupiter" `
                -ArtifactId "junit-jupiter" -Version "5.11.3" -Content "one"
            $lock = @($script:Header, (New-LockLine -Coordinate "org.junit.jupiter:junit-jupiter:5.11.3" -JarPath $jar)) -join "`n"
            @(& $script:Maven.GetInstalledArtefactFindings $null $project $lock) | Should -BeNullOrEmpty
        }
        finally { Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It "reads a sha1 digest as readily as a sha256 one" {
        $project = New-Project
        try {
            $jar = New-Artefact -ProjectPath $project -GroupId "org.example" `
                -ArtifactId "lib" -Version "1.0.0" -Content "one"
            $lock = @($script:Header,
                (New-LockLine -Coordinate "org.example:lib:1.0.0" -JarPath $jar -Algorithm "SHA1")) -join "`n"
            @(& $script:Maven.GetInstalledArtefactFindings $null $project $lock) | Should -BeNullOrEmpty
        }
        finally { Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It "reports an artefact the lock pins that the install did not fetch" {
        $project = New-Project
        try {
            $jar = New-Artefact -ProjectPath $project -GroupId "org.example" `
                -ArtifactId "lib" -Version "1.0.0" -Content "one"
            $lock = @($script:Header,
                (New-LockLine -Coordinate "org.example:lib:1.0.0" -JarPath $jar),
                "org.example:missing:2.0.0 sha256:$('0' * 64) https://repo.example/missing") -join "`n"
            $findings = @(& $script:Maven.GetInstalledArtefactFindings $null $project $lock)
            $findings.Count | Should -Be 1
            $findings[0] | Should -BeLike "*org.example:missing:2.0.0*did not fetch it*"
        }
        finally { Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It "reports an artefact the install fetched that the lock does not pin" {
        $project = New-Project
        try {
            $jar = New-Artefact -ProjectPath $project -GroupId "org.example" `
                -ArtifactId "lib" -Version "1.0.0" -Content "one"
            New-Artefact -ProjectPath $project -GroupId "org.example" `
                -ArtifactId "unlocked" -Version "9.9.9" -Content "smuggled" | Out-Null
            $lock = @($script:Header, (New-LockLine -Coordinate "org.example:lib:1.0.0" -JarPath $jar)) -join "`n"
            $findings = @(& $script:Maven.GetInstalledArtefactFindings $null $project $lock)
            $findings.Count | Should -Be 1
            $findings[0] | Should -BeLike "*org.example:unlocked:9.9.9*does not pin*"
        }
        finally { Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # The whole point of pinning bytes: the coordinate is right, the version is
    # right, and the contents are something else.
    It "reports an artefact whose bytes are not the bytes the lock pins" {
        $project = New-Project
        try {
            $jar = New-Artefact -ProjectPath $project -GroupId "org.example" `
                -ArtifactId "lib" -Version "1.0.0" -Content "one"
            $lock = @($script:Header, (New-LockLine -Coordinate "org.example:lib:1.0.0" -JarPath $jar)) -join "`n"
            Set-Content -LiteralPath $jar -Value "something else entirely" -Encoding utf8 -NoNewline
            $findings = @(& $script:Maven.GetInstalledArtefactFindings $null $project $lock)
            $findings.Count | Should -Be 1
            $findings[0] | Should -BeLike "*org.example:lib:1.0.0*lock file pins*"
        }
        finally { Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # A repository that served the wrong jar would serve a checksum file to match
    # it, so the digest is computed over what arrived rather than read from the
    # file sitting next to it.
    It "does not accept the checksum file the repository wrote beside the artefact" {
        $project = New-Project
        try {
            $jar = New-Artefact -ProjectPath $project -GroupId "org.example" `
                -ArtifactId "lib" -Version "1.0.0" -Content "one"
            $lock = @($script:Header,
                (New-LockLine -Coordinate "org.example:lib:1.0.0" -JarPath $jar -Algorithm "SHA1")) -join "`n"
            Set-Content -LiteralPath $jar -Value "tampered" -Encoding utf8 -NoNewline
            Set-Content -LiteralPath "$jar.sha1" -Value (
                (Get-FileHash -LiteralPath $jar -Algorithm SHA1).Hash.ToLowerInvariant()) -Encoding utf8 -NoNewline
            $findings = @(& $script:Maven.GetInstalledArtefactFindings $null $project $lock)
            $findings.Count | Should -Be 1
            $findings[0] | Should -BeLike "*lock file pins*"
        }
        finally { Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It "refuses a lock that names no artefact rather than reporting nothing to compare" {
        $project = New-Project
        try {
            $findings = @(& $script:Maven.GetInstalledArtefactFindings $null $project $script:Header)
            $findings.Count | Should -Be 1
            $findings[0] | Should -BeLike "*names no artefact*"
        }
        finally { Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It "refuses an install that left no local repository to compare" {
        $project = New-Project -WithoutRepository
        try {
            $findings = @(& $script:Maven.GetInstalledArtefactFindings $null $project (
                @($script:Header, "org.example:lib:1.0.0 sha256:$('0' * 64) https://repo.example/lib") -join "`n"))
            $findings.Count | Should -Be 1
            $findings[0] | Should -BeLike "*no local repository*"
        }
        finally { Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It "refuses a digest recorded under an algorithm it cannot compute" {
        $project = New-Project
        try {
            New-Artefact -ProjectPath $project -GroupId "org.example" `
                -ArtifactId "lib" -Version "1.0.0" -Content "one" | Out-Null
            $findings = @(& $script:Maven.GetInstalledArtefactFindings $null $project (
                @($script:Header, "org.example:lib:1.0.0 md5:$('0' * 32) https://repo.example/lib") -join "`n"))
            $findings.Count | Should -Be 1
            $findings[0] | Should -BeLike "*cannot compute*"
        }
        finally { Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # The install commands read from a repository beside the project, because a
    # shared ~/.m2 already holds artefacts from other work and "the jar is here"
    # would then say nothing about what this install fetched.
    It "installs, builds and tests against the repository the comparison reads" {
        $install = & $script:Maven.GetInstallCommand ([pscustomobject]@{
            source = [pscustomobject]@{ registry = 'https://repo.example/maven' }
        }) '/work/automation'
        $body = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($install.arguments[-1]))
        $body | Should -Match "-RepositoryPath '.m2-repo'"
        $body | Should -Match "-Registry 'https://repo.example/maven'"
        $body | Should -Not -Match '\$PSScriptRoot'
        foreach ($factory in @($script:Maven.GetBuildCommand, $script:Maven.GetTestCommand)) {
            $command = & $factory $null "/work/automation"
            @($command.arguments) | Should -Contain "-Dmaven.repo.local=.m2-repo"
            @($command.arguments) | Should -Contain '-o'
            @($command.arguments) | Should -Contain 'foundry-maven-settings.xml'
        }
    }
}

Describe 'Resolving the Maven test runtime before enforcing the lock' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../../scripts/ecosystems/maven.Ecosystem.ps1')
        $script:EffectivePom = [xml]@'
<project xmlns="http://maven.apache.org/POM/4.0.0"><build><plugins><plugin>
<groupId>org.apache.maven.plugins</groupId><artifactId>maven-surefire-plugin</artifactId><version>3.2.5</version>
</plugin></plugins></build></project>
'@
    }

    It 'aligns the dynamic launcher with the resolved engine rather than the provider default' {
        $tree = @'
+- org.junit.jupiter:junit-jupiter:jar:5.11.3:test
|  +- org.junit.jupiter:junit-jupiter-api:jar:5.11.3:test
|  +- org.junit.platform:junit-platform-commons:jar:1.11.3:test
|  \- org.junit.jupiter:junit-jupiter-engine:jar:5.11.3:test
|     \- org.junit.platform:junit-platform-engine:jar:1.11.3:test
'@
        $actual = @(Get-QaFoundryMavenTestRuntimeArtifacts $script:EffectivePom $tree)
        $actual.Count | Should -Be 2
        $actual | Should -Contain 'org.apache.maven.surefire:surefire-junit-platform:3.2.5'
        $actual | Should -Contain 'org.junit.platform:junit-platform-launcher:1.11.3'
    }

    It 'prepares the implicit engine when only the Jupiter API is declared' {
        $actual = @(Get-QaFoundryMavenTestRuntimeArtifacts $script:EffectivePom @'
+- org.junit.jupiter:junit-jupiter-api:jar:5.11.3:test
|  \- org.junit.platform:junit-platform-commons:jar:1.11.3:test
'@)
        $actual | Should -Contain 'org.junit.jupiter:junit-jupiter-engine:5.11.3'
        $actual | Should -Contain 'org.junit.platform:junit-platform-launcher:1.11.3'
    }

    It 'uses the effective plugin version instead of a hardcoded provider version' {
        $pom = [xml]($script:EffectivePom.OuterXml.Replace('3.2.5', '3.5.4'))
        @(Get-QaFoundryMavenTestRuntimeArtifacts $pom '+- org.testng:testng:jar:7.10.2:test') |
            Should -Contain 'org.apache.maven.surefire:surefire-testng:3.5.4'
    }

    It 'supports JUnit 4 including its parallel provider without assuming Jupiter' {
        $actual = @(Get-QaFoundryMavenTestRuntimeArtifacts $script:EffectivePom '+- junit:junit:jar:4.13.2:test')
        $actual | Should -Contain 'org.apache.maven.surefire:surefire-junit4:3.2.5'
        $actual | Should -Contain 'org.apache.maven.surefire:surefire-junit47:3.2.5'
        ($actual -join ' ') | Should -Not -Match 'junit-platform'
    }

    It 'refuses an unresolved Surefire version' {
        $pom = [xml]($script:EffectivePom.OuterXml.Replace('3.2.5', '${surefire.version}'))
        { Get-QaFoundryMavenTestRuntimeArtifacts $pom '+- junit:junit:jar:4.13.2:test' } |
            Should -Throw '*concrete Surefire version*'
    }
}

Describe "Remembering the toolchain between runs" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        . (Join-Path $script:Root "scripts/Common.ps1")
        $script:Config = [pscustomobject]@{
            project = [pscustomobject]@{ automation_root = "automation" }
            automation = [pscustomobject]@{ toolchain_record = "automation-toolchain.json" }
        }
    }

    BeforeEach {
        $script:Repo = Join-Path ([IO.Path]::GetTempPath()) ("foundry-record-" + [guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Path (Join-Path $script:Repo "automation") -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Repo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "reports no recorded decision for a repository that has never been bootstrapped" {
        Get-QaFoundryRecordedToolchain -RepositoryRoot $script:Repo -Config $script:Config |
            Should -BeNullOrEmpty
    }

    It "reads back what a previous run settled on" {
        $lock = [pscustomobject]@{
            runId = "run-first"
            blueprintSha256 = ("c" * 64)
            toolchains = @(
                [pscustomobject]@{
                    id = "nuget-automation"
                    ecosystem = "nuget"
                    language = "C#"
                    testFramework = "xunit"
                    runtime = [pscustomobject]@{ sdkMajor = 8 }
                    decidedFor = @("Contoso.Automation.Api")
                    sha256 = ("d" * 64)
                }
            )
        }
        $record = ConvertTo-QaFoundryToolchainRecord -Lock $lock
        $recordPath = Join-Path $script:Repo "automation/automation-toolchain.json"
        $record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $recordPath -Encoding utf8
        $null = & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $recordPath `
            -SchemaPath (Join-Path $script:Root "schemas/config/automation-toolchain-record.schema.json")

        $read = Get-QaFoundryRecordedToolchain -RepositoryRoot $script:Repo -Config $script:Config
        $read.runId | Should -Be "run-first"
        @($read.toolchains)[0].ecosystem | Should -Be "nuget"
        @($read.toolchains)[0].projects | Should -Contain "Contoso.Automation.Api"
    }

    # Treating an unreadable record as "no decision yet" would let the run choose
    # a second time, which is the exact outcome the record exists to prevent.
    It "stops rather than treating an unreadable record as an open question" {
        Set-Content -LiteralPath (Join-Path $script:Repo "automation/automation-toolchain.json") `
            -Value "{ not json" -Encoding utf8
        { Get-QaFoundryRecordedToolchain -RepositoryRoot $script:Repo -Config $script:Config } |
            Should -Throw "*could not be read as JSON*"
    }

    It "stops on a record that names no toolchain" {
        Set-Content -LiteralPath (Join-Path $script:Repo "automation/automation-toolchain.json") `
            -Value '{"recordedBy":"x","recordedAt":"now","runId":"r","toolchains":[]}' -Encoding utf8
        { Get-QaFoundryRecordedToolchain -RepositoryRoot $script:Repo -Config $script:Config } |
            Should -Throw "*names no toolchain*"
    }

    # A repository can maintain more than one suite, and the record says which
    # technology belongs to which project. Comparing only the set of ecosystems
    # let either stack stand in for either project, so the .NET API suite could
    # be rewritten in the UI's TypeScript and still read as reuse of a recorded
    # decision.
    Context "Holding each project to the technology recorded for it" {
        BeforeAll {
            $script:TwoSuiteRecord = [pscustomobject]@{
                runId = "run-first"
                toolchains = @(
                    [pscustomobject]@{
                        id = "nuget-api"; ecosystem = "nuget"; language = "C#"
                        testFramework = "xunit"; projects = @("automation/api")
                    },
                    [pscustomobject]@{
                        id = "npm-ui"; ecosystem = "npm"; language = "TypeScript"
                        testFramework = "@playwright/test"; projects = @("automation/ui")
                    }
                )
            }
        }

        It "accepts a design that keeps every project where the record left it" {
            $conflicts = @(Get-QaFoundryToolchainRecordConflicts -Recorded $script:TwoSuiteRecord -Proposed @(
                [pscustomobject]@{ name = "api"; path = "automation/api"; ecosystem = "nuget"; language = "C#"; testFramework = "xunit" },
                [pscustomobject]@{ name = "ui"; path = "./automation/ui/"; ecosystem = "npm"; language = "TypeScript "; testFramework = "@playwright/test" }
            ))
            $conflicts | Should -BeNullOrEmpty
        }

        It "refuses moving a recorded project onto the other suite's ecosystem" {
            $conflicts = @(Get-QaFoundryToolchainRecordConflicts -Recorded $script:TwoSuiteRecord -Proposed @(
                [pscustomobject]@{ name = "api"; path = "automation/api"; ecosystem = "npm"; language = "TypeScript"; testFramework = "@playwright/test" }
            ))
            $conflicts.Count | Should -Be 1
            $conflicts[0] | Should -Match "records that very project on 'nuget'"
            $conflicts[0] | Should -Match "migration"
        }

        It "refuses a second test framework beside the one recorded for the project" {
            $conflicts = @(Get-QaFoundryToolchainRecordConflicts -Recorded $script:TwoSuiteRecord -Proposed @(
                [pscustomobject]@{ name = "api"; path = "automation/api"; ecosystem = "nuget"; language = "C#"; testFramework = "nunit" }
            ))
            $conflicts.Count | Should -Be 1
            $conflicts[0] | Should -Match "records that project with testFramework 'xunit'"
        }

        It "lets a new project join a toolchain the repository already maintains" {
            $conflicts = @(Get-QaFoundryToolchainRecordConflicts -Recorded $script:TwoSuiteRecord -Proposed @(
                [pscustomobject]@{ name = "batch"; path = "automation/batch"; ecosystem = "nuget"; language = "C#"; testFramework = "xunit" }
            ))
            $conflicts | Should -BeNullOrEmpty
        }

        It "refuses a new project that arrives on a third ecosystem" {
            $conflicts = @(Get-QaFoundryToolchainRecordConflicts -Recorded $script:TwoSuiteRecord -Proposed @(
                [pscustomobject]@{ name = "batch"; path = "automation/batch"; ecosystem = "pypi"; language = "Python"; testFramework = "pytest" }
            ))
            $conflicts.Count | Should -Be 1
            $conflicts[0] | Should -Match "already records automation on \(nuget, npm\)"
        }

        It "compares project paths as written rather than folding their case" {
            # Two directories differing only in case are two directories on the
            # agents this runs on, so the record does not speak for the second.
            $conflicts = @(Get-QaFoundryToolchainRecordConflicts -Recorded $script:TwoSuiteRecord -Proposed @(
                [pscustomobject]@{ name = "api"; path = "automation/API"; ecosystem = "npm" }
            ))
            $conflicts | Should -BeNullOrEmpty
        }

        It "has nothing to say about a repository with no record" {
            @(Get-QaFoundryToolchainRecordConflicts -Recorded $null -Proposed @(
                [pscustomobject]@{ name = "api"; path = "automation/api"; ecosystem = "npm" }
            )) | Should -BeNullOrEmpty
        }
    }

    # The blueprint check holds an architect to the record. An ordinary task -
    # "add a regression test for this fix" - never meets an architect, and the
    # change set it produces reaches the repository just the same. What that
    # change set writes is therefore checked against the record too.
    Context "Holding an ordinary change to the technology recorded for it" {
        BeforeAll {
            $script:ChangeRecord = [pscustomobject]@{
                runId = "run-first"
                toolchains = @(
                    [pscustomobject]@{
                        id = "nuget-api"; ecosystem = "nuget"; language = "C#"
                        testFramework = "xunit"; projects = @("automation/Api")
                    },
                    [pscustomobject]@{
                        id = "npm-ui"; ecosystem = "npm"; language = "TypeScript"
                        testFramework = "@playwright/test"; projects = @("automation/Ui")
                    }
                )
            }
        }

        It "accepts a change that stays in each project's recorded ecosystem" {
            @(Get-QaFoundryToolchainManifestConflicts -Recorded $script:ChangeRecord -Paths @(
                "automation/Api/Api.csproj",
                "automation/Api/Tests/QuoteTests.cs",
                "automation/Ui/package.json",
                "src/Pricing/Pricing.csproj",
                "package.json"
            )) | Should -BeNullOrEmpty
        }

        It "refuses a second toolchain arriving inside a recorded suite" {
            $conflicts = @(Get-QaFoundryToolchainManifestConflicts -Recorded $script:ChangeRecord -Paths @(
                "automation/Api/package.json"
            ))
            $conflicts.Count | Should -Be 1
            $conflicts[0] | Should -Match "is a 'npm' manifest"
            $conflicts[0] | Should -Match "records on 'nuget'"
            $conflicts[0] | Should -Match "migration"
        }

        It "refuses a new suite on an ecosystem this repository does not maintain" {
            $conflicts = @(Get-QaFoundryToolchainManifestConflicts -Recorded $script:ChangeRecord -Paths @(
                "automation/Batch/requirements.txt"
            ))
            $conflicts.Count | Should -Be 1
            $conflicts[0] | Should -Match "records automation on \(nuget, npm\)"
        }

        It "lets a new suite join a toolchain the repository already maintains" {
            @(Get-QaFoundryToolchainManifestConflicts -Recorded $script:ChangeRecord -Paths @(
                "automation/Batch/Batch.csproj"
            )) | Should -BeNullOrEmpty
        }

        It "leaves the product's own manifests alone" {
            # The record says what the automation is written in. It says nothing
            # about the product, and a run that refused a change to the product's
            # own package.json would be enforcing a decision nobody made.
            @(Get-QaFoundryToolchainManifestConflicts -Recorded $script:ChangeRecord -Paths @(
                "pricing-service-ui/package.json",
                "CommodityPricingService/CommodityPricingService.csproj"
            )) | Should -BeNullOrEmpty
        }

        It "reads the automation root from configuration rather than assuming one" {
            $conflicts = @(Get-QaFoundryToolchainManifestConflicts -Recorded $script:ChangeRecord `
                -AutomationRoot "tests/e2e" -Paths @("tests/e2e/Batch/requirements.txt"))
            $conflicts.Count | Should -Be 1
            # And the default root now means nothing here, so what used to be
            # inside it is somebody else's business.
            @(Get-QaFoundryToolchainManifestConflicts -Recorded $script:ChangeRecord `
                -AutomationRoot "tests/e2e" -Paths @("automation/Batch/requirements.txt")) |
                Should -BeNullOrEmpty
        }

        It "attributes a manifest to the deepest recorded project that contains it" {
            $nested = [pscustomobject]@{
                runId = "run-first"
                toolchains = @(
                    [pscustomobject]@{ id = "root"; ecosystem = "npm"; projects = @("automation") },
                    [pscustomobject]@{ id = "api"; ecosystem = "nuget"; projects = @("automation/Api") }
                )
            }
            $conflicts = @(Get-QaFoundryToolchainManifestConflicts -Recorded $nested -Paths @(
                "automation/Api/package.json"
            ))
            $conflicts.Count | Should -Be 1
            $conflicts[0] | Should -Match "automation/Api"
            $conflicts[0] | Should -Match "records on 'nuget'"
            @(Get-QaFoundryToolchainManifestConflicts -Recorded $nested -Paths @(
                "automation/Ui/package.json"
            )) | Should -BeNullOrEmpty
        }

        It "has nothing to say about a repository with no record" {
            @(Get-QaFoundryToolchainManifestConflicts -Recorded $null -Paths @(
                "automation/Api/package.json"
            )) | Should -BeNullOrEmpty
        }
    }
}
