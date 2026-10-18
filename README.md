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
- Installs Falcon BMS (public installs also require Falcon 4.0 from GoG or Steam; internal installs do not)

`Maintenance and Troubleshooting`
- `Target a different Falcon BMS installation`
  - Select a different wine prefix for the Helper to target in its operations

- `Installation checks`
  - Applies the WPF/launcher compatibility registry fixes (disables hardware acceleration, normalizes DPI), installs `corefonts`/`tahoma`/`gdiplus`, refreshes the OpenXR/VR registry setup and runtime JSON for the configured Proton runner, and reports whether .NET Framework 4.8 is detected. `Install Falcon BMS` already does all of this automatically; use this to (re)apply/check it on a prefix targeted via `Target a different Falcon BMS installation` that skipped that step.

- `Open Wine prefix configuration`
  - Runs *winecfg* in the game's Wine prefix

- `Open Wine controller configuration`
  - Opens Wine's game controller configuration in the Wine prefix

- `Open Protontricks package manager`
  - Opens the package manager GUI for the currently targeted Falcon BMS prefix

- `Install PowerShell into Wine prefix`
  - Uses protontricks for the install workflow

- `Set up OpenTrack head tracking (native Linux)`
  - Configures native Linux OpenTrack to feed Falcon BMS through Proton (see **Head tracking (OpenTrack)** below). Offers to remove a Windows OpenTrack from the prefix, and builds OpenTrack from source if no Wine-enabled build is installed

- `Uninstall an application from the prefix`
  - Lists the Windows applications registered in the targeted prefix and runs the selected one's own uninstaller, then removes helper shortcuts whose executable is gone. Falcon BMS, Wine Mono/Gecko, .NET and Visual C++ runtimes are not listed

- `Display Helper and Falcon BMS directories`
  - Show all the directories currently in use by both the Helper and Falcon BMS

- `Reset Helper configs`
  - Delete the configs saved by the helper in *$XDG_CONFIG_HOME/bms-helper/*


## Installation

**From Source:**
1. Download it! https://github.com/benchmarksims/bms-helper/releases
2. Extract it!
3. Public install: place `Falcon BMS_4.38.1_Full_Setup.exe`, `Falcon BMS_4.38.1_Full_Setup.nsisbin` and `setup_falcon_4_2.0.0.1.exe` (from GoG) in the bms-helper extracted folder
4. Internal install: place the internal Falcon BMS installer package in the helper folder (Falcon 4.0 media is not required)
4. Run the `bms-helper.sh`!

_Dependencies: **bash**, **coreutils**, **curl**, **polkit**, **wine**, **protontricks**_
_Archive Dependencies: **cabextract**, **unzip**_
_Optional Dependencies: **zenity** (GUI), **opentrack** built with Wine support (head tracking; the helper can build it), **winetricks** (custom-prefix launcher font/runtime fixes), **python3** + **python-evdev** (MFD helper), **gamemode**, **mangohud**_

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
- Head tracking now uses native Linux OpenTrack through its Wine output and a per-prefix Proton bridge; a Windows OpenTrack inside the prefix is no longer needed or auto-started.
- The MFD helper can also be overridden with `BMS_MFD_JOYSTICK_SCRIPT` if you keep the script in a different path.
- When the launcher is regenerated or repaired, the helper also refreshes an existing `mfd-joystick.py` copy already placed beside `bms-launcher.sh`.
- Proton management now includes a dedicated menu entry for Proton installs detected from Steam and common OS locations.
- Steam/OS-provided Proton installs can be selected for launch, but only helper-downloaded runners under the prefix are removable from the helper UI.

**Launcher toggles**

The generated launcher exports a set of environment variables you can override before starting Falcon BMS:

- `BMS_USE_GAMEMODE=1|0`: wrap the game/launcher process with `gamemoderun` when available.
- `BMS_USE_MANGOHUD=1|0`: wrap the game/launcher process with `mangohud` when available.
- `BMS_USE_FSYNC=1|0`: disable fsync by exporting `PROTON_NO_FSYNC=1` when set to `0`.
- `BMS_USE_ESYNC=1|0`: disable esync by exporting `PROTON_NO_ESYNC=1` when set to `0`.
- `BMS_MFD_JOYSTICK_SCRIPT=/path/to/mfd-joystick.py`: point the launcher at a custom MFD helper script.
- `BMS_MFD_GRAB_PHYSICAL=1|0`: when the MFD helper runs, exclusively grab the physical MFD evdev devices so only the virtual replacements are visible to the game.
- `BMS_PROTONTRICKS_APPID=<steam app id>`: let the launcher use `protontricks` for one-time font/runtime setup on Steam-backed installs.

The launcher always runs Falcon BMS through Proton; it exits with an error if no Proton runner is configured instead of falling back to Wine. Use `Manage Proton Runners` in the helper to install or select one.

**Head tracking (OpenTrack)**

Falcon BMS reads head tracking through the TrackIR interface (`NPClient64.dll`). Native Linux OpenTrack provides it with its `Wine -- Windows layer for Unix` output, which runs a small bridge (`opentrack-wrapper-wine.exe.so`) inside the game's prefix. No Windows OpenTrack is needed.

`Set up OpenTrack head tracking (native Linux)` in `Manage & Install other Apps`:

- Offers to uninstall a Windows OpenTrack found in the prefix (it would compete for the TrackIR registry path).
- Uses an installed OpenTrack built with Wine support (e.g. the AUR `opentrack` package). Otherwise it installs the build dependencies with your package manager (pacman, apt, dnf or zypper) and builds OpenTrack from source into `~/.local/share/bms-helper/opentrack`, with an `OpenTrack` menu entry.
- Writes `opentrack-proton-bridge.sh` into the prefix and sets the active OpenTrack profile's output to `Wine`, protocol `NPClient`, with that script as the custom Wine binary. The previous profile is saved as `<profile>.ini.bms-helper.bak`.

Start OpenTrack and press Start, before or after launching Falcon BMS. The bridge waits until Falcon's launcher or game is running, then starts the wrapper with the prefix's Proton runner and the game's esync/fsync/ntsync settings, so it joins the game's wineserver inside the umu/pressure-vessel container. It stops the wrapper again when Falcon exits. The wrapper and DLLs are staged in `<prefix>/opentrack/`, because the container cannot see host paths like `/usr/libexec`. Bridge log: `<prefix>/opentrack/bridge.log`.

**MFD helper**

`tools/mfd-joystick.py` creates virtual joystick-style devices for supported Thrustmaster F-16 MFD panels so Falcon BMS can see a more compatible input layout.

- It is started automatically if the file exists either next to the launcher or in `tools/`.
- It requires `python3` and the Python `evdev` package.
- It exposes an internal `MFD_JOYSTICK_VERSION` value and prints that version on startup for tracking deployed copies.
- Place the script in the falcon-bms master folder (the one created by wine / proton) along side `bms-launcher.sh`
- On most systems you will also need permissions for `uinput` and access to the source input devices.
- By default it exclusively grabs the physical MFD evdev nodes while it is running, which hides the source devices from Wine/Proton and leaves the virtual devices as the ones the game sees. Set `BMS_MFD_GRAB_PHYSICAL=0` to disable that behavior.
- When `mfd-joystick.py` is present beside `bms-launcher.sh`, the launcher now asks that Python file to set the Wine `Software\\Wine\\DirectInput\\Joysticks` disable entries for the original MFDs through `wine reg add` before any Wine or Proton command is run.

