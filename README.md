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

