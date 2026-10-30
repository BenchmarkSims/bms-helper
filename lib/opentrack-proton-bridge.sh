#!/usr/bin/env bash
# OpenTrack -> Falcon BMS (Proton) bridge, installed by bms-helper into the
# Falcon BMS install root. Replaced whenever the helper repairs the install.
prefix="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)"

# OpenTrack's "Wine" output starts this script as its custom Wine binary:
#   <this script> <opentrack libexec>/opentrack-wrapper-wine.exe.so
# The wrapper copies head pose from OpenTrack into the TrackIR/FreeTrack shared
# memory that Falcon BMS reads through NPClient64.dll.
#
# Under Proton the game's wineserver runs inside the umu/pressure-vessel
# container and can only open files visible there, so the wrapper and DLLs are
# staged inside the prefix. The wrapper is started only once Falcon BMS runs,
# with the runner's own wine and the game's sync settings, so it joins the
# game's wineserver instead of starting a separate one.

bridge_dir="$prefix/opentrack"
stage_dir="$bridge_dir/libexec/opentrack"
log="$bridge_dir/bridge.log"
mkdir -p "$bridge_dir/bin" "$stage_dir"
: > "$log"
log_msg() { echo "$(date '+%H:%M:%S') $*" >> "$log"; }

src_dir="$(dirname "${1:-.}")"
for f in opentrack-wrapper-wine.exe.so NPClient.dll NPClient64.dll freetrackclient.dll freetrackclient64.dll; do
    if [ -f "$src_dir/$f" ]; then
        cp -u "$src_dir/$f" "$stage_dir/$f"
    fi
done
if [ ! -f "$stage_dir/opentrack-wrapper-wine.exe.so" ]; then
    log_msg "error: opentrack-wrapper-wine.exe.so not found (argument: '${1:-}')"
    exit 1
fi

runner="$(sed -n "s/^PROTONPATH='\\(.*\\)'$/\\1/p" "$prefix/bms-launch.conf" 2>/dev/null | sed "s/'\\\\''/'/g")"
if [ -x "$runner/files/bin/wine" ]; then
    wine_bin="$runner/files/bin/wine"
elif [ -x "$runner/bin/wine" ]; then
    wine_bin="$runner/bin/wine"
else
    log_msg "error: no Proton runner configured for $prefix"
    exit 1
fi

# Proton runs the game with WINEPREFIX=<install root>/pfx
export WINEPREFIX="$prefix/pfx"
export WINEDEBUG="${WINEDEBUG:--all}"
wrapper_pattern='\\opentrack-wrapper-wine\.exe\.so'

# Only match Windows-side processes: Wine rewrites their command line to a
# Windows path (backslashes), while the host-side umu-run/proton processes
# carry the unix path to the same exe. Matching those would start the wrapper
# before the game's wineserver exists, and keep umu from exiting afterwards.
find_game_pid() {
    local pid env
    for pid in $(pgrep -fi '\\(Falcon BMS|FalconBMS_Alternative_Launcher|FalconBMS\.Launcher)\.exe'); do
        env="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null)" || continue
        case $'\n'"$env"$'\n' in
            *$'\n'"WINEPREFIX=$prefix"$'\n'*|*$'\n'"WINEPREFIX=$prefix/"$'\n'*|\
            *$'\n'"WINEPREFIX=$prefix/pfx"$'\n'*|*$'\n'"WINEPREFIX=$prefix/pfx/"$'\n'*)
                echo "$pid"
                return 0
                ;;
        esac
    done
    return 1
}

# A wine client whose esync/fsync/ntsync mode differs from the wineserver's
# can hang, so copy exactly what Proton set for the game.
load_game_sync_env() {
    local line
    unset WINEESYNC WINEFSYNC WINENTSYNC
    while IFS= read -r line; do
        case "$line" in
            WINEESYNC=*|WINEFSYNC=*|WINENTSYNC=*) export "$line" ;;
        esac
    done < <(tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null)
}

stop_wrapper() {
    # The wine client exiting does not end the Windows-side wrapper process.
    if [ -n "$child" ]; then
        kill "$child" 2>/dev/null
    fi
    pkill -f "$wrapper_pattern" 2>/dev/null
}

child=""
trap 'stop_wrapper; exit 0' TERM INT HUP

log_msg "waiting for Falcon BMS (prefix=$prefix runner=$runner)"
while true; do
    game_pid="$(find_game_pid)"
    if [ -z "$game_pid" ]; then
        sleep 2
        continue
    fi

    load_game_sync_env "$game_pid"
    log_msg "starting wrapper for pid $game_pid (WINEESYNC=${WINEESYNC:-} WINEFSYNC=${WINEFSYNC:-} WINENTSYNC=${WINENTSYNC:-})"
    # The wrapper registers <cwd>/../libexec/opentrack/ as the NPClient/FreeTrack path.
    (cd "$bridge_dir/bin" && exec "$wine_bin" "$stage_dir/opentrack-wrapper-wine.exe.so") >> "$log" 2>&1 &
    child=$!

    # Stop the wrapper once Falcon BMS is gone (two consecutive misses, to ride
    # out the launcher -> game hand-off), so the game's wineserver can exit.
    misses=0
    while kill -0 "$child" 2>/dev/null; do
        sleep 2
        if find_game_pid >/dev/null; then
            misses=0
        else
            misses=$((misses + 1))
            if [ "$misses" -ge 2 ]; then
                log_msg "Falcon BMS exited, stopping wrapper"
                stop_wrapper
                break
            fi
        fi
    done
    wait "$child"
    rc=$?
    child=""

    # Exit code 0 means OpenTrack stopped tracking and told the wrapper to quit.
    if [ "$misses" -lt 2 ] && [ "$rc" -eq 0 ]; then
        log_msg "wrapper stopped by OpenTrack"
        exit 0
    fi
    log_msg "wrapper exited (code $rc), waiting for Falcon BMS"
    sleep 2
done
