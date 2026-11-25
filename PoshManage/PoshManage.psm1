<#
.SYNOPSIS
Lists and switches local Oh My Posh themes in PowerShell 7 on Windows.

.DESCRIPTION
Themes are JSON prompt designs stored in `$HOME\.poshthemes`.
The module reads the profile for the current user and PowerShell host.
This profile is the startup script for that host.
It parses the profile before it adds or changes an Oh My Posh startup command.
It preserves the profile encoding and line endings. It backs up an existing profile before each change.
It stops when the current profile is signed or its Oh My Posh startup command is complex.
It also stops when another standard profile runs an Oh My Posh startup command.
It prepares the requested theme before it updates the prompt in the current session.
Importing the module does not change the prompt.

.NOTES
Exports `Invoke-PoshThemes` and the `poshthemes` alias.
Theme switching requires Oh My Posh on `PATH`.
#>
#requires -Version 7.0

if (-not $IsWindows) {
    throw 'PoshManage supports PowerShell 7 on Windows only.'
}

function Get-PoshManageContext {
    if (-not $PROFILE.CurrentUserCurrentHost) {
        throw 'This host does not define a current-user profile. Run PoshManage in a local PowerShell host.'
    }
    [pscustomobject]@{
        HomePath = $HOME
        ThemeDirectory = Join-Path $HOME '.poshthemes'
        BackupDirectory = Join-Path $HOME '.powershell_profile_backups'
        ProfilePath = $PROFILE.CurrentUserCurrentHost
        OtherProfiles = @(
            $PROFILE.AllUsersAllHosts
            $PROFILE.AllUsersCurrentHost
            $PROFILE.CurrentUserAllHosts
        ) | Where-Object { $_ -and $_ -ne $PROFILE.CurrentUserCurrentHost } | Select-Object -Unique
    }
}

function Read-PoshProfile {
    param([string]$Path)

    $encoding = [Text.UTF8Encoding]::new($false, $true)
    $bytes = [byte[]]@()
    $exists = $false
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.PSIsContainer) {
            throw "The profile path is a directory: $Path"
        }
        $bytes = [IO.File]::ReadAllBytes($Path)
        $exists = $true
    }
    catch [Management.Automation.ItemNotFoundException] {
        # A new host can have no profile or profile directory.
    }

    $offset = 0
    if ($bytes.Length -ge 4 -and (
        ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0 -and $bytes[3] -eq 0) -or
        ($bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF)
    )) {
        throw "Unsupported profile encoding at $Path. Save the profile as UTF-8 or BOM-marked UTF-16."
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encoding = [Text.UTF8Encoding]::new($true, $true)
        $offset = 3
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $encoding = [Text.UnicodeEncoding]::new($false, $true, $true)
        $offset = 2
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $encoding = [Text.UnicodeEncoding]::new($true, $true, $true)
        $offset = 2
    }
    try {
        $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch [Text.DecoderFallbackException] {
        throw "Unsupported profile encoding at $Path. Save the profile as UTF-8 or BOM-marked UTF-16."
    }
    if ($text.Contains([char]0)) {
        throw "Unsupported profile encoding at $Path. Save the profile as UTF-8 or BOM-marked UTF-16."
    }
    $newline = "`r`n"
    $match = [regex]::Match($text, '\r\n|\n|\r')
    if ($match.Success) {
        $newline = $match.Value
    }
    [pscustomobject]@{
        Path = $Path
        Exists = $exists
        Bytes = $bytes
        Text = $text
        Encoding = $encoding
        Newline = $newline
    }
}

function Get-PoshLiteral {
    param([Management.Automation.Language.Ast]$Node, [string]$HomePath)

    if ($Node -is [Management.Automation.Language.CommandParameterAst] -and -not $Node.Argument) {
        return '-' + $Node.ParameterName
    }
    if ($Node -is [Management.Automation.Language.StringConstantExpressionAst]) {
        return $Node.Value
    }
    if ($Node -is [Management.Automation.Language.ExpandableStringExpressionAst]) {
        if (-not $Node.NestedExpressions.Count) {
            return $Node.Value
        }
        $expression = $Node.NestedExpressions[0]
        $start = $Node.Extent.StartOffset
        if ($Node.Extent.Text.StartsWith('"')) {
            $start++
        }
        if ($Node.NestedExpressions.Count -ne 1 -or
            $expression -isnot [Management.Automation.Language.VariableExpressionAst] -or
            $expression.VariablePath.UserPath -ne 'HOME' -or $expression.Extent.StartOffset -ne $start) {
            return $null
        }
        $prefix = [regex]::Match($Node.Value, '(?i)^\$(?:\{HOME\}|HOME)(?=[\\]|$)')
        if (-not $prefix.Success) {
            return $null
        }
        return $HomePath + $Node.Value.Substring($prefix.Length)
    }
    return $null
}

function Get-PoshProfileState {
    param($Profile, $Context)

    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Profile.Text, [ref]$tokens, [ref]$errors)
    if ($errors.Count) {
        throw "The profile has syntax errors: $($Profile.Path). Correct the profile before selecting a theme. $($errors[0].Message)"
    }
    $initializers = @($ast.FindAll({
        param($node)
        if ($node -isnot [Management.Automation.Language.CommandAst]) {
            return $false
        }
        $name = $node.GetCommandName()
        if ($name -and [IO.Path]::GetFileName($name) -in @('oh-my-posh', 'oh-my-posh.exe')) {
            if ($node.CommandElements.Count -lt 2) {
                return $false
            }
            $operation = Get-PoshLiteral $node.CommandElements[1] ''
            return $null -eq $operation -or $operation -eq 'init' -or
                ($operation.StartsWith('-') -and $operation -notin @('--help', '-h', '--version'))
        }
        return -not $name -and $node.CommandElements.Count -gt 2 -and
            (Get-PoshLiteral $node.CommandElements[1] '') -eq 'init' -and
            (Get-PoshLiteral $node.CommandElements[2] '') -in @('pwsh', 'powershell')
    }, $true))
    if ($initializers.Count -gt 1) {
        throw "Multiple Oh My Posh initializers exist in $($Profile.Path). Keep one simple initializer before switching themes."
    }
    $state = [pscustomobject]@{ ConfigPath = $null; ConfigNode = $null; ConfigPrefix = '' }
    if (-not $initializers.Count) {
        return $state
    }

    $command = $initializers[0]
    $pipeline = $command.Parent
    if (-not $command.GetCommandName() -or (Get-PoshLiteral $command.CommandElements[1] '') -ne 'init' -or
        $pipeline -isnot [Management.Automation.Language.PipelineAst] -or
        $pipeline.Parent -ne $ast.EndBlock -or $pipeline.Background -or
        $pipeline.PipelineElements.Count -ne 2 -or
        $pipeline.PipelineElements[0] -ne $command -or
        $command.Redirections.Count -or
        $command.InvocationOperator -notin @(
            [Management.Automation.Language.TokenKind]::Unknown,
            [Management.Automation.Language.TokenKind]::Ampersand
        )) {
        throw "Complex Oh My Posh initialization exists in $($Profile.Path). Replace it manually with one simple initializer before switching themes."
    }
    $consumer = $pipeline.PipelineElements[1]
    if ($consumer -isnot [Management.Automation.Language.CommandAst] -or
        $consumer.GetCommandName() -notin @('Invoke-Expression', 'iex') -or
        $consumer.CommandElements.Count -ne 1 -or $consumer.Redirections.Count) {
        throw "Unsupported Oh My Posh pipeline in $($Profile.Path). Use one initializer piped directly to Invoke-Expression."
    }
    $elements = $command.CommandElements
    if ($elements.Count -lt 3 -or (Get-PoshLiteral $elements[2] $Context.HomePath) -notin @('pwsh', 'powershell')) {
        throw "Unsupported Oh My Posh shell in $($Profile.Path). Use init pwsh."
    }
    for ($i = 3; $i -lt $elements.Count; $i++) {
        $value = Get-PoshLiteral $elements[$i] $Context.HomePath
        if ($null -eq $value) {
            throw "Dynamic Oh My Posh arguments exist in $($Profile.Path). Resolve them manually before switching themes."
        }
        if ($value -in @('--config', '-c')) {
            $i++
            if ($i -ge $elements.Count -or $state.ConfigNode) {
                throw "Ambiguous Oh My Posh configuration in $($Profile.Path). Keep one --config argument."
            }
            $state.ConfigNode = $elements[$i]
            $state.ConfigPath = Get-PoshLiteral $elements[$i] $Context.HomePath
        }
        elseif ($value.StartsWith('--config=', [StringComparison]::OrdinalIgnoreCase)) {
            if ($state.ConfigNode) {
                throw "Ambiguous Oh My Posh configuration in $($Profile.Path). Keep one --config argument."
            }
            $state.ConfigNode = $elements[$i]
            $state.ConfigPrefix = '--config='
            $state.ConfigPath = $value.Substring(9)
        }
        elseif ($value -notin @('--eval', '--strict')) {
            throw "Unsupported Oh My Posh argument '$value' in $($Profile.Path). Resolve the initializer manually before switching themes."
        }
    }
    if (-not $state.ConfigPath) {
        throw "Unmanaged Oh My Posh setup in $($Profile.Path). Set one literal --config path under $($Context.ThemeDirectory), or remove that initializer manually."
    }
    if ($state.ConfigPath.StartsWith('~\') -or $state.ConfigPath.StartsWith('~/')) {
        $state.ConfigPath = Join-Path $Context.HomePath $state.ConfigPath.Substring(2)
    }
    if (-not [IO.Path]::IsPathFullyQualified($state.ConfigPath)) {
        throw "Unmanaged Oh My Posh path in $($Profile.Path). Use an absolute path under $($Context.ThemeDirectory)."
    }
    $state.ConfigPath = [IO.Path]::GetFullPath($state.ConfigPath)
    $directory = [IO.Path]::GetDirectoryName($state.ConfigPath)
    if (-not [string]::Equals($directory.TrimEnd('\'), $Context.ThemeDirectory.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) -or
        -not $state.ConfigPath.EndsWith('.omp.json', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unmanaged Oh My Posh setup in $($Profile.Path). It uses '$($state.ConfigPath)'. Move its theme into $($Context.ThemeDirectory) and update the initializer manually, or remove that initializer."
    }
    return $state
}

function ConvertTo-PoshProfileBytes {
    param($Profile, [string]$Text)
    return ,([byte[]]($Profile.Encoding.GetPreamble() + $Profile.Encoding.GetBytes($Text)))
}

function Assert-PoshProfileUnchanged {
    param($Profile)

    $exists = [IO.File]::Exists($Profile.Path)
    if ($exists -ne $Profile.Exists -or [IO.Directory]::Exists($Profile.Path)) {
        throw "The profile changed during this operation: $($Profile.Path). Run the command again after resolving the change."
    }
    if ($exists -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($Profile.Path)) -cne
        [Convert]::ToBase64String($Profile.Bytes)) {
        throw "The profile changed during this operation: $($Profile.Path). Run the command again after resolving the change."
    }
}

function Write-PoshProfileBytes {
    param($Expected, [byte[]]$Bytes)

    $parent = [IO.Path]::GetDirectoryName($Expected.Path)
    [void][IO.Directory]::CreateDirectory($parent)
    $temporary = Join-Path $parent ('.posh-manage-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        Assert-PoshProfileUnchanged $Expected
        if ($Expected.Exists) {
            [IO.File]::Replace($temporary, $Expected.Path, [NullString]::Value)
        }
        else {
            [IO.File]::Move($temporary, $Expected.Path)
        }
    }
    finally {
        if ([IO.File]::Exists($temporary)) {
            [IO.File]::Delete($temporary)
        }
    }
}

function Backup-PoshProfile {
    param($Profile, [string]$Directory)

    [void][IO.Directory]::CreateDirectory($Directory)
    $name = [IO.Path]::GetFileName($Profile.Path) + '_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmss_fffffff') +
        '_' + [guid]::NewGuid().ToString('N') + '.bak'
    $path = Join-Path $Directory $name
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($Profile.Bytes, 0, $Profile.Bytes.Length)
    }
    finally {
        $stream.Dispose()
    }
    return $path
}

function Get-PoshExecutable {
    $command = Get-Command oh-my-posh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        throw 'Oh My Posh is not installed or is not on PATH. Install Oh My Posh before switching themes.'
    }
    return $command.Source
}

function Get-PoshInitializationScript {
    param([string]$Executable, [string]$ThemePath)

    $ErrorActionPreference = 'Stop'
    $process = [Diagnostics.Process]::new()
    try {
        $start = $process.StartInfo
        $start.FileName = $Executable
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.Encoding]::UTF8
        $start.StandardErrorEncoding = [Text.Encoding]::UTF8
        foreach ($argument in @('init', 'pwsh', '--config', $ThemePath, '--print')) {
            $start.ArgumentList.Add($argument)
        }
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $diagnostic = $stderr.Result.Trim()
        if ($process.ExitCode -ne 0 -or $diagnostic) {
            throw "Oh My Posh initialization failed (exit $($process.ExitCode)). $diagnostic"
        }
        $script = $stdout.Result
        if ([string]::IsNullOrWhiteSpace($script)) {
            throw 'Oh My Posh returned an empty initializer.'
        }
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($script, [ref]$tokens, [ref]$errors)
        if ($errors.Count) {
            throw "Oh My Posh returned an invalid initializer: $($errors[0].Message)"
        }
        $sources = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.UserPath -eq 'env:POSH_CONFIG'
        }, $true))
        if (-not $sources.Count) {
            $sources = @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -eq 'env:POSH_THEME'
            }, $true))
        }
        if ($sources.Count -ne 1 -or
            $sources[0].Right -isnot [Management.Automation.Language.CommandExpressionAst]) {
            throw 'Oh My Posh returned an initializer without a readable configuration source. Update Oh My Posh before switching themes.'
        }
        $resolved = Get-PoshLiteral $sources[0].Right.Expression ''
        if (-not $resolved -or -not [IO.Path]::IsPathFullyQualified($resolved) -or
            -not [string]::Equals([IO.Path]::GetFullPath($resolved), $ThemePath, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Oh My Posh did not load the selected theme: $ThemePath. Correct its configuration instead of using a fallback theme."
        }
        return $script
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-PoshInitialization {
    param([string]$Script)

    $ErrorActionPreference = 'Stop'
    Invoke-Expression -Command $Script -ErrorAction Stop
}

function Set-PoshTheme {
    param([string]$Name, $Context)

    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -in @('.', '..') -or
        $Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw 'Specify a theme filename, not a directory or path.'
    }
    if (-not $Name.EndsWith('.omp.json', [StringComparison]::OrdinalIgnoreCase)) {
        $Name += '.omp.json'
    }
    $themePath = Join-Path $Context.ThemeDirectory $Name
    $theme = Get-Item -LiteralPath $themePath -ErrorAction Stop
    if ($theme.PSIsContainer) {
        throw "The theme is not a file: $themePath"
    }
    $executable = Get-PoshExecutable
    $profile = Read-PoshProfile $Context.ProfilePath
    $state = Get-PoshProfileState $profile $Context
    if ($profile.Text -match '(?m)^# SIG # Begin signature block') {
        throw "The profile is signed: $($profile.Path). Edit and sign it manually before switching themes."
    }
    foreach ($otherPath in $Context.OtherProfiles) {
        $other = Read-PoshProfile $otherPath
        $otherState = Get-PoshProfileState $other $Context
        if ($otherState.ConfigNode) {
            throw "Oh My Posh is initialized in another startup profile: $otherPath. Resolve that initializer manually before switching themes."
        }
    }

    $literal = "'" + $themePath.Replace("'", "''") + "'"
    if ($state.ConfigNode) {
        $extent = $state.ConfigNode.Extent
        $text = $profile.Text.Substring(0, $extent.StartOffset) + $state.ConfigPrefix + $literal +
            $profile.Text.Substring($extent.EndOffset)
        if ([string]::Equals($state.ConfigPath, $themePath, [StringComparison]::OrdinalIgnoreCase)) {
            $text = $profile.Text
        }
    }
    else {
        $text = $profile.Text
        if ($text.Length -and -not ($text.EndsWith("`n") -or $text.EndsWith("`r"))) {
            $text += $profile.Newline
        }
        $text += "oh-my-posh init pwsh --config $literal | Invoke-Expression" + $profile.Newline
    }
    $candidate = [pscustomobject]@{ Path = $profile.Path; Text = $text }
    [void](Get-PoshProfileState $candidate $Context)
    $initializer = Get-PoshInitializationScript $executable $themePath
    $bytes = ConvertTo-PoshProfileBytes $profile $text
    $changed = $text -cne $profile.Text
    $backup = $null
    if ($changed) {
        Assert-PoshProfileUnchanged $profile
        if ($profile.Exists) {
            $backup = Backup-PoshProfile $profile $Context.BackupDirectory
        }
        Write-PoshProfileBytes $profile $bytes
    }
    try {
        Invoke-PoshInitialization $initializer
    }
    catch {
        $failure = $_.Exception.Message
        if ($changed) {
            $written = [pscustomobject]@{ Path = $profile.Path; Exists = $true; Bytes = $bytes }
            try {
                if ($profile.Exists) {
                    Write-PoshProfileBytes $written $profile.Bytes
                }
                else {
                    Assert-PoshProfileUnchanged $written
                    [IO.File]::Delete($profile.Path)
                }
            }
            catch {
                throw "Theme activation failed: $failure Rollback failed: $($_.Exception.Message) Backup: $backup. Resolve the profile manually and restart PowerShell."
            }
        }
        throw "Theme activation failed: $failure The saved profile was not changed or was restored. The current prompt can be partly changed. Restart PowerShell after resolving the error. Backup: $backup"
    }
    if ($backup) {
        Write-Output "Backed up profile to: $backup"
    }
    Write-Output "Theme switched to: $Name"
    Write-Output "Applied to the current session and saved in: $($profile.Path)"
}

function Show-PoshHelp {
    param($Context)

    @(
        'Oh My Posh Theme Manager'
        'Usage: poshthemes [COMMAND] [THEME_NAME]'
        '  list              List available themes (ls, -l)'
        '  switch <theme>    Save and apply a theme (set, -s)'
        '  current           Show the saved theme and ten-line preview (show, -c)'
        '  help              Show help (-h, --help)'
        'Examples: poshthemes switch iterm2; poshthemes current'
        "Themes: $($Context.ThemeDirectory)"
        "Profile: $($Context.ProfilePath)"
        "Backups: $($Context.BackupDirectory)"
        'Requires PowerShell 7 on Windows. Switching requires Oh My Posh on PATH.'
        'Existing unmanaged or complex initialization must be resolved manually.'
    )
}

function Invoke-PoshThemes {
    <#
    .SYNOPSIS
    Lists and switches local Oh My Posh themes.
    .DESCRIPTION
    Use list, switch <theme>, current, or help. The poshthemes alias accepts
    the existing command aliases, including -l, -s, -c, -h, and --help.
    Switching updates the invoking host's user profile and the current prompt.
    .EXAMPLE
    poshthemes switch iterm2
    #>
    $arguments = @($args)
    $context = Get-PoshManageContext
    $command = if ($arguments.Count) { [string]$arguments[0] } else { 'help' }
    $expected = if ($command -in @('switch', 'set', '-s')) { 2 } else { 1 }
    if ($arguments.Count -gt $expected) {
        throw "Unexpected arguments. Use: poshthemes $command$(if ($expected -eq 2) { ' <theme>' })"
    }
    switch ($command) {
        { $_ -in @('help', '-h', '--help') } { Show-PoshHelp $context; return }
        { $_ -in @('switch', 'set', '-s') } {
            if ($arguments.Count -lt 2) {
                throw 'Specify a theme name. Usage: poshthemes switch <theme>'
            }
            Set-PoshTheme ([string]$arguments[1]) $context
            return
        }
        { $_ -in @('list', 'ls', '-l', 'current', 'show', '-c') } {
            $profile = Read-PoshProfile $context.ProfilePath
            $state = Get-PoshProfileState $profile $context
            $current = if ($state.ConfigPath) { [IO.Path]::GetFileName($state.ConfigPath) } else { $null }
            if ($command -in @('current', 'show', '-c')) {
                if (-not $current) {
                    Write-Output "No Oh My Posh theme is configured in: $($context.ProfilePath)"
                    return
                }
                Write-Output "Current theme: $current"
                Write-Output 'Theme configuration preview:'
                Get-Content -LiteralPath $state.ConfigPath -TotalCount 10 -ErrorAction Stop
                return
            }
            $themes = @(Get-ChildItem -LiteralPath $context.ThemeDirectory -File -ErrorAction Stop |
                Where-Object { $_.Name.EndsWith('.omp.json', [StringComparison]::OrdinalIgnoreCase) } |
                Sort-Object Name)
            if (-not $themes.Count) {
                throw "No .omp.json theme files found in: $($context.ThemeDirectory)"
            }
            Write-Output "Available Oh My Posh themes in: $($context.ThemeDirectory)"
            for ($i = 0; $i -lt $themes.Count; $i++) {
                $marker = if ($themes[$i].Name -eq $current) { ' (current)' } else { '' }
                Write-Output "$($i + 1). $($themes[$i].Name)$marker"
            }
            Write-Output "Total themes found: $($themes.Count)"
            if (-not $current) {
                Write-Output "No Oh My Posh theme is configured in: $($context.ProfilePath)"
            }
            return
        }
        default { throw "Unknown command: $command. Use poshthemes help." }
    }
}

Set-Alias -Name poshthemes -Value Invoke-PoshThemes
Export-ModuleMember -Function Invoke-PoshThemes -Alias poshthemes
