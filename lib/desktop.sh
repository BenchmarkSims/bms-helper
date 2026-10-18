# shellcheck shell=bash
# bms-helper: icons and .desktop files.
# Sourced by bms-helper.sh; defines functions only.

# MARK: ensure_bms_icon_installed()
# Install/refresh the bundled icon in the user's local hicolor icon directory.
ensure_bms_icon_installed() {
    icon_target_dir_256="${data_dir}/icons/hicolor/256x256/apps"
    icon_target_dir_512="${data_dir}/icons/hicolor/512x512/apps"
    icon_target_dir_pixmaps="${data_dir}/pixmaps"
    icon_target_path_256="${icon_target_dir_256}/bms-launcher.png"
    icon_target_path_512="${icon_target_dir_512}/bms-launcher.png"
    icon_target_path_pixmaps="${icon_target_dir_pixmaps}/bms-launcher.png"
    icon_prefix_path=""
    icon_source_512="$bms_icon"
    icon_source_256="$bms_icon_256"

    if [ ! -f "$icon_source_512" ]; then
        debug_print continue "Bundled icon was not found at $icon_source_512"
        return 1
    fi

    if [ ! -s "$icon_source_512" ]; then
        debug_print continue "Bundled icon is empty and cannot be installed: $icon_source_512"
        return 1
    fi

    # Prefer the bundled 256 icon for 256x256 installs, fallback to 512 if missing.
    if [ ! -f "$icon_source_256" ] || [ ! -s "$icon_source_256" ]; then
        icon_source_256="$icon_source_512"
    fi

    mkdir -p "$icon_target_dir_256" "$icon_target_dir_512" "$icon_target_dir_pixmaps" || return 1

    # Force overwrite so repair/recreate always refreshes stale or corrupted icons.
    if ! cp -f -- "$icon_source_256" "$icon_target_path_256"; then
        debug_print continue "Failed to copy icon to $icon_target_path_256"
        return 1
    fi
    if ! cp -f -- "$icon_source_512" "$icon_target_path_512"; then
        debug_print continue "Failed to copy icon to $icon_target_path_512"
        return 1
    fi
    if ! cp -f -- "$icon_source_512" "$icon_target_path_pixmaps"; then
        debug_print continue "Failed to copy icon to $icon_target_path_pixmaps"
        return 1
    fi

    if [ ! -s "$icon_target_path_256" ] || [ ! -s "$icon_target_path_512" ] || [ ! -s "$icon_target_path_pixmaps" ]; then
        debug_print continue "Installed icon appears empty in one or more target locations"
        return 1
    fi

    # Also place the icon beside the generated launcher in the prefix root.
    # This allows desktop files to use an absolute icon path that does not depend on icon themes.
    if [ -n "$bms_root" ] && [ -d "$bms_root" ]; then
        icon_prefix_path="$bms_root/bms-launcher.png"
        if ! cp -f -- "$icon_source_512" "$icon_prefix_path"; then
            debug_print continue "Failed to copy icon beside launcher: $icon_prefix_path"
        fi
    fi

    # Refresh icon cache when available so desktop environments pick the new icon.
    if [ -x "$(command -v gtk-update-icon-cache)" ]; then
        gtk-update-icon-cache -q -t "${data_dir}/icons/hicolor" >/dev/null 2>&1 || true
    fi

    debug_print continue "Installed icon to $icon_target_path_256"
    return 0
}

# MARK: create_desktop_files()
# Create the Falcon BMS .desktop files. They run bms-launcher.sh, so they
# never need to change when the runner changes. A backup copy is always
# written to the install root.
#
# This function takes one optional string argument:
# "needed" will only create the menu/desktop files that don't exist
create_desktop_files() {
    if [ -z "$bms_root" ]; then
        debug_print exit "Script error: The string 'bms_root' was not set before calling the create_desktop_files function. Aborting."
    fi

    prefix_desktop_file="$bms_root/$bms_desktop_basename"
    localshare_desktop_file="${data_dir}/applications/$bms_desktop_basename"
    home_desktop_file="${XDG_DESKTOP_DIR:-$HOME/Desktop}/$bms_desktop_basename"

    create_localshare_file="true"
    create_home_file="true"
    if [ "$1" = "needed" ]; then
        [ -f "$localshare_desktop_file" ] && create_localshare_file="false"
        [ -f "$home_desktop_file" ] && create_home_file="false"
    fi

    if ! ensure_bms_icon_installed; then
        debug_print continue "Warning: unable to install or refresh desktop icon from $bms_icon"
    fi
    desktop_icon_value="bms-launcher"
    if [ -s "$bms_root/bms-launcher.png" ]; then
        desktop_icon_value="$bms_root/bms-launcher.png"
    fi

    desktop_path="$game_path/Launcher"
    if desktop_launcher_exe="$(find_launcher_exe)"; then
        desktop_path="$(dirname "$desktop_launcher_exe")"
    fi

    debug_print continue "Creating ${prefix_desktop_file}..."
    cat > "$prefix_desktop_file" <<DESKTOP
[Desktop Entry]
Name=$bms_base_dir Launcher
Type=Application
Comment=$bms_base_dir
Keywords=Falcon BMS;Simulation;Flight;Game;
Terminal=false
StartupNotify=true
Categories=Game;Simulation;X-WiVRn-VR;
StartupWMClass=FalconBMS_Alternative_Launcher.exe
Exec="$bms_root/$bms_launcher_name"
Path=$desktop_path
Icon=$desktop_icon_value
DESKTOP

    if [ "$create_localshare_file" = "true" ]; then
        mkdir -p "${data_dir}/applications"
        cp "$prefix_desktop_file" "$localshare_desktop_file"
        [ -f "$localshare_desktop_file" ] || message warning "Warning: The .desktop file could not be created!\n\n${localshare_desktop_file}"
    fi
    if [ "$create_home_file" = "true" ] && [ -d "$(dirname "$home_desktop_file")" ]; then
        cp "$prefix_desktop_file" "$home_desktop_file"
        chmod +x "$home_desktop_file" 2>/dev/null
    fi

    if [ -x "$(command -v update-desktop-database)" ]; then
        update-desktop-database "${data_dir}/applications" 2>/dev/null
    fi
}

# MARK: remove_gog_falcon4_desktop()
# Remove desktop shortcuts created by the GOG Falcon 4.0 installer (if present)
remove_gog_falcon4_desktop() {
    home_desktop_dir="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
    localshare_dir="${data_dir}/applications"
    install_dir_safe="${bms_root:-}" # may be empty in some contexts

    removed_any=0
    patterns=("Falcon 4" "Falcon4" "Falcon_4" "Falcon4.0" "Falcon_4.0")

    for d in "$home_desktop_dir" "$localshare_dir" "$install_dir_safe"; do
        [ -n "$d" ] || continue
        for p in "${patterns[@]}"; do
            # Use simple globbing; enable nullglob to avoid literal pattern
            shopt -s nullglob 2>/dev/null || true
            for f in "$d"/*"$p"*.desktop; do
                if [ -f "$f" ]; then
                    rm -f -- "$f" 2>/dev/null || true
                    removed_any=1
                    debug_print continue "Removed GOG-created desktop shortcut: $f"
                fi
            done
            shopt -u nullglob 2>/dev/null || true
        done
    done

    if [ "$removed_any" -eq 1 ]; then
        # Update desktop database if available
        if [ -x "$(command -v update-desktop-database)" ]; then
            update-desktop-database "${data_dir}/applications" 2>/dev/null || true
        fi
        message info "Removed GOG Falcon 4.0 desktop shortcuts that were created during installation."
    fi
}
