# shellcheck shell=bash
# bms-helper: maintenance and troubleshooting.
# Sourced by bms-helper.sh; defines functions only.

# MARK: maintenance_menu()
# Show maintenance/troubleshooting options
maintenance_menu() {
    looping_menu="true"
    while [ "$looping_menu" = "true" ]; do
        if [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
            maint_root="$(cat "$conf_dir/$conf_subdir/$wine_conf")"
        else
            maint_root="Not configured"
        fi

        menu_text_zenity="<b><big>Game Maintenance and Troubleshooting</big>\n\nBMS Wiki: $bms_wiki\n\nInstall:</b> $maint_root"
        menu_text_terminal="Game Maintenance and Troubleshooting\n\nBMS Wiki: $bms_wiki\n\nInstall: $maint_root"
        menu_text_height="320"
        menu_type="radiolist"

        prefix_msg="Target a different Falcon BMS installation"
        launcher_msg="Update/Repair launch script"
        checkinstall_msg="Installation checks"
        reinstall_msg="Reinstall Falcon BMS (keeps your settings and logbooks)"
        launchconf_msg="Edit launch settings"
        config_msg="Open Wine prefix configuration"
        winetricks_msg="Open Winetricks"
        logs_msg="Show logs"
        dirs_msg="Display Helper and Falcon BMS directories"
        reset_msg="Reset Helper configs"
        quit_msg="Return to the main menu"

        menu_options=("$prefix_msg" "$launcher_msg" "$checkinstall_msg" "$reinstall_msg" "$launchconf_msg" "$config_msg" "$winetricks_msg" "$logs_msg" "$dirs_msg" "$reset_msg" "$quit_msg")
        menu_actions=("switch_prefix" "update_launch_script" "run_installation_checks" "reinstall_bms" "edit_launch_script" "call_launch_script config" "launch_winetricks" "show_logs" "display_dirs" "reset_helper" "menu_loop_done")

        menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"
        cancel_label="Go Back"
        menu
    done
}

# MARK: update_launch_script()
# Reinstall the launcher, its settings file and desktop files, refresh umu
# and the prefix settings, and make sure a usable runner is configured
update_launch_script() {
    getdirs
    if [ "$?" -eq 1 ]; then
        message warning "Unable to update launch script."
        return 0
    fi
    get_current_runner

    repair_notes=""
    if ! runner_supported "$proton_path"; then
        if [ -n "$proton_path" ]; then
            repair_notes+="\n\nThe configured Proton runner could not be used and was replaced:\n$proton_path"
        fi
        if ! choose_default_runner; then
            message error "No usable Proton runner could be found or downloaded.\n\nUse 'Manage Proton Runners' to install one."
            return 1
        fi
        conf_set "$bms_conf" PROTONPATH "$proton_path"
    fi

    if [ -f "$bms_root/$bms_launcher_name" ] && ! grep -q '^# version: '"$bms_launcher_version"'$' "$bms_root/$bms_launcher_name"; then
        cp "$bms_root/$bms_launcher_name" "$bms_root/$(basename "$bms_launcher_name" .sh).bak"
    fi
    if ! install_launch_script; then
        message error "Unable to install the launch script.\n\n$bms_root/$bms_launcher_name"
        return 1
    fi
    create_desktop_files

    # Repairs are also the time to update umu and the Steam Runtime, which
    # the launcher doesn't check on every start
    progress_bar start "Updating umu-launcher and applying prefix settings..."
    update_local_umu
    ensure_umu
    apply_prefix_settings || repair_notes+="\n\nApplying the prefix settings failed; see the terminal output."
    progress_bar stop

    message info "Your game launch script has been updated/repaired.\n\nLauncher: $bms_root/$bms_launcher_name\nSettings: $bms_conf\nProton: $(basename "$proton_path")$repair_notes"
}

# MARK: run_installation_checks()
# Re-apply the prefix settings, install missing launcher fonts/runtime bits
# and report .NET 4.8 status for the targeted install
run_installation_checks() {
    getdirs
    if [ "$?" -eq 1 ]; then
        message warning "Unable to run installation checks."
        return 1
    fi
    get_current_runner
    if ! runner_supported "$proton_path"; then
        message error "No usable Proton runner is configured for this install.\n\nRun 'Update/Repair launch script' first."
        return 1
    fi
    ensure_umu

    progress_bar start "Running installation checks. Please wait..."
    checks_result=0

    if apply_prefix_settings; then
        settings_line="Prefix settings (WPF fixes, BMS registry, VR): applied"
    else
        settings_line="Prefix settings: FAILED (see terminal output)"
        checks_result=1
    fi

    # Only install what is missing; winetricks logs every verb it installed
    missing_verbs=()
    for verb in corefonts tahoma gdiplus; do
        grep -qx "$verb" "$bms_pfx/winetricks.log" 2>/dev/null || missing_verbs+=("$verb")
    done
    if [ "${#missing_verbs[@]}" -eq 0 ]; then
        fonts_line="Launcher fonts/runtime (corefonts, tahoma, gdiplus): installed"
    elif prefix_winetricks "${missing_verbs[@]}"; then
        fonts_line="Launcher fonts/runtime: installed ${missing_verbs[*]}"
    else
        fonts_line="Launcher fonts/runtime: FAILED to install ${missing_verbs[*]}"
        checks_result=1
    fi
    progress_bar stop

    if check_dotnet48; then
        dotnet_line=".NET Framework 4.8: detected"
    elif message question ".NET Framework 4.8 is not installed in this prefix.\n\nWithout it the Alternative Launcher runs on wine-mono, which is slow and known to crash.\n\nInstall it now? (this takes several minutes)"; then
        progress_bar start "Installing .NET Framework 4.8. Please wait..."
        prefix_winetricks dotnet48
        progress_bar stop
        if check_dotnet48; then
            dotnet_line=".NET Framework 4.8: installed"
        else
            dotnet_line=".NET Framework 4.8: installation FAILED (see terminal output)"
            checks_result=1
        fi
    else
        dotnet_line=".NET Framework 4.8: NOT installed"
        checks_result=1
    fi

    # Proton installs DXVK into the prefix; without it Direct3D 11 runs on
    # wined3d at a fraction of the frame rate
    if [ "$(conf_get "$bms_conf" PROTON_USE_WINED3D)" = "1" ] || grep -Eq '^[[:space:]]*export[[:space:]]+PROTON_USE_WINED3D=1' "$bms_conf" 2>/dev/null; then
        dxvk_line="DXVK: DISABLED by PROTON_USE_WINED3D=1 in $bms_conf"
        checks_result=1
    elif grep -qa 'dxvk' "$bms_pfx/drive_c/windows/system32/d3d11.dll" 2>/dev/null; then
        dxvk_line="DXVK (Direct3D 11 to Vulkan): active"
    else
        dxvk_line="DXVK: NOT found in the prefix (run 'Update/Repair launch script')"
        checks_result=1
    fi

    if reg_get "$bms_pfx/system.reg" "Software\Benchmark Sims\$bms_base_dir" baseDir >/dev/null; then
        registry_line="Falcon BMS registry keys: present"
    else
        registry_line="Falcon BMS registry keys: MISSING (Falcon BMS will not start; reinstall it)"
        checks_result=1
    fi

    case "$(findmnt -no FSTYPE -T "$bms_root" 2>/dev/null)" in
        ntfs|ntfs3|fuseblk|exfat|vfat|msdos)
            fs_line="Install drive: $(findmnt -no FSTYPE -T "$bms_root") (slow: the Alternative Launcher can take 30 s or more to start; ext4, btrfs or xfs are recommended)"
            checks_result=1
            ;;
        *) fs_line="" ;;
    esac

    # Rewrite the menu/desktop shortcuts and icon, in case they are stale or missing
    if create_desktop_files >/dev/null 2>&1 && [ -f "${data_dir}/applications/$bms_desktop_basename" ]; then
        desktop_line="Desktop shortcuts and icon: refreshed"
    else
        desktop_line="Desktop shortcuts and icon: FAILED (see terminal output)"
        checks_result=1
    fi

    if [ -f "$bms_root/xr-wivrn-runtime.json" ]; then
        vr_line="OpenXR runtime (WiVRn): configured"
    else
        vr_line="OpenXR runtime: WiVRn not found (VR is optional)"
    fi

    summary="Installation checks finished for:\n$bms_root\n\n- $settings_line\n- $registry_line\n- $dxvk_line\n- $fonts_line\n- $dotnet_line\n- $desktop_line\n- $vr_line${fs_line:+\n- $fs_line}"
    if [ "$checks_result" -eq 0 ]; then
        message info "$summary"
    else
        message warning "$summary"
    fi
}

# MARK: edit_launch_script()
# Open the launch settings file (bms-launch.conf) in the user's editor
edit_launch_script() {
    getdirs
    if [ "$?" -eq 1 ]; then
        return 0
    fi

    if [ ! -f "$bms_conf" ]; then
        message error "Unable to find $bms_conf\n\nRun 'Update/Repair launch script' first."
        return 1
    fi

    if ! { [ -x "$(command -v xdg-open)" ] && xdg-open "$bms_conf" 2>/dev/null; }; then
        message info "Open the launch settings in a text editor:\n\n$bms_conf"
    fi
}

# MARK: call_launch_script()
# Call the launch script with the given argument (config, controllers, ...),
# refreshing it first if it is older than this helper's launcher
call_launch_script() {
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The call_launch_script function expects an argument. Aborting."
    fi

    getdirs
    if [ "$?" -eq 1 ]; then
        return 1
    fi

    if ! grep -q '^# version: '"$bms_launcher_version"'$' "$bms_root/$bms_launcher_name" 2>/dev/null; then
        get_current_runner
        install_launch_script || {
            message error "Unable to install $bms_root/$bms_launcher_name"
            return 1
        }
    fi

    "$bms_root/$bms_launcher_name" "$1"
}

# MARK: launch_winetricks()
# Open the winetricks GUI for the targeted prefix, using the winetricks and
# Wine bundled in the configured Proton runner
launch_winetricks() {
    getdirs
    if [ "$?" -eq 1 ]; then
        message warning "Unable to open Winetricks."
        return 1
    fi
    get_current_runner
    if ! runner_supported "$proton_path"; then
        message warning "No usable Proton runner is configured for this install.\n\nSet one first from 'Manage Proton Runners'."
        return 1
    fi
    if [ "$use_zenity" -eq 0 ]; then
        message info "Winetricks needs a graphical session (zenity) for its GUI.\n\nFrom a terminal you can run verbs with:\n$bms_root/$bms_launcher_name shell\nthen: bash \"$proton_path/protonfixes/winetricks\" <verb>"
        return 0
    fi

    debug_print continue "Launching Winetricks for prefix: $bms_pfx"
    PATH="$proton_path/files/bin:$PATH" WINEPREFIX="$bms_pfx" \
        WINE="$proton_path/files/bin/wine" WINESERVER="$proton_path/files/bin/wineserver" \
        WINEDLLOVERRIDES="winemenubuilder.exe=d" bash "$proton_path/protonfixes/winetricks" --gui
}

# MARK: show_logs()
# Show where the launch, install and head tracking logs are
show_logs() {
    getdirs
    if [ "$?" -eq 1 ]; then
        return 1
    fi

    latest_log="$(ls -1t "$bms_root/bms-launch-logs"/*.log 2>/dev/null | head -n1)"
    logs_list=""
    for log_entry in "Latest launch log|$latest_log" "Launch logs folder|$bms_root/bms-launch-logs" \
        "Install log|$bms_root/bms-install.log" "OpenTrack bridge log|$bms_root/opentrack/bridge.log" \
        "Falcon BMS logs|$game_path/User/Logs"; do
        log_label="${log_entry%%|*}"
        log_path="${log_entry#*|}"
        [ -n "$log_path" ] && [ -e "$log_path" ] || continue
        if [ "$use_zenity" -eq 1 ]; then
            logs_list+="$log_label:\n<a href='file://$log_path'>$log_path</a>\n\n"
        else
            logs_list+="$log_label:\n$log_path\n\n"
        fi
    done

    if [ -z "$logs_list" ]; then
        message info "No logs were found yet. Launch Falcon BMS once to create a launch log."
        return 0
    fi
    message info "Falcon BMS and Helper logs\n\nFor troubleshooting help, see: $bms_wiki\n\n$logs_list"
}

# MARK: display_dirs()
# Display all directories currently used by this helper and Falcon BMS
display_dirs() {
    dirs_list="\n"
    saved_root=""
    [ -f "$conf_dir/$conf_subdir/$wine_conf" ] && saved_root="$(cat "$conf_dir/$conf_subdir/$wine_conf")"

    for dir_entry in "Helper configuration|$conf_dir/$conf_subdir" \
        "Falcon BMS install|$saved_root" \
        "Wine prefix|${saved_root:+$saved_root/pfx}" \
        "Falcon BMS game directory|${saved_root:+$saved_root/pfx/drive_c/$bms_base_dir}" \
        "Launch settings|${saved_root:+$saved_root/bms-launch.conf}" \
        "Proton runners|${saved_root:+$saved_root/runners}" \
        "Helper's umu-launcher|$umu_local_dir" \
        "Joystick rules|$joystick_rules_file"; do
        dir_label="${dir_entry%%|*}"
        dir_path="${dir_entry#*|}"
        [ -n "$dir_path" ] && [ -e "$dir_path" ] || continue
        if [ "$use_zenity" -eq 1 ]; then
            dirs_list+="$dir_label:\n<a href='file://$dir_path'>$dir_path</a>\n\n"
        else
            dirs_list+="$dir_label:\n$dir_path\n\n"
        fi
    done

    message_heading="These directories are currently being used by this Helper and Falcon BMS"
    if [ "$use_zenity" -eq 1 ]; then
        message_heading="<b>$message_heading</b>"
    fi
    message info "$message_heading\n$dirs_list"
}

# MARK: display_wiki()
# Display the BMS Wiki
display_wiki() {
    message info "See the Wiki for our Quick-Start Guide, Troubleshooting,\nand Performance Tuning Recommendations:\n\n$bms_wiki"
}

# MARK: display_about()
# Show the helper version and support links
display_about() {
    message info "Falcon BMS Linux Helper $current_version\n\nWiki: $bms_wiki\nHelper releases and issues: $releases_url"
}
