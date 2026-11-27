BeforeAll {
    $script:Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root scripts/Common.ps1)
    $script:Resolver=Join-Path $script:Root scripts/actions/Resolve-EcosystemLock.ps1
    function New-SdkToolchain([int]$Major) {
        [pscustomobject]@{id='sdk-selection';ecosystem='nuget';source=@{registry='https://api.nuget.org/v3/index.json'};
            runtime=@{sdkMajor=$Major;targetFramework="net$Major.0"};packages=@()}
    }
}

Describe 'NuGet resolver pins the approved SDK before probing or restoring' {
    It 'creates a scratch SDK selection bounded by the locked major' {
        $adapter=Get-QaFoundryEcosystemAdapter -Ecosystem nuget
        $files=@(& $adapter.NewNeutralConfigFiles (New-SdkToolchain 10) $TestDrive)
        $sdk=@($files|Where-Object key -eq dotnetsdk)
        $sdk.Count|Should -Be 1
        $sdk[0].path|Should -Be 'project/global.json'
        $json=$sdk[0].content|ConvertFrom-Json
        $json.sdk.version|Should -Be '10.0.100'
        $json.sdk.rollForward|Should -Be latestMinor
        $json.sdk.allowPrerelease|Should -BeFalse
    }

    It 'overrides a conflicting parent SDK pin before the version check and builds with the installed approved SDK' -Skip:(-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        $installed=@(& dotnet --list-sdks)
        $versions=@($installed|ForEach-Object {if($_ -match '^(\d+\.\d+\.\d+) \['){[version]$matches[1]}}|Sort-Object -Descending)
        if(-not $versions.Count){Set-ItResult -Skipped -Because 'No stable SDK installed';return}
        $major=$versions[0].Major
        $parent=Join-Path $TestDrive 'product'
        New-Item -ItemType Directory $parent -Force|Out-Null
        $pin=Join-Path $parent global.json
        @{sdk=@{version='9999.0.100';rollForward='disable'}}|ConvertTo-Json|Set-Content $pin
        $hash=(Get-FileHash $pin).Hash
        $scratch=Join-Path $parent resolver
        $result=& $script:Resolver -Toolchain (New-SdkToolchain $major) -WorkRoot $scratch -ManifestName SdkProbe -BuildProbe
        $result.succeeded|Should -BeTrue -Because $result.detail
        (Get-FileHash $pin).Hash|Should -BeExactly $hash
        Test-Path (Join-Path $scratch "project/bin/Release/net$major.0/SdkProbe.dll")|Should -BeTrue
        Test-Path (Join-Path $scratch project/packages.lock.json)|Should -BeTrue
    }

    It 'refuses a missing approved SDK rather than falling forward to an installed major' -Skip:(-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        $scratch=Join-Path $TestDrive unavailable
        $result=& $script:Resolver -Toolchain (New-SdkToolchain 9999) -WorkRoot $scratch -ManifestName MissingSdk
        $result.succeeded|Should -BeFalse
        $result.infrastructureUnavailable|Should -BeTrue
        Test-Path (Join-Path $scratch project/packages.lock.json)|Should -BeFalse
    }
}
