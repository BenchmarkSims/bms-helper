# shellcheck shell=bash
# bms-helper: game controllers and head tracking.
# Sourced by bms-helper.sh; defines functions only.

joystick_rules_file="/etc/udev/rules.d/40-falcon-bms-joystick-uaccess.rules"

# USB vendor ids of flight sim hardware that Wine/Proton reads through
# hidraw, which gives full button/axis counts but needs the device node to be
# accessible by the logged-in user
joystick_vendors=(
    "231d" "VKB"
    "3344" "Virpil"
    "044f" "Thrustmaster"
    "4098" "WinWing"
)

# MARK: controllers_menu()
# Show controller and head tracking options
controllers_menu() {
    looping_menu="true"
    while [ "$looping_menu" = "true" ]; do
        menu_text_zenity="<b><big>Controllers and Head Tracking</big></b>"
        menu_text_terminal="Controllers and Head Tracking"
        menu_text_height="300"
        menu_type="radiolist"

        if [ -f "$joystick_rules_file" ]; then
            udev_msg="Remove joystick access rules (hidraw)"
            udev_action="remove_joystick_rules"
        else
            udev_msg="Install joystick access rules (hidraw, for VKB/Virpil/Thrustmaster/WinWing)"
            udev_action="install_joystick_rules"
        fi
        restore_msg="Restore controller bindings from a backup"
        mfd_msg="Thrustmaster MFD helper (enable/disable)"
        joy_msg="Open Wine game controllers panel"
        opentrack_msg="Set up OpenTrack head tracking (native Linux)"
        quit_msg="Return to the main menu"

        menu_options=("$restore_msg" "$udev_msg" "$mfd_msg" "$joy_msg" "$opentrack_msg" "$quit_msg")
        menu_actions=("restore_controller_config_menu" "$udev_action" "toggle_mfd_helper" "call_launch_script controllers" "setup_opentrack_native" "menu_loop_done")

        menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"
        cancel_label="Go Back"
        menu
    done
}

# MARK: install_joystick_rules()
# Install udev rules giving the logged-in user access to the hidraw nodes of
# common flight sim devices, then reload udev
install_joystick_rules() {
    rules_tmp="$tmp_dir/joystick-uaccess.rules"
    vendor_list=""
    echo "# Added by bms-helper: let Wine/Proton read flight sim devices through hidraw" > "$rules_tmp"
    for (( i=0; i<"${#joystick_vendors[@]}"; i=i+2 )); do
        printf 'SUBSYSTEM=="hidraw", ATTRS{idVendor}=="%s", MODE="0660", TAG+="uaccess"\n' "${joystick_vendors[i]}" >> "$rules_tmp"
        vendor_list+="\n- ${joystick_vendors[i+1]}"
    done

    if ! message question "This adds a udev rule so Falcon BMS can read these devices directly (hidraw), with all of their buttons and axes:\n$vendor_list\n\nRule file: $joystick_rules_file\n\nAdministrator rights are required. Continue?"; then
        return 0
    fi

    if ! try_exec root "install -m 644 '$rules_tmp' '$joystick_rules_file' && udevadm control --reload-rules && udevadm trigger --subsystem-match=hidraw"; then
        message error "The joystick rules could not be installed. See terminal output for details."
        return 1
    fi
    message info "Joystick access rules installed.\n\nReconnect your devices (or reboot) if Falcon BMS does not see them right away."
}

# MARK: remove_joystick_rules()
# Remove the udev rules added by install_joystick_rules()
remove_joystick_rules() {
    if ! message question "Remove the joystick access rules?\n\n$joystick_rules_file\n\nAdministrator rights are required."; then
        return 0
    fi
    if ! try_exec root "rm -f '$joystick_rules_file' && udevadm control --reload-rules && udevadm trigger --subsystem-match=hidraw"; then
        message error "The joystick rules could not be removed. See terminal output for details."
        return 1
    fi
    message info "Joystick access rules removed."
}

# MARK: toggle_mfd_helper()
# Enable or disable the Thrustmaster MFD helper (tools/mfd-joystick.py),
# which remaps the MFD Cougar panels to joystick-style virtual devices
toggle_mfd_helper() {
    getdirs || return 1
    get_current_runner

    if [ "$(conf_get "$bms_conf" BMS_MFD_HELPER)" = "1" ]; then
        if ! message question "The Thrustmaster MFD helper is enabled.\n\nDisable it?"; then
            return 0
        fi
        conf_set "$bms_conf" BMS_MFD_HELPER 0
        mfd_state="disabled"
    else
        if [ ! -f "$SCRIPT_DIR/tools/mfd-joystick.py" ]; then
            message error "The MFD helper script is missing from the Helper:\n\n$SCRIPT_DIR/tools/mfd-joystick.py"
            return 1
        fi
        if ! message question "The Thrustmaster MFD helper presents your Thrustmaster F16 MFDs to Falcon BMS as joystick-style virtual devices, and hides the physical ones.\n\nIt starts and stops with Falcon BMS. Enable it?"; then
            return 0
        fi
        cp -f "$SCRIPT_DIR/tools/mfd-joystick.py" "$bms_root/mfd-joystick.py"
        conf_set "$bms_conf" BMS_MFD_HELPER 1
        mfd_state="enabled"

        mfd_notes=""
        if ! python3 -c 'import evdev' >/dev/null 2>&1; then
            mfd_notes+="\n- Install python-evdev (python3-evdev) for the helper to work."
        fi
        if [ ! -w /dev/uinput ]; then
            mfd_notes+="\n- /dev/uinput is not writable by your user; the helper needs it to create the virtual devices (add your user to the 'input' group or a udev rule for uinput)."
        fi
    fi

    # Hide (or show again) the physical MFDs in DirectInput
    if runner_supported "$proton_path"; then
        ensure_umu
        progress_bar start "Updating controller settings..."
        apply_prefix_settings
        progress_bar stop
    fi

    message info "The Thrustmaster MFD helper is now $mfd_state.${mfd_notes:+\n\nNote:$mfd_notes}"
}

# MARK: restore_controller_config_menu()
# List the controller setup snapshots bms-launcher.sh takes before launches
restore_controller_config_menu() {
    getdirs || return 1

    unset backup_dirs
    unset menu_options
    unset menu_actions
    while IFS= read -r backup_dir; do
        backup_dirs+=("$backup_dir")
    done < <(ls -1d "$bms_root/config-backups"/*/ 2>/dev/null | sort -r | sed 's:/$::')

    if [ "${#backup_dirs[@]}" -eq 0 ]; then
        message info "No controller backups were found yet.\n\nA backup of your bindings is saved each time you start Falcon BMS (when they changed)."
        return 0
    fi

    for (( i=0; i<"${#backup_dirs[@]}"; i++ )); do
        backup_name="$(basename "${backup_dirs[i]}")"
        # 20261018-123456 -> 2026-10-18 12:34
        menu_options+=("${backup_name:0:4}-${backup_name:4:2}-${backup_name:6:2} ${backup_name:9:2}:${backup_name:11:2}  ($(ls -1 "${backup_dirs[i]}" | wc -l) files)")
        menu_actions+=("restore_controller_config $i")
    done

    menu_text_zenity="Select the controller backup to restore (newest first):"
    menu_text_terminal="Select the controller backup to restore (newest first):"
    menu_text_height="320"
    menu_type="radiolist"
    menu_options+=("Return to the controllers menu")
    menu_actions+=(":")
    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"
    if [ "$menu_height" -gt "$menu_height_max" ]; then
        menu_height="$menu_height_max"
    fi
    cancel_label="Go Back"
    menu
}

# MARK: restore_controller_config()
# Copy a controller snapshot back into User/Config, saving the current
# files first so the restore can be undone
restore_controller_config() {
    restore_src="${backup_dirs[$1]}"
    restore_dest="$game_path/User/Config"

    if bms_running; then
        message warning "Close Falcon BMS before restoring controller bindings."
        return 1
    fi
    if ! message question "Restore the controller bindings, axis setup and keyfiles from:\n\n$(basename "$restore_src")\n\nYour current files are backed up first."; then
        return 0
    fi

    restore_undo="$bms_root/config-backups/$(date '+%Y%m%d-%H%M%S')-before-restore"
    mkdir -p "$restore_undo"
    (
        cd "$restore_dest" || exit 0
        shopt -s nullglob nocaseglob
        files=(Setup.v100.*.xml axismapping.dat joystick.cal DeviceSorting.txt *.key)
        [ "${#files[@]}" -gt 0 ] && cp -p -- "${files[@]}" "$restore_undo/"
    )

    if cp -p -- "$restore_src"/* "$restore_dest/"; then
        message info "Controller bindings restored.\n\nThe previous files were saved as backup:\n$(basename "$restore_undo")"
    else
        message error "Restoring the controller bindings failed. See terminal output for details."
        return 1
    fi
}
