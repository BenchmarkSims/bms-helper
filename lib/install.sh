# shellcheck shell=bash
# bms-helper: Falcon BMS installation and removal.
# Sourced by bms-helper.sh; defines functions only.

# Files copied back into the new <game>/User/Config when Falcon BMS is
# reinstalled (the whole old User/Config folder is backed up first):
# - user and VR configs, editor and display settings
# - .ini files: server list (PhoneBkn.ini), per-callsign settings and MFD
#   preferences (<callsign>.ini), 3D UI settings...
# - keyfiles
# - controller setup: the launcher's per-device Setup.v100.*.xml, axis
#   mapping, calibration and device order
# - per-callsign pilot files (logbook .lbk, .pop, .rul, .plc)
bms_user_config_patterns=(
    "Falcon BMS User.cfg" "Falcon BMS VR.cfg" "Falcon BMS Editor.cfg" "d3d11.dsp"
    "*.ini" "*.key"
    "Setup.v100.*.xml" "axismapping.dat" "joystick.cal" "DeviceSorting.txt"
    "*.lbk" "*.pop" "*.rul" "*.plc"
)
# Default files shipped by Falcon BMS (the new install's copies win) and
# leftovers that match the patterns above
bms_user_config_exclude=("*_Def.ini" "Feedback.ini" "*_tmp.*")

# MARK: reinstall_bms()
# Reinstall Falcon BMS into the targeted install, keeping the user's settings
reinstall_bms() {
    getdirs || return 1
    if ! message question "Reinstall Falcon BMS?\n\n$bms_root\n\nThe game is installed again from scratch. Your User/Config folder is backed up first, and your settings, keyfiles, server list and pilot logbooks are copied into the new install.\n\nApplications you installed into the Wine prefix are removed."; then
        return 0
    fi
    install_game reinstall
}

# MARK: install_game()
# Install Falcon BMS into a new Proton prefix.
# With the argument "reinstall", reinstall into the targeted install root.
install_game() {
    reinstall_root=""
    if [ "$1" = "reinstall" ]; then
        reinstall_root="$bms_root"
    fi

    preflight_check "wine"
    if [ "$?" -eq 1 ]; then
        install_question="Before proceeding, be sure all Preflight Checks have passed!\n\nPlease refer to our Quick Start Guide:\n$bms_wiki\n\nAre you ready to continue?"
    else
        install_question="Before proceeding, please refer to our Quick Start Guide:\n$bms_wiki\n\nAll Preflight Checks have passed\nAre you ready to continue?"
    fi
    if ! message question "$install_question"; then
        return 1
    fi

    # Get the install path from the user
    if [ -n "$reinstall_root" ]; then
        new_root="$reinstall_root"
    elif message question "Would you like to use the default install path?\n\n$bms_default_install_path"; then
        new_root="$bms_default_install_path"
    elif [ "$use_zenity" -eq 1 ]; then
        message info "On the next screen, select your Falcon BMS install location"
        while true; do
            new_root="$(zenity --file-selection --directory --title="Choose your Falcon BMS install directory" --filename="$HOME/" 2>/dev/null)"
            if [ -z "$new_root" ]; then
                message warning "Installation cancelled."
                return 1
            fi
            if [ -d "$new_root/$bms_dirname" ]; then
                message warning "A directory named \"$bms_dirname\" already exists!\nPlease choose a different install location.\n\n$new_root"
                continue
            fi
            new_root="$new_root/$bms_dirname"
            break
        done
    else
        clear
        printf "Enter the desired Falcon BMS install path (case sensitive)\nie. %s\n\n" "$bms_default_install_path"
        while read -rp "Install path: " new_root; do
            new_root="${new_root/#\~/$HOME}"
            if [ -z "$new_root" ]; then
                printf "Invalid directory. Please try again.\n\n"
            elif [ ! -d "$new_root" ]; then
                if message question "That directory does not exist.\nWould you like it to be created for you?\n"; then
                    break
                fi
            else
                break
            fi
        done
    fi

    reinstalling=0
    user_config_backup=""
    if is_bms_install "$new_root"; then
        if [ -z "$reinstall_root" ] && ! message question "A Falcon BMS install already exists at:\n\n$new_root\n\nReinstall Falcon BMS there? Your settings, keyfiles, server list and pilot logbooks are kept; applications installed into its Wine prefix are removed."; then
            return 1
        fi
        if bms_running; then
            message warning "Close Falcon BMS before reinstalling it."
            return 1
        fi
    fi
    check_install_filesystem "$new_root" || return 1

    # Gather everything that needs user input before the long unattended part
    if [ "$bms_mode" != "internal" ]; then
        choose_falcon4_source || { cleanup_conf_if_only_firstrun; return 1; }
        if [ "$falcon4_source" = "gog" ]; then
            if ! download_gog_installer; then
                message error "Unable to prepare Falcon 4.0 from GOG. Aborting."
                cleanup_conf_if_only_firstrun
                return 1
            fi
        fi
    else
        # Internal installs do not require Falcon 4.0 media.
        falcon4_source="none"
        steam_falcon4_dir=""
    fi

    if ! download_bms_installer; then
        message error "Unable to install Falcon BMS. Aborting."
        cleanup_conf_if_only_firstrun
        return 1
    fi
    if ! is_bms_install "$new_root" && ! check_install_space "$new_root"; then
        cleanup_conf_if_only_firstrun
        return 1
    fi

    # Reinstall: back up User/Config, then remove only the old Wine prefix.
    # The install root keeps the runners, launch settings and companion scripts.
    if is_bms_install "$new_root"; then
        if ! backup_bms_user_config "$new_root"; then
            message error "Your Falcon BMS settings could not be backed up, so the reinstall was cancelled.\n\nNothing was changed."
            return 1
        fi
        reinstalling=1
        progress_bar start "Removing the old Falcon BMS prefix..."
        remove_old_prefix "$new_root"
        progress_bar stop
    fi

    set_install_paths "$new_root"
    if ! mkdir -p "$bms_pfx"; then
        install_failed "Unable to create $bms_pfx"
        return 1
    fi
    write_install_marker "$bms_root"

    ensure_umu

    # Pick (and download if needed) the Proton runner
    if ! choose_default_runner; then
        install_failed "No Proton runner could be downloaded or found. Installation cannot proceed."
        return 1
    fi
    # A reinstall keeps the existing launch settings
    [ -f "$bms_conf" ] || write_launch_conf_template "$bms_conf"
    conf_set "$bms_conf" PROTONPATH "$proton_path"

    install_log="$bms_root/bms-install.log"
    debug_print continue "Installation log file created at $install_log"
    {
        echo "=== Falcon BMS install diagnostic log ==="
        echo "timestamp: $(date -Iseconds)"
        echo "install_root: $bms_root"
        echo "proton: $proton_path"
        echo "umu: ${umu_bin:-<none, plain Proton>}"
        echo "falcon4_source: $falcon4_source"
        echo "selected_gog_installer: ${selected_gog_installer:-<default>}"
        echo "selected_bms_installer: ${selected_bms_installer:-<default>}"
        echo ""
    } > "$install_log"

    # Timeouts for long-running install stages (override via environment if needed)
    prefix_setup_timeout_seconds="${BMS_PREFIX_SETUP_TIMEOUT_SECONDS:-5400}"
    installer_timeout_seconds="${BMS_INSTALLER_TIMEOUT_SECONDS:-7200}"

    progress_bar start "Preparing Wine prefix and installing Falcon BMS. Please wait..."

    # Let Proton create the prefix in pfx/
    progress_update "Creating the Wine prefix..."
    echo "=== Stage: prefix_create ===" >> "$install_log"
    if ! prefix_run_timeout "$prefix_setup_timeout_seconds" wineboot -u >> "$install_log" 2>&1 || [ ! -f "$bms_pfx/system.reg" ]; then
        install_failed "Wine prefix creation failed."
        return 1
    fi

    # Runtime components, with the winetricks bundled in the Proton runner.
    # Proton already provides DXVK and VKD3D.
    progress_update "Installing required components into the Wine prefix..."
    prefix_components=(corefonts tahoma lucida verdana gdiplus powershell win11)
    # The BMS installer installs .NET 4.8.1 itself; dotnet48 is only added
    # afterwards if that didn't work (see below), or up front on request
    if [ "${BMS_PREINSTALL_DOTNET48:-0}" = "1" ]; then
        prefix_components+=(dotnet48)
    fi
    {
        echo "=== Stage: prefix_setup ==="
        echo "verbs=${prefix_components[*]}"
    } >> "$install_log"
    if ! prefix_winetricks_timeout "$prefix_setup_timeout_seconds" "${prefix_components[@]}" >> "$install_log" 2>&1; then
        install_failed "Installing the Wine prefix components failed."
        return 1
    fi

    # Fix oversized fonts in the WPF / MahApps.Metro .NET Launcher
    progress_update "Applying display scaling and font fixes..."
    if curl -sL "https://github.com/mrbvrz/segoe-ui-linux/archive/refs/heads/master.tar.gz" | tar -xz -C "$tmp_dir" 2>/dev/null; then
        cp "$tmp_dir"/segoe-ui-linux-master/font/*.ttf "$bms_pfx/drive_c/windows/Fonts/" 2>/dev/null || true
    fi

    if [ "$falcon4_source" = "steam" ]; then
        # Mirror the Steam Falcon 4.0 files into the prefix's C: drive
        steam_target_dir="$bms_pfx/drive_c/Falcon 4.0"
        progress_update "Copying Steam Falcon 4.0 files into the Wine prefix..."
        echo "=== Stage: falcon4_steam_copy ($steam_falcon4_dir) ===" >> "$install_log"
        mkdir -p "$steam_target_dir"
        if ! cp -a "$steam_falcon4_dir"/. "$steam_target_dir"/ >> "$install_log" 2>&1 || [ ! -f "$steam_target_dir/falcon4.exe" ]; then
            install_failed "Failed to copy Steam Falcon 4.0 files into the Wine prefix."
            return 1
        fi

        progress_update "Applying Falcon 4.0 registry keys..."
        if ! apply_falcon4_registry_key >> "$install_log" 2>&1; then
            install_failed "Falcon 4.0 registry initialization failed."
            return 1
        fi
    elif [ "$falcon4_source" = "gog" ]; then
        progress_update "Running Falcon 4.0 GoG installer..."
        echo "=== Stage: gog_install ===" >> "$install_log"
        if [ "${falcon4_interactive:-0}" = "1" ]; then
            prefix_run_timeout "$installer_timeout_seconds" "$selected_gog_installer" >> "$install_log" 2>&1
        else
            prefix_run_timeout "$installer_timeout_seconds" "${selected_gog_installer:-$SCRIPT_DIR/$gog_installer}" /VERYSILENT /NOICONS >> "$install_log" 2>&1
        fi
        gog_exit_code="$?"
        if [ "$gog_exit_code" -ne 0 ] || grep -Eiq "Cannot Imprt dll|Cannot Import dll|get_hw_caps\.dll" "$install_log"; then
            if grep -Eiq "Cannot Imprt dll|Cannot Import dll|get_hw_caps\.dll" "$install_log"; then
                install_failed "The Falcon 4.0 GoG installer failed during DLL import initialization (get_hw_caps.dll).\n\nThis usually points to a runtime mismatch or broken prefix runtime state."
            else
                install_failed "The Falcon 4.0 GoG installer failed with exit code: $gog_exit_code"
            fi
            return 1
        fi
    fi

    progress_update "Running Falcon BMS installer..."
    if ! build_bms_installer_args; then
        install_failed "Falcon BMS installer arguments could not be prepared."
        return 1
    fi
    # Log the arguments without the internal installer key
    installer_args_shown="${installer_args[*]/#\/key=*//key=<hidden>}"
    debug_print continue "Falcon BMS selected arguments: $installer_args_shown"
    echo "=== Stage: bms_install ($installer_args_shown) ===" >> "$install_log"
    prefix_run_timeout "$installer_timeout_seconds" "${selected_bms_installer:-$SCRIPT_DIR/$bms_installer}" "${installer_args[@]}" >> "$install_log" 2>&1
    exit_code="$?"
    if [ "$exit_code" -eq 124 ]; then
        install_failed "The Falcon BMS installer timed out after ${installer_timeout_seconds} seconds."
        return 1
    elif [ "$exit_code" -ne 0 ] || [ ! -d "$game_path" ]; then
        install_failed "The Falcon BMS installer failed (exit code $exit_code)."
        return 1
    fi

    # Without .NET 4.8 the Alternative Launcher runs on wine-mono, which is
    # slow and crashes; install it if the BMS installer's own setup failed
    if ! check_dotnet48; then
        progress_update "Installing .NET Framework 4.8 (this takes several minutes)..."
        echo "=== Stage: dotnet48 (not installed by the BMS installer) ===" >> "$install_log"
        prefix_winetricks_timeout "$prefix_setup_timeout_seconds" dotnet48 >> "$install_log" 2>&1 ||
            debug_print continue "Installing dotnet48 failed; 'Installation checks' can retry it."
    fi

    if [ "${use_16k_tiles:-0}" = "1" ]; then
        progress_bar stop
        download_16k_tiles || debug_print continue "The 16K tiles download did not finish; it can be finished from the main menu."
        progress_bar start "Finishing the Falcon BMS installation..."
    fi

    if [ -n "$user_config_backup" ]; then
        progress_update "Restoring your Falcon BMS settings..."
        restore_bms_user_config >> "$install_log" 2>&1
    fi

    # Persistent prefix settings (WPF fixes, BMS registry views, VR) in one go
    progress_update "Applying Falcon BMS prefix settings..."
    apply_prefix_settings >> "$install_log" 2>&1 || debug_print continue "Applying prefix settings failed; run 'Installation checks' later."
    progress_bar stop

    # Target the new install
    reset_helper "switchprefix"
    echo "$bms_root" > "$conf_dir/$conf_subdir/$wine_conf"
    getdirs || return 1

    install_launch_script || message warning "Failed to install the launch script at $bms_root/$bms_launcher_name"
    remove_gog_falcon4_desktop
    create_desktop_files

    debug_print continue "Installation finished"
    if [ "$reinstalling" -eq 1 ]; then
        message info "Falcon BMS was reinstalled${user_config_backup:+ and your settings were restored.\n\nA copy of your previous User/Config folder is kept at:\n$user_config_backup}"
    fi
    message info "Installation has finished. The install log was written to $install_log\n\nTo start Falcon BMS, use the following .desktop files:\n     $home_desktop_file\n     $localshare_desktop_file\n\nOr run the following launch script:\n     $bms_root/$bms_launcher_name"
}

# MARK: prefix_winetricks_timeout()
# prefix_winetricks with a timeout (exit 124 when it expires)
prefix_winetricks_timeout() {
    pwt_seconds="$1"
    shift
    if find_umu; then
        prefix_run_timeout "$pwt_seconds" winetricks "$@"
    else
        prefix_winetricks "$@"
    fi
}

# MARK: install_failed()
# Report a failed installation and offer to remove the partial install. A
# failed reinstall keeps the install root (runners, settings) and the backup.
install_failed() {
    prefix_kill
    progress_bar stop
    if [ "${reinstalling:-0}" -eq 1 ]; then
        message error "$1\n\nThe install log was written to\n$install_log${user_config_backup:+\n\nYour previous User/Config folder is backed up at:\n$user_config_backup}\n\nRun 'Reinstall Falcon BMS' again once the problem is fixed."
    elif message question "$1\n\nThe install log was written to\n$install_log\n\nDo you want to delete\n${bms_root}?"; then
        debug_print continue "Deleting $bms_root..."
        rm -r --interactive=never "${bms_root:?}"
    fi
    cleanup_conf_if_only_firstrun
}

# MARK: remove_old_prefix()
# Delete the Wine prefix of an install root (either layout) together with
# Proton's bookkeeping files, so Proton creates a fresh prefix. Runners,
# launch settings and companion scripts in the root are kept.
remove_old_prefix() {
    rop_root="$1"
    rop_runner="$(conf_get "$rop_root/bms-launch.conf" PROTONPATH 2>/dev/null)"
    [ -n "$rop_runner" ] || rop_runner="$(legacy_runner_path "$rop_root")"
    if [ -x "$rop_runner/files/bin/wineserver" ]; then
        WINEPREFIX="$rop_root/pfx" "$rop_runner/files/bin/wineserver" -k 2>/dev/null
        WINEPREFIX="$rop_root" "$rop_runner/files/bin/wineserver" -k 2>/dev/null
    fi

    if [ -L "$rop_root/pfx" ]; then
        rm -f "$rop_root/pfx"
    elif [ -d "$rop_root/pfx" ]; then
        rm -r --interactive=never "${rop_root:?}/pfx"
    fi

    # Layout 1 prefix files in the root, plus Proton's files that describe the prefix
    shopt -s nullglob dotglob
    for rop_item in "$rop_root"/drive_c "$rop_root"/dosdevices "$rop_root"/*.reg "$rop_root"/*.reg.* \
        "$rop_root"/.update-timestamp "$rop_root"/winetricks.log "$rop_root"/.windows-serial \
        "$rop_root"/creation_sync_guard "$rop_root"/version "$rop_root"/tracked_files \
        "$rop_root"/config_info "$rop_root"/pfx.lock "$rop_root"/current_runner; do
        [ -e "$rop_item" ] || [ -L "$rop_item" ] || continue
        rm -r --interactive=never "$rop_item"
    done
    shopt -u nullglob dotglob

    # App shortcuts point into the old prefix
    for rop_shortcut in "$rop_root/shortcuts"/*.sh; do
        [ -f "$rop_shortcut" ] && delete_application_shortcut "$rop_shortcut"
    done
}

# MARK: find_user_config_dir()
# Print the User/Config directory of an install root (either layout)
find_user_config_dir() {
    for ucd in "$1/pfx/drive_c/$bms_base_dir/User/Config" "$1/drive_c/$bms_base_dir/User/Config"; do
        if [ -d "$ucd" ]; then
            printf '%s\n' "$ucd"
            return 0
        fi
    done
    return 1
}

# MARK: backup_bms_user_config()
# Copy the old User/Config folder to a dated backup outside the install and
# set user_config_backup to it. Succeeds with nothing to back up.
backup_bms_user_config() {
    user_config_backup=""
    ucb_src="$(find_user_config_dir "$1")" || return 0

    ucb_dest="$data_dir/bms-helper/backups/$conf_subdir-$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$(dirname "$ucb_dest")" || return 1
    cp -a -- "$ucb_src" "$ucb_dest" || return 1

    user_config_backup="$ucb_dest"
    debug_print continue "Backed up $ucb_src to $user_config_backup"
    return 0
}

# MARK: restore_bms_user_config()
# Copy the user's settings files from the backup into the new User/Config
restore_bms_user_config() {
    [ -n "$user_config_backup" ] && [ -d "$user_config_backup" ] || return 0
    ucr_dest="$game_path/User/Config"
    mkdir -p "$ucr_dest"

    # Match names against the patterns case-insensitively (names have spaces,
    # so the patterns are matched with [[ ]] instead of being globbed)
    shopt -s nocasematch
    for ucr_file in "$user_config_backup"/*; do
        [ -f "$ucr_file" ] || continue
        ucr_name="$(basename "$ucr_file")"
        ucr_skip=0
        for ucr_pattern in "${bms_user_config_exclude[@]}"; do
            # shellcheck disable=SC2053
            [[ "$ucr_name" == $ucr_pattern ]] && ucr_skip=1 && break
        done
        [ "$ucr_skip" -eq 1 ] && continue
        for ucr_pattern in "${bms_user_config_patterns[@]}"; do
            # shellcheck disable=SC2053 # the pattern is meant to match as a glob
            if [[ "$ucr_name" == $ucr_pattern ]]; then
                cp -p -- "$ucr_file" "$ucr_dest/" && echo "Restored $ucr_name"
                break
            fi
        done
    done
    shopt -u nocasematch
}

# MARK: uninstall_bms()
# Remove the Falcon BMS installation, desktop files and icon
uninstall_bms() {
    getdirs
    if [ "$?" -eq 1 ]; then
        return 0
    fi
    get_current_runner

    prefix_desktop_file="$bms_root/$bms_desktop_basename"
    localshare_desktop_file="${data_dir}/applications/$bms_desktop_basename"
    home_desktop_file="${XDG_DESKTOP_DIR:-$HOME/Desktop}/$bms_desktop_basename"

    if ! message question "This will permanently delete the Falcon BMS installation at:\n\n$bms_root\n\nand remove desktop shortcuts and icon. Continue?"; then
        return 0
    fi
    if bms_running; then
        message warning "Close Falcon BMS before removing it."
        return 1
    fi

    prefix_kill

    # Remove app shortcuts pointing into this install
    for uninstall_shortcut in "$bms_root/shortcuts"/*.sh; do
        [ -f "$uninstall_shortcut" ] && delete_application_shortcut "$uninstall_shortcut"
    done

    if [ -d "$bms_root" ]; then
        rm -r --interactive=never "${bms_root:?}"
    fi

    rm -f -- "$prefix_desktop_file" "$localshare_desktop_file" "$home_desktop_file"
    if [ -x "$(command -v update-desktop-database)" ]; then
        update-desktop-database "${data_dir}/applications" 2>/dev/null || true
    fi

    rm -f -- "${conf_dir:?}/$conf_subdir/$wine_conf" "${conf_dir:?}/$conf_subdir/$game_conf"
    cleanup_conf_if_only_firstrun

    if [ -f "$joystick_rules_file" ] && message question "Also remove the joystick access rules?\n\n$joystick_rules_file\n\n(Keep them if you use these devices in other games.)"; then
        remove_joystick_rules
    fi

    message info "Falcon BMS has been uninstalled."
    exit 0
}

# MARK: build_bms_installer_args()
# Build installer argument array for public/internal variants.
build_bms_installer_args() {
    installer_args=("/S")

    # Keep installer behavior consistent across public/internal builds.
    installer_args+=("/noshort")

    # The installer's own /16k download runs a Windows torrent client and
    # firewall rules inside the prefix; the Helper downloads the tiles
    # natively after the install instead (download_16k_tiles)

    if [ "$bms_mode" = "internal" ]; then
        bms_key="$(echo "${bms_key:-}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [ -z "$bms_key" ]; then
            message error "Internal installer key is required for internal Falcon BMS installs.\n\nPlease run install again and enter a valid key."
            return 1
        fi
        installer_args+=("/key=$bms_key")
    fi

    return 0
}

# MARK: detect_steam_falcon4_install()
# Detect Falcon 4.0 in known Steam default locations
detect_steam_falcon4_install() {
    steam_falcon4_dir=""
    local candidates=(
        "$HOME/.steam/steam/steamapps/common/Falcon 4.0"
        "$HOME/.steam/root/steamapps/common/Falcon 4.0"
        "$HOME/.local/share/Steam/steamapps/common/Falcon 4.0"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/Falcon 4.0"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [ -d "$candidate" ] && [ -f "$candidate/falcon4.exe" ]; then
            steam_falcon4_dir="$candidate"
            return 0
        fi
    done
    return 1
}

# MARK: select_steam_falcon4_install()
# Ask the user to select their Steam Falcon 4.0 folder and validate falcon4.exe
# Allows retrying so non-standard Steam library locations can be selected.
select_steam_falcon4_install() {
    local default_dir="$HOME/.steam/steam/steamapps/common/Falcon 4.0"
    local selected_dir=""

    while true; do
        selected_dir=""

        if [ "$use_zenity" -eq 1 ]; then
            selected_dir="$(zenity --file-selection --directory --title="Select Steam Falcon 4.0 directory" --filename="$default_dir/" 2>/dev/null)"
            if [ -z "$selected_dir" ]; then
                if message question "No directory was selected. Would you like to try again?"; then
                    continue
                fi
                message error "No Steam Falcon 4.0 directory selected. Aborting installation."
                return 1
            fi
        else
            printf "Enter your Steam Falcon 4.0 directory\nExample: %s\n\n" "$default_dir"
            read -rp "Directory path: " selected_dir
            if [ -z "$selected_dir" ]; then
                if message question "No directory was provided. Would you like to try again?"; then
                    continue
                fi
                message error "No Steam Falcon 4.0 directory provided. Aborting installation."
                return 1
            fi
        fi

        if [ -d "$selected_dir" ] && [ -f "$selected_dir/falcon4.exe" ]; then
            steam_falcon4_dir="$selected_dir"
            return 0
        fi

        if ! message question "Invalid Steam Falcon 4.0 directory. Expected to find falcon4.exe in:\n$selected_dir\n\nWould you like to choose another folder?"; then
            message error "Invalid Steam Falcon 4.0 directory. Installation cancelled."
            return 1
        fi
    done
}

# MARK: choose_falcon4_source()
# Ask user whether Falcon 4.0 should come from Steam; fallback to GOG by default
choose_falcon4_source() {
    if [ "$bms_mode" = "internal" ]; then
        falcon4_source="none"
        steam_falcon4_dir=""
        return 0
    fi

    falcon4_source="gog"
    steam_falcon4_dir=""

    if message question "Do you have Falcon 4.0 installed from Steam (or an already installed Falcon 4.0 folder)?\n\nSelect 'No' to use the GOG installer or a Falcon 4.0 CD installer."; then
        falcon4_source="steam"
        if detect_steam_falcon4_install; then
            message info "Steam Falcon 4.0 detected at:\n$steam_falcon4_dir"
            return 0
        fi

        message warning "Steam Falcon 4.0 was not found in default locations.\nPlease select your Falcon 4.0 folder manually."
        if ! select_steam_falcon4_install; then
            return 1
        fi
    else
        falcon4_source="gog"
    fi

    return 0
}

# MARK: apply_falcon4_registry_key()
# Import Falcon 4.0 registry keys into the current prefix without external files
apply_falcon4_registry_key() {
    if [ ! -d "$bms_pfx/drive_c" ]; then
        message error "Unable to apply Falcon 4.0 registry key: Wine prefix is not ready."
        return 1
    fi

    local falcon4_reg_file="$tmp_dir/falcon_4.reg"
    cat > "$falcon4_reg_file" << 'EOF'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\Software\MicroProse]

[HKEY_LOCAL_MACHINE\Software\MicroProse\Falcon]

[HKEY_LOCAL_MACHINE\Software\MicroProse\Falcon\4.0]
"baseDir"="C:\\Falcon 4.0"
"misctexDir"="C:\\Falcon 4.0\\terrdata\\misctex"
"movieDir"="C:\\Falcon 4.0"
"objectDir"="C:\\Falcon 4.0\\terrdata\\objects"
"theaterDir"="C:\\Falcon 4.0\\terrdata\\korea"

[HKEY_LOCAL_MACHINE\Software\MicroProse\Falcon\4.0\MPR]
"MPRDetect3Dx"=dword:00000001
"MPRDetectCPU"=dword:00000001
"MPRDetectMMX"=dword:00000001
"MPRDetectXMM"=dword:00000001

[HKEY_LOCAL_MACHINE\Software\Wow6432Node\MicroProse]

[HKEY_LOCAL_MACHINE\Software\Wow6432Node\MicroProse\Falcon]

[HKEY_LOCAL_MACHINE\Software\Wow6432Node\MicroProse\Falcon\4.0]
"baseDir"="C:\\Falcon 4.0"
"misctexDir"="C:\\Falcon 4.0\\terrdata\\misctex"
"movieDir"="C:\\Falcon 4.0"
"objectDir"="C:\\Falcon 4.0\\terrdata\\objects"
"theaterDir"="C:\\Falcon 4.0\\terrdata\\korea"

[HKEY_LOCAL_MACHINE\Software\Wow6432Node\MicroProse\Falcon\4.0\MPR]
"MPRDetect3Dx"=dword:00000001
"MPRDetectCPU"=dword:00000001
"MPRDetectMMX"=dword:00000001
"MPRDetectXMM"=dword:00000001
EOF

    prefix_reg_import "$falcon4_reg_file"
    local reg_exit_code="$?"

    if [ "$reg_exit_code" -eq 0 ]; then
        reg_get "$bms_pfx/system.reg" 'Software\MicroProse\Falcon\4.0' baseDir >/dev/null
        reg_exit_code="$?"
    fi

    if [ "$reg_exit_code" -ne 0 ]; then
        message error "Failed to apply Falcon 4.0 registry keys."
        return 1
    fi

    return 0
}

# MARK: download_gog_installer()
# Ask for the GOG Falcon 4.0 installer (or use --installer)
download_gog_installer() {

    # If installer_path was provided and looks like the GOG launcher, accept it
    if [ -n "$installer_path" ]; then
        bn="$(basename "$installer_path")"
        if echo "$bn" | grep -qi "setup_falcon_4_2.0.0.1"; then
            selected_gog_installer="$installer_path"
            # avoid extra popup on success
            debug_print continue "GOG installer selected: $selected_gog_installer"
            return 0
        fi
        # if user provided a path but it's not valid, clean up and fail
        if [ -n "$installer_path" ] && [ ! -f "$installer_path" ]; then
            message error "Specified GOG installer not found: $installer_path"
            cleanup_conf_if_only_firstrun
            return 1
        fi
    fi

    # Retry loop: prompt up to 3 times before failing
    attempts=0
    # Show an informational popup once before the first prompt
    if [ -x "$(command -v zenity)" ]; then
        zenity --info --no-wrap --text="Please locate the GOG Falcon 4.0 installer (setup_falcon_4_2.0.0.1.exe)\nor another Falcon 4.0 installer, such as the original CD's Setup.exe" --title="Falcon BMS Helper" 2>/dev/null
    else
        printf "Please locate the GOG Falcon 4.0 installer (setup_falcon_4_2.0.0.1.exe)\nor another Falcon 4.0 installer, such as the original CD's Setup.exe\n"
    fi
    while [ "$attempts" -lt 3 ]; do
        attempts=$((attempts + 1))
        if [ -x "$(command -v zenity)" ]; then
            gog_choice="$(zenity --file-selection --title="Select the GOG Falcon 4.0 installer" --filename="$HOME/Downloads/" 2>/dev/null)"
            if [ -z "$gog_choice" ]; then
                message warning "No file selected. Attempt $attempts of 3 failed."
                continue
            fi
        else
            printf "Attempt %d of 3 - Enter the full path to the GOG installer:\n" "$attempts"
            read -rp ": " gog_choice
            if [ -z "$gog_choice" ]; then
                message warning "No file specified. Attempt $attempts of 3 failed."
                continue
            fi
        fi

        if [ ! -f "$gog_choice" ]; then
            message warning "File not found: $gog_choice (Attempt $attempts of 3)"
            continue
        fi

        bn="$(basename "$gog_choice")"
        falcon4_interactive=0
        if ! echo "$bn" | grep -qi "setup_falcon_4_2.0.0.1"; then
            # Other Falcon 4.0 installers (ie. the original CD's Setup.exe)
            # work too, but don't support GOG's unattended install
            if ! message question "This is not the GOG Falcon 4.0 installer (setup_falcon_4_2.0.0.1.exe):\n\n$bn\n\nIs it another Falcon 4.0 installer, such as the original CD's Setup.exe?\nIts setup windows will open during the installation; keep the default install location."; then
                continue
            fi
            falcon4_interactive=1
        fi

        selected_gog_installer="$gog_choice"
        # avoid extra popup on success
        debug_print continue "GOG installer selected: $selected_gog_installer"
        return 0
    done

    message error "Failed to select a valid GOG installer after 3 attempts. Aborting installation."
    cleanup_conf_if_only_firstrun
    return 1
}

# MARK: download_bms_installer()
# Ask for the Falcon BMS installer (or use --installer) and its options
download_bms_installer() {

    # If a specific installer path was provided, prefer it
    if [ -n "$installer_path" ]; then
        if [ -f "$installer_path" ]; then
            # try to detect type from the provided installer
            detect_installer_from_path "$installer_path"
            message info "Falcon BMS Installer found at: $installer_path"
            # remember the selected installer for downstream use
            selected_bms_installer="$installer_path"
            # Offer high-res tiles (/16k) option
            if message question "Would you like to install the High Resolution Tiles for Falcon BMS? (Internet required)"; then
                use_16k_tiles=1
            else
                use_16k_tiles=0
            fi
            # If we're in internal mode, prompt for an internal installation key
            bms_key=""
            if [ "$bms_mode" = "internal" ]; then
                if [ "$use_zenity" -eq 1 ]; then
                    bms_key="$(zenity --entry --title="Falcon BMS Internal Key" --text="Enter internal installation key (leave blank to skip):" --entry-text="" 2>/dev/null)"
                    # treat cancel as empty
                    if [ $? -ne 0 ]; then
                        bms_key=""
                    fi
                else
                    printf "Enter internal installation key (optional): "
                    read -r bms_key
                fi
                # Trim whitespace
                bms_key="$(echo "$bms_key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                if [ -z "$bms_key" ]; then
                    message error "Internal installer key is required for internal Falcon BMS installs."
                    cleanup_conf_if_only_firstrun
                    return 1
                fi
            fi
            return 0
        else
            message error "Specified installer not found: $installer_path"
            cleanup_conf_if_only_firstrun
            return 1
        fi
    fi
    # Public releases can be downloaded straight from the Falcon BMS servers
    if [ "$bms_mode" = "public" ] && bms_latest_release &&
       message question "Download the latest Falcon BMS installer ($latest_version) automatically?\n\nThis is a large download (over 15 GB) from the Falcon BMS servers; it resumes if interrupted and is checked against the checksum published on falcon-bms.com.\n\nSelect No to use an installer you already downloaded."; then
        if ! download_latest_bms_installer "$(dirname "${new_root:-$bms_default_install_path}")/falcon-bms-installers"; then
            cleanup_conf_if_only_firstrun
            return 1
        fi
        bms_choice="$selected_bms_installer"
        bn="$(basename "$bms_choice")"
    # Prompt the user to select the Falcon BMS installer file
    # show an informational popup once before the first prompt
    elif [ -x "$(command -v zenity)" ]; then
        zenity --info --no-wrap --text="Please locate the Falcon BMS installer" --title="Falcon BMS Helper" 2>/dev/null
        bms_choice="$(zenity --file-selection --title="Select the Falcon BMS installer" --filename="$HOME/Downloads/" 2>/dev/null)"
        if [ -z "$bms_choice" ]; then
            message error "No Falcon BMS installer selected. Aborting."
            cleanup_conf_if_only_firstrun
            return 1
        fi
        bn="$(basename "$bms_choice")"
    else
        printf "Please locate the Falcon BMS installer"
        read -rp ": " bms_choice
        if [ -z "$bms_choice" ]; then
            message error "No Falcon BMS installer specified. Aborting."
            cleanup_conf_if_only_firstrun
            return 1
        fi
        if [ ! -f "$bms_choice" ]; then
            message error "File not found: $bms_choice"
            cleanup_conf_if_only_firstrun
            return 1
        fi
        bn="$(basename "$bms_choice")"
    fi

    # Validate filename for public or internal patterns
    # Public: Falcon BMS_4.<YY>.<X>_Full_Setup(.exe)
    # Internal: Falcon BMS_4.<YY>.<X>_Internal_Full_Setup(.exe)
    if echo "$bn" | grep -Eq "^Falcon BMS_4\.[0-9]+\.[0-9]+_Internal_Full_Setup(\.exe)?$"; then
        detected_type="internal"
    elif echo "$bn" | grep -Eq "^Falcon BMS_4\.[0-9]+\.[0-9]+_Full_Setup(\.exe)?$"; then
        detected_type="public"
    else
        message error "Selected file does not match expected Falcon BMS installer patterns: $bn"
        return 1
    fi

    # If user requested internal mode but selected a public installer (or vice versa), warn
    if [ "$bms_mode" = "internal" ] && [ "$detected_type" != "internal" ]; then
        if ! message question "You requested internal mode but selected a public installer ($bn). Continue?"; then
            cleanup_conf_if_only_firstrun
            return 1
        fi
    elif [ "$bms_mode" = "public" ] && [ "$detected_type" = "internal" ]; then
        if ! message question "You selected an internal installer ($bn) but are in public mode. Restart the Helper in internal mode now?"; then
            cleanup_conf_if_only_firstrun
            return 1
        else
            # Relaunch the helper in internal mode, preserving the selected installer
            exec "${SCRIPT_DIR:-.}/$(basename "$0")" --internal --installer "$bms_choice"
            # If exec fails for some reason, fall back to switching mode in-process
            set_bms_mode internal
        fi
    fi

    # Save the selection for downstream use (local variable only)
    selected_bms_installer="$bms_choice"
    # Offer the high resolution tiles (downloaded by the Helper after the install)
    if message question "Would you like to install the High Resolution (16K) terrain tiles? (about 27 GB download)\n\nNot recommended with 12 GB of video memory or less. You can add or remove them later from the main menu."; then
        use_16k_tiles=1
    else
        use_16k_tiles=0
    fi
    # If we're in internal mode, prompt for an internal installation key
    bms_key=""
    if [ "$bms_mode" = "internal" ]; then
        if [ "$use_zenity" -eq 1 ]; then
            bms_key="$(zenity --entry --hide-text --title="Falcon BMS Internal Key" --text="Enter internal installation key:" 2>/dev/null)"
            if [ $? -ne 0 ]; then
                bms_key=""
            fi
        else
            read -rsp "Enter internal installation key: " bms_key
            printf '\n'
        fi
        bms_key="$(echo "$bms_key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [ -z "$bms_key" ]; then
            message error "Internal installer key is required for internal Falcon BMS installs."
            cleanup_conf_if_only_firstrun
            return 1
        fi
    fi
    # Don't show a popup on successful selection to reduce interruptions.
    # Never print the key.
    debug_print continue "Falcon BMS installer selected: $selected_bms_installer (16K tiles: $use_16k_tiles)"
    return 0
}
