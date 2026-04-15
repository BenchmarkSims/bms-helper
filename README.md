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

- `Open Protontricks package manager`
  - Opens the package manager GUI for the currently targeted Falcon BMS prefix

- `Install PowerShell into Wine prefix`
  - Uses protontricks for the install workflow

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

_Dependencies: **bash**, **coreutils**, **curl**, **polkit**, **wine**, **protontricks**_
_Archive Dependencies: **cabextract**, **unzip**_
_Optional Dependencies: **zenity** (GUI), **winetricks** (custom-prefix launcher font/runtime fixes), **python3** + **python-evdev** (MFD helper), **gamemode**, **mangohud**_

## Notes
#### Forked and inspired from:
- https://github.com/starcitizen-lug/lug-helper

## Recent changes (helper and launcher)

These notes summarize the current launcher behavior reflected in the latest script changes.

- The generated per-prefix launcher now applies launcher UI compatibility fixes by default for .NET/WPF-based launchers running under Proton.
- One-time launcher runtime fixes can install `corefonts`, `tahoma`, and `gdiplus` automatically through `protontricks` when an app ID is known, or through `winetricks` for custom prefixes.
- Launches can now be wrapped with `gamemoderun` and `mangohud` without modifying the generated script manually.
- `PROTON_LOG` is no longer forced on for every launch; it is now controlled through an environment toggle.
- Proton fsync and esync can be disabled explicitly for troubleshooting without editing the launcher.
- The launcher can auto-start the bundled `tools/mfd-joystick.py` helper when present and stop it again when Falcon BMS exits.
- The MFD helper can also be overridden with `BMS_MFD_JOYSTICK_SCRIPT` if you keep the script in a different path.

**Launcher toggles**

The generated launcher exports a set of environment variables you can override before starting Falcon BMS:

- `BMS_LAUNCHER_UI_FIXES=1|0`: enable or disable the default WPF/launcher registry fixes.
- `BMS_LAUNCHER_INSTALL_FONTS=1|0`: allow the one-time `corefonts` / `tahoma` / `gdiplus` install pass.
- `BMS_LAUNCHER_FORCE_WINED3D=1|0`: set `PROTON_USE_WINED3D` for the launcher path.
- `BMS_USE_GAMEMODE=1|0`: wrap the game/launcher process with `gamemoderun` when available.
- `BMS_USE_MANGOHUD=1|0`: wrap the game/launcher process with `mangohud` when available.
- `BMS_PROTON_LOG=1|0`: enable Proton logging only when you actually need it.
- `BMS_USE_FSYNC=1|0`: disable fsync by exporting `PROTON_NO_FSYNC=1` and `WINEFSYNC=0` when set to `0`.
- `BMS_USE_ESYNC=1|0`: disable esync by exporting `PROTON_NO_ESYNC=1` and `WINEESYNC=0` when set to `0`.
- `BMS_MFD_JOYSTICK_SCRIPT=/path/to/mfd-joystick.py`: point the launcher at a custom MFD helper script.
- `BMS_PROTONTRICKS_APPID=<steam app id>`: let the launcher use `protontricks` for one-time font/runtime setup on Steam-backed installs.

The launcher still supports `--proton`, `--wine`, and `--auto` to select the runner mode at launch time.

**MFD helper**

`tools/mfd-joystick.py` creates virtual joystick-style devices for supported Thrustmaster F-16 MFD panels so Falcon BMS can see a more compatible input layout.

- It is started automatically if the file exists either next to the launcher or in `tools/`.
- It requires `python3` and the Python `evdev` package.
- Place the script in the falcon-bms master folder (the one created by wine / proton) along side `bms-launcher.sh`
- On most systems you will also need permissions for `uinput` and access to the source input devices.

