<#
.SYNOPSIS
Defines the PoshManage module manifest.

.DESCRIPTION
The manifest declares the module version, main module file, and PowerShell requirements.
It exports `Invoke-PoshThemes` and the `poshthemes` alias.
The module requires PowerShell 7 or later on Windows.
#>
@{
    RootModule = 'PoshManage.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'bfbd4cfe-a58b-4dec-a30d-230825e22fbd'
    Author = 'Posh Manage contributors'
    Description = 'List and switch local Oh My Posh themes in PowerShell 7 on Windows.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @('Invoke-PoshThemes')
    AliasesToExport = @('poshthemes')
    CmdletsToExport = @()
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Windows', 'OhMyPosh', 'Themes')
            LicenseUri = 'https://github.com/SpencerAxelrod/posh-manage/blob/main/LICENSE'
            ProjectUri = 'https://github.com/SpencerAxelrod/posh-manage'
        }
    }
}
