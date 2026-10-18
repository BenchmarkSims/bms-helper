# shellcheck shell=bash
# bms-helper: extra Windows applications in the Falcon BMS prefix.
# Sourced by bms-helper.sh; defines functions only.

# MARK: manage_apps_menu()
# Show options for installing/managing extra Windows applications in the prefix
manage_apps_menu() {
    looping_menu="true"
    while [ "$looping_menu" = "true" ]; do
        menu_text_zenity="<b><big>Manage &amp; Install other Apps</big>\n\nInstall or create shortcuts for extra Windows applications in your Falcon BMS Wine prefix</b>"
        menu_text_terminal="Manage & Install other Apps\n\nInstall or create shortcuts for extra Windows applications in your Falcon BMS Wine prefix"
        menu_text_height="300"
        menu_type="radiolist"

        install_app_msg="Install a new application"
        add_shortcut_msg="Add an application shortcut"
        remove_shortcut_msg="Remove an application shortcut"
        uninstall_app_msg="Uninstall an application from the prefix"
        powershell_msg="Install PowerShell for Windows"
        quit_msg="Return to the main menu"

        menu_options=("$install_app_msg" "$add_shortcut_msg" "$remove_shortcut_msg" "$uninstall_app_msg" "$powershell_msg" "$quit_msg")
        menu_actions=("install_new_application" "add_application_shortcut" "remove_shortcut_menu" "uninstall_application_menu" "install_powershell" "menu_loop_done")

        menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"
        cancel_label="Go Back"
        menu
    done
}

# MARK: install_new_application()
# Let the user pick a Windows installer/executable and run it inside the
# targeted Wine prefix, through the same Proton environment as the game.
install_new_application() {
    getdirs
    if [ "$?" -eq 1 ]; then
        message warning "Unable to install a new application."
        return 1
    fi

    if ! get_current_runner || ! runner_supported "$proton_path"; then
        message error "No usable Proton runner is configured for this install.\n\nSelect one in 'Manage Proton Runners' first."
        return 1
    fi

    # Ask the user to select the installer/executable to run
    new_app_exe=""
    while true; do
        if [ "$use_zenity" -eq 1 ]; then
            new_app_exe="$(zenity --file-selection --title="Select the application installer (.exe) to run" --filename="$HOME/Downloads/" 2>/dev/null)"
        else
            printf "Enter the full path to the application installer (.exe)\n\n"
            read -rp "Installer path: " new_app_exe
        fi

        if [ -z "$new_app_exe" ]; then
            if message question "No installer was selected. Would you like to try again?"; then
                continue
            fi
            return 1
        fi

        if [ -f "$new_app_exe" ]; then
            break
        fi

        if ! message question "The selected path does not exist:\n$new_app_exe\n\nWould you like to choose another file?"; then
            return 1
        fi
    done

    message info "The selected installer will now run inside the Falcon BMS Wine prefix:\n$bms_pfx\n\nIf Falcon BMS is currently running, close it first."

    ensure_umu
    debug_print continue "Launching installer $new_app_exe in prefix ${bms_pfx}..."
    (cd "$(dirname "$new_app_exe")" && prefix_run "$new_app_exe")
    exit_code="$?"

    if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 126 ] || [ "$exit_code" -eq 127 ] || [ "$exit_code" -eq 130 ]; then
        message warning "The application installer exited with code $exit_code. See terminal output for details."
        return 1
    fi

    message info "The application installer has finished running in prefix:\n$bms_pfx"
    return 0
}

# MARK: extract_exe_icon()
# Best-effort extraction of the largest embedded icon from a Windows .exe
# into a PNG at $2, using icoutils (wrestool/icotool). Not a hard dependency:
# nothing is written and the caller should fall back to a generic icon if
# this returns non-zero. Return codes:
#   0 = icon extracted successfully
#   1 = icoutils is present but extraction failed (no icon resource, etc.)
#   2 = icoutils (wrestool/icotool) is not installed
extract_exe_icon() {
    icon_exe_path="$1"
    icon_dest_path="$2"

    if [ -z "$(command -v wrestool 2>/dev/null)" ] || [ -z "$(command -v icotool 2>/dev/null)" ]; then
        return 2
    fi

    icon_extract_dir="$(mktemp -d -p "$tmp_dir" icon-extract.XXXXXX)"
    icon_ico_file="$icon_extract_dir/icon.ico"

    # Type 14 = RT_GROUP_ICON: the icon group resource(s) embedded in the PE file
    wrestool -x -t 14 "$icon_exe_path" > "$icon_ico_file" 2>/dev/null
    if [ ! -s "$icon_ico_file" ]; then
        return 1
    fi

    if ! icotool -x "$icon_ico_file" -o "$icon_extract_dir" 2>/dev/null; then
        return 1
    fi

    # icotool names extracted frames "..._<width>x<height>x<depth>.png" -- pick
    # the largest by parsed width, falling back to largest file size if the
    # naming convention doesn't match.
    icon_best_png=""
    icon_best_width=0
    for icon_png in "$icon_extract_dir"/*.png; do
        [ -f "$icon_png" ] || continue
        icon_png_width="$(echo "$icon_png" | sed -nE 's/.*_([0-9]+)x[0-9]+x[0-9]+\.png$/\1/p')"
        if [ -n "$icon_png_width" ] && [ "$icon_png_width" -gt "$icon_best_width" ]; then
            icon_best_width="$icon_png_width"
            icon_best_png="$icon_png"
        fi
    done

    if [ -z "$icon_best_png" ]; then
        # Naming convention didn't match; fall back to the largest file by size
        icon_best_png="$(ls -S "$icon_extract_dir"/*.png 2>/dev/null | head -n 1)"
    fi

    if [ -z "$icon_best_png" ] || [ ! -f "$icon_best_png" ]; then
        return 1
    fi

    mkdir -p "$(dirname "$icon_dest_path")"
    cp "$icon_best_png" "$icon_dest_path"
    return 0
}

# MARK: write_app_shortcut_script()
# Write the wrapper an app shortcut runs: the app starts through the Falcon
# BMS launcher, so it gets the same Proton environment as the game.
# Usage: write_app_shortcut_script script_path bms_root exe_path
write_app_shortcut_script() {
    {
        echo "#!/usr/bin/env bash"
        echo "# Application shortcut generated by bms-helper.sh"
        echo "exec \"$2/$bms_launcher_name\" run \"$3\" \"\$@\""
    } > "$1"
    chmod +x "$1"
}

# MARK: app_shortcut_exe()
# Print the executable an app shortcut wrapper runs (current or v1 format)
app_shortcut_exe() {
    sed -n -e 's/^exec "[^"]*" run "\(.*\)" "\$@"$/\1/p' -e 's/^exec "[^"]*" "\(.*\)" "\$@"$/\1/p' "$1" | head -n1
}

# MARK: add_application_shortcut()
# Create a desktop shortcut that launches an already-installed Windows
# application in the Falcon BMS prefix.
add_application_shortcut() {
    getdirs
    if [ "$?" -eq 1 ]; then
        message warning "Unable to add an application shortcut."
        return 1
    fi

    if ! get_current_runner || ! runner_supported "$proton_path"; then
        message error "No usable Proton runner is configured for this install.\n\nSelect one in 'Manage Proton Runners' first."
        return 1
    fi

    # Ask the user to select the installed application's executable
    shortcut_exe=""
    while true; do
        if [ "$use_zenity" -eq 1 ]; then
            shortcut_exe="$(zenity --file-selection --title="Select the application executable for the shortcut" --filename="$bms_pfx/drive_c/" 2>/dev/null)"
        else
            printf "Enter the full path to the application's executable inside the prefix\n\n"
            read -rp "Executable path: " shortcut_exe
        fi

        if [ -z "$shortcut_exe" ]; then
            if message question "No executable was selected. Would you like to try again?"; then
                continue
            fi
            return 1
        fi

        if [ -f "$shortcut_exe" ]; then
            break
        fi

        if ! message question "The selected path does not exist:\n$shortcut_exe\n\nWould you like to choose another file?"; then
            return 1
        fi
    done

    # Default the shortcut's display name from the executable, tagging it
    # with "(Internal)" in internal mode so it doesn't collide with (or get
    # mistaken for) the same app's shortcut from a public-mode install.
    default_shortcut_name="$(basename "$shortcut_exe")"
    default_shortcut_name="${default_shortcut_name%.[eE][xX][eE]}"
    if [ "$bms_mode" = "internal" ]; then
        case "$default_shortcut_name" in
            *" (Internal)") : ;;
            *) default_shortcut_name="$default_shortcut_name (Internal)" ;;
        esac
    fi

    # Ask for (or default) the shortcut's display name, retrying if the
    # resulting shortcut name would overwrite an existing one
    while true; do
        shortcut_name="$default_shortcut_name"
        if [ "$use_zenity" -eq 1 ]; then
            entered_name="$(zenity --entry --title="Falcon BMS Linux Helper" --text="Enter a name for this application shortcut:" --entry-text="$shortcut_name" 2>/dev/null)"
            if [ -n "$entered_name" ]; then
                shortcut_name="$entered_name"
            fi
        fi

        if [ "$bms_mode" = "internal" ]; then
            case "$shortcut_name" in
                *" (Internal)") : ;;
                *) shortcut_name="$shortcut_name (Internal)" ;;
            esac
        fi

        # Sanitize the name for use as a filename
        safe_shortcut_name="$(echo "$shortcut_name" | tr -cd '[:alnum:] _.-')"
        if [ -z "$safe_shortcut_name" ]; then
            safe_shortcut_name="Application"
        fi

        shortcuts_dir="$bms_root/shortcuts"
        shortcut_script="$shortcuts_dir/$safe_shortcut_name.sh"
        localshare_shortcut_desktop="${data_dir}/applications/$safe_shortcut_name.desktop"
        home_shortcut_desktop="${XDG_DESKTOP_DIR:-$HOME/Desktop}/$safe_shortcut_name.desktop"

        if [ -e "$shortcut_script" ] || [ -e "$localshare_shortcut_desktop" ] || [ -e "$home_shortcut_desktop" ]; then
            if message question "A shortcut named \"$shortcut_name\" already exists.\n\nOverwrite it?"; then
                break
            fi
            if [ "$use_zenity" -eq 0 ]; then
                message error "A shortcut named \"$shortcut_name\" already exists and zenity is unavailable to rename it.\n\nAborting."
                return 1
            fi
            continue
        fi
        break
    done

    # Generate a small wrapper script that carries the correct Wine environment
    mkdir -p "$shortcuts_dir"
    shortcut_exe_dir="$(dirname "$shortcut_exe")"

    # Try to reuse the executable's own embedded icon (saved alongside the
    # wrapper script, named after the shortcut); fall back to a generic Wine
    # icon if icoutils isn't installed or nothing could be extracted.
    shortcut_icon_value="wine"
    extract_exe_icon "$shortcut_exe" "$shortcuts_dir/$safe_shortcut_name.png"
    shortcut_icon_extract_status="$?"
    if [ "$shortcut_icon_extract_status" -eq 0 ]; then
        shortcut_icon_value="$shortcuts_dir/$safe_shortcut_name.png"
    elif [ "$shortcut_icon_extract_status" -eq 2 ]; then
        message warning "icoutils (wrestool/icotool) was not found on this system.\n\nThe shortcut icon could not be extracted from the executable, so a generic icon will be used instead.\n\nInstall the 'icoutils' package to enable icon extraction."
    fi

    write_app_shortcut_script "$shortcut_script" "$bms_root" "$shortcut_exe"

    # Write the .desktop file to the user's Desktop and the applications menu
    echo "[Desktop Entry]
Name=$shortcut_name
Type=Application
Comment=$shortcut_name
Terminal=false
StartupNotify=true
Categories=Application;
Exec=\"$shortcut_script\"
Path=$shortcut_exe_dir
Icon=$shortcut_icon_value" > "$home_shortcut_desktop.tmp"

    if [ -d "$(dirname "$home_shortcut_desktop")" ]; then
        cp "$home_shortcut_desktop.tmp" "$home_shortcut_desktop"
        chmod +x "$home_shortcut_desktop"
    fi

    mkdir -p "${data_dir}/applications"
    cp "$home_shortcut_desktop.tmp" "$localshare_shortcut_desktop"
    chmod +x "$localshare_shortcut_desktop"
    rm -f "$home_shortcut_desktop.tmp"

    if [ -x "$(command -v update-desktop-database)" ]; then
        update-desktop-database "${data_dir}/applications" 2>/dev/null
    fi

    message info "A desktop shortcut for $shortcut_name has been created:\n$home_shortcut_desktop"
    return 0
}

# MARK: remove_shortcut_menu()
# List the application shortcuts created for the current prefix (via
# add_application_shortcut) and let the user select which ones to remove.
remove_shortcut_menu() {
    getdirs
    if [ "$?" -eq 1 ]; then
        message warning "Unable to list application shortcuts."
        return 1
    fi

    shortcuts_dir="$bms_root/shortcuts"

    unset shortcut_list_names
    unset shortcut_list_scripts
    unset menu_options
    unset menu_actions

    if [ -d "$shortcuts_dir" ]; then
        for item in "$shortcuts_dir"/*.sh; do
            [ -f "$item" ] || continue
            shortcut_list_names+=("$(basename "$item" .sh)")
            shortcut_list_scripts+=("$item")
        done
    fi

    if [ "${#shortcut_list_scripts[@]}" -eq 0 ]; then
        message info "No application shortcuts found in this prefix."
        return 0
    fi

    # Configure the menu
    menu_text_zenity="Select the application shortcut(s) you want to remove:"
    menu_text_terminal="Select the application shortcut(s) you want to remove:"
    menu_text_height="320"
    menu_type="checklist"
    goback="Return to the apps menu"

    # Create menu options for the installed shortcuts
    for (( i=0; i<"${#shortcut_list_names[@]}"; i++ )); do
        menu_options+=("${shortcut_list_names[i]}")
        menu_actions+=("remove_shortcut_delete $i")
    done

    # Complete the menu by adding the option to go back to the previous menu
    menu_options+=("$goback")
    menu_actions+=(":") # no-op

    # Calculate the total height the menu should be
    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"
    # Cap menu height
    if [ "$menu_height" -gt "$menu_height_max" ]; then
        menu_height="$menu_height_max"
    fi

    # Set the label for the cancel button
    cancel_label="Go Back"

    # Call the menu function.  It will use the options as configured above
    menu
}

# MARK: remove_shortcut_delete()
# Remove the wrapper script, icon, and .desktop files for the selected
# shortcut(s). Called by remove_shortcut_menu() with array index arguments.
#
# The following variables are expected to be set before calling this function:
# - shortcuts_dir (string)
# - shortcut_list_names (array)
# - shortcut_list_scripts (array)
remove_shortcut_delete() {
    # This function expects at least one index number for the array shortcut_list_names to be passed in as an argument
    if [ -z "$1" ]; then
        debug_print exit "Script error: The remove_shortcut_delete function expects an argument. Aborting."
    fi

    if [ "${#shortcut_list_names[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'shortcut_list_names' was not set before calling the remove_shortcut_delete function. Aborting."
    fi

    unset removed_shortcut_names
    for shortcut_index in "$@"; do
        delete_application_shortcut "${shortcut_list_scripts[shortcut_index]}"
        removed_shortcut_names+=("${shortcut_list_names[shortcut_index]}")
    done

    if [ -x "$(command -v update-desktop-database)" ]; then
        update-desktop-database "${data_dir}/applications" 2>/dev/null
    fi

    message info "Removed the following application shortcut(s):\n$(printf '%s\n' "${removed_shortcut_names[@]}")"
}

# MARK: delete_application_shortcut()
# Remove a shortcut's wrapper script, icon and .desktop files.
# Takes the path of the wrapper script under $bms_root/shortcuts.
delete_application_shortcut() {
    deleted_shortcut_name="$(basename "$1" .sh)"
    rm -f "$1"
    rm -f "$(dirname "$1")/$deleted_shortcut_name.png"
    rm -f "${data_dir}/applications/$deleted_shortcut_name.desktop"
    rm -f "${XDG_DESKTOP_DIR:-$HOME/Desktop}/$deleted_shortcut_name.desktop"
}

# MARK: uninstall_application_menu()
# List the Windows applications registered in the prefix and run the selected
# one's own uninstaller. Falcon BMS (see 'Uninstall Falcon BMS') and the
# runtimes its launcher depends on are not listed.
uninstall_application_menu() {
    getdirs
    if [ "$?" -eq 1 ]; then
        message warning "Unable to list installed applications."
        return 1
    fi

    if ! get_current_runner || ! runner_supported "$proton_path"; then
        message error "No usable Proton runner is configured for this install.\n\nSelect one in 'Manage Proton Runners' first."
        return 1
    fi

    if bms_running; then
        message warning "Close Falcon BMS before uninstalling applications from its prefix."
        return 1
    fi
    ensure_umu

    unset uninstall_app_ids
    unset uninstall_app_names
    unset menu_options
    unset menu_actions

    # Wine's uninstaller prints one "<id>|||<display name>" line per application
    while IFS= read -r uninstall_line; do
        case "$uninstall_line" in
            *"|||"*) ;;
            *) continue ;;
        esac
        uninstall_app_name="${uninstall_line#*|||}"
        case "$uninstall_app_name" in
            "Falcon BMS"*|"Wine Mono"*|"Wine Gecko"*|"Microsoft .NET"*|"Microsoft Visual C++"*|"Microsoft Windows Desktop Runtime"*)
                continue
                ;;
        esac
        uninstall_app_ids+=("${uninstall_line%%|||*}")
        uninstall_app_names+=("$uninstall_app_name")
    done < <(prefix_run uninstaller --list 2>/dev/null | tr -d '\r')

    if [ "${#uninstall_app_ids[@]}" -eq 0 ]; then
        message info "No uninstallable applications were found in this prefix.\n\n(Falcon BMS, Wine Mono/Gecko, .NET and Visual C++ runtimes are not listed.)"
        return 0
    fi

    # Configure the menu
    menu_text_zenity="Select the application to uninstall from:\n$bms_pfx"
    menu_text_terminal="Select the application to uninstall from:\n$bms_pfx"
    menu_text_height="320"
    menu_type="radiolist"
    goback="Return to the maintenance menu"

    for (( i=0; i<"${#uninstall_app_names[@]}"; i++ )); do
        menu_options+=("${uninstall_app_names[i]}")
        menu_actions+=("uninstall_application_run $i")
    done

    # Complete the menu by adding the option to go back to the previous menu
    menu_options+=("$goback")
    menu_actions+=(":") # no-op

    # Calculate the total height the menu should be
    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"
    # Cap menu height
    if [ "$menu_height" -gt "$menu_height_max" ]; then
        menu_height="$menu_height_max"
    fi

    # Set the label for the cancel button
    cancel_label="Go Back"

    # Call the menu function.  It will use the options as configured above
    menu
}

# MARK: uninstall_application_run()
# Run the uninstaller for the application at the given index of the list
# built by uninstall_application_menu(), then drop helper shortcuts whose
# executable no longer exists.
uninstall_application_run() {
    uninstall_app_id="${uninstall_app_ids[$1]}"
    uninstall_app_name="${uninstall_app_names[$1]}"

    if ! message question "Uninstall \"$uninstall_app_name\" from:\n$bms_pfx ?\n\nThe application's own uninstaller may open; follow its prompts."; then
        return 0
    fi

    debug_print continue "Uninstalling $uninstall_app_name ($uninstall_app_id) from $bms_pfx..."
    # prefix_run waits for the whole prefix to go idle, which also covers
    # uninstallers that re-spawn themselves
    prefix_run uninstaller --remove "$uninstall_app_id"

    unset removed_shortcut_names
    for uninstall_shortcut in "$bms_root/shortcuts"/*.sh; do
        [ -f "$uninstall_shortcut" ] || continue
        uninstall_shortcut_exe="$(app_shortcut_exe "$uninstall_shortcut")"
        if [ -n "$uninstall_shortcut_exe" ] && [ ! -f "$uninstall_shortcut_exe" ]; then
            delete_application_shortcut "$uninstall_shortcut"
            removed_shortcut_names+=("$(basename "$uninstall_shortcut" .sh)")
        fi
    done
    if [ "${#removed_shortcut_names[@]}" -gt 0 ] && [ -x "$(command -v update-desktop-database)" ]; then
        update-desktop-database "${data_dir}/applications" 2>/dev/null
    fi

    if prefix_run uninstaller --list 2>/dev/null | tr -d '\r' | grep -qF "$uninstall_app_id|||"; then
        message warning "\"$uninstall_app_name\" is still registered in the prefix. Its uninstaller may have been cancelled or failed; see terminal output for details."
        return 1
    fi

    uninstall_done_msg="\"$uninstall_app_name\" has been uninstalled."
    if [ "${#removed_shortcut_names[@]}" -gt 0 ]; then
        uninstall_done_msg="$uninstall_done_msg\n\nRemoved its shortcut(s):\n$(printf '%s\n' "${removed_shortcut_names[@]}")"
    fi
    message info "$uninstall_done_msg"
    return 0
}

# MARK: install_powershell()
# Install PowerShell into the game's prefix with the runner's winetricks
install_powershell() {
    getdirs
    if [ "$?" -eq 1 ]; then
        message warning "Unable to install PowerShell."
        return 1
    fi
    if ! get_current_runner || ! runner_supported "$proton_path"; then
        message error "No usable Proton runner is configured for this install.\n\nSelect one in 'Manage Proton Runners' first."
        return 1
    fi
    ensure_umu

    progress_bar start "Installing PowerShell. Please wait..."
    debug_print continue "Installing PowerShell into ${bms_pfx}..."
    prefix_winetricks powershell
    exit_code="$?"
    progress_bar stop

    if [ "$exit_code" -ne 0 ]; then
        message warning "PowerShell could not be installed. See terminal output for details."
        return 1
    fi
    message info "PowerShell has been installed."
}
