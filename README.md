# posh-manage

A theme file controls how your shell prompt looks. `posh-manage` lists and switches Oh My Posh themes in Zsh and PowerShell 7 on Windows. The Zsh script reads `.omp.json` files from `~/.poshthemes` and updates `~/.zshrc`. The PowerShell module reads `$HOME\.poshthemes` and updates the invoking host's user profile. Neither version installs Oh My Posh or downloads theme files.

## Requirements

Run the script with Zsh on macOS or Linux. Install Oh My Posh before you switch themes. Store one or more `.omp.json` theme files in `~/.poshthemes`. The script reads and updates the startup file at `~/.zshrc`.

For the module, use PowerShell 7 on Windows. Windows PowerShell 5.1 is not supported. Store your `.omp.json` files in `$HOME\.poshthemes` and make sure that `oh-my-posh` is on `PATH` before switching themes.

## Setup

Clone this repository. Enter its directory. Create `~/.poshthemes` if it does not exist. Copy your `.omp.json` theme files into that folder. Run the help command from the repository directory:

```sh
git clone https://github.com/SpencerAxelrod/posh-manage.git
cd posh-manage
mkdir -p ~/.poshthemes
./poshthemes help
```

## Commands

Run these commands from the repository directory:

- Run `./poshthemes list` to display available theme files.
- Run `./poshthemes switch <theme>` to select a theme.
- Run `./poshthemes current` to display the selected theme and the first ten lines of its file.
- Run `./poshthemes help` to display command help.

Use a theme file name with or without the `.omp.json` suffix when you run `switch`. The `list` command also accepts `ls` and `-l`. The `switch` command also accepts `set` and `-s`. The `current` command also accepts `show` and `-c`. The `help` command also accepts `-h` and `--help`.

## Theme changes

Before it changes `~/.zshrc`, the script tries to save a timestamped copy in `~/.zshrc_backups`. It creates the backup folder if needed. If `~/.zshrc` has an Oh My Posh startup line that uses a path under `~/.poshthemes`, `switch` replaces the theme path. If `~/.zshrc` has no Oh My Posh startup line, `switch` adds one. If an existing Oh My Posh line uses a different path, `switch` leaves it unchanged.

Run `source ~/.zshrc` in your current Zsh session to load the new theme. A new Zsh session reads the updated file at startup.

## PowerShell installation

Run the following commands in PowerShell 7 on Windows. If you already cloned the repository, enter its directory and run the installer. The installer copies module version `0.1.0` into the current user's PowerShell module directory:

```powershell
git clone https://github.com/SpencerAxelrod/posh-manage.git
Set-Location posh-manage
.\Install-PoshManage.ps1
Import-Module PoshManage
New-Item -ItemType Directory -Path (Join-Path $HOME '.poshthemes') -Force
poshthemes help
```

Copy your `.omp.json` theme files into `$HOME\.poshthemes`. The installer does not change a profile or require administrator rights. A new session can load the installed module when you first run `poshthemes`.

An identical installation makes no changes. If this module version contains different files, the installer stops. Use `.\Install-PoshManage.ps1 -Force` to replace that version, or `.\Install-PoshManage.ps1 -WhatIf` to display the planned operation.

You can also load the module directly from the repository with `Import-Module .\PoshManage\PoshManage.psd1`. This release uses installation from the cloned repository, not a PowerShell Gallery package. Gallery publication is a separate follow-up.

## PowerShell commands

Use the `poshthemes` command after installing or importing the module. `Invoke-PoshThemes` is the full function name for the same command. The commands and aliases match the Zsh interface:

| Command | Aliases | Result |
| --- | --- | --- |
| `poshthemes list` | `ls`, `-l` | List themes and mark the saved selection. |
| `poshthemes switch <theme>` | `set`, `-s` | Save and apply the selected theme. |
| `poshthemes current` | `show`, `-c` | Show the saved selection and up to ten lines from its file. |
| `poshthemes help` | `-h`, `--help` | Show commands, paths, and requirements. |

Use a theme filename with or without the `.omp.json` suffix. Quote filenames that contain spaces or special characters. With no arguments, `poshthemes` displays help.

```powershell
poshthemes list
poshthemes switch iterm2
poshthemes -s 'my theme.omp.json'
poshthemes current
```

Only `switch` requires the Oh My Posh executable. `current` reports the theme saved in the profile, not an independently changed prompt. Invalid input and file failures produce errors without claiming that a switch succeeded.

## PowerShell profile changes

A profile is the startup script that PowerShell loads. The module updates `$PROFILE.CurrentUserCurrentHost`. PowerShell terminals and Visual Studio Code can use different profiles, so switch themes in each host that you want to configure.

Before changing an existing profile, the module saves an exact timestamped backup in `$HOME\.powershell_profile_backups`. It preserves unrelated code, text encoding, and line endings. A missing profile is created without an empty backup, and selecting the already saved theme creates no extra backup.

The module accepts one simple initializer that points to a theme under `$HOME\.poshthemes`. It replaces only the theme argument. If no initializer exists, it adds a standard Oh My Posh startup line with the theme's absolute path.

If an initializer uses a different directory, a built-in theme, or a URL, the module stops without changing it. It also stops for duplicate, conditional, dynamic, or inherited initialization. Review the profile named in the error and resolve the setup manually before switching.

The module inspects direct commands in the standard startup profiles without executing them. It does not follow arbitrary imports or evaluate expressions to discover theme paths. A signed profile includes a digital signature, so the module refuses to edit it automatically.

After saving the profile, `switch` applies the theme to the current session. It does not reload the entire profile. Future sessions load the selected theme from the updated profile.

Before changing a profile, the module prepares the initializer from the installed Oh My Posh executable. It makes sure that Oh My Posh loads the selected file instead of silently using a fallback theme. Invalid configuration produces an error without changing the saved profile or current prompt.

## PowerShell recovery and removal

If activation fails, the module tries to restore the original profile. If another editor changes the profile, the module preserves that later edit and reports the backup path. Resolve the reported error, restore the required profile content from that backup, and restart PowerShell.

If PowerShell blocks scripts, follow your organization's execution policy. An execution policy controls which scripts PowerShell can run. The installer and module do not change that policy or bypass it.

To unload the module from the current session, run `Remove-Module PoshManage`. To remove the installation, delete only the `PoshManage\0.1.0` directory reported by the installer. The profile initializer, theme files, and backups remain until you remove them separately.

## PowerShell development

The tests require Pester 5 and PowerShell 7 on Windows. The integration test also requires Oh My Posh on `PATH`. Tests use temporary profiles and installation directories rather than your actual profile.

Run these commands from the repository directory:

```powershell
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
$result = Invoke-Pester -Path .\tests\PoshManage.Tests.ps1 -Output Normal -PassThru
if ($result.FailedCount) { throw "$($result.FailedCount) tests failed." }
```

## License

This project uses the MIT License. The license permits you to use, modify, and distribute the software. Read [LICENSE](LICENSE) for the full terms.
