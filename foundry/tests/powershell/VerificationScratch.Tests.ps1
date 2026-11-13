BeforeAll {
    . (Join-Path $PSScriptRoot '../../scripts/VerificationScratch.ps1')
}

Describe 'Independent verification scratch directories' {
    It 'places executable files on the workspace filesystem and confines cleanup to that parent' {
        $parent = Join-Path $TestDrive '.scratch'
        $directory = New-QaFoundryVerificationScratch -Parent $parent
        [IO.Path]::GetDirectoryName($directory) | Should -Be $parent
        { Remove-QaFoundryVerificationScratch -Path $directory } | Should -Throw '*outside the owned*'
        Test-Path $directory | Should -BeTrue
        Remove-QaFoundryVerificationScratch -Path $directory -Parent $parent
        Test-Path $directory | Should -BeFalse
        Test-Path $parent | Should -BeTrue
    }
    It 'isolates concurrent runs and removes only their own directories' {
        $first = New-QaFoundryVerificationScratch
        $second = New-QaFoundryVerificationScratch
        try {
            $first | Should -Not -Be $second
            Set-Content (Join-Path $first 'generated.txt') 'temporary build output'
            Remove-QaFoundryVerificationScratch -Path $first
            Test-Path -LiteralPath $first | Should -BeFalse
            Test-Path -LiteralPath $second | Should -BeTrue
        }
        finally {
            Remove-QaFoundryVerificationScratch -Path $first
            Remove-QaFoundryVerificationScratch -Path $second
        }
    }
    It 'refuses cleanup of an unrelated directory' {
        { Remove-QaFoundryVerificationScratch -Path $TestDrive } | Should -Throw '*outside the owned*'
        Test-Path -LiteralPath $TestDrive | Should -BeTrue
    }
    It 'preserves the result when a Windows compiler still holds a temporary file' -Skip:(-not $IsWindows) {
        $directory = New-QaFoundryVerificationScratch
        $file = Join-Path $directory 'compiler.dll'
        Set-Content -LiteralPath $file 'held by a compiler'
        $handle = [IO.File]::Open($file, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            Remove-QaFoundryVerificationScratch -Path $directory -WarningVariable cleanupWarning -WarningAction SilentlyContinue
            @($cleanupWarning).Count | Should -Be 1
            Test-Path -LiteralPath $file | Should -BeTrue
        }
        finally {
            $handle.Dispose()
            Remove-QaFoundryVerificationScratch -Path $directory
        }
        Test-Path -LiteralPath $directory | Should -BeFalse
    }
    It 'keeps Unix IPC paths under the MTP limit with a private directory' -Skip:$IsWindows {
        $directory = New-QaFoundryVerificationScratch
        try {
            $pipePath = Join-Path $directory ('.verification-home/tmp/' + [guid]::NewGuid().ToString('N'))
            [Text.Encoding]::UTF8.GetByteCount($pipePath) | Should -BeLessOrEqual 103
            [int][IO.File]::GetUnixFileMode($directory) | Should -Be 448
            $directory | Should -Match '^/tmp/qaf-'
        }
        finally { Remove-QaFoundryVerificationScratch -Path $directory }
    }
}
