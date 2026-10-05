#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'PoshManage supports PowerShell 7 on Windows only.'
}
if (-not $PROFILE.CurrentUserAllHosts) {
    throw 'This host does not define a current-user profile directory.'
}

$source = Join-Path $PSScriptRoot 'PoshManage'
$manifestPath = Join-Path $source 'PoshManage.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
$moduleDirectory = Join-Path (Split-Path -Parent $PROFILE.CurrentUserAllHosts) 'Modules'
$available = @($env:PSModulePath -split [IO.Path]::PathSeparator |
    Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })
if ($moduleDirectory.TrimEnd('\') -notin $available) {
    throw "The current-user module directory is not on PSModulePath: $moduleDirectory. Resolve PSModulePath before installation."
}
$destination = Join-Path (Join-Path $moduleDirectory 'PoshManage') $manifest.Version.ToString()
$files = @('PoshManage.psd1', 'PoshManage.psm1')
$identical = [IO.Directory]::Exists($destination)
foreach ($name in $files) {
    $target = Join-Path $destination $name
    if ([IO.Directory]::Exists($target)) {
        throw "A directory occupies a module file path: $target. Resolve that directory before installation."
    }
    if (-not [IO.File]::Exists($target) -or
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) -cne
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $source $name)))) {
        $identical = $false
    }
}
if ($identical) {
    Write-Output "PoshManage $($manifest.Version) is already installed in: $destination"
    return
}
if ([IO.Directory]::Exists($destination) -and -not $Force) {
    throw "An installation with different files exists at $destination. Run Install-PoshManage.ps1 -Force to replace this version."
}
if (-not $PSCmdlet.ShouldProcess($destination, "Install PoshManage $($manifest.Version)")) {
    return
}

$original = @{}
foreach ($name in $files) {
    $target = Join-Path $destination $name
    $original[$name] = if ([IO.File]::Exists($target)) { ,([IO.File]::ReadAllBytes($target)) } else { $null }
}
[void][IO.Directory]::CreateDirectory($destination)
try {
    foreach ($name in $files) {
        Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $destination $name) -Force -ErrorAction Stop
    }
    [void](Test-ModuleManifest -Path (Join-Path $destination 'PoshManage.psd1') -ErrorAction Stop)
}
catch {
    $failure = $_.Exception.Message
    try {
        foreach ($name in $files) {
            $target = Join-Path $destination $name
            if ($null -ne $original[$name]) {
                [IO.File]::WriteAllBytes($target, $original[$name])
            }
            elseif ([IO.File]::Exists($target)) {
                [IO.File]::Delete($target)
            }
        }
    }
    catch {
        throw "Installation failed: $failure Recovery also failed: $($_.Exception.Message). Inspect $destination before retrying."
    }
    throw "Installation failed and its file changes were rolled back: $failure"
}
Write-Output "Installed PoshManage $($manifest.Version) in: $destination"
Write-Output 'Run Import-Module PoshManage, then poshthemes help. New sessions can auto-load the module.'
