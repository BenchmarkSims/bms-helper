# shellcheck shell=bash
# bms-helper: everything that runs inside, or changes, the Wine prefix.
# Sourced by bms-helper.sh; defines functions only.
#
# All prefix operations go through prefix_run(), which uses umu-run (the
# same Proton + Steam Runtime environment as the game) and falls back to
# plain Proton when umu is unavailable. Persistent prefix settings are
# applied here at install/repair time, so the launcher never needs to touch
# the prefix before starting the game.

umu_release_api="https://api.github.com/repos/Open-Wine-Components/umu-launcher/releases/latest"

# MARK: find_umu()
# Set umu_bin to a system umu-run or the helper's own copy; return 1 if none
find_umu() {
    umu_bin="$(command -v umu-run 2>/dev/null)"
    if [ -z "$umu_bin" ] && [ -x "$umu_local_dir/umu-run" ]; then
        umu_bin="$umu_local_dir/umu-run"
    fi
    [ -n "$umu_bin" ]
}

# MARK: install_local_umu()
# Download umu-launcher's self-contained zipapp into the helper's data dir.
# It only needs python3, so no root or distro package is required.
install_local_umu() {
    if ! command -v python3 >/dev/null 2>&1; then
        debug_print continue "python3 is not installed; cannot set up umu-launcher."
        return 1
    fi

    umu_url="$(curl -s "$umu_release_api" | grep -Eo '"browser_download_url": ?"[^"]+-zipapp\.tar"' | cut -d '"' -f4 | head -n1)"
    if [ -z "$umu_url" ]; then
        debug_print continue "Could not find the umu-launcher zipapp. The Github API may be down or rate limited."
        return 1
    fi

    umu_tmp="$tmp_dir/umu-zipapp"
    rm -rf "$umu_tmp" && mkdir -p "$umu_tmp"
    debug_print continue "Downloading umu-launcher from $umu_url..."
    if ! curl -sfL "$umu_url" -o "$umu_tmp/umu.tar" || ! tar -xf "$umu_tmp/umu.tar" -C "$umu_tmp" ||
       [ ! -f "$umu_tmp/umu/umu-run" ]; then
        debug_print continue "Downloading or extracting umu-launcher failed."
        return 1
    fi

    mkdir -p "$umu_local_dir"
    cp -f "$umu_tmp/umu/umu-run" "$umu_local_dir/umu-run" && chmod +x "$umu_local_dir/umu-run"
    rm -rf "$umu_tmp"
    "$umu_local_dir/umu-run" --version >/dev/null 2>&1
}

# MARK: ensure_umu()
# Make umu-run available, offering to download it when it is missing.
# Returns 1 if umu is unavailable (callers then fall back to plain Proton).
ensure_umu() {
    find_umu && return 0
    [ "${umu_declined:-0}" = "1" ] && return 1

    if message question "umu-launcher was not found on this system.\n\nIt runs Falcon BMS and prefix tools inside the Steam Linux Runtime, which VR (OpenXR) needs. Without it the Helper falls back to plain Proton.\n\nDownload it now? (no administrator rights needed, installed to\n$umu_local_dir)"; then
        progress_bar start "Downloading umu-launcher..."
        install_local_umu
        umu_install_ok="$?"
        progress_bar stop
        if [ "$umu_install_ok" -eq 0 ] && find_umu; then
            return 0
        fi
        message warning "umu-launcher could not be installed. The Helper will use plain Proton instead.\n\nYou can install the 'umu-launcher' package from your distribution later."
    fi
    umu_declined=1
    return 1
}

# MARK: update_local_umu()
# Refresh the helper's own umu copy (a system umu is left to the package manager)
update_local_umu() {
    if [ -x "$umu_local_dir/umu-run" ] && [ -z "$(command -v umu-run 2>/dev/null)" ]; then
        install_local_umu || debug_print continue "Unable to update $umu_local_dir/umu-run; keeping the current copy."
    fi
}

# MARK: set_prefix_cmd()
# Set prefix_cmd to the command that runs a Windows program or Wine tool in
# the targeted prefix and waits for the prefix to go idle. Expects bms_root,
# bms_pfx and proton_path to be set.
set_prefix_cmd() {
    if [ -z "$proton_path" ] || [ ! -x "$proton_path/proton" ]; then
        debug_print continue "No valid Proton runner is configured for $bms_root."
        return 1
    fi

    if find_umu; then
        prefix_cmd=(env GAMEID=0 WINEPREFIX="$bms_root" PROTONPATH="$proton_path"
            WINEDEBUG="${WINEDEBUG:--all}" WINEDLLOVERRIDES="winemenubuilder.exe=d"
            "$umu_bin")
    else
        prefix_cmd=(env WINEPREFIX="$bms_pfx" STEAM_COMPAT_DATA_PATH="$bms_root"
            STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$proton_path}"
            WINEDEBUG="${WINEDEBUG:--all}" WINEDLLOVERRIDES="winemenubuilder.exe=d"
            "$proton_path/proton" waitforexitandrun)
    fi
}

# MARK: prefix_run()
# Run a Windows program or Wine tool inside the targeted prefix through umu
# (plain Proton as a fallback) and wait until the prefix is idle.
# Usage: prefix_run <exe|wine tool> [args...]
prefix_run() {
    set_prefix_cmd || return 1
    "${prefix_cmd[@]}" "$@"
}

# MARK: prefix_run_timeout()
# Like prefix_run, but give up after the given number of seconds (exit 124)
# Usage: prefix_run_timeout seconds <exe|wine tool> [args...]
prefix_run_timeout() {
    prt_seconds="$1"
    shift
    set_prefix_cmd || return 1
    if [ -x "$(command -v timeout)" ] && [ -n "$prt_seconds" ]; then
        timeout --foreground "$prt_seconds" "${prefix_cmd[@]}" "$@"
    else
        "${prefix_cmd[@]}" "$@"
    fi
}

# MARK: prefix_winetricks()
# Install winetricks verbs with the winetricks bundled in the Proton runner
# Usage: prefix_winetricks verb [verb...]
prefix_winetricks() {
    if find_umu; then
        # umu runs the runner's protonfixes/winetricks inside the runtime
        prefix_run winetricks "$@"
        return $?
    fi

    wt_bin="$proton_path/protonfixes/winetricks"
    if [ ! -f "$wt_bin" ]; then
        debug_print continue "The Proton runner has no bundled winetricks: $proton_path"
        return 1
    fi
    PATH="$proton_path/files/bin:$PATH" WINEPREFIX="$bms_pfx" \
        WINE="$proton_path/files/bin/wine" WINESERVER="$proton_path/files/bin/wineserver" \
        WINEDLLOVERRIDES="winemenubuilder.exe=d" bash "$wt_bin" -q "$@"
}

# MARK: prefix_kill()
# Stop every Wine process in the targeted prefix (cleanup after failures)
prefix_kill() {
    if [ -x "$proton_path/files/bin/wineserver" ]; then
        WINEPREFIX="$bms_pfx" "$proton_path/files/bin/wineserver" -k 2>/dev/null
    fi
}

# MARK: prefix_reg_import()
# Import a .reg file into the prefix with one regedit run
prefix_reg_import() {
    reg_import_name="bms-helper-import.reg"
    cp -f "$1" "$bms_pfx/drive_c/$reg_import_name" || return 1
    prefix_run regedit /S "C:\\$reg_import_name"
    reg_import_rc="$?"
    rm -f "$bms_pfx/drive_c/$reg_import_name"
    return "$reg_import_rc"
}

# MARK: reg_get()
# Print a value straight from a Wine registry file, without starting Wine.
# The data is printed as stored, ie. "C:\\Falcon BMS 4.38" or dword:0001.
# Usage: reg_get system.reg 'Software\Key\Path' ValueName
reg_get() {
    [ -f "$1" ] || return 1
    K="[${2//\\/\\\\}]" V="$3" awk '
        BEGIN { key = tolower(ENVIRON["K"]); val = "\"" tolower(ENVIRON["V"]) "\"=" }
        /^\[/ { line = $0; sub(/\][^\]]*$/, "]", line); insec = (tolower(line) == key); next }
        insec && index(tolower($0), val) == 1 { print substr($0, length(val) + 1); found = 1; exit }
        END { exit(found ? 0 : 1) }
    ' "$1"
}

# MARK: check_dotnet48()
# True if .NET Framework 4.8 (release >= 528040) is registered in the prefix
check_dotnet48() {
    dotnet_release=""
    for dotnet_key in 'Software\Microsoft\NET Framework Setup\NDP\v4\Full' 'Software\Wow6432Node\Microsoft\NET Framework Setup\NDP\v4\Full'; do
        dotnet_release="$(reg_get "$bms_pfx/system.reg" "$dotnet_key" Release)" && break
    done
    case "$dotnet_release" in
        dword:*) [ "$((16#${dotnet_release#dword:}))" -ge 528040 ] ;;
        *) return 1 ;;
    esac
}

# MARK: setup_openxr_runtime_json()
# Pre-build the WiVRn OpenXR runtime JSON so launches only check for a file
setup_openxr_runtime_json() {
    xr_json_out="$bms_root/xr-wivrn-runtime.json"
    home_lib="$HOME/.local/lib/wivrn/libopenxr_wivrn.so"
    sys_lib=""

    for search_path in \
        /usr/lib/wivrn/libopenxr_wivrn.so \
        /usr/lib/x86_64-linux-gnu/wivrn/libopenxr_wivrn.so \
        /usr/lib64/wivrn/libopenxr_wivrn.so \
        /usr/local/lib/wivrn/libopenxr_wivrn.so; do
        if [ -f "$search_path" ]; then
            sys_lib="$search_path"
            break
        fi
    done

    # The runtime container can only see the library under $HOME
    if [ -n "$sys_lib" ] && { [ ! -f "$home_lib" ] || [ "$sys_lib" -nt "$home_lib" ]; }; then
        mkdir -p "$HOME/.local/lib/wivrn"
        cp -p "$sys_lib" "$home_lib" 2>/dev/null || true
    fi

    [ -f "$home_lib" ] || return 1

    printf '{\n    "file_format_version": "1.0.0",\n    "runtime": {\n        "name": "WiVRn",\n        "library_path": "%s"\n    }\n}\n' "$home_lib" > "$xr_json_out"
}

# MARK: build_prefix_reg()
# Print the .reg file with every persistent setting the helper manages
build_prefix_reg() {
    printf 'Windows Registry Editor Version 5.00\n\n'

    # Keep Wine from creating file type associations on the host
    printf '[HKEY_CURRENT_USER\\Software\\Wine\\FileOpenAssociations]\n"Enable"="N"\n\n'
    # Predictable text metrics in the WPF launcher
    printf '[HKEY_CURRENT_USER\\Control Panel\\Desktop]\n"LogPixels"=dword:00000060\n\n'
    # Avoid black windows/artifacts in WPF under Proton + DXVK
    printf '[HKEY_CURRENT_USER\\Software\\Microsoft\\Avalon.Graphics]\n"DisableHWAcceleration"=dword:00000001\n\n'

    # OpenXR: wineopenxr needs WiVRn's Vulkan extension lists and the GPU ids,
    # which Steam's steam_helper would normally write
    vk_vid="" vk_pid=""
    if command -v vulkaninfo >/dev/null 2>&1; then
        eval "$(vulkaninfo --summary 2>/dev/null | awk '
            /vendorID/{vid=$3}
            /deviceID/{did=$3}
            /DISCRETE_GPU/{print "vk_vid=" vid " vk_pid=" did; found=1; exit}
            END{if(!found && vid) print "vk_vid=" vid " vk_pid=" did}
        ')"
    fi
    printf '[HKEY_CURRENT_USER\\Software\\Wine\\VR]\n'
    printf '"openxr_vulkan_instance_extensions"="VK_KHR_external_fence_capabilities VK_KHR_external_memory_capabilities VK_KHR_external_semaphore_capabilities VK_KHR_get_physical_device_properties2"\n'
    printf '"openxr_vulkan_device_extensions"="VK_KHR_dedicated_allocation VK_KHR_external_fence VK_KHR_external_memory VK_KHR_external_semaphore VK_KHR_get_memory_requirements2 VK_KHR_image_format_list VK_KHR_external_memory_fd VK_KHR_external_semaphore_fd VK_KHR_external_fence_fd"\n'
    printf '"state"=dword:00000001\n"is_hmd_present"=dword:00000001\n'
    printf '"openxr_vulkan_device_vid"=dword:%08x\n"openxr_vulkan_device_pid"=dword:%08x\n\n' "${vk_vid:-0}" "${vk_pid:-0}"

    # Thrustmaster MFD helper: hide the physical MFDs so only the virtual
    # devices created by mfd-joystick.py reach DirectInput
    printf '[HKEY_CURRENT_USER\\Software\\Wine\\DirectInput\\Joysticks]\n'
    for mfd_name in "${mfd_physical_names[@]}"; do
        if [ "$(conf_get "$bms_conf" BMS_MFD_HELPER)" = "1" ]; then
            printf '"%s"="disabled"\n' "$mfd_name"
        else
            printf '"%s"=-\n' "$mfd_name"
        fi
    done
    printf '\n'

    # The 32-bit BMS installer only writes its keys to the WOW6432Node view;
    # mirror missing values into the 64-bit view that the game and launcher read
    bms_reg_key='Software\Benchmark Sims\'"$bms_base_dir"
    bms_reg_key_wow='Software\Wow6432Node\Benchmark Sims\'"$bms_base_dir"
    bms_mirror=""
    for reg_name in baseDir curPatch curTheater curUpdate Key; do
        reg_get "$bms_pfx/system.reg" "$bms_reg_key" "$reg_name" >/dev/null && continue
        reg_value="$(reg_get "$bms_pfx/system.reg" "$bms_reg_key_wow" "$reg_name")" || continue
        bms_mirror+="\"$reg_name\"=$reg_value"$'\n'
    done
    if [ -n "$bms_mirror" ]; then
        printf '[HKEY_LOCAL_MACHINE\\%s]\n%s\n' "$bms_reg_key" "$bms_mirror"
    fi
}

# MARK: apply_prefix_settings()
# Apply every persistent prefix setting in a single regedit run and refresh
# the OpenXR runtime JSON. Called at install and repair time.
apply_prefix_settings() {
    build_prefix_reg > "$tmp_dir/bms-prefix-settings.reg"
    prefix_reg_import "$tmp_dir/bms-prefix-settings.reg" || return 1
    setup_openxr_runtime_json || true
    return 0
}

# MARK: find_launcher_exe()
# Print the path of the Falcon BMS launcher executable inside the prefix
find_launcher_exe() {
    launcher_exe="$game_path/Launcher/FalconBMS_Alternative_Launcher.exe"
    if [ ! -f "$launcher_exe" ]; then
        launcher_exe="$(find "$bms_pfx/drive_c" -type f -name 'FalconBMS_Alternative_Launcher.exe' 2>/dev/null | head -n 1)"
    fi
    [ -n "$launcher_exe" ] && printf '%s\n' "$launcher_exe"
}

# MARK: install_launch_script()
# Install the static launcher and its settings file into bms_root, and
# refresh the companion scripts that live beside it. The launcher itself is
# never generated: per-install values are only written to bms-launch.conf.
# Uses proton_path when set.
install_launch_script() {
    cp -f "$SCRIPT_DIR/lib/bms-launcher.sh" "$bms_root/$bms_launcher_name" || return 1
    chmod +x "$bms_root/$bms_launcher_name"

    [ -f "$bms_conf" ] || write_launch_conf_template "$bms_conf"
    if [ -n "$proton_path" ]; then
        conf_set "$bms_conf" PROTONPATH "$proton_path"
    fi
    if installed_launcher_exe="$(find_launcher_exe)"; then
        conf_set "$bms_conf" BMS_LAUNCHER_EXE "$installed_launcher_exe"
    fi

    # Keep companion scripts current if they are in use
    if [ -f "$bms_root/$opentrack_bridge_name" ]; then
        install_opentrack_bridge
    fi
    if [ -f "$bms_root/mfd-joystick.py" ] && [ -f "$SCRIPT_DIR/tools/mfd-joystick.py" ]; then
        cp -f "$SCRIPT_DIR/tools/mfd-joystick.py" "$bms_root/mfd-joystick.py"
    fi
    sync_opentrack_conf_note
    return 0
}
