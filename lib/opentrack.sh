# shellcheck shell=bash
# bms-helper: native Linux OpenTrack head tracking for Falcon BMS under Proton.
# Sourced by bms-helper.sh; defines functions only.

# MARK: opentrack_find_native()
# Locate a native Linux OpenTrack built with Wine output support (SDK_WINE).
# Prefers a distro/AUR install over the helper's own source build.
# Sets opentrack_bin and opentrack_libexec; returns 1 if none is usable.
opentrack_find_native() {
    opentrack_bin=""
    opentrack_libexec=""

    for ot_candidate in "$(command -v opentrack 2>/dev/null)" "$opentrack_local_prefix/bin/opentrack"; do
        [ -n "$ot_candidate" ] && [ -x "$ot_candidate" ] || continue
        ot_libexec="$(dirname "$(realpath "$ot_candidate")")/../libexec/opentrack"
        if [ -f "$ot_libexec/opentrack-wrapper-wine.exe.so" ] && [ -f "$ot_libexec/NPClient64.dll" ]; then
            opentrack_bin="$ot_candidate"
            opentrack_libexec="$(realpath "$ot_libexec")"
            return 0
        fi
    done

    return 1
}

# MARK: opentrack_install_build_deps()
# Install the packages needed to build OpenTrack with Wine support, using the
# distro's package manager. Returns 1 if the user declined or it failed.
opentrack_install_build_deps() {
    ot_pm=""
    ot_pkgs=()
    ot_alts=()
    if command -v pacman >/dev/null 2>&1; then
        ot_pm="pacman"
        ot_pkgs=(base-devel cmake ninja pkgconf curl qt6-base qt6-tools opencv procps-ng libx11 libxcb xorgproto wine)
    elif command -v apt-get >/dev/null 2>&1; then
        ot_pm="apt"
        ot_pkgs=(build-essential cmake ninja-build pkg-config curl qt6-base-dev qt6-base-private-dev qt6-tools-dev qt6-tools-dev-tools qt6-l10n-tools libopencv-dev libx11-dev libxcb1-dev x11proto-dev)
        ot_alts=("libproc2-dev libprocps-dev" "wine64-tools wine-tools")
    elif command -v dnf >/dev/null 2>&1; then
        ot_pm="dnf"
        ot_pkgs=(gcc-c++ cmake ninja-build pkgconf-pkg-config curl qt6-qtbase-devel qt6-qtbase-private-devel qt6-qttools-devel qt6-linguist opencv-devel procps-ng-devel libX11-devel libxcb-devel xorg-x11-proto-devel wine-devel)
    elif command -v zypper >/dev/null 2>&1; then
        ot_pm="zypper"
        ot_pkgs=(gcc-c++ cmake ninja pkgconf curl qt6-base-devel qt6-base-private-devel qt6-tools-devel qt6-linguist-devel opencv-devel libX11-devel libxcb-devel xorgproto-devel wine-devel)
        ot_alts=("procps4-devel procps-devel")
    else
        message warning "Unable to detect a supported package manager (pacman, apt, dnf, zypper).\n\nInstall these build dependencies manually, then retry:\ncmake, ninja, pkg-config, a C++ compiler, Qt6 (base, private headers, tools/linguist), OpenCV, libproc2 or libprocps, X11/xcb headers and Wine development tools (wineg++)."
        return 1
    fi

    # Pick the first available package from each "a b" alternatives group
    for ot_group in "${ot_alts[@]}"; do
        for ot_alt in $ot_group; do
            case "$ot_pm" in
                apt) apt-cache show "$ot_alt" >/dev/null 2>&1 || continue ;;
                zypper) zypper -q -n info "$ot_alt" 2>/dev/null | grep -q '^Name' || continue ;;
            esac
            ot_pkgs+=("$ot_alt")
            break
        done
    done

    case "$ot_pm" in
        pacman) ot_install_cmd="pacman -S --needed --noconfirm ${ot_pkgs[*]}" ;;
        apt) ot_install_cmd="apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y ${ot_pkgs[*]}" ;;
        dnf) ot_install_cmd="dnf install -y ${ot_pkgs[*]}" ;;
        zypper) ot_install_cmd="zypper --non-interactive install ${ot_pkgs[*]}" ;;
    esac

    if ! message question "Building OpenTrack requires these packages:\n\n${ot_pkgs[*]}\n\nInstall them now with $ot_pm? (requires administrator privileges)\n\nChoose No if they are already installed."; then
        return 0
    fi

    debug_print continue "Installing OpenTrack build dependencies: $ot_install_cmd"
    if ! try_exec root "$ot_install_cmd"; then
        message error "Installing the OpenTrack build dependencies failed. See terminal output for details."
        return 1
    fi
    return 0
}

# MARK: build_opentrack_native()
# Download OpenTrack at the pinned commit and build it with Wine output support
# into $opentrack_local_prefix (no root needed apart from build dependencies).
build_opentrack_native() {
    opentrack_install_build_deps || return 1

    # Some distros keep winegcc/wineg++ outside of PATH
    for ot_wine_tools in /usr/lib/wine /usr/lib64/wine /usr/lib/x86_64-linux-gnu/wine /usr/lib/x86_64-linux-gnu/wine/bin; do
        if [ -x "$ot_wine_tools/wineg++" ]; then
            PATH="$PATH:$ot_wine_tools"
            break
        fi
    done
    for ot_tool in cmake wineg++ curl tar; do
        if ! command -v "$ot_tool" >/dev/null 2>&1; then
            message error "'$ot_tool' was not found. It is required to build OpenTrack with Wine support.\n\nInstall your distro's Wine development tools (e.g. wine-devel or wine64-tools) and CMake, then retry."
            return 1
        fi
    done

    ot_generator="Unix Makefiles"
    if command -v ninja >/dev/null 2>&1; then
        ot_generator="Ninja"
    fi

    ot_src="$tmp_dir/opentrack-src"
    ot_build="$tmp_dir/opentrack-build"
    ot_log="$(dirname "$opentrack_local_prefix")/opentrack-build.log"
    mkdir -p "$ot_src" "$(dirname "$opentrack_local_prefix")"
    : > "$ot_log"

    progress_bar start "Building OpenTrack. This takes a few minutes..."
    progress_update "Downloading OpenTrack source ($opentrack_build_ref)..."
    debug_print continue "Building OpenTrack $opentrack_build_ref into $opentrack_local_prefix (log: $ot_log)..."

    if ! curl -fsSL "https://github.com/opentrack/opentrack/archive/${opentrack_build_ref}.tar.gz" -o "$tmp_dir/opentrack-src.tar.gz" >> "$ot_log" 2>&1 ||
       ! tar -xzf "$tmp_dir/opentrack-src.tar.gz" -C "$ot_src" --strip-components=1 >> "$ot_log" 2>&1; then
        progress_bar stop
        message error "Unable to download the OpenTrack source code.\n\nLog: $ot_log"
        return 1
    fi

    # OPENTRACK_WINE_ARCH=-m64: Falcon BMS is 64-bit and loads NPClient64.dll,
    # and 64-bit winelib builds work with both old and new WoW64 Wine/Proton.
    progress_update "Configuring and compiling OpenTrack..."
    if ! cmake -S "$ot_src" -B "$ot_build" -G "$ot_generator" \
            -DCMAKE_BUILD_TYPE=Release \
            -DSDK_WINE=ON \
            -DOPENTRACK_WINE_ARCH=-m64 \
            -DCMAKE_INSTALL_PREFIX="$opentrack_local_prefix" >> "$ot_log" 2>&1 ||
       ! cmake --build "$ot_build" -j"$(nproc)" >> "$ot_log" 2>&1; then
        progress_bar stop
        message error "Building OpenTrack failed. Check that all build dependencies are installed.\n\nLog: $ot_log\n\n$(tail -n 5 "$ot_log")"
        return 1
    fi

    progress_update "Installing OpenTrack to $opentrack_local_prefix..."
    rm -rf "${opentrack_local_prefix:?}"
    if ! cmake --install "$ot_build" >> "$ot_log" 2>&1; then
        progress_bar stop
        message error "Installing OpenTrack failed.\n\nLog: $ot_log"
        return 1
    fi
    echo "$opentrack_build_ref" > "$opentrack_local_prefix/.bms-helper-ref"
    progress_bar stop

    # Menu entry for the local build. --platform xcb keeps global hotkeys working on Wayland.
    mkdir -p "$data_dir/applications"
    cat > "$data_dir/applications/opentrack-bms-helper.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=OpenTrack
Comment=Head tracking software (built by bms-helper)
Exec="$opentrack_local_prefix/bin/opentrack" --platform xcb
Icon=camera-web
Terminal=false
StartupNotify=true
Categories=Utility;
EOF
    return 0
}

# MARK: remove_windows_opentrack()
# Uninstall a Windows OpenTrack from the prefix. It is no longer needed and its
# NPClient registry path would compete with the native Linux bridge.
remove_windows_opentrack() {
    ot_win_dir="$1"

    if bms_running || pgrep -fi '\\opentrack\.exe' >/dev/null 2>&1; then
        message warning "Close Falcon BMS and the Windows OpenTrack before removing it."
        return 1
    fi

    if [ -f "$ot_win_dir/unins000.exe" ] && runner_supported "$proton_path"; then
        debug_print continue "Running the Windows OpenTrack uninstaller in $bms_pfx..."
        # The Inno Setup uninstaller re-spawns itself from a temp copy;
        # prefix_run waits for the whole prefix to go idle.
        prefix_run "$ot_win_dir/unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
    fi
    rm -rf "${ot_win_dir:?}"

    # Drop start-menu entries Wine created for it in this prefix. The menu
    # folder is shared by all prefixes, so only remove it once empty.
    ot_menu_dir="$data_dir/applications/wine/Programs/opentrack"
    if [ -d "$ot_menu_dir" ]; then
        grep -lF "$bms_root" "$ot_menu_dir"/*.desktop 2>/dev/null | xargs -r -d '\n' rm -f
        rmdir "$ot_menu_dir" 2>/dev/null
    fi
    return 0
}

# Explains head tracking in bms-launch.conf while OpenTrack is set up
opentrack_conf_note=(
    "# Head tracking (OpenTrack): there is no setting for it here. This launcher"
    "# never starts OpenTrack. To fly with head tracking, start OpenTrack and press"
    "# Start (before or after Falcon BMS); to fly without it, don't start it."
)

# MARK: sync_opentrack_conf_note()
# Add the head tracking note to bms-launch.conf when this install has the
# OpenTrack bridge, and remove it otherwise. Rewrites the note each time, so
# it never appears twice.
sync_opentrack_conf_note() {
    [ -f "$bms_conf" ] || return 0
    # Drop the note (and the blank line before it), keeping everything else
    awk -v first="${opentrack_conf_note[0]}" -v count="${#opentrack_conf_note[@]}" '
        $0 == first { skip = count; blank = 0 }
        skip > 0 { skip--; next }
        /^$/ { if (blank) print ""; blank = 1; next }
        { if (blank) print ""; blank = 0; print }
        END { if (blank) print "" }
    ' "$bms_conf" > "$bms_conf.tmp" && mv "$bms_conf.tmp" "$bms_conf"

    if [ -f "$bms_root/$opentrack_bridge_name" ]; then
        { echo; printf '%s\n' "${opentrack_conf_note[@]}"; } >> "$bms_conf"
    fi
}

# MARK: install_opentrack_bridge()
# Copy the OpenTrack -> Proton bridge into the install root. OpenTrack's
# "Wine" output runs it as its custom Wine binary; see the script's comments.
install_opentrack_bridge() {
    cp -f "$SCRIPT_DIR/lib/$opentrack_bridge_name" "$bms_root/$opentrack_bridge_name" && chmod +x "$bms_root/$opentrack_bridge_name"
}

# MARK: opentrack_ini_set()
# Set key=value in [section] of a QSettings ini file, creating either if missing.
opentrack_ini_set() {
    ot_ini="$1"
    awk -v sec="[$2]" -v key="$3" -v val="$4" '
        function emit() { if (insec && !done) { print key "=" val; done = 1 } }
        /^\[.*\]$/ { emit(); insec = ($0 == sec); print; next }
        insec && index($0, key "=") == 1 { if (!done) { print key "=" val; done = 1 }; next }
        { print }
        END { if (!done) { if (!insec) print sec; print key "=" val } }
    ' "$ot_ini" > "$ot_ini.bms-helper.tmp" && mv "$ot_ini.bms-helper.tmp" "$ot_ini"
}

# MARK: configure_opentrack_profile()
# Point the active OpenTrack profile's output at the Proton bridge script.
configure_opentrack_profile() {
    ot_bridge_script="$1"
    ot_prefix="$2"

    # Same lookup as OpenTrack: ~/Documents/opentrack-2.3 if it exists, else the config dir
    ot_ini_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opentrack-2.3"
    if [ -d "${XDG_DOCUMENTS_DIR:-$HOME/Documents}/opentrack-2.3" ]; then
        ot_ini_dir="${XDG_DOCUMENTS_DIR:-$HOME/Documents}/opentrack-2.3"
    fi
    ot_profile="$(sed -n 's/^settings-filename=//p' "${XDG_CONFIG_HOME:-$HOME/.config}/opentrack-2.3.conf" 2>/dev/null | tail -n 1 | tr -d '"\r')"
    ot_profile="${ot_profile:-default.ini}"
    ot_ini="$ot_ini_dir/$ot_profile"

    mkdir -p "$ot_ini_dir"
    [ -f "$ot_ini" ] || : > "$ot_ini"
    cp "$ot_ini" "$ot_ini.bms-helper.bak"

    # protocol 1 = NPClient (TrackIR), which is what Falcon BMS uses
    opentrack_ini_set "$ot_ini" modules protocol-dll wine
    opentrack_ini_set "$ot_ini" proto-wine variant-wine true
    opentrack_ini_set "$ot_ini" proto-wine variant-proton false
    opentrack_ini_set "$ot_ini" proto-wine variant-proton-steamplay false
    opentrack_ini_set "$ot_ini" proto-wine variant-proton-external false
    opentrack_ini_set "$ot_ini" proto-wine wine-select-version CUSTOM
    opentrack_ini_set "$ot_ini" proto-wine wine-custom-version "\"$ot_bridge_script\""
    opentrack_ini_set "$ot_ini" proto-wine wineprefix "\"$ot_prefix\""
    opentrack_ini_set "$ot_ini" proto-wine protocol 1
    opentrack_ini_set "$ot_ini" proto-wine esync false
    opentrack_ini_set "$ot_ini" proto-wine fsync false
}

# MARK: setup_opentrack_native()
# Set up head tracking with native Linux OpenTrack: remove a Windows OpenTrack
# from the prefix, find or build a Wine-enabled OpenTrack, write the Proton
# bridge script and configure OpenTrack's output to use it.
setup_opentrack_native() {
    getdirs
    if [ "$?" -eq 1 ]; then
        message warning "Unable to set up OpenTrack."
        return 1
    fi
    get_current_runner

    if pgrep -x opentrack >/dev/null 2>&1; then
        message warning "OpenTrack is running. Close it first so it does not overwrite the new settings."
        return 1
    fi

    for ot_win_dir in "$bms_pfx/drive_c/Program Files (x86)/opentrack" "$bms_pfx/drive_c/Program Files/opentrack"; do
        [ -d "$ot_win_dir" ] || continue
        if message question "A Windows OpenTrack is installed in this prefix:\n$ot_win_dir\n\nIt is not needed with native Linux OpenTrack and would conflict with it. Remove it? (recommended)"; then
            remove_windows_opentrack "$ot_win_dir" || return 1
        fi
    done

    ot_rebuild=0
    if opentrack_find_native; then
        # Offer a rebuild when our own build is older than the pinned commit
        if [ "$opentrack_bin" = "$opentrack_local_prefix/bin/opentrack" ] &&
           [ "$(cat "$opentrack_local_prefix/.bms-helper-ref" 2>/dev/null)" != "$opentrack_build_ref" ]; then
            if message question "A newer OpenTrack version is available for the helper-built copy.\n\nRebuild it now?"; then
                ot_rebuild=1
            fi
        fi
    else
        if ! message question "No OpenTrack with Wine support was found.\n\n(Distro packages are often built without it; on Arch-based distros the AUR 'opentrack' package includes it.)\n\nBuild OpenTrack from source into:\n$opentrack_local_prefix ?"; then
            return 1
        fi
        ot_rebuild=1
    fi
    if [ "$ot_rebuild" -eq 1 ]; then
        build_opentrack_native || return 1
        if ! opentrack_find_native; then
            message error "OpenTrack was built, but its Wine bridge was not found in:\n$opentrack_local_prefix"
            return 1
        fi
    fi

    install_opentrack_bridge
    configure_opentrack_profile "$bms_root/$opentrack_bridge_name" "$bms_root"
    sync_opentrack_conf_note

    message info "OpenTrack is set up for Falcon BMS.\n\nOpenTrack: $opentrack_bin\nOutput: Wine (NPClient), via $bms_root/$opentrack_bridge_name\n\nOpenTrack is never started automatically, and there is no launcher setting for it:\n- With head tracking: start OpenTrack and press Start, before or after launching Falcon BMS. It connects once Falcon's launcher is running.\n- Without head tracking: just don't start OpenTrack.\n\nBridge log: $bms_root/opentrack/bridge.log"
    return 0
}
