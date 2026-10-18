# Falcon BMS Helper

_**This script is designed to help you install, run and maintain Falcon BMS on Linux.**_

Falcon BMS runs through Proton (GE-Proton, UMU-Proton or CachyOS Proton) with
[umu-launcher](https://github.com/Open-Wine-Components/umu-launcher), the same
way Steam runs Windows games. The Helper sets the prefix up once, at install or
repair time, so starting the game is quick.

Zenity menus are used for a GUI experience, with a fallback to terminal menus
where Zenity is unavailable. Command line arguments are available for quickly
launching functions from the terminal (`bms-helper.sh --help`).

Configuration is saved in *$XDG_CONFIG_HOME/falcon-bms/* (or *falcon-bms-internal/*).

## Installation

1. Download it! https://github.com/BenchmarkSims/bms-helper/releases
2. Extract it! Keep the `lib/` and `tools/` folders next to `bms-helper.sh`.
3. Public install: the Helper can download the latest Falcon BMS installer for you, or use `Falcon BMS_4.38.x_Full_Setup.exe` with its `.nsisbin` file if you already have it. You need Falcon 4.0 from GOG (`setup_falcon_4_2.0.0.1.exe`), the original CD, or Steam.
4. Internal install: have the internal Falcon BMS installer (Falcon 4.0 media is not required).
5. Run `bms-helper.sh` and choose `Install Falcon BMS`.

_Dependencies: **bash**, **coreutils**, **findutils**, **curl**, **tar**, **gawk**, **cabextract**, **unzip**, **python3**_
_Recommended: **zenity** (GUI), **umu-launcher**, **polkit** (Preflight fixes, joystick rules)_
_Optional: **7zip** or **p7zip** (automatic installer download), **gamemode**, **mangohud**, **icoutils** (app shortcut icons), **vulkan-tools** (VR GPU detection), **python-evdev** (MFD helper), **opentrack** built with Wine support (head tracking; the Helper can build it)_

**umu-launcher** does not have to be installed: if it is missing, the Helper
offers to download its self-contained build into
`~/.local/share/bms-helper/umu` (it only needs `python3`, no administrator
rights). Without umu, the Helper falls back to plain Proton, which works except
for VR.

Protontricks and a system Wine are no longer needed: winetricks verbs run with
the winetricks bundled in the Proton runner.

## Upgrading from Helper 1.x

Just start the new Helper. If your install was made by Helper 1.x, it is
updated automatically the first time (it takes a few seconds):

- The Wine prefix moves into a real `pfx` folder inside your install directory
  (the layout Proton and umu expect). Game files, settings and logbooks are not
  touched.
- Your Proton runner, GameMode/MangoHud choices and MFD helper are kept.
- `bms-launcher.sh` is replaced by the new, faster launcher. Desktop shortcuts
  keep working; the old launcher is kept as `bms-launcher.v1.bak`.
- Application shortcuts made with the Helper are updated.
- If the old Proton runner can't be used (for example Valve's Steam Proton), the
  newest GE-Proton you downloaded is used, or the default one is downloaded.

Close Falcon BMS before starting the new Helper.

## Install layout

```
~/Games/falcon-bms/
├── pfx/                  the Wine prefix (drive_c/Falcon BMS 4.38/...)
├── runners/              Proton runners downloaded by the Helper
├── bms-launcher.sh       starts Falcon BMS (used by the desktop shortcuts)
├── bms-launch.conf       launch settings
├── bms-launch-logs/      the last 10 launch logs
└── bms-install.log       install log
```

## Options

`Preflight Check`
- Checks memory, AVX support, `vm.max_map_count` (at least 1048576), the hard open file descriptors limit (at least 524288) and that an audio output device exists (Falcon BMS has been reported to crash without one), and offers to fix what it can.
- Reports the VR runtimes and tools that were found (informational).

`Install Falcon BMS`
- Creates a Proton prefix, installs the fonts/runtime components the Falcon BMS launcher needs, installs Falcon 4.0 (GOG or Steam copy, public only) and Falcon BMS, and creates desktop shortcuts.
- Public releases: offers to download the latest installer from the Falcon BMS servers. The version and checksum come from the falcon-bms.com website; the download is spread over the three public download servers, resumes if interrupted, and the installer is checked against the published checksum before it runs. It is kept in `falcon-bms-installers/` next to the install directory for reinstalls. The installer then runs unattended.
- The 16K terrain tiles, when selected, are downloaded by the Helper after the installation (see below).
- Installing over an existing install reinstalls it (see `Reinstall Falcon BMS`).
- Warns before installing to NTFS, exFAT or FAT drives (Wine prefixes break there, and the Alternative Launcher takes 30 s or more to start), and when the drive has less free space than an install needs (about 70 GB, 110 GB with the high resolution tiles).
- Falcon 4.0 can come from the GOG installer, another Falcon 4.0 installer such as the original CD's `Setup.exe` (its setup windows open during the install), or an existing Falcon 4.0 folder (Steam or a previous install).
- .NET Framework 4.8 comes with the Falcon BMS installer; if that step fails, the Helper installs it.

`16K terrain tiles: <state>`
- Shown once Falcon BMS is installed; the label shows whether the Korea 16K tiles are not installed, installed, incomplete or disabled, and the menu offers what fits:
  - **Add**: download the tiles (about 27 GB; not recommended with 12 GB of video memory or less).
  - **Repair**: keeps every tile that is intact and only downloads what is needed: missing tiles, tiles whose size doesn't match the server's (damaged or truncated), and interrupted downloads, which resume.
  - **Disable**: renames the `16K` folder to `16K_disabled`, so Falcon BMS uses the standard tiles while the 16K ones stay on disk. **Enable** renames it back, without downloading.
  - **Remove**: deletes the tiles (active or disabled).
- Downloads are spread over the three Falcon BMS download servers at the same time.

`Manage Proton Runners`
- Download GE-Proton builds, or select a GE-Proton, UMU-Proton or CachyOS Proton already installed by Steam, Heroic or your distribution.
- Valve's Proton builds (Steam's "Proton x.y" and "Proton - Experimental") are not offered: they lack the protonfixes/winetricks the Helper relies on and don't work reliably outside Steam.

`Controllers and Head Tracking`
- `Install joystick access rules (hidraw)`: adds a udev rule so Wine/Proton can read VKB, Virpil, Thrustmaster and WinWing devices directly (hidraw) instead of through the Linux input layer, which exposes at most 80 buttons per device. Removing Falcon BMS offers to remove the rule too.
- `Restore controller bindings from a backup`: `bms-launcher.sh` saves your controller setup (`Setup.v100.*.xml`, axis mapping, calibration, device order, keyfiles) before each launch when it changed, keeping the last 5 (`BMS_CONFIG_BACKUPS`). The Alternative Launcher can lose bindings when a device comes back with a new DirectInput id; this puts them back.
- `Thrustmaster MFD helper`: enables or disables `tools/mfd-joystick.py` (see **MFD helper** below).
- `Open Wine game controllers panel`
- `Set up OpenTrack head tracking (native Linux)` (see **Head tracking** below).

`Manage & Install other Apps`
- Run a Windows installer in the Falcon BMS prefix, create or remove application shortcuts, uninstall applications registered in the prefix, and install PowerShell. Applications start through `bms-launcher.sh run`, with the same Proton environment as the game.

`Maintenance and Troubleshooting`
- `Target a different Falcon BMS installation`
- `Update/Repair launch script`: reinstalls the launcher, settings file, desktop shortcuts and icon, replaces an unusable Proton runner, updates the Helper's umu copy and the Steam Runtime, and re-applies the prefix settings.
- `Installation checks`: re-applies the prefix settings (launcher WPF fixes, the 64-bit view of the Falcon BMS registry keys, OpenXR), installs missing launcher fonts (`corefonts`, `tahoma`, `gdiplus`), offers to install .NET Framework 4.8 when it is missing, refreshes the desktop shortcuts and icon, and checks that DXVK is active, that the Falcon BMS registry keys exist and that the install is not on an NTFS drive.
- `Reinstall Falcon BMS (keeps your settings and logbooks)`: see below.
- `Edit launch settings`: opens `bms-launch.conf`.
- `Open Wine prefix configuration` (winecfg) and `Open Winetricks`
- `Show logs`: the latest launch log, install log, OpenTrack bridge log and Falcon BMS logs.
- `Display Helper and Falcon BMS directories`
- `Reset Helper configs`

## Reinstall Falcon BMS

`Reinstall Falcon BMS` installs the game again from scratch while keeping what you set up:

1. The whole `User/Config` folder is backed up to `~/.local/share/bms-helper/backups/`.
2. The old Wine prefix is removed. Downloaded Proton runners and `bms-launch.conf` are kept.
3. Falcon BMS is installed again, then your files are copied into the new `User/Config`:
   `Falcon BMS User.cfg`, `Falcon BMS VR.cfg`, `Falcon BMS Editor.cfg`, `d3d11.dsp`, `.ini` files (server list `PhoneBkn.ini`, callsign and MFD preferences, 3D UI settings), keyfiles (`.key`), controller setups (`Setup.v100.*.xml`, `axismapping.dat`, `joystick.cal`, `DeviceSorting.txt`) and pilot files (`.lbk`, `.pop`, `.rul`, `.plc`).
   Default files shipped with Falcon BMS (`*_Def.ini`, `Feedback.ini`, `Falcon BMS.cfg`) come from the new install.

Applications you installed into the prefix are removed; reinstall them afterwards. The backup folder is kept, so anything else can be copied back by hand.

## Launch settings

`bms-launch.conf` in the install directory is read by `bms-launcher.sh`. The
Helper manages `PROTONPATH` and `BMS_LAUNCHER_EXE`; the rest is yours.
Standard Proton, umu and MangoHud variables are used where they exist; `BMS_*`
variables only cover what the launcher itself does:

- `BMS_USE_GAMEMODE=1|0`: run through `gamemoderun` when installed (default 1).
- `MANGOHUD=1|0`: show the MangoHud overlay (default 0).
- `PROTON_ENABLE_WAYLAND=1|0`: use Proton's native Wayland driver instead of XWayland (default 0; experimental, the WPF launcher's windows and popups may misbehave).
- `BMS_MFD_HELPER=1|0`: start the Thrustmaster MFD helper with the game.
- `BMS_UMU_LAUNCH=1|0`: set to 0 to launch with plain Proton instead of umu (troubleshooting only; VR needs umu).
- `BMS_EXTRA_ARGS`: extra arguments for the Falcon BMS launcher.
- `BMS_CONFIG_BACKUPS`: number of controller setup snapshots to keep (default 5, 0 = off).
- Add your own `export` lines at the end of the file, for example `export DXVK_HUD=fps`.

Any of these can also be set in the environment for a single run, for example
`MANGOHUD=1 ~/Games/falcon-bms/bms-launcher.sh`.

`bms-launcher.sh` also accepts `config` (winecfg), `controllers`, `shell` and
`run <exe> [args]`. It is replaced when the launch script is repaired, so put
your changes in `bms-launch.conf`.

## Troubleshooting

- **Low frame rate (about half of Windows):** check that DXVK is active with `Installation checks`. Prefixes created with `PROTON_VERB=runinprefix` or plain Wine don't get Proton's DXVK.
- **Alternative Launcher slow or crashing with Mono errors:** .NET Framework 4.8 is missing; `Installation checks` installs it.
- **"Culture ID 4096 is not a supported culture":** add `export LC_ALL=en_US.UTF-8` to `bms-launch.conf`.
- **Bindings or axes lost:** `Controllers and Head Tracking` > `Restore controller bindings from a backup`.
- **Crash a few seconds after entering the cockpit:** make sure an audio output device is available.
- **No ATIS voice/text:** Falcon BMS uses the Windows text-to-speech engine, which is not available under Wine/Proton.

## Head tracking (OpenTrack)

Falcon BMS reads head tracking through the TrackIR interface (`NPClient64.dll`). Native Linux OpenTrack provides it with its `Wine -- Windows layer for Unix` output, which runs a small bridge (`opentrack-wrapper-wine.exe.so`) inside the game's prefix. No Windows OpenTrack is needed.

`Set up OpenTrack head tracking (native Linux)`:

- Offers to uninstall a Windows OpenTrack found in the prefix (it would compete for the TrackIR registry path).
- Uses an installed OpenTrack built with Wine support (e.g. the AUR `opentrack` package). Otherwise it installs the build dependencies with your package manager (pacman, apt, dnf or zypper) and builds OpenTrack from source into `~/.local/share/bms-helper/opentrack`, with an `OpenTrack` menu entry.
- Installs `opentrack-proton-bridge.sh` into the install directory and sets the active OpenTrack profile's output to `Wine`, protocol `NPClient`, with that script as the custom Wine binary. The previous profile is saved as `<profile>.ini.bms-helper.bak`.

OpenTrack is never started automatically, and there is no setting for it in `bms-launch.conf`: to fly with head tracking, start OpenTrack and press Start, before or after launching Falcon BMS; to fly without it, don't start it. The bridge waits until Falcon's launcher or game is running, then starts the wrapper with the install's Proton runner and the game's esync/fsync/ntsync settings, so it joins the game's wineserver. It stops the wrapper again when Falcon exits. Bridge log: `<install>/opentrack/bridge.log`.

## MFD helper

`tools/mfd-joystick.py` presents Thrustmaster F-16 MFD panels to Falcon BMS as joystick-style virtual devices, and hides the physical ones from DirectInput.

- Enable it from `Controllers and Head Tracking`. It then starts and stops with Falcon BMS.
- It requires `python3`, the Python `evdev` package and write access to `/dev/uinput`.
- By default it exclusively grabs the physical MFD devices while running. Set `BMS_MFD_GRAB_PHYSICAL=0` (for example in `bms-launch.conf`, with `export`) to disable that.

## Notes

#### Forked and inspired from:
- https://github.com/starcitizen-lug/lug-helper
