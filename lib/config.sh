# shellcheck shell=bash
# bms-helper: helper configuration, install discovery and install layout.
# Sourced by bms-helper.sh; defines functions only.
#
# Install layout (layout 2), the standard Steam/umu compatdata layout:
#
#   <bms_root>/                 STEAM_COMPAT_DATA_PATH, umu's WINEPREFIX
#   ├── pfx/                    the real Wine prefix (drive_c, *.reg)
#   ├── runners/                Proton runners downloaded by the helper
#   ├── bms-launcher.sh         static launcher (copied from lib/)
#   ├── bms-launch.conf         launcher settings (runner, exe, toggles)
#   └── .bms-helper             layout/version marker
#
# Layout 1 (helper v1.x) had the prefix directly in <bms_root> with a
# pfx -> . symlink; ensure_install_layout() migrates it.

# MARK: set_bms_mode()
# Populate names for the chosen mode (public|internal)
set_bms_mode() {
    case "$1" in
        internal)
            bms_mode="internal"
            bms_dirname="falcon-bms-internal"
            bms_desktop_basename="Falcon BMS Internal.desktop"
            bms_default_install_path="$HOME/Games/$bms_dirname"
            conf_subdir="falcon-bms-internal"
            bms_base_dir="Falcon BMS 4.38 (Internal)"
            bms_installer="Falcon BMS_4.38.1_Internal_Full_Setup.exe"
            bms_wiki="https://wiki.benchmarksims.org"
            ;;
        *)
            bms_mode="public"
            bms_dirname="falcon-bms"
            bms_desktop_basename="Falcon BMS.desktop"
            bms_default_install_path="$HOME/Games/$bms_dirname"
            conf_subdir="falcon-bms"
            bms_base_dir="Falcon BMS 4.38"
            bms_installer="Falcon BMS_4.38.0_Full_Setup.exe"
            bms_wiki="https://wiki.falcon-bms.com"
            ;;
    esac

    # Ensure a sane default for max items to request/iterate
    max_download_items=${max_download_items:-50}
}

# MARK: detect_installer_from_path()
# Switch to internal mode when the installer file name says so
detect_installer_from_path() {
    local p="$1"
    if [ -z "$p" ]; then
        return 1
    fi
    local lbn
    lbn="$(basename "$p" | tr '[:upper:]' '[:lower:]')"

    if echo "$lbn" | grep -qi "internal"; then
        set_bms_mode internal
    else
        set_bms_mode public
    fi
    return 0
}

# MARK: cleanup_conf_if_only_firstrun()
# Remove the config subdir if it contains only the firstrun marker
cleanup_conf_if_only_firstrun() {
    target_dir="$conf_dir/$conf_subdir"
    if [ -d "$target_dir" ]; then
        shopt -s nullglob
        entries=("$target_dir"/*)
        shopt -u nullglob
        if [ "${#entries[@]}" -eq 1 ] && [ "$(basename "${entries[0]}")" = "$firstrun_conf" ]; then
            rm -r --interactive=never "$target_dir"
        fi
    fi
}

############################################################################
######## launch settings file (bms-launch.conf) ############################
############################################################################

# The file holds one KEY='value' assignment per line so the launcher can
# source it. These helpers read and change single keys without sourcing it.

# MARK: conf_get()
# Print the value of KEY from a launch settings file
# Usage: conf_get file KEY
conf_get() {
    [ -f "$1" ] || return 1
    K="$2" awk '
        index($0, ENVIRON["K"] "=") == 1 {
            v = substr($0, length(ENVIRON["K"]) + 2)
            if (v ~ /^'\''.*'\''$/) {
                v = substr(v, 2, length(v) - 2)
                gsub(/'\''\\'\'''\''/, "'\''", v)
            }
            print v
            found = 1
            exit
        }
        END { exit(found ? 0 : 1) }
    ' "$1"
}

# MARK: conf_set()
# Set KEY to a value in a launch settings file, appending it if missing
# Usage: conf_set file KEY value
conf_set() {
    conf_file="$1"
    conf_quoted="'${3//\'/\'\\\'\'}'"

    if grep -q "^$2=" "$conf_file" 2>/dev/null; then
        K="$2" V="$conf_quoted" awk '
            index($0, ENVIRON["K"] "=") == 1 && !done { print ENVIRON["K"] "=" ENVIRON["V"]; done = 1; next }
            { print }
        ' "$conf_file" > "$conf_file.tmp" && mv "$conf_file.tmp" "$conf_file"
    else
        printf '%s=%s\n' "$2" "$conf_quoted" >> "$conf_file"
    fi
}

# MARK: write_launch_conf_template()
# Create a launch settings file with documented defaults
write_launch_conf_template() {
    cat > "$1" <<'EOF'
# Falcon BMS launch settings, read by bms-launcher.sh.
#
# PROTONPATH and BMS_LAUNCHER_EXE are managed by bms-helper; everything else
# is yours to change. Variables set in the environment when starting
# bms-launcher.sh take precedence over the values in this file.
# Standard Proton/umu/MangoHud variables are used where they exist; BMS_*
# variables are only for what the launcher itself does.

# Proton runner (GE-Proton, UMU-Proton or CachyOS Proton).
# Change it with 'Manage Proton Runners' in the helper.
PROTONPATH=''
# Falcon BMS launcher executable
BMS_LAUNCHER_EXE=''

# 1 = run through gamemoderun when it is installed
BMS_USE_GAMEMODE='1'
# 1 = show the MangoHud overlay (MangoHud's own variable)
MANGOHUD='0'
# 1 = use Proton's native Wayland driver instead of XWayland (experimental:
#     the WPF launcher's windows and popups may misbehave)
PROTON_ENABLE_WAYLAND='0'
# 1 = start the Thrustmaster MFD helper (mfd-joystick.py) with the game
BMS_MFD_HELPER='0'
# Controller setup snapshots kept before launches (bindings, axis mapping,
# keyfiles); restore them from the helper's Controllers menu. 0 = off
BMS_CONFIG_BACKUPS='5'
# 0 = launch with plain Proton instead of umu-run (troubleshooting only)
BMS_UMU_LAUNCH='1'
# Extra arguments passed to the launcher executable
BMS_EXTRA_ARGS=''

# Add your own environment variables below, for example:
# export DXVK_HUD=fps
#
# If the Alternative Launcher fails with "Culture ID 4096 is not a supported
# culture", your system locale is unknown to Windows; use a common one:
# export LC_ALL=en_US.UTF-8
EOF
}

############################################################################
######## install discovery #################################################
############################################################################

# MARK: set_install_paths()
# Derive every install path from the install root
set_install_paths() {
    bms_root="$1"
    bms_pfx="$bms_root/pfx"
    bms_conf="$bms_root/bms-launch.conf"
    game_path="$bms_pfx/drive_c/$bms_base_dir"
    download_dir="$bms_root/runners"
}

# MARK: is_bms_install()
# True if the directory looks like a Falcon BMS install root (either layout)
is_bms_install() {
    [ -d "$1/pfx/drive_c" ] || [ -d "$1/drive_c" ]
}

# MARK: getdirs()
# Resolve the targeted install root, asking the user if none is saved, and
# make sure it uses the current layout. Sets bms_root, bms_pfx, bms_conf,
# game_path and download_dir.
# Returns 1 on error/cancel, 3 if the user was asked to select the install.
getdirs() {
    if [ ! -d "$conf_dir" ]; then
        message error "Config directory not found. The Helper is unable to proceed.\n\n$conf_dir"
        return 1
    fi
    mkdir -p "$conf_dir/$conf_subdir"

    retval=0
    selected_root=""

    if [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
        selected_root="$(cat "$conf_dir/$conf_subdir/$wine_conf")"
        if [ ! -d "$selected_root" ]; then
            debug_print continue "The saved install directory does not exist, ignoring."
            selected_root=""
            rm --interactive=never "${conf_dir:?}/$conf_subdir/$wine_conf"
        fi
    fi

    # Use the default install location without asking when it holds an install
    if [ -z "$selected_root" ] && is_bms_install "$bms_default_install_path"; then
        selected_root="$bms_default_install_path"
    fi

    if [ -z "$selected_root" ]; then
        message info "At the next screen, please select the directory where you installed Falcon BMS\nIt will be remembered for future use.\n\nDefault install path: $bms_default_install_path"
        while [ -z "$selected_root" ]; do
            if [ "$use_zenity" -eq 1 ]; then
                selected_root="$(zenity --file-selection --directory --title="Select your Falcon BMS install directory" --filename="$bms_default_install_path/" 2>/dev/null)"
                if [ -z "$selected_root" ]; then
                    message warning "Operation cancelled.\nNo changes have been made to your game."
                    return 1
                fi
            else
                printf "Enter the full path to your Falcon BMS install directory (case sensitive)\n"
                printf "ie. %s\n" "$bms_default_install_path"
                read -rp ": " selected_root
                if [ -z "$selected_root" ]; then
                    return 1
                fi
            fi

            if ! is_bms_install "$selected_root"; then
                message warning "This does not look like a Falcon BMS install (no Wine prefix found):\n\n$selected_root"
                selected_root=""
            fi
        done
        retval=3
    fi

    set_install_paths "$selected_root"
    ensure_install_layout || return 1

    # If the install only contains the other release type, offer to switch modes
    if [ ! -d "$game_path" ]; then
        if [ "$bms_mode" = "public" ] && [ -d "$bms_pfx/drive_c/Falcon BMS 4.38 (Internal)" ]; then
            if message question "This is an internal Falcon BMS installation:\n\n$bms_root\n\nbut the Helper is in public mode. Switch to internal mode and use the 'falcon-bms-internal' config folder?"; then
                set_bms_mode internal
                mkdir -p "$conf_dir/$conf_subdir"
                set_install_paths "$selected_root"
            fi
        elif [ "$bms_mode" = "internal" ] && [ -d "$bms_pfx/drive_c/Falcon BMS 4.38" ]; then
            if message question "This is a public Falcon BMS installation:\n\n$bms_root\n\nbut the Helper is in internal mode. Switch to public mode and use the 'falcon-bms' config folder?"; then
                set_bms_mode public
                mkdir -p "$conf_dir/$conf_subdir"
                set_install_paths "$selected_root"
            fi
        fi
    fi

    echo "$bms_root" > "$conf_dir/$conf_subdir/$wine_conf"
    return "$retval"
}

# MARK: write_install_marker()
# Record the layout and helper version in the install root
write_install_marker() {
    printf 'layout=%s\nhelper_version=%s\n' "$bms_layout_version" "$current_version" > "$1/.bms-helper"
}

# MARK: ensure_install_layout()
# Make sure bms_root uses the current layout, migrating an older install
# automatically so users don't need to know about prefix layouts.
ensure_install_layout() {
    if [ -d "$bms_root/pfx/drive_c" ] && [ ! -L "$bms_root/pfx" ]; then
        [ -f "$bms_root/.bms-helper" ] || write_install_marker "$bms_root"
        return 0
    fi

    if [ ! -d "$bms_root/drive_c" ]; then
        message error "No Wine prefix was found in:\n\n$bms_root"
        return 1
    fi

    migrate_install_layout "$bms_root"
}

# MARK: legacy_launcher_toggle()
# Print the default a user gave a toggle in a v1 generated launcher, ie.
# export BMS_USE_MANGOHUD="${BMS_USE_MANGOHUD:-1}" prints 1
legacy_launcher_toggle() {
    sed -n "s/^export $2=\"\\\${$2:-\\([^}]*\\)}\"\$/\\1/p" "$1" 2>/dev/null | head -n1
}

# MARK: legacy_runner_path()
# Print the Proton runner a v1 install was configured with, if any
legacy_runner_path() {
    lr_path="$(sed -n '1p' "$1/current_runner" 2>/dev/null | tr -d '\r')"
    if [ -z "$lr_path" ] && [ -f "$1/$bms_launcher_name" ]; then
        lr_path="$(sed -n 's/^export proton_path="\(.*\)"$/\1/p' "$1/$bms_launcher_name" | head -n1)"
    fi
    printf '%s\n' "$lr_path"
}

# MARK: migrate_install_layout()
# Upgrade an install made by helper v1.x, where the prefix sat directly in
# the install root behind a pfx -> . symlink and the launcher was generated.
# The prefix moves into a real <root>/pfx (Proton's own files such as
# version and tracked_files stay in the root, where Proton expects them),
# launcher settings move into bms-launch.conf, and desktop/app shortcuts are
# refreshed. Any failure while moving files restores the old layout.
migrate_install_layout() {
    mig_root="$1"

    if bms_running; then
        message warning "Falcon BMS needs a quick update, but it is running.\n\nClose Falcon BMS, then try again."
        return 1
    fi

    progress_bar start "Updating your Falcon BMS install. This only takes a moment..."
    debug_print continue "Migrating $mig_root to the pfx layout..."

    mig_runner="$(legacy_runner_path "$mig_root")"
    mig_old_launcher="$mig_root/$bms_launcher_name"

    # Stop anything still using the old prefix
    if [ -x "$mig_runner/files/bin/wineserver" ]; then
        WINEPREFIX="$mig_root" "$mig_runner/files/bin/wineserver" -k 2>/dev/null
    fi

    mig_had_symlink=0
    if [ -L "$mig_root/pfx" ]; then
        mig_had_symlink=1
        rm -f "$mig_root/pfx"
    fi
    if [ -e "$mig_root/pfx" ] || ! mkdir "$mig_root/pfx"; then
        [ "$mig_had_symlink" -eq 1 ] && ln -s . "$mig_root/pfx"
        progress_bar stop
        message error "Unable to update the install: '$mig_root/pfx' could not be created.\n\nYour install was not changed."
        return 1
    fi

    shopt -s nullglob dotglob
    mig_items=("$mig_root"/drive_c "$mig_root"/dosdevices "$mig_root"/*.reg "$mig_root"/*.reg.* \
        "$mig_root"/.update-timestamp "$mig_root"/winetricks.log "$mig_root"/.windows-serial \
        "$mig_root"/creation_sync_guard)
    shopt -u nullglob dotglob

    mig_moved=()
    for mig_item in "${mig_items[@]}"; do
        [ -e "$mig_item" ] || [ -L "$mig_item" ] || continue
        if ! mv -- "$mig_item" "$mig_root/pfx/"; then
            for mig_back in "${mig_moved[@]}"; do
                mv -- "$mig_root/pfx/$mig_back" "$mig_root/"
            done
            rmdir "$mig_root/pfx" 2>/dev/null
            [ "$mig_had_symlink" -eq 1 ] && ln -s . "$mig_root/pfx"
            progress_bar stop
            message error "Unable to update the install (could not move $mig_item).\n\nYour install was restored and still works with its current launcher."
            return 1
        fi
        mig_moved+=("$(basename "$mig_item")")
    done

    # Carry the old launcher's settings over to bms-launch.conf
    mig_conf="$mig_root/bms-launch.conf"
    [ -f "$mig_conf" ] || write_launch_conf_template "$mig_conf"
    if [ -f "$mig_old_launcher" ] && grep -q '^# Falcon BMS launcher generated by bms-helper.sh' "$mig_old_launcher"; then
        # v1 toggle name -> bms-launch.conf variable
        for mig_toggle in BMS_USE_GAMEMODE:BMS_USE_GAMEMODE BMS_USE_MANGOHUD:MANGOHUD; do
            mig_value="$(legacy_launcher_toggle "$mig_old_launcher" "${mig_toggle%%:*}")"
            case "$mig_value" in
                0|1) conf_set "$mig_conf" "${mig_toggle#*:}" "$mig_value" ;;
            esac
        done
        cp -f "$mig_old_launcher" "$mig_root/bms-launcher.v1.bak"
    fi
    # v1 launchers started an MFD helper found beside them
    if [ -f "$mig_root/mfd-joystick.py" ]; then
        conf_set "$mig_conf" BMS_MFD_HELPER 1
    fi
    rm -f "$mig_root/current_runner"

    migrate_app_shortcuts "$mig_root"
    write_install_marker "$mig_root"
    set_install_paths "$mig_root"
    progress_bar stop

    # Keep the old runner when it can still be used, otherwise pick a working one
    if runner_supported "$mig_runner"; then
        proton_path="$mig_runner"
    else
        if [ -n "$mig_runner" ]; then
            debug_print continue "The previous runner can't be used with this Helper: $mig_runner"
        fi
        proton_path=""
        choose_default_runner || message warning "No usable Proton runner could be set up.\n\nUse 'Manage Proton Runners' to select one before launching Falcon BMS."
    fi

    # New launcher (same file name, so existing shortcuts keep working),
    # refreshed desktop files and the prefix settings the v1 launcher used
    # to re-apply on every start
    install_launch_script
    create_desktop_files
    if [ -n "$proton_path" ]; then
        ensure_umu
        progress_bar start "Applying Falcon BMS prefix settings..."
        apply_prefix_settings || debug_print continue "Applying prefix settings after migration failed."
        progress_bar stop
    fi

    debug_print continue "Migrated $mig_root to the pfx layout (${#mig_moved[@]} items moved)."
    message info "Your Falcon BMS install was updated for this version of the Helper.\n\nYour game, settings and shortcuts are unchanged; Falcon BMS will now start faster."
    return 0
}

# MARK: migrate_app_shortcuts()
# Rewrite layout 1 app shortcut wrappers ('exec <wine> <exe>') to run through
# the launcher, with exe paths moved into pfx/
migrate_app_shortcuts() {
    msc_root="$1"
    for msc_script in "$msc_root/shortcuts"/*.sh; do
        [ -f "$msc_script" ] || continue
        msc_exe="$(sed -n 's/^exec "[^"]*" "\(.*\)" "\$@"$/\1/p' "$msc_script")"
        [ -n "$msc_exe" ] || continue
        case "$msc_exe" in
            "$msc_root/drive_c/"*) msc_exe="$msc_root/pfx/${msc_exe#"$msc_root/"}" ;;
        esac
        write_app_shortcut_script "$msc_script" "$msc_root" "$msc_exe"

        msc_name="$(basename "$msc_script" .sh)"
        for msc_desktop in "${data_dir}/applications/$msc_name.desktop" "${XDG_DESKTOP_DIR:-$HOME/Desktop}/$msc_name.desktop"; do
            [ -f "$msc_desktop" ] || continue
            sed -i "s|^Path=$msc_root/drive_c/|Path=$msc_root/pfx/drive_c/|" "$msc_desktop"
        done
    done
}

# MARK: bms_running()
# True if a Falcon BMS (or its launcher) Windows process is running.
# Matches the Windows-side command line, which Wine rewrites with backslashes.
bms_running() {
    pgrep -fi '\\(Falcon BMS|FalconBMS_Alternative_Launcher)\.exe' >/dev/null 2>&1
}

# MARK: switch_prefix()
# Target the Helper at a different Falcon BMS installation
switch_prefix() {
    if [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
        getdirs
        # getdirs returns 3 if the user just had to select a new install,
        # so don't ask a second time
        if [ "$?" -ne 3 ] && message question "The Helper is currently targeting this Falcon BMS install\nWould you like to change it?\n\n$bms_root"; then
            reset_helper "switchprefix"
            getdirs
        fi
    else
        getdirs
    fi
}

# MARK: reset_helper()
# Delete the helper's config directory
reset_helper() {
    if [ "$1" = "switchprefix" ]; then
        # Only forget the targeted install
        debug_print continue "Deleting $conf_dir/$conf_subdir/{$wine_conf,$game_conf}..."
        rm -f -- "${conf_dir:?}/$conf_subdir/$wine_conf" "${conf_dir:?}/$conf_subdir/$game_conf"
    elif message question "All config files will be deleted from:\n\n$conf_dir/$conf_subdir\n\nDo you want to proceed?"; then
        debug_print continue "Deleting $conf_dir/$conf_subdir/*.conf..."
        rm --interactive=never "${conf_dir:?}/$conf_subdir/"*.conf
        message info "The Helper has been reset!"
        exit 0
    fi
    bms_root=""
    game_path=""
}
