<#
.SYNOPSIS
Tests the PoshManage module and installer.

.DESCRIPTION
The tests cover command aliases, theme listing and switching, startup-script edits, backups, and installation.
They use temporary profiles (startup scripts) and module paths.
The integration test (a test of parts used together) runs the real Oh My Posh program.
It tests prompt updates in the current session and a fresh session.
It also tests that invalid themes leave the saved profile unchanged.
Run the suite with Pester 5 or later in PowerShell 7 on Windows.
#>
#requires -Version 7.0
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'PoshManage\PoshManage.psd1') -Force

InModuleScope PoshManage {
    Describe 'Theme commands and profile safety' {
        BeforeAll {
            function Save-TestProfile {
                param([string]$Text, [Text.Encoding]$Encoding = [Text.UTF8Encoding]::new($false))
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:context.ProfilePath))
                [IO.File]::WriteAllBytes($script:context.ProfilePath, [byte[]]($Encoding.GetPreamble() + $Encoding.GetBytes($Text)))
            }
            function Get-TestInitializer {
                param([string]$Name = 'alpha')
                $path = (Join-Path $script:context.ThemeDirectory "$Name.omp.json").Replace("'", "''")
                return "oh-my-posh init pwsh --config '$path' | Invoke-Expression"
            }
            function Get-TestProfileBytes {
                return [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:context.ProfilePath))
            }
        }
        BeforeEach {
            $homePath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + ' home')
            $script:context = [pscustomobject]@{
                HomePath = $homePath
                ThemeDirectory = Join-Path $homePath '.poshthemes'
                BackupDirectory = Join-Path $homePath '.powershell_profile_backups'
                ProfilePath = Join-Path $homePath 'Profiles\Console.ps1'
                OtherProfiles = @(Join-Path $homePath 'Profiles\shared.ps1')
            }
            [void][IO.Directory]::CreateDirectory($script:context.ThemeDirectory)
            [IO.File]::WriteAllText((Join-Path $script:context.ThemeDirectory 'alpha.omp.json'), ((1..15) -join "`n"))
            [IO.File]::WriteAllText((Join-Path $script:context.ThemeDirectory 'beta.omp.json'), '{}')
            Mock Get-PoshManageContext { $script:context }
            Mock Get-PoshExecutable { 'fake.exe' }
            Mock Get-PoshInitializationScript { $ThemePath }
            Mock Invoke-PoshInitialization { $script:applied = $Script }
            $script:applied = $null
        }

        It 'exports only the intended command and alias' {
            $module = Get-Module PoshManage
            @($module.ExportedFunctions.Keys) | Should -Be @('Invoke-PoshThemes')
            @($module.ExportedAliases.Keys) | Should -Be @('poshthemes')
        }
        It 'shows help for <Command>' -TestCases @(
            @{ Command = 'help' }, @{ Command = '-h' }, @{ Command = '--help' }
        ) {
            param($Command)
            (poshthemes $Command) -join "`n" | Should -Match 'Usage: poshthemes'
            Should -Invoke Invoke-PoshInitialization -Times 0
        }
        It 'shows help without arguments' {
            (poshthemes) -join "`n" | Should -Match 'Usage: poshthemes'
        }
        It 'lists and marks the saved theme for <Command>' -TestCases @(
            @{ Command = 'list' }, @{ Command = 'ls' }, @{ Command = '-l' }
        ) {
            param($Command)
            Save-TestProfile (Get-TestInitializer)
            [IO.File]::WriteAllText((Join-Path $script:context.ThemeDirectory 'ignore.json'), '{}')
            $output = poshthemes $Command
            $output[1] | Should -Be '1. alpha.omp.json (current)'
            $output[2] | Should -Be '2. beta.omp.json'
            $output[3] | Should -Be 'Total themes found: 2'
        }
        It 'shows exactly ten preview lines for <Command>' -TestCases @(
            @{ Command = 'current' }, @{ Command = 'show' }, @{ Command = '-c' }
        ) {
            param($Command)
            Save-TestProfile (Get-TestInitializer)
            $output = @(poshthemes $Command)
            $output.Count | Should -Be 12
            $output[2..11] | Should -Be @((1..10) | ForEach-Object { [string]$_ })
        }
        It 'reports an unconfigured profile without creating files' {
            poshthemes current | Should -Match 'No Oh My Posh theme'
            Test-Path -LiteralPath $script:context.ProfilePath | Should -BeFalse
        }
        It 'reports a missing selected file' {
            Save-TestProfile (Get-TestInitializer 'missing')
            { poshthemes current } | Should -Throw
        }
        It 'reports an empty theme directory' {
            $script:context.ThemeDirectory = Join-Path $script:context.HomePath 'empty'
            [void][IO.Directory]::CreateDirectory($script:context.ThemeDirectory)
            { poshthemes list } | Should -Throw '*No .omp.json*'
        }
        It 'reports a missing theme directory' {
            $script:context.ThemeDirectory = Join-Path $script:context.HomePath 'missing'
            { poshthemes list } | Should -Throw
        }
        It 'switches with <Command> and creates a profile without a fake backup' -TestCases @(
            @{ Command = 'switch' }, @{ Command = 'set' }, @{ Command = '-s' }
        ) {
            param($Command)
            poshthemes $Command alpha | Out-Null
            [IO.File]::ReadAllText($script:context.ProfilePath) | Should -Be ((Get-TestInitializer) + "`r`n")
            $script:applied | Should -Be (Join-Path $script:context.ThemeDirectory 'alpha.omp.json')
            Test-Path -LiteralPath $script:context.BackupDirectory | Should -BeFalse
        }
        It 'does not rewrite or back up the already saved theme' {
            $text = (Get-TestInitializer) + "`n"
            Save-TestProfile $text
            $before = Get-TestProfileBytes
            poshthemes switch alpha.omp.json | Out-Null
            Get-TestProfileBytes | Should -Be $before
            Test-Path -LiteralPath $script:context.BackupDirectory | Should -BeFalse
            Should -Invoke Invoke-PoshInitialization -Times 1
        }
        It 'preserves <EncodingName> and <NewlineName> while making an exact backup' -TestCases @(
            @{ EncodingName = 'UTF8'; NewlineName = 'LF' }
            @{ EncodingName = 'UTF8BOM'; NewlineName = 'CRLF' }
            @{ EncodingName = 'UTF16LE'; NewlineName = 'LF' }
            @{ EncodingName = 'UTF16BE'; NewlineName = 'CRLF' }
        ) {
            param($EncodingName, $NewlineName)
            $encoding = switch ($EncodingName) {
                'UTF8' { [Text.UTF8Encoding]::new($false) }
                'UTF8BOM' { [Text.UTF8Encoding]::new($true) }
                'UTF16LE' { [Text.UnicodeEncoding]::new($false, $true) }
                'UTF16BE' { [Text.UnicodeEncoding]::new($true, $true) }
            }
            $newline = if ($NewlineName -eq 'LF') { "`n" } else { "`r`n" }
            $text = '# Keep this comment' + $newline + (Get-TestInitializer) + $newline + '$global:unrelated = 42'
            Save-TestProfile $text $encoding
            $before = Get-TestProfileBytes
            poshthemes switch beta | Out-Null
            $expected = $text.Replace('alpha.omp.json', 'beta.omp.json')
            Get-TestProfileBytes | Should -Be ([Convert]::ToBase64String([byte[]]($encoding.GetPreamble() + $encoding.GetBytes($expected))))
            $backups = @(Get-ChildItem -LiteralPath $script:context.BackupDirectory -File)
            $backups.Count | Should -Be 1
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($backups[0].FullName)) | Should -Be $before
            Get-Variable unrelated -Scope Global -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
        It 'creates distinct backups for rapid switches and retains one initializer' {
            Save-TestProfile (Get-TestInitializer)
            poshthemes switch beta | Out-Null
            poshthemes switch alpha | Out-Null
            @(Get-ChildItem -LiteralPath $script:context.BackupDirectory -File).Count | Should -Be 2
            ([regex]::Matches([IO.File]::ReadAllText($script:context.ProfilePath), 'oh-my-posh init')).Count | Should -Be 1
        }
        It 'uses literal special-character filenames' {
            $name = "space's [theme] " + [char]0x03A9
            [IO.File]::WriteAllText((Join-Path $script:context.ThemeDirectory "$name.omp.json"), '{}')
            poshthemes switch $name | Out-Null
            poshthemes current | Select-Object -First 1 | Should -Be "Current theme: $name.omp.json"
            (poshthemes list) -join "`n" | Should -Match '\(current\)'
        }
        It 'supports an expanded HOME configuration without evaluating other expressions' {
            Save-TestProfile 'oh-my-posh init pwsh --config "$HOME\.poshthemes\alpha.omp.json" | iex'
            poshthemes switch beta | Out-Null
            [IO.File]::ReadAllText($script:context.ProfilePath) | Should -Match 'beta.omp.json'
        }
        It 'preserves an escaped HOME token in a literal filename' {
            $name = '$HOME.omp.json'
            [IO.File]::WriteAllText((Join-Path $script:context.ThemeDirectory $name), '{}')
            Save-TestProfile 'oh-my-posh init pwsh --config "$HOME\.poshthemes\`$HOME.omp.json" | iex'
            poshthemes current | Select-Object -First 1 | Should -Be "Current theme: $name"
            poshthemes switch beta | Out-Null
            poshthemes current | Select-Object -First 1 | Should -Be 'Current theme: beta.omp.json'
        }
        It 'supports quoted init arguments and an equals-form configuration' {
            $path = (Join-Path $script:context.ThemeDirectory 'alpha.omp.json').Replace("'", "''")
            Save-TestProfile "oh-my-posh 'init' 'pwsh' --config='$path' | iex"
            poshthemes switch beta | Out-Null
            poshthemes current | Select-Object -First 1 | Should -Be 'Current theme: beta.omp.json'
        }
        It 'supports the native short configuration flag' {
            Save-TestProfile ((Get-TestInitializer).Replace('--config', '-c'))
            poshthemes switch beta | Out-Null
            [IO.File]::ReadAllText($script:context.ProfilePath) | Should -Match ' -c '
            poshthemes current | Select-Object -First 1 | Should -Be 'Current theme: beta.omp.json'
        }
        It 'rejects invalid invocation <Label>' -TestCases @(
            @{ Label = 'unknown command'; Arguments = @('unknown') }
            @{ Label = 'missing theme'; Arguments = @('switch') }
            @{ Label = 'extra argument'; Arguments = @('list', 'extra') }
            @{ Label = 'missing file'; Arguments = @('switch', 'missing') }
            @{ Label = 'traversal'; Arguments = @('switch', '..\alpha') }
            @{ Label = 'absolute path'; Arguments = @('switch', 'C:\alpha') }
            @{ Label = 'empty name'; Arguments = @('switch', '') }
        ) {
            param($Arguments)
            Save-TestProfile '# Preserve this'
            $before = Get-TestProfileBytes
            { poshthemes @Arguments } | Should -Throw
            Get-TestProfileBytes | Should -Be $before
            Should -Invoke Invoke-PoshInitialization -Times 0
        }
        It 'refuses unsafe profile <Label>' -TestCases @(
            @{ Label = 'external path'; Text = "oh-my-posh init pwsh --config 'C:\outside\theme.omp.json' | iex" }
            @{ Label = 'remote URL'; Text = "oh-my-posh init pwsh --config 'https://example.com/theme.omp.json' | iex" }
            @{ Label = 'built-in theme'; Text = "oh-my-posh init pwsh --config 'jandedobbeleer' | iex" }
            @{ Label = 'default configuration'; Text = 'oh-my-posh init pwsh | iex' }
            @{ Label = 'dynamic configuration'; Text = 'oh-my-posh init pwsh --config (Get-ThemePath) | iex' }
            @{ Label = 'dynamic operation'; Text = '$operation = "init"; oh-my-posh $operation pwsh --config "C:\outside\theme.omp.json" | iex' }
            @{ Label = 'flags before init'; Text = 'oh-my-posh --config "C:\outside\theme.omp.json" init pwsh | iex' }
            @{ Label = 'syntax error'; Text = 'function {' }
            @{ Label = 'signature'; Text = '# SIG # Begin signature block' }
        ) {
            param($Text)
            Save-TestProfile $Text
            $before = Get-TestProfileBytes
            { poshthemes switch beta } | Should -Throw
            Get-TestProfileBytes | Should -Be $before
            Test-Path -LiteralPath $script:context.BackupDirectory | Should -BeFalse
            Should -Invoke Invoke-PoshInitialization -Times 0
        }
        It 'refuses conditional and duplicate initializers' {
            Save-TestProfile ('if ($true) { ' + (Get-TestInitializer) + ' }')
            { poshthemes switch beta } | Should -Throw '*Complex*'
            Save-TestProfile ((Get-TestInitializer) + "`n" + (Get-TestInitializer))
            { poshthemes switch beta } | Should -Throw '*Multiple*'
        }
        It 'refuses an initializer in another startup profile without editing it' {
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:context.OtherProfiles[0]))
            [IO.File]::WriteAllText($script:context.OtherProfiles[0], (Get-TestInitializer))
            $before = [IO.File]::ReadAllText($script:context.OtherProfiles[0])
            { poshthemes switch beta } | Should -Throw '*another startup profile*'
            [IO.File]::ReadAllText($script:context.OtherProfiles[0]) | Should -Be $before
            Test-Path -LiteralPath $script:context.ProfilePath | Should -BeFalse
        }
        It 'refuses unsupported encoding' {
            Save-TestProfile ''
            [IO.File]::WriteAllBytes($script:context.ProfilePath, [byte[]](0xFF, 0x80))
            $before = Get-TestProfileBytes
            { poshthemes switch beta } | Should -Throw '*Unsupported profile encoding*'
            Get-TestProfileBytes | Should -Be $before
        }
        It 'stops before writing when Oh My Posh is missing' {
            Mock Get-PoshExecutable { throw 'Oh My Posh is missing' }
            { poshthemes switch alpha } | Should -Throw '*missing*'
            Test-Path -LiteralPath $script:context.ProfilePath | Should -BeFalse
        }
        It 'stops when a backup fails' {
            Save-TestProfile (Get-TestInitializer)
            $before = Get-TestProfileBytes
            Mock Backup-PoshProfile { throw 'Backup denied' }
            { poshthemes switch beta } | Should -Throw '*Backup denied*'
            Get-TestProfileBytes | Should -Be $before
            Should -Invoke Invoke-PoshInitialization -Times 0
        }
        It 'stops before writing when native configuration preparation fails' {
            Save-TestProfile (Get-TestInitializer)
            $before = Get-TestProfileBytes
            Mock Get-PoshInitializationScript { throw 'Native configuration failed' }
            { poshthemes switch beta } | Should -Throw '*Native configuration failed*'
            Get-TestProfileBytes | Should -Be $before
            Test-Path -LiteralPath $script:context.BackupDirectory | Should -BeFalse
            Should -Invoke Invoke-PoshInitialization -Times 0
        }
        It 'stops when a write fails' {
            Save-TestProfile (Get-TestInitializer)
            $before = Get-TestProfileBytes
            Mock Write-PoshProfileBytes { throw 'Write denied' }
            { poshthemes switch beta } | Should -Throw '*Write denied*'
            Get-TestProfileBytes | Should -Be $before
            Should -Invoke Invoke-PoshInitialization -Times 0
        }
        It 'restores the existing profile after failed activation' {
            Save-TestProfile (Get-TestInitializer)
            $before = Get-TestProfileBytes
            Mock Invoke-PoshInitialization { throw 'Init failed' }
            { poshthemes switch beta } | Should -Throw '*Theme activation failed*'
            Get-TestProfileBytes | Should -Be $before
        }
        It 'removes only a newly created profile after failed activation' {
            Mock Invoke-PoshInitialization { throw 'Init failed' }
            { poshthemes switch alpha } | Should -Throw '*Theme activation failed*'
            Test-Path -LiteralPath $script:context.ProfilePath | Should -BeFalse
        }
        It 'preserves a later edit instead of overwriting it during rollback' {
            Save-TestProfile (Get-TestInitializer)
            Mock Invoke-PoshInitialization {
                [IO.File]::WriteAllText($script:context.ProfilePath, '# A later edit')
                throw 'Init failed'
            }
            { poshthemes switch beta } | Should -Throw '*Rollback failed*Backup:*'
            [IO.File]::ReadAllText($script:context.ProfilePath) | Should -Be '# A later edit'
        }
        It 'detects a changed profile before replacement and cleans its staged file' {
            Save-TestProfile '# Original'
            $expected = Read-PoshProfile $script:context.ProfilePath
            Save-TestProfile '# Later edit'
            { Write-PoshProfileBytes $expected ([byte[]](1, 2, 3)) } | Should -Throw '*profile changed*'
            [IO.File]::ReadAllText($script:context.ProfilePath) | Should -Be '# Later edit'
            @(Get-ChildItem -LiteralPath (Split-Path -Parent $script:context.ProfilePath) -Filter '.posh-manage-*.tmp').Count | Should -Be 0
        }
    }
}

Describe 'Current-user installer' {
    BeforeAll {
        $installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'Install-PoshManage.ps1'
        $pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        function Invoke-TestInstaller {
            param([string]$Options = '', [switch]$WrongModulePath)
            $modulePath = if ($WrongModulePath) { Join-Path $root 'wrong' } else { $modules }
            $script = @"
`$ErrorActionPreference = 'Stop'
`$PROFILE = [pscustomobject]@{ CurrentUserAllHosts = '$($profile.Replace("'", "''"))' }
`$env:PSModulePath = '$($modulePath.Replace("'", "''"))'
& '$($installer.Replace("'", "''"))' $Options
"@
            $output = & $pwsh -NoLogo -NoProfile -NonInteractive -Command $script 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $output -join "`n" }
        }
    }
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + ' install')
        $profile = Join-Path $root 'PowerShell\profile.ps1'
        $modules = Join-Path $root 'PowerShell\Modules'
        $destination = Join-Path $modules 'PoshManage\0.1.0'
    }
    It 'installs and auto-loads the alias in a fresh session without creating a profile' {
        (Invoke-TestInstaller).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $destination 'PoshManage.psd1') | Should -BeTrue
        Test-Path -LiteralPath $profile | Should -BeFalse
        $output = & $pwsh -NoLogo -NoProfile -NonInteractive -Command "`$env:PSModulePath = '$modules'; poshthemes --help" 2>&1
        $LASTEXITCODE | Should -Be 0
        $output -join "`n" | Should -Match 'Usage: poshthemes'
    }
    It 'does nothing for an identical installation' {
        (Invoke-TestInstaller).ExitCode | Should -Be 0
        $before = (Get-Item -LiteralPath (Join-Path $destination 'PoshManage.psm1')).LastWriteTimeUtc
        (Invoke-TestInstaller).Text | Should -Match 'already installed'
        (Get-Item -LiteralPath (Join-Path $destination 'PoshManage.psm1')).LastWriteTimeUtc | Should -Be $before
    }
    It 'refuses overwrite without Force and preserves unrelated files with Force' {
        (Invoke-TestInstaller).ExitCode | Should -Be 0
        $module = Join-Path $destination 'PoshManage.psm1'
        [IO.File]::WriteAllText($module, '# Changed')
        $sentinel = Join-Path $destination 'unrelated.txt'
        [IO.File]::WriteAllText($sentinel, 'Keep')
        (Invoke-TestInstaller).ExitCode | Should -Not -Be 0
        [IO.File]::ReadAllText($module) | Should -Be '# Changed'
        (Invoke-TestInstaller '-Force').ExitCode | Should -Be 0
        [IO.File]::ReadAllText($module) | Should -Match 'function Invoke-PoshThemes'
        [IO.File]::ReadAllText($sentinel) | Should -Be 'Keep'
    }
    It 'makes no directories with WhatIf' {
        (Invoke-TestInstaller '-WhatIf').ExitCode | Should -Be 0
        Test-Path -LiteralPath $modules | Should -BeFalse
    }
    It 'refuses a current-user directory absent from PSModulePath' {
        $result = Invoke-TestInstaller -WrongModulePath
        $result.ExitCode | Should -Not -Be 0
        $result.Text | Should -Match 'not on PSModulePath'
        Test-Path -LiteralPath $modules | Should -BeFalse
    }
    It 'refuses a directory at a module file path even with Force' {
        $occupied = Join-Path $destination 'PoshManage.psm1'
        [void][IO.Directory]::CreateDirectory($occupied)
        $result = Invoke-TestInstaller '-Force'
        $result.ExitCode | Should -Not -Be 0
        $result.Text | Should -Match 'directory occupies a module file path'
        @(Get-ChildItem -LiteralPath $occupied -Force).Count | Should -Be 0
    }
}

Describe 'Real Oh My Posh activation' -Tag Integration {
    It 'renders two themes in the caller session and persists the second theme' {
        $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'PoshManage\PoshManage.psd1'
        $root = Join-Path $TestDrive 'real activation'
        [void][IO.Directory]::CreateDirectory($root)
        $script = @'
$ErrorActionPreference = 'Stop'
$root = '__ROOT__'
$env:POSH_SESSION_ID = $null
$env:POSH_CONFIG = $null
$env:LOCALAPPDATA = Join-Path $root 'LocalAppData'
Import-Module '__MODULE__'
Import-Module PSReadLine
$context = [pscustomobject]@{
    HomePath = $root
    ThemeDirectory = Join-Path $root '.poshthemes'
    BackupDirectory = Join-Path $root 'backups'
    ProfilePath = Join-Path $root 'profile.ps1'
    OtherProfiles = @()
}
[void][IO.Directory]::CreateDirectory($context.ThemeDirectory)
foreach ($name in @('alpha', 'beta')) {
    $theme = @{
        version = 4
        blocks = @(@{
            type = 'prompt'
            alignment = 'left'
            segments = @(@{ type = 'text'; style = 'plain'; template = "POSH_MANAGE_$($name.ToUpperInvariant())" })
        })
    } | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText((Join-Path $context.ThemeDirectory "$name.omp.json"), $theme)
}
& (Get-Module PoshManage) {
    param($context)
    $script:integrationContext = $context
    function script:Get-PoshManageContext { $script:integrationContext }
} $context
poshthemes switch alpha | Out-Null
if ((prompt | Out-String) -notmatch 'POSH_MANAGE_ALPHA') { throw 'The caller prompt did not render alpha.' }
poshthemes switch beta | Out-Null
if ((prompt | Out-String) -notmatch 'POSH_MANAGE_BETA') { throw 'The caller prompt did not render beta.' }
$profilePath = $context.ProfilePath.Replace("'", "''")
$fresh = & pwsh -NoLogo -NoProfile -NonInteractive -Command "Import-Module PSReadLine; . '$profilePath'; prompt" 2>&1
if ($LASTEXITCODE -ne 0 -or ($fresh -join "`n") -notmatch 'POSH_MANAGE_BETA') {
    throw "A fresh session did not render beta: $fresh"
}
$before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($context.ProfilePath))
$backupCount = @(Get-ChildItem -LiteralPath $context.BackupDirectory -File).Count
foreach ($invalid in @('{', '{"blocks":1}', '"scalar"', '[{}]')) {
    [IO.File]::WriteAllText((Join-Path $context.ThemeDirectory 'broken.omp.json'), $invalid)
    $failed = $false
    try { poshthemes switch broken | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'An invalid theme silently activated a fallback.' }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($context.ProfilePath)) -cne $before) {
        throw 'An invalid theme changed the saved profile.'
    }
    if (@(Get-ChildItem -LiteralPath $context.BackupDirectory -File).Count -ne $backupCount) {
        throw 'An invalid theme created an unnecessary backup.'
    }
}
'@
        $script = $script.Replace('__ROOT__', $root.Replace("'", "''")).Replace('__MODULE__', $module.Replace("'", "''"))
        $output = & pwsh -NoLogo -NoProfile -NonInteractive -Command $script 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}
