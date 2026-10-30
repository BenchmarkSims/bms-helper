#!/usr/bin/env bash
#
# Falcon BMS launcher, installed by bms-helper.
# https://github.com/BenchmarkSims/bms-helper
#
# This file is replaced whenever the helper updates/repairs the launch script.
# Put your settings in bms-launch.conf next to it instead. Variables set in
# the environment when calling this script take precedence over that file.
#
# Usage: bms-launcher.sh                    start the Falcon BMS launcher
#        bms-launcher.sh run <exe> [args]   run another Windows program in the prefix
#        bms-launcher.sh config             Wine configuration (winecfg)
#        bms-launcher.sh controllers        Wine game controllers panel
#        bms-launcher.sh shell              shell with the prefix's Wine environment
#
# The prefix is fully set up by the helper at install/repair time, so this
# script only prepares the environment and starts Proton.
#
# version: 2.1
# License: GPLv3.0

BMS_ROOT="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)"
conf="$BMS_ROOT/bms-launch.conf"
if [ ! -f "$conf" ]; then
    echo "Missing $conf. Run 'Update/Repair launch script' in bms-helper." >&2
    exit 1
fi

# Settings from the environment win over the config file
env_overrides="$(export -p | grep -E '^declare -x (BMS_[A-Z_]+|PROTONPATH|PROTON_[A-Z_]+|MANGOHUD|GAMEID)=')"
# shellcheck source=/dev/null
. "$conf"
eval "$env_overrides"
# Standard variables from the config file must reach Proton/MangoHud
export MANGOHUD PROTON_ENABLE_WAYLAND

############################################################################
# Environment
############################################################################
export WINEPREFIX="$BMS_ROOT/pfx"
export WINEDEBUG="${WINEDEBUG:--all}"
# Keep Wine from adding menu entries for programs installed in the prefix
export WINEDLLOVERRIDES="winemenubuilder.exe=d${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
# The helper updates the Steam Runtime; don't check for updates on every launch
export UMU_RUNTIME_UPDATE="${UMU_RUNTIME_UPDATE:-0}"
# Shader caches next to the prefix
export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_PATH="${__GL_SHADER_DISK_CACHE_PATH:-$BMS_ROOT/shadercache}"
export __GL_SHADER_DISK_CACHE_SIZE="${__GL_SHADER_DISK_CACHE_SIZE:-10737418240}"
export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
export MESA_SHADER_CACHE_DIR="${MESA_SHADER_CACHE_DIR:-$BMS_ROOT/shadercache}"
export MESA_SHADER_CACHE_MAX_SIZE="${MESA_SHADER_CACHE_MAX_SIZE:-10G}"
unset SDL_VIDEODRIVER

log_dir="$BMS_ROOT/bms-launch-logs"
mkdir -p "$log_dir"
launch_log="$log_dir/$(date '+%Y%m%d-%H%M%S')-$$.log"
# Keep only the last 10 run logs
ls -1t "$log_dir"/*.log 2>/dev/null | tail -n +10 | xargs -r -d '\n' rm -f

if [ -z "$PROTONPATH" ] || [ ! -x "$PROTONPATH/proton" ]; then
    echo "No valid Proton runner is configured in $conf" | tee -a "$launch_log" >&2
    echo "Use 'Manage Proton Runners' in bms-helper to select one." >&2
    exit 1
fi

umu_bin="$(command -v umu-run 2>/dev/null)"
if [ -z "$umu_bin" ] && [ -x "${XDG_DATA_HOME:-$HOME/.local/share}/bms-helper/umu/umu-run" ]; then
    umu_bin="${XDG_DATA_HOME:-$HOME/.local/share}/bms-helper/umu/umu-run"
fi

############################################################################
# Helpers
############################################################################
# Build prefix_cmd: the command that runs a Windows program in the prefix and
# waits until the prefix is idle. umu-run sets up the Steam Runtime
# container, which VR (wineopenxr) needs.
set_prefix_cmd() {
    if [ -n "$umu_bin" ] && [ "${BMS_UMU_LAUNCH:-1}" != "0" ]; then
        # Expose the WiVRn socket to the container and point wineopenxr to the
        # runtime JSON pre-built by the helper (or the user's active runtime)
        wivrn_socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wivrn/comp_ipc"
        pv_fs_rw="${PRESSURE_VESSEL_FILESYSTEMS_RW:-$wivrn_socket:$HOME/.local/lib/wivrn}"
        if [ -n "${XR_RUNTIME_JSON:-}" ]; then
            xr_json="$XR_RUNTIME_JSON"
        elif [ -f "$BMS_ROOT/xr-wivrn-runtime.json" ]; then
            xr_json="$BMS_ROOT/xr-wivrn-runtime.json"
        else
            xr_json="${XDG_CONFIG_HOME:-$HOME/.config}/openxr/1/active_runtime.json"
        fi
        echo "runner=umu umu=$umu_bin proton=$PROTONPATH XR_RUNTIME_JSON=$xr_json" >> "$launch_log"
        prefix_cmd=(env GAMEID="${GAMEID:-0}" PROTONPATH="$PROTONPATH" WINEPREFIX="$BMS_ROOT"
            XR_RUNTIME_JSON="$xr_json" PRESSURE_VESSEL_FILESYSTEMS_RW="$pv_fs_rw" "$umu_bin")
    else
        echo "runner=proton proton=$PROTONPATH" >> "$launch_log"
        prefix_cmd=(env STEAM_COMPAT_DATA_PATH="$BMS_ROOT"
            STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$PROTONPATH}"
            "$PROTONPATH/proton" waitforexitandrun)
    fi
}

# Optional wrappers for the game launch only (MangoHud needs none: MANGOHUD=1
# enables its Vulkan layer for the DXVK-rendered game)
set_launch_wrappers() {
    launch_wrappers=()
    if [ "${BMS_USE_GAMEMODE:-1}" = "1" ] && command -v gamemoderun >/dev/null 2>&1; then
        launch_wrappers+=(gamemoderun)
    fi
}

# Thrustmaster MFD helper: started with the game, stopped when it exits
mfd_pid=""
start_mfd_helper() {
    [ "${BMS_MFD_HELPER:-0}" = "1" ] || return 0
    mfd_script="$BMS_ROOT/mfd-joystick.py"
    if [ ! -f "$mfd_script" ] || ! command -v python3 >/dev/null 2>&1; then
        echo "WARNING: BMS_MFD_HELPER=1 but $mfd_script or python3 is missing" >> "$launch_log"
        return 0
    fi
    if pgrep -f "$mfd_script" >/dev/null 2>&1; then
        echo "mfd_helper=already_running" >> "$launch_log"
        return 0
    fi
    python3 "$mfd_script" >> "$launch_log" 2>&1 &
    mfd_pid=$!
    echo "mfd_helper=started pid=$mfd_pid" >> "$launch_log"
}
trap '[ -n "$mfd_pid" ] && kill "$mfd_pid" 2>/dev/null' EXIT

# Snapshot the controller setup before each launch: the launcher sometimes
# loses bindings when a device comes back with a new DirectInput id. Only
# changed setups are kept (BMS_CONFIG_BACKUPS snapshots, 0 = off); restore
# them with the helper's Controllers menu.
backup_controller_config() {
    keep="${BMS_CONFIG_BACKUPS:-5}"
    [ "$keep" -gt 0 ] 2>/dev/null || return 0
    cfg_dir="$(dirname "$BMS_LAUNCHER_EXE")/../User/Config"
    [ -d "$cfg_dir" ] || return 0
    backup_root="$BMS_ROOT/config-backups"
    snapshot="$backup_root/$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$snapshot" || return 0
    (
        cd "$cfg_dir" || exit 0
        shopt -s nullglob nocaseglob
        files=(Setup.v100.*.xml axismapping.dat joystick.cal DeviceSorting.txt *.key)
        [ "${#files[@]}" -gt 0 ] && cp -p -- "${files[@]}" "$snapshot/"
    )
    latest="$(ls -1d "$backup_root"/*/ 2>/dev/null | grep -vF "$snapshot/" | sort | tail -n1)"
    if [ -z "$(ls -A "$snapshot")" ] || { [ -n "$latest" ] && diff -rq "$snapshot" "$latest" >/dev/null 2>&1; }; then
        rm -r "$snapshot"
        return 0
    fi
    ls -1d "$backup_root"/*/ | sort | head -n -"$keep" | xargs -r -d '\n' rm -r
    echo "config_backup=$snapshot" >> "$launch_log"
}

set_prefix_cmd

############################################################################
# Subcommands
############################################################################
case "$1" in
    shell)
        echo "Entering Wine prefix shell. Type 'exit' when done."
        export PATH="$PROTONPATH/files/bin:$PATH"
        cd "$WINEPREFIX" || exit 1
        /usr/bin/env bash --norc
        exit 0
        ;;
    config)
        "${prefix_cmd[@]}" winecfg >> "$launch_log" 2>&1
        exit $?
        ;;
    controllers)
        "${prefix_cmd[@]}" control joy.cpl >> "$launch_log" 2>&1
        exit $?
        ;;
    run)
        shift
        if [ -z "$1" ]; then
            echo "Usage: $0 run <exe> [args]" >&2
            exit 1
        fi
        cd "$(dirname "$1")" 2>/dev/null || true
        "${prefix_cmd[@]}" "$@" >> "$launch_log" 2>&1
        exit $?
        ;;
esac

############################################################################
# Launch
############################################################################
# BMS replaced FalconBMS_Alternative_Launcher.exe with FalconBMS.Launcher.exe
# in the same folder. When the configured exe is one of the two, start the new
# one if it is there and fall back to the old one. Other exes are left alone.
case "$(basename -- "$BMS_LAUNCHER_EXE")" in
    FalconBMS.Launcher.exe | FalconBMS_Alternative_Launcher.exe)
        launcher_dir="$(dirname -- "$BMS_LAUNCHER_EXE")"
        for candidate in FalconBMS.Launcher.exe FalconBMS_Alternative_Launcher.exe; do
            if [ -f "$launcher_dir/$candidate" ]; then
                BMS_LAUNCHER_EXE="$launcher_dir/$candidate"
                break
            fi
        done
        ;;
esac
if [ ! -f "$BMS_LAUNCHER_EXE" ]; then
    echo "Launcher executable not found: $BMS_LAUNCHER_EXE" | tee -a "$launch_log" >&2
    exit 1
fi
echo "launcher_exe=$BMS_LAUNCHER_EXE" >> "$launch_log"
# Relative paths in the launcher resolve from its own directory
cd "$(dirname "$BMS_LAUNCHER_EXE")" || true

echo "=== $(date '+%Y-%m-%d %H:%M:%S') bms-launcher start ===" >> "$launch_log"
backup_controller_config
start_mfd_helper
set_launch_wrappers

# shellcheck disable=SC2086 # BMS_EXTRA_ARGS is a word list
"${launch_wrappers[@]}" "${prefix_cmd[@]}" "$BMS_LAUNCHER_EXE" $BMS_EXTRA_ARGS >> "$launch_log" 2>&1
launch_exit=$?
echo "exit_code=$launch_exit" >> "$launch_log"
exit "$launch_exit"
