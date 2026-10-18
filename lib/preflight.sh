# shellcheck shell=bash
# bms-helper: Preflight Check (system optimization checks and fixes).
# Sourced by bms-helper.sh; defines functions only.

############################################################################
######## begin preflight check functions ###################################
############################################################################

# MARK: preflight_check()
# Check that the system is optimized for Falcon BMS
# Accepts an optional string argument, "wine"
# This argument is used by the install functions to indicate which
# Preflight Check functions should be called and cause the Preflight Check
# to only output problems that must be fixed
#
# There are two options for automatically fixing problems:
# See existing functions for examples of setting
# preflight_root_actions or preflight_user_actions
preflight_check() {
    # Initialize variables
    unset preflight_pass
    unset preflight_fail
    unset preflight_action_funcs
    unset preflight_root_actions
    unset preflight_user_actions
    unset preflight_fix_results
    unset preflight_manual
    unset preflight_followup
    unset preflight_fail_string
    unset preflight_pass_string
    unset preflight_manual_string
    unset preflight_fix_results_string
    unset preflight_root_actions_string
    unset preflight_user_actions_string
    unset install_mode
    retval=0

    # Capture optional argument that determines which install function called us
    install_mode="$1"

    # Check the optional argument for valid values
    if [ -n "$install_mode" ] && [ "$install_mode" != "wine" ]; then
        debug_print exit "Script error: Unexpected argument passed to the preflight_check function. Aborting."
    fi

    # Call the optimization functions to perform the checks
    memory_check
    avx_check
    mapcount_check
    filelimit_check
    audio_check
    vr_check

    # Populate info strings with the results and add formatting
    if [ "${#preflight_fail[@]}" -gt 0 ]; then
        # Failed checks
        preflight_fail_string="Failed Checks:"
        for (( i=0; i<"${#preflight_fail[@]}"; i++ )); do
            if [ "$i" -eq 0 ]; then
                preflight_fail_string="$preflight_fail_string\n- ${preflight_fail[i]//\\n/\\n    }"
            else
                preflight_fail_string="$preflight_fail_string\n\n- ${preflight_fail[i]//\\n/\\n    }"
            fi
        done
        # Add extra newlines if there are also passes to report
        if [ "${#preflight_pass[@]}" -gt 0 ]; then
            preflight_fail_string="$preflight_fail_string\n\n"
        fi
    fi
    if [ "${#preflight_pass[@]}" -gt 0 ]; then
        # Passed checks
        preflight_pass_string="Passed Checks:"
        for (( i=0; i<"${#preflight_pass[@]}"; i++ )); do
            preflight_pass_string="$preflight_pass_string\n- ${preflight_pass[i]//\\n/\\n    }"
        done
    fi
    for (( i=0; i<"${#preflight_manual[@]}"; i++ )); do
        # Instructions for manually fixing problems
        if [ "$i" -eq 0 ]; then
            preflight_manual_string="${preflight_manual[i]}"
        else
            preflight_manual_string="$preflight_manual_string\n\n${preflight_manual[i]}"
        fi
    done

    # Format a message heading
    message_heading="Preflight Check Results"
    if [ "$use_zenity" -eq 1 ]; then
        message_heading="<big><b>$message_heading</b></big>"
    fi

    # Display the results of the preflight check
    if [ -z "$preflight_fail_string" ]; then
        # If install_mode was set by an install function, we won't bother the user when all checks pass
        if [ -z "$install_mode" ]; then
            # All checks pass!
            message info "$message_heading\n\nYour system is optimized for Falcon BMS!\n\n$preflight_pass_string"
        fi

        return 0
    else
        if [ "${#preflight_action_funcs[@]}" -eq 0 ]; then
            # We have failed checks, but they're issues we can't automatically fix
            message warning "$message_heading\n\n$preflight_fail_string$preflight_pass_string"
        elif message question "$message_heading\n\n$preflight_fail_string$preflight_pass_string\n\nWould you like these configuration issues to be fixed for you?"; then
            # We have failed checks, but we can fix them for the user
            # Call functions to build fixes for any issues found
            for (( i=0; i<"${#preflight_action_funcs[@]}"; i++ )); do
                ${preflight_action_funcs[i]}
            done

            # Populate a string of actions to be executed with root privileges
            for (( i=0; i<"${#preflight_root_actions[@]}"; i++ )); do
                if [ "$i" -eq 0 ]; then
                    preflight_root_actions_string="${preflight_root_actions[i]}"
                else
                    preflight_root_actions_string="$preflight_root_actions_string; ${preflight_root_actions[i]}"
                fi
            done
            # Populate a string of actions to be executed with user privileges
            for (( i=0; i<"${#preflight_user_actions[@]}"; i++ )); do
                if [ "$i" -eq 0 ]; then
                    preflight_user_actions_string="${preflight_user_actions[i]}"
                else
                    preflight_user_actions_string="$preflight_user_actions_string; ${preflight_user_actions[i]}"
                fi
            done

            # Execute the root privilege actions set by the functions
            if [ -n "$preflight_root_actions_string" ]; then
                # Try to execute the actions as root
                try_exec root "$preflight_root_actions_string"
                if [ "$?" -eq 1 ]; then
                    message error "The Preflight Check was unable to finish fixing problems.\nDid authentication fail? See terminal for more information.\n\nReturning to main menu."
                    return 0
                fi
            fi
            # Execute the user privilege actions set by the functions
            if [ -n "$preflight_user_actions_string" ]; then
                # Try to execute the actions as root
                try_exec user "$preflight_user_actions_string"
                if [ "$?" -eq 1 ]; then
                    message error "The Preflight Check was unable to finish fixing problems.\nSee terminal for more information.\n\nReturning to main menu."
                    return 0
                fi
            fi

            # Call any followup functions
            for (( i=0; i<"${#preflight_followup[@]}"; i++ )); do
                ${preflight_followup[i]}
            done

            # Populate the results string
            for (( i=0; i<"${#preflight_fix_results[@]}"; i++ )); do
                if [ "$i" -eq 0 ]; then
                    preflight_fix_results_string="${preflight_fix_results[i]}"
                else
                    preflight_fix_results_string="$preflight_fix_results_string\n\n${preflight_fix_results[i]}"
                fi
            done

            # Display the results
            message info "$preflight_fix_results_string"
        else
            # User declined to automatically fix configuration issues
            # Show manual configuration options
            if [ -n "$preflight_manual_string" ]; then
                message info "$preflight_manual_string"
            fi
        fi

            # Clean up config dir if it only contains firstrun.conf
            cleanup_conf_if_only_firstrun
            return 1
    fi
}

# MARK: memory_check()
# Check system memory and swap space
memory_check() {
    # Get totals in bytes
    memtotal="$(LC_NUMERIC=C awk '/MemTotal/ {printf $2}' /proc/meminfo)"
    swaptotal="$(LC_NUMERIC=C awk '/SwapTotal/ {printf $2}' /proc/meminfo)"
    memtotal="$(($memtotal * 1024))"
    swaptotal="$(($swaptotal * 1024))"
    combtotal="$(($memtotal + $swaptotal))"

    # Convert to whole number GiB
    memtotal="$(numfmt --to=iec-i --format="%.0f" --suffix="B" "$memtotal")"
    swaptotal="$(numfmt --to=iec-i --format="%.0f" --suffix="B" "$swaptotal")"
    combtotal="$(numfmt --to=iec-i --format="%.0f" --suffix="B" "$combtotal")"

    if [ "${memtotal: -3}" != "GiB" ] || [ "${memtotal::-3}" -lt "$(($memory_required-1))" ]; then
        # Minimum requirements are not met
        preflight_fail+=("Your system has $memtotal of memory.\n${memory_required}GiB is the minimum required to avoid crashes.")
    elif [ "${memtotal::-3}" -ge "$memory_combined_required" ]; then
        # System has sufficient RAM
        preflight_pass+=("Your system has $memtotal of memory.")
    elif [ "${combtotal::-3}" -ge "$memory_combined_required" ]; then
        # System has sufficient combined RAM + swap
        preflight_pass+=("Your system has $memtotal memory and $swaptotal swap.")
    else
        # Recommend swap
        swap_recommended="$(($memory_combined_required - ${memtotal::-3}))"
        preflight_fail+=("Your system has $memtotal memory and $swaptotal swap.\nWe recommend at least ${swap_recommended}GiB swap to avoid crashes.")
    fi
}

# MARK: avx_check()
# Check CPU for the required AVX extension
avx_check() {
    if grep -q "avx" /proc/cpuinfo; then
        preflight_pass+=("Your CPU supports the necessary AVX instruction set.")
    else
        preflight_fail+=("Your CPU does not appear to support AVX instructions.\nThis requirement was added to Falcon BMS in version 3.11")
    fi
}

############################################################################
######## begin mapcount functions ##########################################
############################################################################

# MARK: mapcount_check()
# Check vm.max_map_count for the correct setting
mapcount_check() {
    mapcount="$(cat /proc/sys/vm/max_map_count)"
    # Add to the results and actions arrays
    if [ "$mapcount" -ge $mapcount_required ]; then
        # All good
        preflight_pass+=("vm.max_map_count is set to $mapcount.")
    elif awk -v req="$mapcount_required" '
        /^[[:space:]]*vm\.max_map_count[[:space:]]*=/ {
            v = $0
            sub(/^[^=]*=[[:space:]]*/, "", v)
            if (v + 0 >= req + 0) found = 1
        }
        END { exit(found ? 0 : 1) }
    ' /etc/sysctl.conf /etc/sysctl.d/* 2>/dev/null; then
        # Was it supposed to have been set by sysctl?
        preflight_fail+=("vm.max_map_count is configured to at least $mapcount_required but the setting has not been loaded by your system.")
        # Add the function that will be called to change the configuration
        preflight_action_funcs+=("mapcount_once")

        # Add info for manually changing the setting
        preflight_manual+=("To change vm.max_map_count until the next reboot, run:\nsudo sysctl -w vm.max_map_count=$mapcount_required")
    else
        # The setting should be changed
        preflight_fail+=("vm.max_map_count is $mapcount\nand should be set to at least $mapcount_required\nto give the game access to sufficient memory.")
        # Add the function that will be called to change the configuration
        preflight_action_funcs+=("mapcount_set")

        # Add info for manually changing the setting
        if [ -d "/etc/sysctl.d" ]; then
            # Newer versions of sysctl
            preflight_manual+=("To change vm.max_map_count permanently, add the following line to\n'/etc/sysctl.d/99-falcon-bms-max_map_count.conf' and reload with 'sudo sysctl --system'\n    vm.max_map_count = $mapcount_required\n\nOr, to change vm.max_map_count temporarily until next boot, run:\n    sudo sysctl -w vm.max_map_count=$mapcount_required")
        else
            # Older versions of sysctl
            preflight_manual+=("To change vm.max_map_count permanently, add the following line to\n'/etc/sysctl.conf' and reload with 'sudo sysctl -p':\n    vm.max_map_count = $mapcount_required\n\nOr, to change vm.max_map_count temporarily until next boot, run:\n    sudo sysctl -w vm.max_map_count=$mapcount_required")
        fi
    fi
}

# MARK: mapcount_set()
# Set vm.max_map_count
mapcount_set() {
    if [ -d "/etc/sysctl.d" ]; then
        # Newer versions of sysctl
        preflight_root_actions+=("printf '\\n# Added by bms-helper:\\nvm.max_map_count = $mapcount_required\\n' > /etc/sysctl.d/99-falcon-bms-max_map_count.conf && sysctl --quiet --system")
        preflight_fix_results+=("The vm.max_map_count configuration has been added to:\n/etc/sysctl.d/99-falcon-bms-max_map_count.conf")
    else
        # Older versions of sysctl
        preflight_root_actions+=("printf '\\n# Added by bms-helper:\\nvm.max_map_count = $mapcount_required\\n' >> /etc/sysctl.conf && sysctl -p")
        preflight_fix_results+=("The vm.max_map_count configuration has been added to:\n/etc/sysctl.conf")
    fi

    # Verify that the setting took effect
    preflight_followup+=("mapcount_confirm")
}

# MARK: mapcount_once()
# Sets vm.max_map_count for the current session only
mapcount_once() {
    preflight_root_actions+=("sysctl -w vm.max_map_count=$mapcount_required")
    preflight_fix_results+=("vm.max_map_count was changed until the next boot.")
    preflight_followup+=("mapcount_confirm")
}

# MARK: mapcount_confirm()
# Check if setting vm.max_map_count was successful
mapcount_confirm() {
    if [ "$(cat /proc/sys/vm/max_map_count)" -lt $mapcount_required ]; then
        preflight_fix_results+=("WARNING: As far as this Helper can detect, vm.max_map_count\nwas not successfully configured on your system.\nYou will most likely experience crashes.")
    fi
}

############################################################################
######## end mapcount functions ############################################
############################################################################

############################################################################
######## begin filelimit functions #########################################
############################################################################

# MARK: filelimit_check()
# Check the open file descriptors limit
filelimit_check() {
    filelimit="$(ulimit -Hn)"

    # Add to the results and actions arrays
    if [ "$filelimit" -ge 524288 ]; then
        # All good
        preflight_pass+=("Hard open file descriptors limit is set to $filelimit.")
    else
        # The file limit should be changed
        preflight_fail+=("Your hard open file descriptors limit is $filelimit\nand should be set to at least 524288\nto increase the maximum number of open files.")
        # Add the function that will be called to change the configuration
        preflight_action_funcs+=("filelimit_set")

        # Add info for manually changing the settings
        if [ -f "/etc/systemd/system.conf" ]; then
            # Using systemd
            preflight_manual+=("To change your open file descriptors limit, add the following to\n'/etc/systemd/system.conf.d/99-falcon-bms-filelimit.conf':\n\n[Manager]\nDefaultLimitNOFILE=524288")
        elif [ -f "/etc/security/limits.conf" ]; then
            # Using limits.conf
            preflight_manual+=("To change your open file descriptors limit, add the following line to\n'/etc/security/limits.conf':\n    * hard nofile 524288")
        else
            # Don't know what method to use
            preflight_manual+=("This Helper is unable to detect the correct method of setting\nthe open file descriptors limit on your system.\n\nWe recommend manually configuring this limit to at least 524288.")
        fi
    fi
}

# MARK: filelimit_set()
# Set the open file descriptors limit
filelimit_set() {
    if [ -f "/etc/systemd/system.conf" ]; then
        # Using systemd
        # Append to the file
        preflight_root_actions+=('mkdir -p /etc/systemd/system.conf.d && printf "[Manager]\n# Added by bms-helper:\nDefaultLimitNOFILE=524288\n" > /etc/systemd/system.conf.d/99-falcon-bms-filelimit.conf && systemctl daemon-reexec')
        preflight_fix_results+=("The open files limit configuration has been added to:\n/etc/systemd/system.conf.d/99-falcon-bms-filelimit.conf")
    elif [ -f "/etc/security/limits.conf" ]; then
        # Using limits.conf
        # Insert before the last line in the file
        preflight_root_actions+=('sed -i "\$i#Added by bms-helper:" /etc/security/limits.conf; sed -i "\$i* hard nofile 524288" /etc/security/limits.conf')
        preflight_fix_results+=("The open files limit configuration has been appended to:\n/etc/security/limits.conf")
    else
        # Don't know what method to use
        preflight_fix_results+=("This Helper is unable to detect the correct method of setting\nthe open file descriptors limit on your system.\n\nWe recommend manually configuring this limit to at least 524288.")
    fi

    # Verify that setting the limit was successful
    preflight_followup+=("filelimit_confirm")
}

# MARK: filelimit_confirm()
# Check if setting the open file descriptors limit was successful
filelimit_confirm() {
    if [ "$(ulimit -Hn)" -lt 524288 ]; then
        preflight_fix_results+=("WARNING: As far as this Helper can detect, the open files limit\nwas not successfully configured on your system.\nYou may experience crashes.")
    fi
}

############################################################################
######## end filelimit functions ###########################################
############################################################################

############################################################################
######## begin vr check functions #########################################
############################################################################

# MARK: _vr_wivrn_lib_found()
# Returns 0 if WiVRn OpenXR library is present in any standard path
_vr_wivrn_lib_found() {
    for d in /usr/lib/wivrn /usr/lib/x86_64-linux-gnu/wivrn /usr/lib64/wivrn \
              "$HOME/.local/lib/wivrn"; do
        [ -f "$d/libopenxr_wivrn.so" ] && return 0
    done
    return 1
}

# MARK: vr_check()
# Detect installed VR runtimes, layers, and helper tools.
# Results are informational only: found items go to preflight_pass,
# so this check never hard-blocks an installation.
vr_check() {
    local vr_detected=()

    # ── Active OpenXR runtime JSON ────────────────────────────────────────
    local openxr_cfg_json="${XR_RUNTIME_JSON:-${XDG_CONFIG_HOME:-$HOME/.config}/openxr/1/active_runtime.json}"
    if [ -f "$openxr_cfg_json" ]; then
        local rt_lib rt_name="unknown"
        rt_lib="$(grep -o '"library_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$openxr_cfg_json" 2>/dev/null | head -1 | cut -d'"' -f4)"
        case "$rt_lib" in
            *wivrn*) rt_name="WiVRn" ;;
        esac
        vr_detected+=("Active OpenXR runtime: $rt_name")
    fi

    # ── OpenXR runtimes ───────────────────────────────────────────────────
    # WiVRn
    if command -v wivrn-server >/dev/null 2>&1; then
        vr_detected+=("WiVRn")
    elif _vr_wivrn_lib_found; then
        vr_detected+=("WiVRn (library only, server not in PATH)")
    fi
    # ── Container / tooling ───────────────────────────────────────────────
    command -v umu-run    >/dev/null 2>&1 && vr_detected+=("umu-run (pressure-vessel VR container support)")
    command -v vulkaninfo >/dev/null 2>&1 && vr_detected+=("vulkaninfo (Vulkan GPU detection)")

    # ── Report ────────────────────────────────────────────────────────────
    if [ "${#vr_detected[@]}" -gt 0 ]; then
        local vr_str="VR packages / runtimes detected:"
        for item in "${vr_detected[@]}"; do
            vr_str="$vr_str\n  •  $item"
        done
        preflight_pass+=("$vr_str")
    else
        preflight_pass+=("No VR packages detected. VR is optional; install WiVRn to enable it.")
    fi
}

############################################################################
######## end vr check functions ############################################
############################################################################

############################################################################
######## end preflight check functions #####################################
############################################################################

# MARK: audio_check()
# Falcon BMS has been reported to crash a few seconds into a flight when no
# audio output device exists (DirectSound). Warn, never block.
audio_check() {
    audio_found=""
    if command -v pactl >/dev/null 2>&1; then
        pactl list short sinks 2>/dev/null | grep -q . && audio_found="1"
    elif command -v wpctl >/dev/null 2>&1; then
        wpctl status 2>/dev/null | awk '/Sinks:/{f=1;next} f && /Sources:/{exit} f && /[0-9]+\./{found=1} END{exit !found}' && audio_found="1"
    elif grep -qv 'no soundcards' /proc/asound/cards 2>/dev/null; then
        audio_found="1"
    else
        # No way to tell; don't report a problem we can't see
        return 0
    fi

    if [ -n "$audio_found" ]; then
        preflight_pass+=("An audio output device is available.")
    else
        preflight_fail+=("No audio output device was found.\nFalcon BMS has been reported to crash shortly after\nentering the cockpit without one.")
        preflight_manual+=("Connect or enable an audio output device (speakers, headphones or HDMI audio) before flying.")
    fi
}

# MARK: check_install_space()
# Warn when the install location has less free space than a Falcon BMS
# install needs (about 60 GB, 85+ GB with the high resolution tiles).
# Returns 1 if the user chose not to continue.
check_install_space() {
    space_dir="$1"
    while [ ! -d "$space_dir" ] && [ "$space_dir" != "/" ]; do
        space_dir="$(dirname "$space_dir")"
    done
    space_needed_gb=70
    [ "${use_16k_tiles:-0}" = "1" ] && space_needed_gb=110
    space_free_gb="$(df -Pk "$space_dir" 2>/dev/null | awk 'NR==2 {printf "%d", $4 / 1048576}')"
    [ -n "$space_free_gb" ] || return 0
    if [ "$space_free_gb" -lt "$space_needed_gb" ]; then
        message question "Only ${space_free_gb} GB are free at:\n\n$1\n\nA Falcon BMS install needs about ${space_needed_gb} GB$([ "${use_16k_tiles:-0}" = "1" ] && echo " with the high resolution tiles"). The installation will probably fail.\n\nContinue anyway?"
        return $?
    fi
    return 0
}

# MARK: check_install_filesystem()
# Warn before installing onto a filesystem Wine prefixes don't work well on
# (no Unix permissions/symlinks, or case-insensitive). Returns 1 if the user
# chose not to continue.
check_install_filesystem() {
    fs_dir="$1"
    # The directory may not exist yet; check the closest existing parent
    while [ ! -d "$fs_dir" ] && [ "$fs_dir" != "/" ]; do
        fs_dir="$(dirname "$fs_dir")"
    done
    fs_type="$(findmnt -no FSTYPE -T "$fs_dir" 2>/dev/null)"
    case "$fs_type" in
        ntfs|ntfs3|fuseblk|exfat|vfat|msdos)
            message question "The selected location is on a '$fs_type' filesystem:\n\n$1\n\nWine prefixes on NTFS, exFAT or FAT drives often break (missing symlinks and permissions). Installing to a Linux filesystem such as ext4, btrfs or xfs is strongly recommended.\n\nContinue anyway?"
            return $?
            ;;
    esac
    return 0
}
