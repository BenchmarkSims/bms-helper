# Falcon BMS Helper

_**This script is designed to help you manage and optimize Falcon BMS on Linux.**_

Zenity menus are used for a GUI experience with a fallback to terminal-based menus where Zenity is unavailable.  
Command line arguments are available for quickly launching functions from the terminal.  

Configuration is saved in *$XDG_CONFIG_HOME/bms-helper/*

## Options

`Preflight Check`
- Runs a series of system optimization checks and offers to fix any issues
  - Checks that vm.max_map_count is set to at least 16777216
    - This sets the maxmimum number of "memory map areas" a process can have. While most applications need less than a thousand maps, Falcon BMS requires access to more
  - Checks that the hard open file descriptors limit is set to at least 524288
    - This limits the maximum number of open files on your system.  On some Linux distributions, the default is set too low for Falcon BMS

`Install Falcon BMS`
- Installs Falcon BMS and Falcon 4.0 (GoG installer)

`Maintenance and Troubleshooting`
- `Target a different Falcon BMS installation`
  - Select a different wine prefix for the Helper to target in its operations

- `Open Wine prefix configuration`
  - Runs *winecfg* in the game's Wine prefix

- `Open Wine controller configuration`
  - Opens Wine's game controller configuration in the Wine prefix

- `Install PowerShell into Wine prefix`
  - Uses winetricks to install PowerShell

- `Display Helper and Falcon BMS directories`
  - Show all the directories currently in use by both the Helper and Falcon BMS

- `Reset Helper configs`
  - Delete the configs saved by the helper in *$XDG_CONFIG_HOME/bms-helper/*


## Installation

**From Source:**
1. Download it! https://github.com/benchmarksims/bms-helper/releases
2. Extract it!
3. Place `Falcon BMS_4.38.1_Full_Setup.exe`, `Falcon BMS_4.38.1_Full_Setup.nsisbin` and `setup_falcon_4_2.0.0.1.exe` (from GoG) in the bms-helper extracted folder
4. Run the `bms-helper.sh`!

_Dependencies: **bash**, **coreutils**, **curl**, **polkit**, **wine**_
_Winetricks Dependencies: **cabextract**, **unzip**_
_Optional Dependencies: **zenity** (for GUI)_

## Notes
#### Forked and inspired from:
- https://github.com/starcitizen-lug/lug-helper

## Recent changes (helper and launcher)

These notes summarize features and changes added to the helper script and the launcher since the earlier README content.

- Added a per-prefix launcher script `bms-launcher.sh` used by desktop entries and maintenance actions to consistently launch the game from the configured Wine/Proton runner.
- Desktop integration: the helper can now refresh existing `.desktop` Exec lines to point at the generated launcher script so the selected Proton/Wine runner is respected.
- Installer detection: the helper accepts `--installer /path/to/installer.exe` (or the `BMS_INSTALLER` environment variable) and heuristically switches between `public` and `internal` modes based on the installer filename.
- Internal mode support: configuration can be persisted under `falcon-bms-internal` and the helper will offer to restart in internal mode if such a config is detected.
- Proton/runner support: the helper recognizes Proton runner installs and will prefer a persisted `current_runner` when deciding which runner binary to use. A default Proton GE version is provided via `PROTON_DEFAULT_VERSION`.
- Protontricks requirement: `protontricks` is now required for prefix setup and maintenance actions (please install it on systems using Proton).
- Archive helper utilities: `cabextract` and `unzip` are required for handling certain installers and archives.
- CLI improvements: simple CLI args supported include `--installer`, `--internal`, and `--public` for quicker scripting and automation.
- Configuration locations: configuration and data directories follow XDG base directories (`$XDG_CONFIG_HOME` and `$XDG_DATA_HOME`) and defaults are provided in the script.
- Preflight and requirements: the helper includes preflight checks (vm.max_map_count, open file descriptors) and documents minimum recommended RAM/swap requirements.
- DXVK / DXVK async: a dedicated dxvk async download source is available and referenced in the script for DXVK-related operations.
- UX improvements: zenity integration for GUI dialogs and a robust fallback to terminal-based messages; progress bar improvements using a FIFO to allow concurrent updates.

If you want these items expanded into a full changelog or split into a dedicated `CHANGELOG.md`, tell me and I will add it.

**Launcher: Proton/Wine options and environment variables**

The per-prefix launcher and helper support choosing between Proton and Wine runners. Key points for configuring and forcing a runner:

- `current_runner` file: place a plain text file named `current_runner` inside the install directory (the directory targeted by the helper). The helper reads the first line and will prefer that path as a Proton runtime when present.
- `proton_path` environment variable: the generated per-prefix launch script may export `proton_path` (for example: `export proton_path="/home/user/.local/share/Steam/compatibilitytools.d/GE-Proton10-32"`). The helper detects this in saved launch scripts and uses it as a Proton candidate.
- `PROTON_DEFAULT_VERSION`: a script-level default used when showing Proton lists or preselecting versions (example value present in the script: `GE-Proton10-32`).
- Fallback behavior: if no Proton candidate is discovered, the helper falls back to the system `wine` binary found in `PATH`.
- CLI flags: the per-prefix launcher commonly supports mode flags such as `--proton /path/to/proton` and `--wine /path/to/wine` to override runner selection at launch time. If your `bms-launcher.sh` supports these, pass them directly; otherwise use `proton_path` or `current_runner` to persist a selection.

Examples:

1. Persist a Proton runtime for an install by creating `current_runner` containing the Proton runtime path.

2. Export `proton_path` before invoking the launcher to use a specific Proton runtime for that invocation:

```
export proton_path="/home/user/.local/share/Steam/compatibilitytools.d/GE-Proton10-32"
./bms-launcher.sh
```

3. To force falling back to Wine, ensure no `current_runner` exists and that `wine` is available in `PATH` (the helper will detect `wine` automatically).

Note: installer-detection and mode selection still use the `BMS_INSTALLER` environment variable and the helper's `--installer`, `--internal`, and `--public` CLI flags described above.

