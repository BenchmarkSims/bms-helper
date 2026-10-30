# AGENTS.md

Notes for coding agents (and humans) working on bms-helper. Read this before
changing the launcher, the prefix code or the install layout.

## What this is

A bash helper (zenity GUI with terminal fallback) that installs and runs
Falcon BMS on Linux through Proton + umu-launcher. Forked from
[lug-helper](https://github.com/starcitizen-lug/lug-helper); check its
releases for ideas now and then (it uses plain Wine runners, not Proton, so
not everything transfers).

## Layout

```
bms-helper.sh               entry point: dependency check, constants, CLI args, main menu,
                            auto-migration on startup. Sources lib/*.sh (functions only).
lib/core.sh                 message/menu/progress_bar/try_exec (zenity + terminal)
lib/config.sh               release mode, getdirs (install discovery), bms-launch.conf
                            helpers (conf_get/conf_set), layout 1 -> 2 migration
lib/prefix.sh               umu discovery/download, prefix_run, winetricks, .reg import,
                            reg_get (reads *.reg files without Wine), persistent prefix
                            settings, install_launch_script
lib/runner.sh               Proton runner discovery/download/selection
lib/desktop.sh              icons and .desktop files
lib/preflight.sh            Preflight Check, filesystem check
lib/install.sh              install, reinstall (User/Config backup/restore), uninstall,
                            Falcon 4.0 / BMS installer selection
lib/maintenance.sh          maintenance menu, repair, installation checks, logs, dirs
lib/apps.sh                 extra Windows apps and their shortcuts
lib/controllers.sh          hidraw udev rules, MFD helper toggle
lib/opentrack.sh            native OpenTrack setup/build
lib/bms-launcher.sh         STATIC launcher, copied to <install>/bms-launcher.sh
lib/opentrack-proton-bridge.sh  STATIC bridge, copied to the install root
tools/mfd-joystick.py       Thrustmaster MFD -> virtual joystick (python-evdev)
```

Each install root (default `~/Games/falcon-bms`, or `falcon-bms-internal`):

```
pfx/              real Wine prefix          bms-launch.conf   launcher settings
runners/          downloaded Proton         bms-launcher.sh   static launcher
version, tracked_files, config_info         Proton's own files (STEAM_COMPAT_DATA_PATH)
.bms-helper       layout=2, helper_version  bms-launch-logs/, bms-install.log
```

## Design rules

- **The launcher never touches the prefix.** Anything persistent (registry
  fixes, BMS registry mirror, VR keys, MFD DirectInput entries) is applied at
  install/repair time by `apply_prefix_settings` in ONE regedit run. Every
  Wine/umu start costs ~3.5 s, which is why the v1 launcher was slow.
- **The launcher is static.** Per-install values live only in
  `bms-launch.conf` (`KEY='value'` lines, sourced by the launcher; environment
  variables win over the file). Never go back to generating the launcher in a
  heredoc. When `lib/bms-launcher.sh` changes in a way installs must pick up,
  bump `# version:` in it AND `bms_launcher_version` in `bms-helper.sh`.
- **All prefix operations go through `prefix_run`/`prefix_run_timeout`**
  (umu-run, plain `proton waitforexitandrun` as fallback). Don't call the
  runner's `files/bin/wine` directly, except `wineserver -k` for cleanup and
  the winetricks GUI.
- **Only runners with `protonfixes/` are supported** (`runner_supported`):
  GE-Proton, UMU-Proton, CachyOS Proton. Valve's Proton has no
  protonfixes/winetricks and fails outside Steam.
- **Non-power users must never need to know about layouts.** Old installs are
  migrated automatically on startup (`auto_migrate_install` ->
  `getdirs` -> `ensure_install_layout`), with rollback on failure. Desktop
  shortcuts keep working because the launcher file name never changes.
- umu is not a hard dependency: `ensure_umu` offers to download its zipapp to
  `~/.local/share/bms-helper/umu` (needs only python3).

## Gotchas (learned the hard way)

- **umu and `pfx`**: umu's `setup_pfx()` creates `$WINEPREFIX/pfx -> .` only
  when `pfx` is not a directory; it leaves a real `pfx/` alone. umu sets
  `WINEPREFIX` and `STEAM_COMPAT_DATA_PATH` to the root you pass; Proton then
  uses `<root>/pfx`. Pass the install ROOT to umu, and `<root>/pfx` to plain
  Wine tools.
- **Proton fills an empty `pfx/`** on the first run (`umu-run wineboot -u`).
  Proton decides whether to rebuild the prefix from `<root>/version` and
  `tracked_files`, so deleting a prefix means deleting those too
  (`remove_old_prefix`).
- **`umu-run winetricks` exits 1 if ANY requested verb is already in
  `<root>/winetricks.log`.** With the real `pfx/` layout winetricks logs to
  `pfx/winetricks.log`, so this never triggers; it did with the v1 symlink layout.
  umu adds `-q` itself and rejects non-verb arguments (no `--gui`), so the GUI
  runs the runner's `protonfixes/winetricks` on the host.
- Console output of a Windows exe passed as a Unix path (`umu.exe` path) is
  not captured; `umu-run cmd /c echo x` (no path) is.
- Through umu/Proton, the console output of Wine tools (`uninstaller --list`
  etc.) arrives on **stderr**, mixed with the Proton/protonfixes log. Read
  `2>&1` and filter; `2>/dev/null` gives an empty result.
- `gamemoderun` and `timeout` can't wrap shell functions. Build a
  command array (`prefix_cmd`) and prepend wrappers.
- Wine registry files: keys look like `[Software\\Wow6432Node\\...] <timestamp>`
  with doubled backslashes; values keep `.reg` escaping (`"C:\\Falcon BMS 4.38"`).
  `reg_get` returns the raw data, which can go straight back into a `.reg`
  file. Pass awk strings through `ENVIRON`, not `-v` (which unescapes `\`).
  The 32-bit BMS installer writes only to `Software\\Wow6432Node\\Benchmark Sims`;
  the 64-bit view is mirrored at install/repair.
- Commands queued for `try_exec root` run later in `sh -c`: expand variables
  when queueing (double quotes), not inside single quotes.
- Keep awk POSIX/mawk compatible (no gawk `match(..., arr)`).
- `nullglob` does nothing for literal paths in a `for` list; check `-e` before
  `rm`. File names with spaces (`Falcon BMS User.cfg`) break unquoted glob
  patterns; match with `[[ $name == $pattern ]]` instead.
- `default_install_path` (a lug-helper leftover) used to be undefined in v1, so
  `gamedir.conf` held a wrong path. Game paths are now derived from the root
  (`set_install_paths`); `gamedir.conf` is no longer written.
- Zenity `--text` is Pango markup: escape `&` as `&amp;` in zenity strings.
- The PROTON_NO_FSYNC/ESYNC=1 exports in the v1 launcher always disabled
  fsync/esync (the comment claimed the opposite); they are gone. Modern
  Proton uses ntsync when the kernel has it.
- Wine's hidraw support is chosen per device inside winebus (VKB, Virpil,
  Thrustmaster...); the Helper only provides the udev `uaccess` rules. Don't
  write hidraw registry keys without checking the runner's winebus source.
- BMS renamed its launcher from `FalconBMS_Alternative_Launcher.exe` to
  `FalconBMS.Launcher.exe` (same `Launcher/` folder). Both are supported:
  `find_launcher_exe` and `bms-launcher.sh` (at every start) prefer the new
  name and fall back to the old one, so an in-game update that swaps the exe
  needs no repair. A custom `BMS_LAUNCHER_EXE` with another name is untouched.
  Process checks (`pgrep`) match both names.
- Native Wayland (`PROTON_ENABLE_WAYLAND=1`) is opt-in and untested with the
  WPF launcher; XWayland is the default.
- Don't invent `BMS_*` variables for things Proton, umu or MangoHud already
  have a variable for (`PROTONPATH`, `PROTON_*`, `MANGOHUD`, `GAMEID`,
  `UMU_*`). Variables in `bms-launch.conf` that Proton must see have to be
  exported by the launcher (see the `export` line after sourcing it).

## Downloads (lib/downloads.sh)

- Release info: public website API, `https://api.falcon-bms.com/api/updates?populate=*`
  (Strapi, no token). The entry with `latest: true` gives the series (4.38),
  its newest `type: base` version (4.38.1.0) and the installer exe's SHA-256
  inside the free-text `hash` field. Patches (4.38.1.1) go through the
  in-game Updater. The `.nsisbin` hash is not published; 7-Zip's archive
  CRCs cover it.
- Installer: `<cdn>/BMS<series>/Base/Base.7z.001..NNN` (512 MiB parts, 34
  for 4.38.1), unpacked with 7-Zip into `Falcon BMS_<ver>_Full_Setup.exe`
  + `.nsisbin`. This layout comes from the official downloader
  (bms-install repo, `Falcon_BMS_downloader.nsi`); the SHA-256 check makes
  a wrong guess fail loudly instead of installing the wrong file.
- 16K tiles: `<cdn>/16K/<n>.dds`, n = 1..1024 with gaps (404), 44,739,384
  bytes each, into `<game>/Data/TerrData/Korea/NewTerrain/Photoreal/16K`.
  BMS picks them up by their presence. The installer's `/16k` switch is not
  used (it runs a Windows torrent client and netsh rules inside the prefix).
- Mirrors: `cdn`, `cdn1`, `cdn2.falcon-bms.com`. Downloads run one worker
  per mirror at the same time, each starting on its own mirror and falling
  back to the others, so the load is shared. Mirrors disagree on errors:
  an unsatisfiable resume gets 416 from some and 404 from others, so a 404
  to a resume is retried from scratch, and a file is only "missing" when
  all mirrors answer 404. On 2026-10-18 cdn2.falcon-bms.com answered 404
  for every file: the origin is a Kubernetes ingress-nginx and no Ingress
  listed that host, so it hit the default backend (fixed the same day).
  A mirror returning 404 for everything, or the ingress "Fake
  Certificate", means a host is missing from the Ingress rules.
- User agent `bmsdownloader`, like the official downloader.
- **Security:** only public endpoints belong in this repo. Never add
  internal CDN paths, licensing/key endpoints or anything else from the
  internal tooling. Internal installs keep manual installer selection. The
  internal installer key must never be printed or logged (installer
  arguments are logged with `/key=<hidden>`; the key prompt hides input).

## Forum findings (Falcon BMS 4.38, reviewed 2026-10-18)

Source: https://forum.falcon-bms.com/category/106/linux-no-official-support
(read through the NodeBB API: `/api/category/106/...?page=N`, `/api/topic/<slug>?page=N`).
Only reports about 4.38.x count; forum advice is often copied from list to
list, so check each claim against a real prefix before acting on it.

Acted on (with the evidence):
- NTFS install -> Alternative Launcher takes ~30 s to start (reproduced by a
  user moving the same prefix between NTFS and xfs). Install and
  Installation checks warn.
- Bindings lost when a device returns with a new DirectInput GUID (several
  users; BMS devs confirmed, fix planned in a future launcher). Launcher
  snapshots the controller files; Controllers menu restores them.
- Linux evdev exposes at most 80 buttons per device (dev statement); the
  hidraw udev rules let Wine read supported devices directly.
- Falcon 4.0 from the original CD (`Setup.exe`) works when run
  interactively (two users). The GOG name check now accepts it.
- Alternative Launcher on wine-mono (Mono stack traces in Launcher_Log.txt)
  is slow and crashes. The BMS installer normally installs .NET 4.8.1 itself
  (verified: release 533320 in the maintainer's prefixes, no winetricks
  dotnet48), so dotnet48 is only installed when check_dotnet48 fails.
- No audio device -> crash shortly after entering the cockpit (one 4.38.1
  report, DirectSound in the trace). Preflight warns only.
- Half frame rate = DXVK missing: a user created the prefix with
  `PROTON_VERB=runinprefix`, which skips Proton's prefix setup (no DXVK).
  The helper always uses the default verb; Installation checks verify the
  prefix's d3d11.dll is DXVK.
- v1 helper made prefixes with Proton's bare wine outside the runtime, so
  wined3d lacked Proton's libvkd3d DLLs and the GOG installer failed on
  CachyOS. Fixed by letting Proton create the prefix.
- "Culture ID 4096 is not a supported culture" (one report, on wine-mono):
  documented `LC_ALL=en_US.UTF-8` in bms-launch.conf, not set by default.

Rejected as placebo or obsolete (don't re-add without new evidence):
- winetricks `vkd3d`: Falcon BMS 4.38.x (including 4.38.2) is Direct3D 11
  only (DXVK); vkd3d-proton (D3D12) ships with Proton anyway. The advice
  dates from BMS 4.36 / Wine 7.

Future renderers: the BMS team plans Direct3D 12 and Vulkan support after
4.38.2. When that ships, revisit:
- D3D12 runs on Proton's vkd3d-proton. Never install winetricks `vkd3d`,
  which replaces it with Wine's own, slower vkd3d. Installation checks
  should then also verify that the prefix's d3d12.dll is vkd3d-proton
  (`grep -qa vkd3d-proton .../system32/d3d12.dll`), as they do for DXVK.
- A native Vulkan renderer bypasses DXVK, so the DXVK check only applies to
  the D3D11 renderer.
- Re-check the forum for renderer-specific environment variables
  (`PROTON_*`, `VKD3D_*`, `DXVK_*`) before adding any.
- `d3dx11_43` native override, `d3dcompiler_47`, `vcrun2022`, extra dotnet
  versions: 4.36/4.37-era or copied lists; 4.38 runs on Proton's builtins in
  the maintainer's prefixes. Companion tools (Mission Commander, WDP) may
  need some of these; nobody has established a minimal set.
- gamemode: no measured gain reported; kept only because it is harmless.

Open questions:
- The launcher's "Update" opened a PowerShell prompt without updating on a
  v1 helper install (one report). The winetricks `powershell` verb replaces
  powershell.exe with PowerShell Core; check whether the updater works with
  and without it before keeping the verb.
- ATIS/TTS: BMS uses the Windows TTS engine, which Wine/Proton lack. No
  working workaround known.

## Testing

There is no test suite. What has worked well:

- `for f in bms-helper.sh lib/*.sh; do bash -n "$f"; done`
- Unit-test functions by sourcing the modules in `bash -c` with the needed
  globals set by hand (see how `bms-helper.sh` sets them).
- A throwaway prefix in a scratch directory: `mkdir -p root/pfx`, then
  `GAMEID=0 WINEPREFIX=root PROTONPATH=<GE-Proton> UMU_RUNTIME_UPDATE=0 umu-run wineboot -u`.
  Point `BMS_LAUNCHER_EXE` at `pfx/drive_c/windows/system32/cmd.exe` with
  `BMS_EXTRA_ARGS="/c exit 0"` to exercise the launcher.
- **Run the full helper only with `XDG_CONFIG_HOME` pointing to a scratch
  directory**, otherwise it finds the real installs through
  `~/.config/falcon-bms*/winedir.conf` and migrates them on startup. Also
  redirect `data_dir`/`XDG_DESKTOP_DIR` when testing functions that write
  desktop files and icons.

Verified on 2026-10-18 with umu 1.4.3 and GE-Proton11-1: prefix creation,
winetricks, registry import, launcher (umu path), v1 -> v2 migration of a v1
style install, User/Config backup/restore against a real config folder,
terminal menus.

Not yet verified end to end: a full install with the real BMS/GOG installers,
the reinstall flow as a whole, the zenity GUI paths, the plain-Proton fallback,
the umu zipapp download path inside the helper, OpenTrack with the static
bridge, the MFD helper, and the hidraw rules with real devices.

## History

- v2.0 (2026-10): split the 6.7k-line script into `lib/` modules; real `pfx/`
  layout with automatic migration; static launcher + `bms-launch.conf`;
  standard Proton/umu/MangoHud variable names in bms-launch.conf;
  umu-only prefix operations (protontricks removed); umu zipapp download;
  runners limited to protonfixes builds; reinstall keeping User/Config;
  hidraw udev rules; Controllers menu; logs menu; NTFS check; lower
  `vm.max_map_count` requirement (1048576); opt-in Wayland; removed dead DXVK
  and reinstall-launcher code.
