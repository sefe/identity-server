BeforeAll {
    $script:Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Resolver=Join-Path $script:Root scripts/actions/Resolve-EcosystemLock.ps1
    function New-IsolationToolchain([int]$Major=10) {
        [pscustomobject]@{id='nuget-isolation';ecosystem='nuget';source=@{registry='https://api.nuget.org/v3/index.json'};
            runtime=@{sdkMajor=$Major;targetFramework="net$Major.0"};packages=@(
                @{key='json';name='Newtonsoft.Json';version='13.0.3';scope='runtime';requested='13.0.3'}
            )}
    }
    function New-FailingDotnet([string]$Code) {
        $padding='x' * 700
        if ($IsWindows) {
            $path=Join-Path $TestDrive "dotnet-$Code.cmd"
            @('@echo off','if "%1"=="--version" (echo 10.0.100 & exit /b 0)',
                'echo incidental warning 1>&2',"echo $padding","echo project.csproj : error ${Code}: resolver refused the project",'exit /b 1') -join "`r`n" |
                Set-Content -LiteralPath $path -Encoding ascii
        } else {
            $path=Join-Path $TestDrive "dotnet-$Code"
            @('#!/bin/sh','if [ "$1" = "--version" ]; then echo 10.0.100; exit 0; fi',
                'echo incidental warning >&2',"echo $padding","echo project.csproj : error ${Code}: resolver refused the project",'exit 1') -join "`n" |
                Set-Content -LiteralPath $path -Encoding ascii
            & chmod +x $path
        }
        return $path
    }
}

Describe 'NuGet scratch resolution is independent of product MSBuild settings' {
    It 'restores only approved packages and builds below conflicting parent props and targets' -Skip:(-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        $versions=@(& dotnet --list-sdks | ForEach-Object {if($_ -match '^(\d+\.\d+\.\d+) \['){[version]$matches[1]}} | Sort-Object -Descending)
        if(-not $versions.Count){Set-ItResult -Skipped -Because 'No stable SDK installed';return}
        $major=$versions[0].Major
        $product=Join-Path $TestDrive product
        New-Item -ItemType Directory -Path $product | Out-Null
        $parents=@{
            'Directory.Packages.props'='<Project><PropertyGroup><ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally><CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled></PropertyGroup><ItemGroup><GlobalPackageReference Include="Foundry.Unapproved.Parent.Package" Version="1.0.0" /></ItemGroup></Project>'
            'Directory.Build.props'='<Project><Import Project="missing-product-only.props" /></Project>'
            'Directory.Build.targets'='<Project><Target Name="ProductOnly" BeforeTargets="Restore;Build"><Error Text="Product targets leaked into resolver" /></Target></Project>'
            'global.json'='{"sdk":{"version":"9999.0.100","rollForward":"disable"}}'
        }
        $hashes=@{}
        foreach($name in $parents.Keys) {
            $path=Join-Path $product $name
            $parents[$name] | Set-Content -LiteralPath $path
            $hashes[$name]=(Get-FileHash $path).Hash
        }
        $scratch=Join-Path $product '.qa-foundry-artifacts/.scratch/resolver'
        $result=& $script:Resolver -Toolchain (New-IsolationToolchain $major) -WorkRoot $scratch -ManifestName IsolationProbe -BuildProbe
        $result.succeeded | Should -BeTrue -Because $result.detail
        $lock=$result.lockJson | ConvertFrom-Json -AsHashtable
        $packages=$lock.dependencies["net$major.0"]
        @($packages.Keys).Count | Should -Be 1
        $packages['Newtonsoft.Json'].resolved | Should -Be '13.0.3'
        Test-Path (Join-Path $scratch "project/bin/Release/net$major.0/IsolationProbe.dll") | Should -BeTrue
        foreach($name in $parents.Keys) { (Get-FileHash (Join-Path $product $name)).Hash | Should -BeExactly $hashes[$name] }
    }

    It 'classifies <Code> without losing stdout errors behind stderr or diagnostic truncation' -ForEach @(
        @{Code='NU1008';Infrastructure=$true},
        @{Code='NU1101';Infrastructure=$false}
    ) {
        $stub=New-FailingDotnet $Code
        $scratch=Join-Path $TestDrive $Code
        $result=& $script:Resolver -Toolchain (New-IsolationToolchain) -WorkRoot $scratch -ManifestName ClassificationProbe -ToolCommandOverrides @{dotnet=$stub}
        $result.succeeded | Should -BeFalse
        $result.exitCode | Should -Be 1
        $result.infrastructureUnavailable | Should -Be $Infrastructure
        if($Infrastructure) { $result.detail | Should -Match 'NU1008.*central package management' }
        Test-Path (Join-Path $scratch project/packages.lock.json) | Should -BeFalse
    }
}
