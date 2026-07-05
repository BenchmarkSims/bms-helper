#!/usr/bin/env bash

############################################################################
# Falcon BMS Linux installer and launcher script
############################################################################
#
# This script is designed to help you run Falcon BMS on Linux.
#
# Please see the project's github repo for more information:
# https://github.com/falcon-bms/linux-helper
#
# Author: https://github.com/maxwaldorf
# Project inspired by community launcher-helper workflows
#
# License: GPLv3.0
############################################################################

# Check if script is run as root
if [ "$(id -u)" -eq 0 ]; then
    echo "This script is not supposed to be run as root!"
    exit 1
fi

# Check for dependencies
if [ ! -x "$(command -v curl)" ]; then
# Print to stderr and also try warning the user through zenity or notify-send
    printf "bms-helper.sh: The required package 'curl' was not found on this system.\n" 1>&2
    if [ -x "$(command -v zenity)" ]; then
        zenity --error --width="400" --title="Falcon BMS Linux Helper" --text="The required package 'curl' was not found on this system."
    elif [ -x "$(command -v notify-send)" ]; then
        notify-send "bms-helper" "The required package 'curl' was not found on this system.\n" --icon=dialog-warning
    fi
    exit 1
fi
if [ ! -x "$(command -v mktemp)" ] || [ ! -x "$(command -v chmod)" ] || [ ! -x "$(command -v sort)" ] || [ ! -x "$(command -v basename)" ] || [ ! -x "$(command -v realpath)" ] || [ ! -x "$(command -v dirname)" ] || [ ! -x "$(command -v cut)" ] || [ ! -x "$(command -v numfmt)" ] || [ ! -x "$(command -v tr)" ] || [ ! -x "$(command -v od)" ] || [ ! -x "$(command -v readlink)" ]; then
    # coreutils
    # Print to stderr and also try warning the user through zenity or notify-send
    printf "bms-helper.sh: One or more required packages were not found on this system.\nPlease check that 'coreutils' is installed!\n" 1>&2
    if [ -x "$(command -v zenity)" ]; then
        zenity --error --width="400" --title="Falcon BMS Linux Helper" --text="One or more required packages were not found on this system.\n\nPlease check that 'coreutils' is installed!"
    elif [ -x "$(command -v notify-send)" ]; then
        notify-send "bms-helper" "One or more required packages were not found on this system.\nPlease check that 'coreutils' is installed!\n" --icon=dialog-warning
    fi
    exit 1
fi
if [ ! -x "$(command -v xargs)" ]; then
    # findutils
    # Print to stderr and also try warning the user through zenity or notify-send
    printf "bms-helper.sh: One or more required packages were not found on this system.\nPlease check that 'findutils' or the following packages are installed:\n- xargs\n" 1>&2
    if [ -x "$(command -v zenity)" ]; then
        zenity --error --width="400" --title="Falcon BMS Linux Helper" --text="One or more required packages were not found on this system.\n\nPlease check that 'findutils' or the following packages are installed:\n- xargs"
    elif [ -x "$(command -v notify-send)" ]; then
        notify-send "bms-helper" "One or more required packages were not found on this system.\nPlease check that 'findutils' or the following packages are installed:\n- xargs\n" --icon=dialog-warning
    fi
    exit 1
fi
if [ ! -x "$(command -v protontricks)" ]; then
    # protontricks is required for prefix setup and maintenance actions
    printf "bms-helper.sh: The required package 'protontricks' was not found on this system.\n" 1>&2
    if [ -x "$(command -v zenity)" ]; then
        zenity --error --width="420" --title="Falcon BMS Linux Helper" --text="The required package 'protontricks' was not found on this system.\n\nPlease install protontricks and run the helper again."
    elif [ -x "$(command -v notify-send)" ]; then
        notify-send "bms-helper" "The required package 'protontricks' was not found on this system. Please install protontricks and run again." --icon=dialog-warning
    fi
    exit 1
fi
    if [ ! -x "$(command -v cabextract)" ] || [ ! -x "$(command -v unzip)" ]; then
    # Required helper utilities for archive handling
    # Print to stderr and also try warning the user through zenity or notify-send
    printf "bms-helper.sh: One or more required helper utilities were not found on this system.\nPlease check that the following packages are installed:\n- cabextract\n- unzip\n" 1>&2
    if [ -x "$(command -v zenity)" ]; then
        zenity --error --width="400" --title="Falcon BMS Linux Helper" --text="One or more required helper utilities were not found on this system.\n\nPlease check that the following packages are installed:\n- cabextract\n- unzip"
    elif [ -x "$(command -v notify-send)" ]; then
        notify-send "bms-helper" "One or more required helper utilities were not found on this system.\nPlease check that the following packages are installed:\n- cabextract\n- unzip\n" --icon=dialog-warning
    fi
    exit 1
fi

######## Config ############################################################

wine_conf="winedir.conf"
game_conf="gamedir.conf"
firstrun_conf="firstrun.conf"

# Falcon BMS directory name and default install path (use variables instead of repeated literals)
# Default to public release. This may be switched to "internal" if an
# internal installer is detected or explicitly provided by the user.
bms_mode="public" # one of: public|internal

# We'll initialize the install-related names via the helper function
# `set_bms_mode` so a supplied installer path can flip settings.

# Populate names for the chosen mode
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

# MARK: refresh_desktop_execs()
# Update existing .desktop files to use the configured Proton runner (if present)
refresh_desktop_execs() {
    # Ensure directories/paths are available
    getdirs || return 1

    # Paths to the desktop files (same as create_desktop_files)
    localshare_desktop_file="${data_dir}/applications/$bms_desktop_basename"
    home_desktop_file="${XDG_DESKTOP_DIR:-$HOME/Desktop}/$bms_desktop_basename"

    # Ensure install_dir is set (fallback to wine_prefix)
    install_dir="${install_dir:-$wine_prefix}"

    # Ensure launch script exists and is up to date
    create_or_update_launch_script || true
    prefix_desktop_file="$install_dir/$bms_desktop_basename"

    # Prefer a persisted current runner in the install dir
    proton_candidate=""
    if [ -n "$install_dir" ] && [ -f "$install_dir/current_runner" ]; then
        proton_candidate="$(sed -n '1p' "$install_dir/current_runner" | tr -d '\r')"
    fi

    # Fallback: try to read proton_path from the saved launch script in the prefix
    if [ -z "$proton_candidate" ] && [ -n "$wine_prefix" ] && [ -d "$wine_prefix" ]; then
        if [ -n "$wine_launch_script_name" ] && [ -f "$wine_prefix/$wine_launch_script_name" ]; then
            launch_script="$wine_prefix/$wine_launch_script_name"
        else
            for f in "$wine_prefix"/*; do
                if [ -f "$f" ] && grep -q -e '^export proton_path=' -e '^proton_path=' "$f" 2>/dev/null; then
                    launch_script="$f"
                    break
                fi
            done
        fi
        if [ -n "$launch_script" ]; then
            proton_candidate="$(grep -e '^export proton_path=' -e '^proton_path=' "$launch_script" | awk -F '=' '{print $2}' | tr -d '"')"
            proton_candidate="$(echo "$proton_candidate" | sed -e 's/^ *"//' -e 's/" *$//' -e 's/^ *//; s/ *$//')"
        fi
    fi

    # Determine which runner binary to use in Exec lines
    runner_exec="wine"
    if [ -n "$proton_candidate" ] && [ -x "$proton_candidate/proton" ]; then
        runner_exec="$proton_candidate/proton"
    else
        wine_bin="$(command -v wine 2>/dev/null || true)"
        if [ -n "$wine_bin" ]; then
            runner_exec="$wine_bin"
        fi
    fi

    # Desktop entries now launch through the generated prefix script
    exec_line="Exec=\"$install_dir/$wine_launch_script_name\""

    # Replace Exec lines in any existing desktop files to use exec_line
    for f in "$localshare_desktop_file" "$home_desktop_file" "$prefix_desktop_file"; do
        if [ -f "$f" ]; then
            sed -i -E "s|^Exec=.*|$exec_line|" "$f" 2>/dev/null || true
        fi
    done

    debug_print continue "Refreshed desktop Exec lines to use launch script: $install_dir/$wine_launch_script_name"
    return 0
}

# initialize defaults
set_bms_mode "$bms_mode"

# Default Proton GE version to preselect on first install. Change this
# to another version basename (example: "GE-Proton10-18") if you want
# a different default when the Proton list is shown for the first time.
PROTON_DEFAULT_VERSION="GE-Proton10-32"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# Paths to bundled icons
bms_icon="$SCRIPT_DIR/bms-launcher.png"
bms_icon_256="$SCRIPT_DIR/bms-launcher-256.png"

# Use XDG base directories if defined
if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]; then
    # Source the user's xdg directories
    source "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
fi
# configuration directories
conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"

# Startup: detect existing internal config and offer to restart in internal mode
internal_conf_dir="$conf_dir/falcon-bms-internal"
has_internal_arg=0
for _arg in "$@"; do
    case "$_arg" in
        --internal)
            has_internal_arg=1
            break
            ;;
    esac
done
if [ -d "$internal_conf_dir" ] && [ "$bms_mode" != "internal" ] && [ "$has_internal_arg" -eq 0 ]; then
    if [ -x "$(command -v zenity)" ]; then
        if zenity --question --width=420 --title="Falcon BMS Linux Helper" --text="A configuration for 'falcon-bms-internal' was detected at\n\n$internal_conf_dir\n\nRestart helper in internal mode?"; then
            exec "$0" --internal "$@"
        fi
    else
        printf "A configuration for 'falcon-bms-internal' was detected at %s\n\nRestart helper in internal mode? [y/N]: " "$internal_conf_dir"
        read -r ans
        case "$ans" in
            y|Y|yes|Yes|YES)
                exec "$0" --internal "$@"
                ;;
        esac
    fi
fi

# Helper directory
helper_dir="$(realpath "$0" | xargs -0 dirname)"

# Per-prefix launcher script used by desktop entries and maintenance actions
wine_launch_script_name="bms-launcher.sh"

# Temporary directory
tmp_dir="$(mktemp -d -t "bmshelper.XXXXXXXXXX")"
trap 'rm -r --interactive=never "$tmp_dir"' EXIT

# Always use the system-installed protontricks executable
protontricks_bin="$(command -v protontricks 2>/dev/null || true)"

# Installer detection
# User can point to an installer with the environment variable `BMS_INSTALLER`
# or the command-line option `--installer /path/to/installer.exe`.
installer_path=""

detect_installer_from_path() {
    # Argument: path to installer (may be a filename)
    local p="$1"
    if [ -z "$p" ]; then
        return 1
    fi
    local bn="$(basename "$p")"
    local lbn="$(echo "$bn" | tr '[:upper:]' '[:lower:]')"

    # Heuristic: filenames containing 'internal' indicate internal builds
    if echo "$lbn" | grep -qi "internal"; then
        set_bms_mode internal
        return 0
    fi

    # Fallback: default to public
    set_bms_mode public
    return 0
}

# Parse a simple CLI args: --installer, --internal, --public
while [ "$#" -gt 0 ]; do
    case "$1" in
        --installer)
            installer_path="$2"
            shift 2
            ;;
        --installer=*)
            installer_path="${1#--installer=}"
            shift
            ;;
        --internal)
            set_bms_mode internal
            shift
            ;;
        --public)
            set_bms_mode public
            shift
            ;;
        *)
            # stop parsing on first non-recognized option
            break
            ;;
    esac
done

# honor environment variable if set and CLI not provided
if [ -z "$installer_path" ] && [ -n "$BMS_INSTALLER" ]; then
    installer_path="$BMS_INSTALLER"
fi

# If we have an installer path, try to detect internal vs public and set names
if [ -n "$installer_path" ]; then
    detect_installer_from_path "$installer_path"
fi

# URLs for downloading Wine runners
# Elements in this array must be added in quoted pairs of: "description" "url"
# The first string in the pair is expected to contain the runner description
# The second is expected to contain the api releases url
# ie. "RawFox" "https://api.github.com/repos/rawfoxDE/raw-wine/releases"
runner_sources=(
    "GE-Proton" "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases"
)

######## DXVK ##############################################################

# URLs for downloading dxvk versions
dxvk_async_source="https://gitlab.com/api/v4/projects/Ph42oN%2Fdxvk-gplasync/releases/permalink/latest"

######## Requirements ######################################################

# Minimum amount of RAM in GiB
memory_required="8"
# Minimum amount of combined RAM + swap in GiB
memory_combined_required="16"

######## Links / Versions ##################################################

# BMS Wiki (only set if not already configured by detected installer mode)
if [ -z "$bms_wiki" ]; then
    bms_wiki="https://wiki.falcon-bms.com"
fi

# Falcon 4.0 Installer on GoG
gog_url="https://www.gog.com/downloads/falcon_gold/61603"
gog_installer="setup_falcon_4_2.0.0.1.exe"
falcon4_source="gog"
steam_falcon4_dir=""
if [ -z "$bms_installer" ]; then
    bms_installer="Falcon BMS_4.38.0_Full_Setup.exe"
fi

# Github repo and script version info
repo="benchmarksims/bms-helper"
releases_url="https://github.com/${repo}/releases"
current_version="v1.0"

############################################################################
############################################################################
############################################################################


# MARK: try_exec()
# Try to execute a supplied command with either user or root privileges
# Expects two string arguments
# Usage: try_exec [root|user] "command"
try_exec() {
    # This function expects two string arguments
    if [ "$#" -lt 2 ]; then
        printf "\nScript error:  The try_exec() function expects two arguments. Aborting.\n"
        read -n 1 -s -p "Press any key..."
        exit 0
    fi

    exec_type="$1"
    exec_command="$2"

    if [ "$exec_type" = "root" ]; then
        # Use pollkit's pkexec for gui authentication with a fallback to sudo
        if [ -x "$(command -v pkexec)" ]; then
            pkexec sh -c "$exec_command"

            # Check the exit status
            exit_code="$?"
            if [ "$exit_code" -eq 126 ] || [ "$exit_code" -eq 127 ]; then
                # User cancel or error
                debug_print continue "pkexec returned an error. Falling back to sudo..."
            else
                # Successful execution, return here
                return 0
            fi
        fi
        # Fall back to sudo if pkexec is unavailable or returned an error
        if [ -x "$(command -v sudo)" ]; then
            sudo sh -c "$exec_command"

            # Check the exit status
            if [ "$?" -eq 1 ]; then
                # Error
                return 1
            fi
        else
            # We don't know how to perform this operation with elevated privileges
            printf "\nNeither Polkit nor sudo appear to be installed. Unable to execute the command with the required privileges.\n"
            return 1
        fi
    elif [ "$exec_type" = "user" ]; then
        sh -c "$exec_command"

        # Check the exit status
        if [ "$?" -eq 1 ]; then
            # Error
            return 1
        fi
    else
        debug_print exit "Script Error: Invalid arguemnt passed to the try_exec function. Aborting."
    fi

    return 0
}

# MARK: debug_print()
# Echo a formatted debug message to the terminal and optionally exit
# Accepts either "continue" or "exit" as the first argument
# followed by the string to be echoed
debug_print() {
    # This function expects two string arguments
    if [ "$#" -lt 2 ]; then
        printf "\nScript error:  The debug_print function expects two arguments. Aborting.\n"
        read -n 1 -s -p "Press any key..."
        exit 0
    fi

    # Echo the provided string and, optionally, exit the script
    case "$1" in
        "continue")
            printf "\n%s\n" "$2"
            ;;
        "exit")
            # Write an error to stderr and exit
            printf "%s\n" "bms-helper.sh: $2" 1>&2
            read -n 1 -s -p "Press any key..."
            exit 1
            ;;
        *)
            printf "%s\n" "bms-helper.sh: Unknown argument provided to debug_print function. Aborting." 1>&2
            read -n 1 -s -p "Press any key..."
            exit 0
            ;;
    esac
}

# MARK: message()
# Display a message to the user.
# Expects the first argument to indicate the message type, followed by
# a string of arguments that will be passed to zenity or echoed to the user.
#
# To call this function, use the following format: message [type] "[string]"
# See the message types below for instructions on formatting the string.
message() {
    # Sanity check
    if [ "$#" -lt 2 ]; then
        debug_print exit "Script error: The message function expects at least two arguments. Aborting."
    fi

    # Use zenity messages if available
    if [ "$use_zenity" -eq 1 ]; then
        case "$1" in
            "info")
                # info message
                # call format: message info "text to display"
                margs=("--info" "--no-wrap" "--text=")
                shift 1   # drop the message type argument and shift up to the text
                ;;
            "warning")
                # warning message
                # call format: message warning "text to display"
                margs=("--warning" "--text=")
                shift 1   # drop the message type argument and shift up to the text
                ;;
            "error")
                # error message
                # call format: message error "text to display"
                margs=("--error" "--text=")
                shift 1   # drop the message type argument and shift up to the text
                ;;
            "question")
                # question
                # call format: if message question "question to ask?"; then...
                margs=("--question" "--text=")
                shift 1   # drop the message type argument and shift up to the text
                ;;
            "options")
                # formats the buttons with two custom options
                # call format: if message options left_button_name right_button_name "which one do you want?"; then...
                # The right button returns 0 (ok), the left button returns 1 (cancel)
                if [ "$#" -lt 4 ]; then
                    debug_print exit "Script error: The options type in the message function expects four arguments. Aborting."
                fi
                margs=("--question" "--cancel-label=$2" "--ok-label=$3" "--text=")
                shift 3   # drop the type and button label arguments and shift up to the text
                ;;
            *)
                debug_print exit "Script Error: Invalid message type passed to the message function. Aborting."
                ;;
        esac

        # Display the message
        zenity "${margs[@]}""$@" --width="420" --title="Falcon BMS Linux Helper"
    else
        # Fall back to text-based messages when zenity is not available
        case "$1" in
            "info")
                # info message
                # call format: message info "text to display"
                printf "\n%b\n\n" "$2"
                if [ "$cmd_line" != "true" ]; then
                    # Don't pause if we've been invoked via command line arguments
                    read -n 1 -s -p "Press any key..."
                fi
                ;;
            "warning")
                # warning message
                # call format: message warning "text to display"
                printf "\n%b\n\n" "$2"
                read -n 1 -s -p "Press any key..."
                ;;
            "error")
                # error message. Does not clear the screen
                # call format: message error "text to display"
                printf "\n%b\n\n" "$2"
                read -n 1 -s -p "Press any key..."
                ;;
            "question")
                # question
                # call format: if message question "question to ask?"; then...
                printf "\n%b\n\n" "$2"
                while read -p "[y/n]: " yn; do
                    case "$yn" in
                        [Yy]*)
                            return 0
                            ;;
                        [Nn]*)
                            return 1
                            ;;
                        *)
                            printf "Please type 'y' or 'n'\n"
                            ;;
                    esac
                done
                ;;
            "options")
                # Choose from two options
                # call format: if message options left_button_name right_button_name "which one do you want?"; then...
                printf "\n%b\n1: %b\n2: %b\n" "$4" "$3" "$2"
                while read -p "[1/2]: " option; do
                    case "$option" in
                        1*)
                            return 0
                            ;;
                        2*)
                            return 1
                            ;;
                        *)
                            printf "Please type '1' or '2'\n"
                            ;;
                    esac
                done
                ;;
            *)
                debug_print exit "Script Error: Invalid message type passed to the message function. Aborting."
                ;;
        esac
    fi
}

# MARK: progress_bar()
# Display a zenity progress bar that pulsates until its PID is killed.
# Takes a start or a stop argument, followed by a message string.
# 
# To call this function, use the following format: progress_bar [start|stop] "[string]".
# The first string argument should be either "start" or "stop".
# If "start" is specified, a second string argument contains the text to display to the user.
# If "stop" is specified, no second argument is used and the progress bar's PID is killed.
#
# This function does not verify whether or not start was called before stop.
progress_bar() {
    # This function expects at least one string argument
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The progress_bar function expects at least one string argument. Aborting."
    fi
    # If the first argument is start, a second argument is required
    if [ "$1" = "start" ] && [ -z "$2" ]; then
        debug_print exit "Script error:  The progress_bar function expects a second string argument when starting the progress bar. Aborting."
    fi

    # Don't do anything if not using zenity
    if [ "$use_zenity" -eq 0 ]; then
        return 0
    fi

    if [ "$1" = "start" ]; then
        # If another progress bar is already running, do nothing
        if [ -f "$tmp_dir/zenity_progress_bar_running" ]; then
            debug_print continue "Script error:  A progress_bar function instance is already running, but a new progress bar was called. This is not handled."
            return 0
        fi

        fifo="$tmp_dir/zenity_progress_fifo"
        pidfile="$tmp_dir/zenity_progress_bar_pid"
        runningflag="$tmp_dir/zenity_progress_bar_running"

        # Ensure no stale FIFO remains
        rm -f "$fifo" "$pidfile" 2>/dev/null || true
        mkfifo "$fifo" 2>/dev/null || {
            debug_print continue "Failed to create progress FIFO. Falling back to old progress behavior."
            touch "$runningflag"
            while [ -f "$runningflag" ]; do
                sleep 1
            done | zenity --progress --pulsate --no-cancel --auto-close --title="Falcon BMS Linux Helper" --text="$2" 2>/dev/null &
            trap 'progress_bar stop' SIGINT
            return 0
        }

        # Start zenity reading from the FIFO and keep a writable FD (3) open so other functions can write updates
        zenity --progress --pulsate --no-cancel --auto-close --title="Falcon BMS Linux Helper" --text="$2" < "$fifo" 2>/dev/null &
        echo "$!" > "$pidfile"

        # Open a write descriptor to the FIFO for updates (fd 3)
        exec 3>"$fifo" || true
        # Send initial text
        printf "# %s\n" "$2" >&3 2>/dev/null || true

        touch "$runningflag"
        trap 'progress_bar stop' SIGINT # catch sigint to cleanly kill the zenity progress window
    elif [ "$1" = "stop" ]; then
        fifo="$tmp_dir/zenity_progress_fifo"
        pidfile="$tmp_dir/zenity_progress_bar_pid"
        runningflag="$tmp_dir/zenity_progress_bar_running"

        # Stop the zenity progress window: close fd3, remove fifo and flag, and kill zenity if still running
        if [ -e /proc/$$/fd/3 ]; then
            exec 3>&- || true
        fi
        if [ -f "$pidfile" ]; then
            zenity_pid=$(cat "$pidfile" 2>/dev/null)
            if [ -n "$zenity_pid" ] && kill -0 "$zenity_pid" 2>/dev/null; then
                kill "$zenity_pid" 2>/dev/null || true
            fi
            rm -f "$pidfile" 2>/dev/null || true
        fi
        rm --interactive=never "$runningflag" 2>/dev/null
        rm -f "$fifo" 2>/dev/null || true
        trap - SIGINT # Remove the trap
    else
        debug_print exit "Script error:  The progress_bar function expects either 'start' or 'stop' as the first argument. Aborting."
    fi
}

# MARK: progress_update()
# Write a step/message to the existing zenity progress window. Accepts a single string.
progress_update() {
    if [ "$use_zenity" -eq 0 ]; then
        return 0
    fi
    if [ -z "$1" ]; then
        return 0
    fi
    fifo="$tmp_dir/zenity_progress_fifo"
    # Try writing to fd 3 first, fall back to writing directly to the FIFO
    if [ -e /proc/$$/fd/3 ]; then
        printf "# %s\n" "$1" >&3 2>/dev/null || true
        return 0
    fi
    if [ -p "$fifo" ]; then
        printf "# %s\n" "$1" > "$fifo" 2>/dev/null &
    fi
}

# MARK: menu()
# Display a menu to the user.
# Uses Zenity for a gui menu with a fallback to plain old text.
#
# How to call this function:
#
# Requires the following variables:
# - The array "menu_options" should contain the strings of each option.
# - The array "menu_actions" should contain function names to be called.
# - The strings "menu_text_zenity" and "menu_text_terminal" should contain
#   the menu description formatted for zenity and the terminal, respectively.
#   This text will be displayed above the menu options.
#   Zenity supports Pango Markup for text formatting.
# - The integer "menu_height" specifies the height of the zenity menu.
# - The string "menu_type" should contain either "radiolist" or "checklist".
# - The string "cancel_label" should contain the text of the cancel button.
#
# The final element in each array is expected to be a quit option.
#
# IMPORTANT: The indices of the elements in "menu_actions"
# *MUST* correspond to the indeces in "menu_options".
# In other words, it is expected that menu_actions[1] is the correct action
# to be executed when menu_options[1] is selected, and so on for each element.
#
# See MAIN at the bottom of this script for an example of generating a menu.
menu() {
    # Sanity checks
    if [ "${#menu_options[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'menu_options' was not set before calling the menu function. Aborting."
    elif [ "${#menu_actions[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'menu_actions' was not set before calling the menu function. Aborting."
    elif [ -z "$menu_text_zenity" ]; then
        debug_print exit "Script error: The string 'menu_text_zenity' was not set before calling the menu function. Aborting."
    elif [ -z "$menu_text_terminal" ]; then
        debug_print exit "Script error: The string 'menu_text_terminal' was not set before calling the menu function. Aborting."
    elif [ -z "$menu_height" ]; then
        debug_print exit "Script error: The string 'menu_height' was not set before calling the menu function. Aborting."
    elif [ "$menu_type" != "radiolist" ] && [ "$menu_type" != "checklist" ]; then
        debug_print exit "Script error: Unknown menu_type in menu() function. Aborting."
    elif [ -z "$cancel_label" ]; then
        debug_print exit "Script error: The string 'cancel_label' was not set before calling the menu function. Aborting."
    fi

    # Use Zenity if it is available
    if [ "$use_zenity" -eq 1 ]; then
        # Format the options array for Zenity by adding TRUE or FALSE to
        # indicate default selections. If `menu_default_choice` is set and
        # matches the start of a menu label, use that index as the default
        # selection. Otherwise fall back to selecting the first item.
        unset zen_options
        default_index=0
        if [ -n "${menu_default_choice:-}" ]; then
            for (( _j=0; _j<"${#menu_options[@]}"-1; _j++ )); do
                if [[ "${menu_options[_j]}" == "${menu_default_choice}"* ]]; then
                    default_index=$_j
                    break
                fi
            done
        fi

        for (( i=0; i<"${#menu_options[@]}"-1; i++ )); do
            if [ "$menu_type" = "radiolist" ]; then
                if [ "$i" -eq "$default_index" ]; then
                    zen_options+=("TRUE")
                else
                    zen_options+=("FALSE")
                fi
            else
                zen_options+=("FALSE")
            fi
            zen_options+=("${menu_options[i]}")
        done

        # Display the zenity radio button menu
        choice="$(zenity --list --"$menu_type" --width="510" --height="$menu_height" --text="$menu_text_zenity" --title="Falcon BMS Linux Helper" --hide-header --cancel-label "$cancel_label" --column="" --column="Option" "${zen_options[@]}")"

        # Match up choice with an element in menu_options
        matched="false"
        if [ "$menu_type" = "radiolist" ]; then
            # Loop through the options array to match the chosen option
            for (( i=0; i<"${#menu_options[@]}"; i++ )); do
                if [ "$choice" = "${menu_options[i]}" ]; then
                    # Execute the corresponding action for a radiolist menu
                    ${menu_actions[i]}
                    matched="true"
                    break
                fi
            done
        elif [ "$menu_type" = "checklist" ]; then
            # choice will be empty if no selection was made
            # Unfortunately, it's also empty when the user presses cancel
            # so we can't differentiate between those two states

            # Convert choice string to array elements for checklists
            IFS='|' read -r -a choices <<< "$choice"

            # Fetch the function to be called
            function_call="$(echo "${menu_actions[0]}" | awk '{print $1}')"

            # Loop through the options array to match the chosen option(s)
            unset arguments_array
            for (( i=0; i<"${#menu_options[@]}"; i++ )); do
                for (( j=0; j<"${#choices[@]}"; j++ )); do
                    if [ "${choices[j]}" = "${menu_options[i]}" ]; then
                        arguments_array+=("$(echo "${menu_actions[i]}" | awk '{print $2}')")
                        matched="true"
                    fi
                done
            done

            # Call the function with all matched elements as arguments
            if [ "$matched" = "true" ]; then
                $function_call "${arguments_array[@]}"
            fi
        fi

        # If no match was found, the user clicked cancel
        if [ "$matched" = "false" ]; then
            # Execute the last option in the actions array
            "${menu_actions[${#menu_actions[@]}-1]}"
        fi
    else
        # Use a text menu if Zenity is not available
        clear
        # Print the terminal menu text without an extra leading blank line.
        # Use %b so embedded \n sequences in the text are interpreted.
        printf "%b\n\n" "$menu_text_terminal"

        PS3="Enter selection number: "
        select choice in "${menu_options[@]}"
        do
            # Loop through the options array to match the chosen option
            matched="false"
            for (( i=0; i<"${#menu_options[@]}"; i++ )); do
                if [ "$choice" = "${menu_options[i]}" ]; then
                    clear
                    # Execute the corresponding action
                    ${menu_actions[i]}
                    matched="true"
                    break
                fi
            done

            # Check if we're done looping the menu
            if [ "$matched" = "true" ]; then
                # Match was found and actioned, so exit the menu
                break
            else
                # If no match was found, the user entered an invalid option
                printf "\nInvalid selection.\n"
                continue
            fi
        done
    fi
}

# MARK: menu_loop_done()
# Called when the user clicks cancel on a looping menu
# Causes a return to the main menu
menu_loop_done() {
    looping_menu="false"
}

# Remove the config subdir if it contains only the firstrun marker
cleanup_conf_if_only_firstrun() {
    target_dir="$conf_dir/$conf_subdir"
    if [ -d "$target_dir" ]; then
        # gather non-hidden entries
        shopt -s nullglob
        entries=("$target_dir"/*)
        shopt -u nullglob
        if [ "${#entries[@]}" -eq 1 ]; then
            if [ "$(basename "${entries[0]}")" = "$firstrun_conf" ]; then
                rm -r --interactive=never "$target_dir"
            fi
        fi
    fi
}

# MARK: getdirs()
# Get paths to the user's wine prefix, game directory, and a backup directory
# Returns 3 if the user was asked to select new directories
getdirs() {
    # Sanity checks
    if [ ! -d "$conf_dir" ]; then
        message error "Config directory not found. The Helper is unable to proceed.\n\n$conf_dir"
        return 1
    fi
    if [ ! -d "$conf_dir/$conf_subdir" ]; then
        mkdir -p "$conf_dir/$conf_subdir"
    fi

    # Initialize a return value
    retval=0

    # Check if the config files already exist
    if [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
        wine_prefix="$(cat "$conf_dir/$conf_subdir/$wine_conf")"
        if [ ! -d "$wine_prefix" ]; then
            debug_print continue "The saved wine prefix does not exist, ignoring."
            wine_prefix=""
            rm --interactive=never "${conf_dir:?}/$conf_subdir/$wine_conf"
        fi
    fi
    if [ -f "$conf_dir/$conf_subdir/$game_conf" ]; then
        game_path="$(cat "$conf_dir/$conf_subdir/$game_conf")"
        # Note: We check for the parent dir here because the game may not have been fully installed yet
        # which  means bms_base_dir may not yet have been created. But the parent RSI dir must exist
        if [ ! -d "$(dirname "$game_path")" ] || [ "$(basename "$game_path")" != "$bms_base_dir" ]; then
            debug_print continue "Unexpected game path found in config file, ignoring."
            game_path=""
            rm --interactive=never "${conf_dir:?}/$conf_subdir/$game_conf"
        fi
    fi

    # If we don't have the directory paths we need yet,
    # ask the user to provide them
    if [ -z "$wine_prefix" ] || [ -z "$game_path" ]; then
        message info "At the next screen, please select the directory where you installed Falcon BMS (your Wine prefix)\nIt will be remembered for future use.\n\nDefault install path: $bms_default_install_path"
        if [ "$use_zenity" -eq 1 ]; then
            # Using Zenity file selection menus
            # Get the wine prefix directory
            while [ -z "$wine_prefix" ]; do
                wine_prefix="$(zenity --file-selection --directory --title="Select your Falcon BMS Wine prefix directory" --filename="$bms_default_install_path" 2>/dev/null)"
                if [ "$?" -eq -1 ]; then
                    message error "An unexpected error has occurred. The Helper is unable to proceed."
                    return 1
                elif [ -z "$wine_prefix" ]; then
                    # User clicked cancel
                    message warning "Operation cancelled.\nNo changes have been made to your game."
                    return 1
                fi

                if ! message question "You selected:\n\n$wine_prefix\n\nIs this correct?"; then
                    wine_prefix=""
                fi
            done

            # Get the game path
            if [ -z "$game_path" ]; then
                if [ -d "$wine_prefix/$default_install_path" ]; then
                    # Default: prefix/drive_c/Program Files/Roberts Space Industries/StarCitizen
                    game_path="$wine_prefix/$default_install_path/$bms_base_dir"
                else
                    message info "Unable to detect the default game install path!\n\n$wine_prefix/$default_install_path/$bms_base_dir\n\nDid you change the install location in the RSI Setup?\nDoing that is generally a bad idea but, if you are sure you want to proceed,\nselect your '$bms_base_dir' game directory on the next screen"
                    while true; do
                        game_path="$(zenity --file-selection --directory --title="Select your Falcon BMS directory" --filename="$wine_prefix/$default_install_path" 2>/dev/null)"

                        if [ "$?" -eq -1 ]; then
                            message error "An unexpected error has occurred. The Helper is unable to proceed."
                            return 1
                        elif [ -z "$game_path" ]; then
                            # User clicked cancel or something else went wrong
                            message warning "Operation cancelled.\nNo changes have been made to your game."
                            return 1
                        elif [ "$(basename "$game_path")" != "$bms_base_dir" ]; then
                            message warning "You must select the base game directory named '$bms_base_dir'\n\nie. [prefix]/drive_c/Program Files/Roberts Space Industries/StarCitizen"
                        else
                            # All good
                            break
                        fi
                    done
                fi
            fi
        else
            # No Zenity, use terminal-based menus
            clear
            # Get the wine prefix directory
            if [ -z "$wine_prefix" ]; then
                printf "Enter the full path to your Falcon BMS Wine prefix directory (case sensitive)\n"
                printf "ie. %s\n" "$bms_default_install_path"
                while read -rp ": " wine_prefix; do
                    if [ ! -d "$wine_prefix" ]; then
                        printf "That directory is invalid or does not exist. Please try again.\n\n"
                    else
                        break
                    fi
                done
            fi

            # Get the game path
            if [ -z "$game_path" ]; then
                if [ -d "$wine_prefix/$default_install_path/s" ]; then
                    # Default: prefix/drive_c/Program Files/Roberts Space Industries/StarCitizen
                    game_path="$wine_prefix/$default_install_path/$bms_base_dir"
                else
                    printf "\nUnable to detect the default game install path!\nDid you change the install location in the RSI Setup?\nDoing that is generally a bad idea but, if you are sure you want to proceed...\n\n"
                    printf "Enter the full path to your %s installation directory (case sensitive)\n" "$bms_base_dir"
                    printf "ie. %s/drive_c/Program Files/Roberts Space Industries/StarCitizen\n" "$bms_default_install_path"
                    while read -rp ": " game_path; do
                        if [ ! -d "$game_path" ]; then
                            printf "That directory is invalid or does not exist. Please try again.\n\n"
                        elif [ "$(basename "$game_path")" != "$bms_base_dir" ]; then
                            printf "You must enter the full path to the directory named '%s'\n\n" "$bms_base_dir"
                        else
                            break
                        fi
                    done
                fi
            fi
        fi

        # Set a return code to indicate to other functions in this script that the user had to select new directories here
        retval=3
    fi

    # Save the paths to config files
    # If the selected game path implies a different BMS mode (internal vs public),
    # offer to switch modes so we use the correct config subdir.
    if [ -n "$game_path" ]; then
        selected_base="$(basename "$game_path")"
        if [ "$selected_base" = "Falcon BMS 4.38 (Internal)" ] && [ "$bms_mode" != "internal" ]; then
            if message question "You selected an internal Falcon BMS installation:\n\n$game_path\n\nbut the Helper is in public mode. Switch to internal mode and use the 'falcon-bms-internal' config folder?"; then
                set_bms_mode internal
                # ensure the new config subdir exists
                if [ ! -d "$conf_dir/$conf_subdir" ]; then
                    mkdir -p "$conf_dir/$conf_subdir"
                fi
            fi
        elif [ "$selected_base" = "Falcon BMS 4.38" ] && [ "$bms_mode" = "internal" ]; then
            if message question "You selected a public Falcon BMS installation:\n\n$game_path\n\nbut the Helper is in internal mode. Switch to public mode and use the 'falcon-bms' config folder?"; then
                set_bms_mode public
                if [ ! -d "$conf_dir/$conf_subdir" ]; then
                    mkdir -p "$conf_dir/$conf_subdir"
                fi
            fi
        fi
    fi

    if [ ! -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
        echo "$wine_prefix" > "$conf_dir/$conf_subdir/$wine_conf"
    fi
    if [ ! -f "$conf_dir/$conf_subdir/$game_conf" ]; then
        echo "$game_path" > "$conf_dir/$conf_subdir/$game_conf"
    fi

    return "$retval"
}

# MARK: get_current_runner()
# Populate `current_runner_path` and `current_runner_basename` based on persisted file or launch script
get_current_runner() {
    current_runner_path=""
    current_runner_basename=""
    launcher_winepath=""

    # Ensure wine_prefix and install_dir are available
    getdirs || return 1
    install_dir="${install_dir:-$wine_prefix}"

    # Prefer persisted selection in the install dir
    if [ -n "$install_dir" ] && [ -f "$install_dir/current_runner" ]; then
        persisted_runner="$(sed -n '1p' "$install_dir/current_runner" | tr -d '\r')"
        if [ -n "$persisted_runner" ] && [ -d "$persisted_runner" ]; then
            current_runner_path="$persisted_runner"
            current_runner_basename="$(basename "$persisted_runner")"
            if [ -x "$persisted_runner/files/bin/wine" ]; then
                launcher_winepath="$persisted_runner/files/bin"
            elif [ -x "$persisted_runner/bin/wine" ]; then
                launcher_winepath="$persisted_runner/bin"
            elif [ -x "$persisted_runner/wine" ]; then
                launcher_winepath="$persisted_runner"
            fi
            return 0
        fi
    fi

    # Fallback: inspect launch scripts in the prefix for proton_path or wine_path
    if [ -n "$wine_prefix" ] && [ -d "$wine_prefix" ]; then
        if [ -n "$wine_launch_script_name" ] && [ -f "$wine_prefix/$wine_launch_script_name" ]; then
            launch_script="$wine_prefix/$wine_launch_script_name"
        else
            for f in "$wine_prefix"/*; do
                if [ -f "$f" ] && (grep -q -e '^export proton_path=' -e '^proton_path=' "$f" 2>/dev/null || grep -q -e '^export wine_path=' -e '^wine_path=' "$f" 2>/dev/null); then
                    launch_script="$f"
                    break
                fi
            done
        fi
        if [ -n "$launch_script" ] && [ -f "$launch_script" ]; then
            launcher_path="$(grep -e '^export proton_path=' -e '^proton_path=' "$launch_script" | awk -F '=' '{print $2}' | tr -d '"')"
            if [ -z "$launcher_path" ]; then
                launcher_path="$(grep -e '^export wine_path=' -e '^wine_path=' "$launch_script" | awk -F '=' '{print $2}' | tr -d '"')"
            fi
            launcher_path="$(echo "$launcher_path" | sed -e 's/^ *"//' -e 's/" *$//' -e 's/^ *//; s/ *$//')"
            if [ -n "$launcher_path" ]; then
                if [ -x "$launcher_path/wine" ]; then
                    launcher_winepath="$launcher_path"
                    current_runner_path="$(dirname "$launcher_path")"
                elif [ -x "$launcher_path/files/bin/wine" ]; then
                    launcher_winepath="$launcher_path/files/bin"
                    current_runner_path="$launcher_path"
                elif [ -x "$launcher_path/bin/wine" ]; then
                    launcher_winepath="$launcher_path/bin"
                    current_runner_path="$launcher_path"
                else
                    current_runner_path="$launcher_path"
                fi
                current_runner_basename="$(basename "$current_runner_path")"
            fi
        fi
    fi

    if [ -z "$launcher_winepath" ] && [ -n "$current_runner_path" ]; then
        if [ -x "$current_runner_path/files/bin/wine" ]; then
            launcher_winepath="$current_runner_path/files/bin"
        elif [ -x "$current_runner_path/bin/wine" ]; then
            launcher_winepath="$current_runner_path/bin"
        elif [ -x "$current_runner_path/wine" ]; then
            launcher_winepath="$current_runner_path"
        fi
    fi
    return 0
}

# MARK: sync_mfd_joystick_script()
# Refresh an already-deployed companion helper next to the generated launcher.
sync_mfd_joystick_script() {
    install_dir="${install_dir:-$wine_prefix}"
    sync_mfd_joystick_status="skipped"
    sync_mfd_joystick_path=""

    if [ -z "$install_dir" ] || [ ! -d "$install_dir" ]; then
        return 0
    fi

    bundled_mfd_script="$SCRIPT_DIR/tools/mfd-joystick.py"
    installed_mfd_script="$install_dir/mfd-joystick.py"
    sync_mfd_joystick_path="$installed_mfd_script"

    if [ ! -f "$bundled_mfd_script" ]; then
        sync_mfd_joystick_status="missing-bundled"
        return 0
    fi

    if [ ! -f "$installed_mfd_script" ]; then
        sync_mfd_joystick_status="missing-installed"
        return 0
    fi

    bundled_mfd_version="$(sed -n 's/^MFD_JOYSTICK_VERSION = "\([^"]*\)"$/\1/p' "$bundled_mfd_script" | head -n1)"
    installed_mfd_version="$(sed -n 's/^MFD_JOYSTICK_VERSION = "\([^"]*\)"$/\1/p' "$installed_mfd_script" | head -n1)"

    if cmp -s "$bundled_mfd_script" "$installed_mfd_script"; then
        sync_mfd_joystick_status="current"
        debug_print continue "MFD helper beside launcher is already current${bundled_mfd_version:+ (v$bundled_mfd_version)}."
        return 0
    fi

    if cp "$bundled_mfd_script" "$installed_mfd_script"; then
        sync_mfd_joystick_status="updated"
        chmod +x "$installed_mfd_script" 2>/dev/null || true
        debug_print continue "Updated adjacent MFD helper at $installed_mfd_script${bundled_mfd_version:+ to v$bundled_mfd_version}${installed_mfd_version:+ from v$installed_mfd_version}."
    else
        sync_mfd_joystick_status="failed"
    fi

    return 0
}

# MARK: create_or_update_launch_script()
# Generate/update a per-prefix launch script.
# The script encapsulates runner/proton invocation so desktop files can call it directly.
create_or_update_launch_script() {
    # Resolve target prefix/install dir
    install_dir="${install_dir:-$wine_prefix}"
    if [ -z "$install_dir" ]; then
        return 1
    fi

    # Determine launcher executable path (prefer expected, fallback to search)
    launcher_exe_unix="$install_dir/drive_c/$bms_base_dir/Launcher/FalconBMS_Alternative_Launcher.exe"
    if [ ! -f "$launcher_exe_unix" ]; then
        detected_launcher="$(find "$install_dir/drive_c" -type f -name 'FalconBMS_Alternative_Launcher.exe' 2>/dev/null | head -n 1)"
        if [ -n "$detected_launcher" ]; then
            launcher_exe_unix="$detected_launcher"
        fi
    fi

    # Determine configured runner directory
    runner_dir=""
    if [ -f "$install_dir/current_runner" ]; then
        runner_dir="$(sed -n '1p' "$install_dir/current_runner" | tr -d '\r')"
    fi
    if [ -z "$runner_dir" ] && [ -f "$install_dir/$wine_launch_script_name" ]; then
        script_proton_path="$(grep -e '^export proton_path=' -e '^proton_path=' "$install_dir/$wine_launch_script_name" | awk -F '=' '{print $2}' | tr -d '\"')"
        script_wine_path="$(grep -e '^export wine_path=' -e '^wine_path=' "$install_dir/$wine_launch_script_name" | awk -F '=' '{print $2}' | tr -d '\"')"
        if [ -n "$script_proton_path" ] && [ -d "$script_proton_path" ]; then
            runner_dir="$script_proton_path"
        elif [ -n "$script_wine_path" ]; then
            # script_wine_path may point to .../bin
            if [ -d "$script_wine_path" ] && [ -x "$script_wine_path/wine" ]; then
                runner_dir="$(dirname "$script_wine_path")"
            fi
        fi
    fi

    # Derive proton_path and wine_path values for script
    proton_path=""
    wine_path=""
    if [ -n "$runner_dir" ] && [ -x "$runner_dir/proton" ]; then
        proton_path="$runner_dir"
    fi
    if [ -n "$runner_dir" ] && [ -x "$runner_dir/files/bin/wine" ]; then
        wine_path="$runner_dir/files/bin"
    elif [ -n "$runner_dir" ] && [ -x "$runner_dir/wine" ]; then
        wine_path="$runner_dir"
    elif [ -n "$runner_dir" ] && [ -x "$runner_dir/bin/wine" ]; then
        wine_path="$runner_dir/bin"
    else
        sys_wine="$(command -v wine 2>/dev/null || true)"
        if [ -n "$sys_wine" ]; then
            wine_path="$(dirname "$sys_wine")"
        fi
    fi

    launch_script_path="$install_dir/$wine_launch_script_name"
    cat > "$launch_script_path" <<EOF
#!/usr/bin/env bash

# Falcon BMS launcher generated by bms-helper.sh
# Inspired by community launch-script patterns.
# version: 1.14

############################################################################
# Environment
############################################################################
export WINEPREFIX="$install_dir"
SCRIPT_DIR="\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)"
launch_log="\$WINEPREFIX/bms-launch.log"

# Default to Proton. Change this to 0 to force Wine fallback.
export BMS_USE_PROTON_LAUNCHER=1

# Map Proton's expected pfx path to the root of the prefix natively to avoid split game installs
if [ -d "\$WINEPREFIX/drive_c" ]; then
    if [ -e "\$WINEPREFIX/pfx" ] && [ ! -L "\$WINEPREFIX/pfx" ]; then
        # Proton mistakenly created a split prefix directory. Move it aside.
        mv "\$WINEPREFIX/pfx" "\$WINEPREFIX/pfx.bak-\$(date +%s)" >> "\$launch_log" 2>&1 || true
    fi
    if [ ! -e "\$WINEPREFIX/pfx" ]; then
        (cd "\$WINEPREFIX" && ln -s . pfx >> "\$launch_log" 2>&1) || true
    fi
fi

export WINEDEBUG="\${WINEDEBUG:--all}"
unset SDL_VIDEODRIVER

# Launcher UI compatibility toggles (safe defaults for .NET/WPF launchers under Proton)
# Set to 0 to disable each behavior.
export BMS_LAUNCHER_UI_FIXES="\${BMS_LAUNCHER_UI_FIXES:-1}"
export BMS_LAUNCHER_INSTALL_FONTS="\${BMS_LAUNCHER_INSTALL_FONTS:-1}"
export BMS_LAUNCHER_FORCE_WINED3D="\${BMS_LAUNCHER_FORCE_WINED3D:-1}"

# Launch/perf toggles (safe defaults for modern Proton GE + Linux kernels)
# - GameMode defaults on if installed (CPU governor/scheduler hints)
# - MangoHud defaults off
# - Proton log defaults off to avoid extra disk I/O each launch
# - fsync/esync default on; set to 0 only for troubleshooting
export BMS_USE_GAMEMODE="\${BMS_USE_GAMEMODE:-1}"
export BMS_USE_MANGOHUD="\${BMS_USE_MANGOHUD:-0}"
export BMS_PROTON_LOG="\${BMS_PROTON_LOG:-0}"
export BMS_USE_FSYNC="\${BMS_USE_FSYNC:-1}"
export BMS_USE_ESYNC="\${BMS_USE_ESYNC:-1}"
export BMS_AUTO_LAUNCH_OPENTRACK="\${BMS_AUTO_LAUNCH_OPENTRACK:-0}"
export BMS_OPENTRACK_DELAY="\${BMS_OPENTRACK_DELAY:-3}"

if [ "\$BMS_USE_FSYNC" != "1" ]; then
    export PROTON_NO_FSYNC=1
    export WINEFSYNC=0
fi
if [ "\$BMS_USE_ESYNC" != "1" ]; then
    export PROTON_NO_ESYNC=1
    export WINEESYNC=0
fi

# Managed runner paths (updated by bms-helper)
export proton_path="$proton_path"
export wine_path="$wine_path"

# Optional helper-side MFD companion script locations.
helper_script_dir="\$SCRIPT_DIR"
python3_bin="\$(command -v python3 2>/dev/null || true)"
adjacent_mfd_registry_script="\$helper_script_dir/mfd-joystick.py"
mfd_joystick_script="\${BMS_MFD_JOYSTICK_SCRIPT:-}"
if [ -z "\$mfd_joystick_script" ]; then
    if [ -f "\$helper_script_dir/mfd-joystick.py" ]; then
        mfd_joystick_script="\$helper_script_dir/mfd-joystick.py"
    elif [ -f "\$helper_script_dir/tools/mfd-joystick.py" ]; then
        mfd_joystick_script="\$helper_script_dir/tools/mfd-joystick.py"
    fi
fi
if [ -n "\$mfd_joystick_script" ] && [ -z "\$python3_bin" ]; then
    echo "WARNING: mfd-joystick.py detected but python3 was not found. Disabling MFD helper integration." >> "\$launch_log"
    mfd_joystick_script=""
fi

# If OS wine fallback is explicitly requested, clear custom runner paths
if [ "\$1" = "--wine" ] || [ "\$1" = "wine" ]; then
    export proton_path=""
    export wine_path=""
fi

# When Proton is configured, prefer its own Wine binaries so registry and
# launcher operations use the same runtime view.
if [ -n "\$proton_path" ]; then
    if [ -x "\$proton_path/files/bin/wine" ]; then
        export wine_path="\$proton_path/files/bin"
    elif [ -x "\$proton_path/bin/wine" ]; then
        export wine_path="\$proton_path/bin"
    fi
fi

launcher_exe="\${BMS_LAUNCHER_EXE:-$launcher_exe_unix}"
bms_reg_path="HKLM\\Software\\Benchmark Sims\\$bms_base_dir"
bms_reg_path_wow="HKLM\\Software\\WOW6432Node\\Benchmark Sims\\$bms_base_dir"

############################################################################
# Helpers
############################################################################
run_wine() {
    if [ -n "\$wine_path" ] && [ -x "\$wine_path/wine" ]; then
        "\$wine_path/wine" "\$@"
        return \$?
    fi

    sys_wine="\$(command -v wine 2>/dev/null || true)"
    if [ -n "\$sys_wine" ] && [ -x "\$sys_wine" ]; then
        "\$sys_wine" "\$@"
        return \$?
    fi

    echo "No usable wine binary found." >&2
    return 1
}

run_with_launch_wrappers() {
    # Apply optional wrappers only for the actual game/launcher process.
    if [ "\$BMS_USE_GAMEMODE" = "1" ] && command -v gamemoderun >/dev/null 2>&1; then
        if [ "\$BMS_USE_MANGOHUD" = "1" ] && command -v mangohud >/dev/null 2>&1; then
            gamemoderun mangohud "\$@"
        else
            gamemoderun "\$@"
        fi
    elif [ "\$BMS_USE_MANGOHUD" = "1" ] && command -v mangohud >/dev/null 2>&1; then
        mangohud "\$@"
    else
        "\$@"
    fi
}

run_prefix_tricks_quiet() {
    local _pt_bin=""
    local _wt_bin=""
    local _appid=""

    _pt_bin="\$(command -v protontricks 2>/dev/null || true)"
    _wt_bin="\$(command -v winetricks 2>/dev/null || true)"
    _appid="\${BMS_PROTONTRICKS_APPID:-\${STEAM_APPID:-}}"

    # protontricks is Steam/APPID-oriented. Use it only when an app id is known.
    if [ -n "\$_appid" ] && [ -n "\$_pt_bin" ]; then
        WINEPREFIX="\$WINEPREFIX" WINE="\$wine_path/wine" WINESERVER="\$wine_path/wineserver" "\$_pt_bin" "\$_appid" "\$@"
        return \$?
    fi

    if [ -z "\$_wt_bin" ]; then
        return 1
    fi

    # For custom non-Steam Proton prefixes, winetricks is the correct interface.
    if [ -n "\$wine_path" ] && [ -d "\$wine_path" ]; then
        PATH="\$wine_path:\$PATH" WINEPREFIX="\$WINEPREFIX" "\$_wt_bin" -q "\$@"
    else
        WINEPREFIX="\$WINEPREFIX" "\$_wt_bin" -q "\$@"
    fi
}

run_wineserver_kill() {
    if [ -n "\$wine_path" ] && [ -x "\$wine_path/wineserver" ]; then
        "\$wine_path/wineserver" -k >/dev/null 2>&1 || true
    elif command -v wineserver >/dev/null 2>&1; then
        wineserver -k >/dev/null 2>&1 || true
    fi
}

sync_mfd_joystick_registry_if_present() {
    if [ -z "\$python3_bin" ] || [ ! -f "\$adjacent_mfd_registry_script" ]; then
        return 0
    fi

    wine_reg_bin=""
    if [ -n "\$wine_path" ] && [ -x "\$wine_path/wine" ]; then
        wine_reg_bin="\$wine_path/wine"
    else
        wine_reg_bin="\$(command -v wine 2>/dev/null || true)"
    fi

    if [ -z "\$wine_reg_bin" ]; then
        echo "WARNING: no usable wine binary found for MFD registry sync." >> "\$launch_log"
        return 0
    fi

    BMS_MFD_REG_WINE_BIN="\$wine_reg_bin" "\$python3_bin" "\$adjacent_mfd_registry_script" --sync-wine-registry "\$WINEPREFIX" >> "\$launch_log" 2>&1 || \
        echo "WARNING: failed to sync Wine joystick registry via \$adjacent_mfd_registry_script" >> "\$launch_log"
}

start_mfd_joystick_if_present() {
    if [ -z "\$mfd_joystick_script" ] || [ ! -f "\$mfd_joystick_script" ]; then
        return 0
    fi

    if pgrep -f "\$mfd_joystick_script" >/dev/null 2>&1; then
        echo "mfd_joystick=already_running script=\$mfd_joystick_script" >> "\$launch_log"
        return 0
    fi

    if [ -z "\$python3_bin" ]; then
        echo "WARNING: python3 is unavailable. Skipping MFD helper launch for script=\$mfd_joystick_script" >> "\$launch_log"
        return 0
    fi

    nohup "\$python3_bin" "\$mfd_joystick_script" >> "\$launch_log" 2>&1 &
    echo "mfd_joystick=started script=\$mfd_joystick_script python3=\$python3_bin" >> "\$launch_log"
}

monitor_mfd_joystick_lifecycle() {
    if [ -z "\$mfd_joystick_script" ] || [ ! -f "\$mfd_joystick_script" ]; then
        return 0
    fi

    (
        while true; do
            # Poll every 5 seconds for either the game or alternative launcher process.
            sleep 5

            if pgrep -fi 'Falcon BMS\.exe|FalconBMS_Alternative_Launcher\.exe' >/dev/null 2>&1; then
                continue
            fi

            # Neither Falcon process is running anymore, stop MFD helper instances.
            pkill -f "\$mfd_joystick_script" >/dev/null 2>&1 || true
            echo "mfd_joystick=stopped reason=no_falcon_processes script=\$mfd_joystick_script" >> "\$launch_log"
            break
        done
    ) >/dev/null 2>&1 &
}

sync_registry_view() {
    # Some installs only write BMS keys under WOW6432Node.
    # Mirror key values into HKLM\\Software\\Benchmark Sims\\... for apps that read 64-bit view.
    if run_wine reg query "\$bms_reg_path" >/dev/null 2>&1; then
        return 0
    fi
    if ! run_wine reg query "\$bms_reg_path_wow" >/dev/null 2>&1; then
        return 0
    fi

    for reg_name in baseDir curPatch curTheater curUpdate Key; do
        reg_value="\$(run_wine reg query "\$bms_reg_path_wow" /v "\$reg_name" 2>/dev/null | awk '/REG_SZ/{\$1="";\$2=""; sub(/^  */,""); sub(/\r\$/, ""); print; exit}')"
        if [ -n "\$reg_value" ]; then
            run_wine reg add "\$bms_reg_path" /v "\$reg_name" /t REG_SZ /d "\$reg_value" /f >/dev/null 2>&1 || true
        fi
    done
}

sync_registry_into_proton_pfx() {
    # Proton may use a separate compat prefix under WINEPREFIX/pfx.
    # Mirror Falcon registry values there so Proton-launched apps can find them.
    if [ ! -d "\$WINEPREFIX/pfx" ]; then
        return 0
    fi
    if [ -L "\$WINEPREFIX/pfx" ]; then
        return 0
    fi

    src_prefix="\$WINEPREFIX"
    dst_prefix="\$WINEPREFIX/pfx"
    if [ "\$src_prefix" = "\$dst_prefix" ]; then
        return 0
    fi

    for reg_name in baseDir curPatch curTheater curUpdate Key; do
        export WINEPREFIX="\$src_prefix"
        reg_value="\$(run_wine reg query "\$bms_reg_path" /v "\$reg_name" 2>/dev/null | awk '/REG_SZ/{\$1="";\$2=""; sub(/^  */,""); sub(/\r\$/, ""); print; exit}')"
        if [ -z "\$reg_value" ]; then
            reg_value="\$(run_wine reg query "\$bms_reg_path_wow" /v "\$reg_name" 2>/dev/null | awk '/REG_SZ/{\$1="";\$2=""; sub(/^  */,""); sub(/\r\$/, ""); print; exit}')"
        fi
        [ -z "\$reg_value" ] && continue

        export WINEPREFIX="\$dst_prefix"
        run_wine reg add "\$bms_reg_path" /v "\$reg_name" /t REG_SZ /d "\$reg_value" /f >/dev/null 2>&1 || true
        run_wine reg add "\$bms_reg_path_wow" /v "\$reg_name" /t REG_SZ /d "\$reg_value" /f >/dev/null 2>&1 || true
    done

    export WINEPREFIX="\$src_prefix"
}

sync_registry_for_proton_run() {
    if [ -z "\$proton_path" ] || [ ! -x "\$proton_path/proton" ]; then
        return 0
    fi

    compat_client_path="\${STEAM_COMPAT_CLIENT_INSTALL_PATH:-\$proton_path}"

    for reg_name in baseDir curPatch curTheater curUpdate Key; do
        # Read from current prefix view first
        reg_value="\$(run_wine reg query "\$bms_reg_path" /v "\$reg_name" 2>/dev/null | awk '/REG_SZ/{\$1="";\$2=""; sub(/^  */,""); sub(/\r\$/, ""); print; exit}')"
        if [ -z "\$reg_value" ]; then
            reg_value="\$(run_wine reg query "\$bms_reg_path_wow" /v "\$reg_name" 2>/dev/null | awk '/REG_SZ/{\$1="";\$2=""; sub(/^  */,""); sub(/\r\$/, ""); print; exit}')"
        fi
        [ -z "\$reg_value" ] && continue

        env WINEPREFIX="\$WINEPREFIX" \
            STEAM_COMPAT_DATA_PATH="\$WINEPREFIX" \
            STEAM_COMPAT_CLIENT_INSTALL_PATH="\$compat_client_path" \
            UMU_ID=0 \
            "\$proton_path/proton" run reg add "\$bms_reg_path" /v "\$reg_name" /t REG_SZ /d "\$reg_value" /f >/dev/null 2>&1 || true

        env WINEPREFIX="\$WINEPREFIX" \
            STEAM_COMPAT_DATA_PATH="\$WINEPREFIX" \
            STEAM_COMPAT_CLIENT_INSTALL_PATH="\$compat_client_path" \
            UMU_ID=0 \
            "\$proton_path/proton" run reg add "\$bms_reg_path_wow" /v "\$reg_name" /t REG_SZ /d "\$reg_value" /f >/dev/null 2>&1 || true
    done
}

ensure_wine_vr_key() {
    # wineopenxr.dll uses RegOpenKeyExA on HKCU\\Software\\Wine\\VR to read
    # WiVRn's required Vulkan extension lists. This key is normally written by
    # steam_helper (requires Steam running); without it the OpenXR session init
    # fails with XR_ERROR_RUNTIME_FAILURE (-6). Pre-populate it so VR works
    # with umu-run without Steam.
    if [ -z "\$proton_path" ] || [ ! -x "\$proton_path/proton" ]; then
        return 0
    fi
    local compat_client_path="\${STEAM_COMPAT_CLIENT_INSTALL_PATH:-\$proton_path}"
    # Write a Windows .reg file to drive_c/ (visible as C:\\ inside Wine),
    # then import it with regedit in one proton invocation.
    local reg_file="\$WINEPREFIX/drive_c/wivrn_vr_init.reg"
    # Auto-detect VR-capable GPU (prefer discrete over integrated).
    # wineopenxr reads openxr_vulkan_device_vid/pid to select the GPU;
    # without them init fails with status 0x2 (key not found).
    local _vk_vid="" _vk_pid=""
    if ! command -v vulkaninfo >/dev/null 2>&1; then
        echo "WARNING: vulkaninfo not found. Install vulkan-tools for GPU auto-detection." >> "\$launch_log"
    fi
    if command -v vulkaninfo >/dev/null 2>&1; then
        # Pick the first DISCRETE_GPU; fall back to first device.
        eval "\$(vulkaninfo --summary 2>/dev/null | awk '
            /vendorID/{vid=\$3}
            /deviceID/{did=\$3}
            /DISCRETE_GPU/{print "_vk_vid=" vid " _vk_pid=" did; found=1; exit}
            END{if(!found && vid) print "_vk_vid=" vid " _vk_pid=" did}
        ')"
    fi
    # Pad to 4-hex-digit dwords for the .reg file (strip 0x prefix).
    local vid_dword="\$(printf '%08x' "\${_vk_vid:-0}" 2>/dev/null)"
    local pid_dword="\$(printf '%08x' "\${_vk_pid:-0}" 2>/dev/null)"
    cat > "\$reg_file" <<REGEOF
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\VR]
"openxr_vulkan_instance_extensions"="VK_KHR_external_fence_capabilities VK_KHR_external_memory_capabilities VK_KHR_external_semaphore_capabilities VK_KHR_get_physical_device_properties2"
"openxr_vulkan_device_extensions"="VK_KHR_dedicated_allocation VK_KHR_external_fence VK_KHR_external_memory VK_KHR_external_semaphore VK_KHR_get_memory_requirements2 VK_KHR_image_format_list VK_KHR_external_memory_fd VK_KHR_external_semaphore_fd VK_KHR_external_fence_fd"
"state"=dword:00000001
"is_hmd_present"=dword:00000001
"openxr_vulkan_device_vid"=dword:\$vid_dword
"openxr_vulkan_device_pid"=dword:\$pid_dword
REGEOF
    env WINEPREFIX="\$WINEPREFIX" \\
        STEAM_COMPAT_DATA_PATH="\$WINEPREFIX" \\
        STEAM_COMPAT_CLIENT_INSTALL_PATH="\$compat_client_path" \\
        UMU_ID=0 \\
        "\$proton_path/proton" run regedit /s "C:\\\\wivrn_vr_init.reg" >/dev/null 2>&1 || true
    rm -f "\$reg_file"
}

ensure_wivrn_runtime_json() {
    # The pressure-vessel container cannot see host system paths like
    # /usr/lib/wivrn/. Build a custom XR runtime JSON under \$WINEPREFIX that
    # uses an absolute path under \$HOME, which IS accessible in the container.
    local xr_json_out="\$WINEPREFIX/xr-wivrn-runtime.json"
    local home_lib="\$HOME/.local/lib/wivrn/libopenxr_wivrn.so"
    # Search common distro paths for the system WiVRn library.
    local sys_lib=""
    local _search_path
    for _search_path in \\
        /usr/lib/wivrn/libopenxr_wivrn.so \\
        /usr/lib/x86_64-linux-gnu/wivrn/libopenxr_wivrn.so \\
        /usr/lib64/wivrn/libopenxr_wivrn.so \\
        /usr/local/lib/wivrn/libopenxr_wivrn.so; do
        if [ -f "\$_search_path" ]; then
            sys_lib="\$_search_path"
            break
        fi
    done
    # Keep the HOME copy in sync with the system library.
    if [ -n "\$sys_lib" ] && { [ ! -f "\$home_lib" ] || [ "\$sys_lib" -nt "\$home_lib" ]; }; then
        mkdir -p "\$HOME/.local/lib/wivrn"
        cp -p "\$sys_lib" "\$home_lib" 2>/dev/null || true
    fi
    if [ ! -f "\$home_lib" ]; then
        return 1  # No WiVRn library found; caller falls back to system JSON
    fi
    printf '{\\n    "file_format_version": "1.0.0",\\n    "runtime": {\\n        "name": "WiVRn",\\n        "library_path": "%s"\\n    }\\n}\\n' "\$home_lib" > "\$xr_json_out"
    echo "\$xr_json_out"
}

check_dotnet48() {
    # .NET Framework 4.8 release key threshold (Windows 10 May 2019 update and later)
    min_release=528040
    dotnet_release=""

    dotnet_release="\$(run_wine reg query 'HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full' /v Release 2>/dev/null | awk '/REG_DWORD/{print \$3; exit}')"
    if [ -z "\$dotnet_release" ]; then
        dotnet_release="\$(run_wine reg query 'HKLM\\Software\\WOW6432Node\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full' /v Release 2>/dev/null | awk '/REG_DWORD/{print \$3; exit}')"
    fi

    if [ -z "\$dotnet_release" ]; then
        echo "WARNING: .NET Framework 4.8 was not detected in this prefix." >> "\$launch_log"
        echo "         Install dotnet48 (for example via protontricks/winetricks) if your launcher requires it." >> "\$launch_log"
        return 1
    fi

    # Sanitize output to a numeric token before arithmetic handling.
    dotnet_release_token="\$(echo "\$dotnet_release" | grep -Eo '0x[0-9A-Fa-f]+|[0-9]+' | head -n1)"
    if [ -z "\$dotnet_release_token" ]; then
        echo "WARNING: Could not parse .NET release value: '\$dotnet_release'" >> "\$launch_log"
        echo "         Your launcher may fail until dotnet48 is installed in this prefix." >> "\$launch_log"
        return 1
    fi

    if echo "\$dotnet_release_token" | grep -qi '^0x'; then
        dotnet_release_dec=\$((dotnet_release_token))
    else
        dotnet_release_dec="\$dotnet_release_token"
    fi

    if [ "\$dotnet_release_dec" -lt "\$min_release" ]; then
        echo "WARNING: Detected .NET release key \$dotnet_release_dec, expected >= \$min_release for .NET 4.8." >> "\$launch_log"
        echo "         Your launcher may fail until dotnet48 is installed in this prefix." >> "\$launch_log"
        return 1
    fi

    return 0
}

ensure_launcher_ui_fixes() {
    if [ "\$BMS_LAUNCHER_UI_FIXES" != "1" ]; then
        return 0
    fi

    # Prevent WPF hardware acceleration issues (black windows/artifacts under Proton + DXVK).
    run_wine reg add 'HKCU\\Software\\Microsoft\\Avalon.Graphics' /v DisableHWAcceleration /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true

    # Keep launcher text metrics predictable to reduce overlap/clipping on some setups.
    run_wine reg add 'HKCU\\Control Panel\\Desktop' /v LogPixels /t REG_DWORD /d 96 /f >/dev/null 2>&1 || true

    # Install common Windows fonts/runtime bits once through protontricks when an
    # APPID is available, otherwise fall back to winetricks for this custom prefix.
    if [ "\$BMS_LAUNCHER_INSTALL_FONTS" = "1" ]; then
        fontfix_marker="\$WINEPREFIX/.bms-launcher-fontfixes-v1"
        if [ ! -f "\$fontfix_marker" ]; then
            if run_prefix_tricks_quiet corefonts tahoma gdiplus >> "\$launch_log" 2>&1; then
                touch "\$fontfix_marker" 2>/dev/null || true
            else
                echo "WARNING: protontricks/winetricks was not found or failed; skipping automatic font/runtime fixes." >> "\$launch_log"
                echo "         Install winetricks for custom prefixes, or set BMS_PROTONTRICKS_APPID for protontricks-backed installs, then run once with BMS_LAUNCHER_INSTALL_FONTS=1 to retry." >> "\$launch_log"
            fi
        fi
    fi
}

############################################################################
# Subcommands (maintenance)
############################################################################
sync_mfd_joystick_registry_if_present

detect_opentrack_exe() {
    opentrack_exe=""

    if [ "\$BMS_AUTO_LAUNCH_OPENTRACK" != "1" ]; then
        return 0
    fi

    default_opentrack_exe="\$WINEPREFIX/drive_c/Program Files (x86)/opentrack/opentrack.exe"
    if [ -f "\$default_opentrack_exe" ]; then
        opentrack_exe="\$default_opentrack_exe"
        return 0
    fi

    default_opentrack_dir="\$WINEPREFIX/drive_c/Program Files (x86)"
    if [ -d "\$default_opentrack_dir" ]; then
        opentrack_exe="\$(find "\$default_opentrack_dir" -maxdepth 3 -type f -iname 'opentrack.exe' 2>/dev/null | head -n 1)"
    fi
}

launch_opentrack_if_present() {
    detect_opentrack_exe

    if [ -z "\$opentrack_exe" ] || [ ! -f "\$opentrack_exe" ]; then
        return 0
    fi

    if pgrep -fi '(^|[[:space:]\\/])opentrack\\.exe([[:space:]]|$)' >/dev/null 2>&1; then
        echo "opentrack=already_running exe=\$opentrack_exe" >> "\$launch_log"
        return 0
    fi

    opentrack_dir="\$(dirname "\$opentrack_exe")"
    opentrack_name="\$(basename "\$opentrack_exe")"

    # Use Wine's start helper so OpenTrack detaches immediately instead of
    # occupying the same Proton launch path as the Falcon launcher.
    (
        cd "\$opentrack_dir" || exit 1
        run_wine start /d "\$opentrack_dir" /b "\$opentrack_name" >> "\$launch_log" 2>&1
    ) >/dev/null 2>&1 &
    echo "opentrack=started runtime=wine-start exe=\$opentrack_exe" >> "\$launch_log"
}

launch_opentrack_after_falcon_start() {
    if [ "\$BMS_AUTO_LAUNCH_OPENTRACK" != "1" ]; then
        return 0
    fi

    (
        opentrack_delay="\$BMS_OPENTRACK_DELAY"
        case "\$opentrack_delay" in
            ''|*[!0-9]*) opentrack_delay=3 ;;
        esac

        attempts=0
        while [ "\$attempts" -lt 30 ]; do
            if pgrep -fi 'Falcon BMS\.exe|FalconBMS_Alternative_Launcher\.exe' >/dev/null 2>&1; then
                if [ "\$opentrack_delay" -gt 0 ]; then
                    echo "opentrack=waiting delay=\${opentrack_delay}s reason=falcon_process_detected" >> "\$launch_log"
                    sleep "\$opentrack_delay"
                fi
                launch_opentrack_if_present
                exit 0
            fi
            attempts=\$((attempts + 1))
            sleep 1
        done

        echo "opentrack=skipped reason=no_falcon_process_detected" >> "\$launch_log"
    ) >/dev/null 2>&1 &
}

case "\$1" in
    shell)
        echo "Entering Wine prefix shell. Type 'exit' when done."
        if [ -n "\$wine_path" ]; then
            export PATH="\$wine_path:\$PATH"
        fi
        cd "\$WINEPREFIX" || exit 1
        /usr/bin/env bash --norc
        exit 0
        ;;
    config)
        run_wine winecfg
        exit \$?
        ;;
    controllers)
        run_wine control joy.cpl
        exit \$?
        ;;
esac

############################################################################
# Launch
############################################################################
if [ ! -f "\$launcher_exe" ]; then
    echo "Launcher executable not found: \$launcher_exe" >&2
    exit 1
fi

# Clear stale wine processes before launch
run_wineserver_kill

# Ensure expected BMS registry path exists for both 32-bit and 64-bit views
sync_registry_view
sync_registry_into_proton_pfx
sync_registry_for_proton_run

# Ensure HKCU\\Software\\Wine\\VR exists so wineopenxr.dll can cache Vulkan extensions
ensure_wine_vr_key

# Warn in the launch log if .NET 4.8 is missing/outdated for launcher apps that require it
check_dotnet48 || true

# Apply launcher-focused rendering/font fixes before process start
ensure_launcher_ui_fixes

# Ensure relative paths resolve from launcher directory
launcher_dir="\$(dirname "\$launcher_exe")"
if [ -d "\$launcher_dir" ]; then
    cd "\$launcher_dir" || true
fi

# Proton is preferred by default. Explicit launch mode can be selected with:
#   --proton (force Proton)
#   --wine   (force Wine)
#   --auto   (use default/env behavior)
# Env overrides:
#   BMS_USE_PROTON_LAUNCHER=0|1
#   BMS_ALLOW_WINE_FALLBACK=0|1
requested_mode="auto"
case "\$1" in
    --proton|proton)
        requested_mode="proton"
        ;;
    --wine|wine)
        requested_mode="wine"
        ;;
    --auto|auto|"")
        requested_mode="auto"
        ;;
esac

# Default to Proton first; if unavailable we'll log and fall back to Wine.
default_proton_mode=1
proton_available=0
if [ -n "\$proton_path" ] && [ -x "\$proton_path/proton" ]; then
    proton_available=1
fi

mode_source="default"
use_proton_launcher="\$default_proton_mode"
if [ -n "\${BMS_USE_PROTON_LAUNCHER+x}" ]; then
    use_proton_launcher="\$BMS_USE_PROTON_LAUNCHER"
    mode_source="env"
fi

if [ "\$requested_mode" = "proton" ]; then
    use_proton_launcher=1
    mode_source="cli"
elif [ "\$requested_mode" = "wine" ]; then
    use_proton_launcher=0
    mode_source="cli"
fi

# Normalize values to 0/1 for predictable behavior and logs.
if [ "\$use_proton_launcher" != "1" ]; then
    use_proton_launcher=0
fi
allow_wine_fallback="\${BMS_ALLOW_WINE_FALLBACK:-0}"
if [ "\$allow_wine_fallback" != "1" ]; then
    allow_wine_fallback=0
fi

echo "=== \$(date '+%Y-%m-%d %H:%M:%S') bms-launcher start (requested_mode=\$requested_mode source=\$mode_source proton_mode=\$use_proton_launcher proton_available=\$proton_available fallback=\$allow_wine_fallback) ===" >> "\$launch_log"
echo "runner_paths proton_path=\$proton_path wine_path=\$wine_path" >> "\$launch_log"

# Start optional helper processes after the final launch mode is known.
start_mfd_joystick_if_present
monitor_mfd_joystick_lifecycle
launch_opentrack_after_falcon_start

if [ "\$use_proton_launcher" = "1" ] && [ "\$proton_available" = "1" ]; then
    runner_root="\$proton_path"
    # Keep Proton launch independent from any local Steam installation.
    # Use an explicit override only if the user provides one.
    compat_client_path="\${STEAM_COMPAT_CLIENT_INSTALL_PATH:-\$runner_root}"

    _umu_bin="\$(command -v umu-run 2>/dev/null)"
    # Use umu-run by default when available: it always sets up the pressure-vessel
    # container which is required for VR (wineopenxr socket access).
    # Set BMS_UMU_LAUNCH=0 to force plain Proton instead.
    if [ -n "\$_umu_bin" ] && [ "\${BMS_UMU_LAUNCH:-1}" != "0" ]; then
        echo "runner_selected=umu umu_bin=\$_umu_bin proton_path=\$proton_path" >> "\$launch_log"
        # PRESSURE_VESSEL_FILESYSTEMS_RW exposes the WiVRn socket to the container.
        # XR_RUNTIME_JSON points wineopenxr to the active OpenXR runtime.
        # Use caller-provided values if set, otherwise fall back to WiVRn defaults.
        _wivrn_socket="\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}/wivrn/comp_ipc"
        _wivrn_lib_dir="\$HOME/.local/lib/wivrn"
        _pv_fs_rw="\${PRESSURE_VESSEL_FILESYSTEMS_RW:-\$_wivrn_socket:\$_wivrn_lib_dir}"
        if [ -z "\${XR_RUNTIME_JSON:-}" ]; then
            _xr_json="\$(ensure_wivrn_runtime_json || echo "\$HOME/.config/openxr/1/active_runtime.json")"
        else
            _xr_json="\$XR_RUNTIME_JSON"
        fi
        echo "umu_env XR_RUNTIME_JSON=\$_xr_json PRESSURE_VESSEL_FILESYSTEMS_RW=\$_pv_fs_rw" >> "\$launch_log"
        run_with_launch_wrappers env GAMEID=0 \
            PROTONPATH="\$proton_path" \
            STEAM_COMPAT_DATA_PATH="\$WINEPREFIX" \
            WINEPREFIX="\$WINEPREFIX" \
            XR_RUNTIME_JSON="\$_xr_json" \
            PRESSURE_VESSEL_FILESYSTEMS_RW="\$_pv_fs_rw" \
            "\$_umu_bin" "\$launcher_exe" \${BMS_EXTRA_ARGS} >> "\$launch_log" 2>&1
        proton_exit=\$?
    else
        echo "runner_selected=proton proton_bin=\$proton_path/proton compat_client_path=\$compat_client_path" >> "\$launch_log"
        run_with_launch_wrappers env WINEPREFIX="\$WINEPREFIX" \
            STEAM_COMPAT_DATA_PATH="\$WINEPREFIX" \
            STEAM_COMPAT_CLIENT_INSTALL_PATH="\$compat_client_path" \
            UMU_ID=0 \
            PROTON_LOG="\$BMS_PROTON_LOG" \
            PROTON_USE_WINED3D="\$BMS_LAUNCHER_FORCE_WINED3D" \
            "\$proton_path/proton" run "\$(basename "\$launcher_exe")" \${BMS_EXTRA_ARGS} >> "\$launch_log" 2>&1
        proton_exit=\$?
    fi
    echo "proton_exit_code=\$proton_exit" >> "\$launch_log"
    if [ "\$proton_exit" -eq 0 ]; then
        exit 0
    fi

    if [ "\$allow_wine_fallback" != "1" ]; then
        echo "Proton launch failed with code \$proton_exit. Wine fallback disabled." >> "\$launch_log"
        exit \$proton_exit
    fi

    echo "Proton launch failed with code \$proton_exit. Falling back to wine." >> "\$launch_log"
fi

if [ "\$use_proton_launcher" = "1" ] && [ "\$proton_available" != "1" ]; then
    echo "Proton was requested but no valid proton binary was found. Falling back to wine." >> "\$launch_log"
fi

wine_bin="system:wine"
if [ -n "\$wine_path" ] && [ -x "\$wine_path/wine" ]; then
    wine_bin="\$wine_path/wine"
elif command -v wine >/dev/null 2>&1; then
    wine_bin="\$(command -v wine)"
fi
echo "runner_selected=wine wine_bin=\$wine_bin" >> "\$launch_log"

run_with_launch_wrappers run_wine "\$(basename "\$launcher_exe")" \${BMS_EXTRA_ARGS} >> "\$launch_log" 2>&1
wine_exit=\$?
echo "wine_exit_code=\$wine_exit" >> "\$launch_log"
exit \$wine_exit
EOF

    chmod +x "$launch_script_path" 2>/dev/null || true
    sync_mfd_joystick_script || true
    return 0
}

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
    if [ -n "$install_dir" ] && [ -d "$install_dir" ]; then
        icon_prefix_path="$install_dir/bms-launcher.png"
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
    if [ "$mapcount" -ge 16777216 ]; then
        # All good
        preflight_pass+=("vm.max_map_count is set to $mapcount.")
    elif awk '
        /^[[:space:]]*#/ { next }
        match($0, /^[[:space:]]*vm\.max_map_count[[:space:]]*=[[:space:]]*([0-9]+)/, m) {
            if (m[1] >= 16777216) found=1
        }
        END { exit(found ? 0 : 1) }
    ' /etc/sysctl.conf /etc/sysctl.d/* 2>/dev/null; then
        # Was it supposed to have been set by sysctl?
        preflight_fail+=("vm.max_map_count is configured to at least 16777216 but the setting has not been loaded by your system.")
        # Add the function that will be called to change the configuration
        preflight_action_funcs+=("mapcount_once")

        # Add info for manually changing the setting
        preflight_manual+=("To change vm.max_map_count until the next reboot, run:\nsudo sysctl -w vm.max_map_count=16777216")
    else
        # The setting should be changed
        preflight_fail+=("vm.max_map_count is $mapcount\nand should be set to at least 16777216\nto give the game access to sufficient memory.")
        # Add the function that will be called to change the configuration
        preflight_action_funcs+=("mapcount_set")

        # Add info for manually changing the setting
        if [ -d "/etc/sysctl.d" ]; then
            # Newer versions of sysctl
            preflight_manual+=("To change vm.max_map_count permanently, add the following line to\n'/etc/sysctl.d/99-starcitizen-max_map_count.conf' and reload with 'sudo sysctl --system'\n    vm.max_map_count = 16777216\n\nOr, to change vm.max_map_count temporarily until next boot, run:\n    sudo sysctl -w vm.max_map_count=16777216")
        else
            # Older versions of sysctl
            preflight_manual+=("To change vm.max_map_count permanently, add the following line to\n'/etc/sysctl.conf' and reload with 'sudo sysctl -p':\n    vm.max_map_count = 16777216\n\nOr, to change vm.max_map_count temporarily until next boot, run:\n    sudo sysctl -w vm.max_map_count=16777216")
        fi
    fi
}

# MARK: mapcount_set()
# Set vm.max_map_count
mapcount_set() {
    if [ -d "/etc/sysctl.d" ]; then
        # Newer versions of sysctl
        preflight_root_actions+=('printf "\n# Added by bms-helper:\nvm.max_map_count = 16777216\n" > /etc/sysctl.d/99-starcitizen-max_map_count.conf && sysctl --quiet --system')
        preflight_fix_results+=("The vm.max_map_count configuration has been added to:\n/etc/sysctl.d/99-starcitizen-max_map_count.conf")
    else
        # Older versions of sysctl
        preflight_root_actions+=('printf "\n# Added by bms-helper:\nvm.max_map_count = 16777216" >> /etc/sysctl.conf && sysctl -p')
        preflight_fix_results+=("The vm.max_map_count configuration has been added to:\n/etc/sysctl.conf")
    fi

    # Verify that the setting took effect
    preflight_followup+=("mapcount_confirm")
}

# MARK: mapcount_once()
# Sets vm.max_map_count for the current session only
mapcount_once() {
    preflight_root_actions+=('sysctl -w vm.max_map_count=16777216')
    preflight_fix_results+=("vm.max_map_count was changed until the next boot.")
    preflight_followup+=("mapcount_confirm")
}

# MARK: mapcount_confirm()
# Check if setting vm.max_map_count was successful
mapcount_confirm() {
    if [ "$(cat /proc/sys/vm/max_map_count)" -lt 16777216 ]; then
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
            preflight_manual+=("To change your open file descriptors limit, add the following to\n'/etc/systemd/system.conf.d/99-starcitizen-filelimit.conf':\n\n[Manager]\nDefaultLimitNOFILE=524288")
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
        preflight_root_actions+=('mkdir -p /etc/systemd/system.conf.d && printf "[Manager]\n# Added by bms-helper:\nDefaultLimitNOFILE=524288\n" > /etc/systemd/system.conf.d/99-starcitizen-filelimit.conf && systemctl daemon-reexec')
        preflight_fix_results+=("The open files limit configuration has been added to:\n/etc/systemd/system.conf.d/99-starcitizen-filelimit.conf")
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

############################################################################
######## begin download functions ##########################################
############################################################################

# MARK: download_manage()
# Manage downloads. Called by a dedicated download type manage function, ie runner_manage()
#
# This function expects the following variables to be set:
#
# - The string download_sources is a formatted array containing the URLs
#   of items to download. It should be pointed to the appropriate
#   array set at the top of the script using indirect expansion.
#   See runner_sources at the top and runner_manage() for examples.
# - The string download_dir should contain the location where the
#   downloaded item will be installed to.
# - The string "download_menu_heading" should contain the type of item
#   being downloaded.  It will appear in the menu heading.
# - The string "download_menu_description" should contain a description of
#   the item being downloaded.  It will appear in the menu subheading.
# - The integer "download_menu_height" specifies the height of the zenity menu.
#
# This function also expects one string argument containing the type of item to
# be downloaded.  ie. runner or dxvk.
#
# See runner_manage() for a configuration example.
download_manage() {
    # This function expects a string to be passed as an argument
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The download_manage function expects a string argument. Aborting."
    fi

    # Sanity checks
    if [ -z "$download_sources" ]; then
        debug_print exit "Script error: The string 'download_sources' was not set before calling the download_manage function. Aborting."
    elif [ -z "$download_dir" ]; then
        debug_print exit "Script error: The string 'download_dir' was not set before calling the download_manage function. Aborting."
    elif [ -z "$download_menu_heading" ]; then
        debug_print exit "Script error: The string 'download_menu_heading' was not set before calling the download_manage function. Aborting."
    elif [ -z "$download_menu_description" ]; then
        debug_print exit "Script error: The string 'download_menu_description' was not set before calling the download_manage function. Aborting."
    elif [ -z "$download_menu_height" ]; then
        debug_print exit "Script error: The string 'download_menu_height' was not set before calling the download_manage function. Aborting."
    fi

    # Get the type of item we're downloading from the function arguments
    download_type="$1"

    # The download management menu will loop until the user cancels
    looping_menu="true"
    while [ "$looping_menu" = "true" ]; do
        # Configure the menu
        menu_text_zenity="<b><big>Manage Your $download_menu_heading</big>\n\n$download_menu_description</b>\n\nYou may choose from the following options:"
        menu_text_terminal="Manage Your $download_menu_heading\n\n$download_menu_description\nYou may choose from the following options:"
        menu_text_height="$download_menu_height"
        menu_type="radiolist"

        # Configure the menu options
        delete="Remove an installed $download_type"
        back="Return to the main menu"
        unset menu_options
        unset menu_actions

        # Initialize success
        unset post_download_required

        # Set variables for the current wine runner configured in the launch script
        if [ "$download_type" = "runner" ] || [ "$download_type" = "proton" ]; then
            get_current_runner
        fi

        # Loop through the download_sources array and create a menu item
        # for each one. Even numbered elements will contain the item name
        for (( i=0; i<"${#download_sources[@]}"; i=i+2 )); do
            # Set the options to be displayed in the menu
            menu_options+=("Install a $download_type from ${download_sources[i]}")
            # Set the corresponding functions to be called for each of the options
            menu_actions+=("download_select_install $i")
        done

        if [ "$download_type" = "proton" ]; then
            collect_external_proton_runners
            if [ "${#external_proton_paths[@]}" -gt 0 ]; then
                menu_options+=("Select an existing Proton runner (Steam / OS)")
                menu_actions+=("select_existing_proton_runner_menu")
            fi
        fi

        # Complete the menu by adding options to uninstall an item
        # or go back to the previous menu
        menu_options+=("$delete" "$back")
        menu_actions+=("download_select_delete" "menu_loop_done")

        # Calculate the total height the menu should be
        # menu_option_height = pixels per menu option
        # #menu_options[@] = number of menu options
        # menu_text_height = height of the title/description text
        # menu_text_height_zenity4 = added title/description height for libadwaita bigness
        menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"

        # Set the label for the cancel button
        cancel_label="Go Back"

        # Call the menu function.  It will use the options as configured above
        menu

        # Perform post-download actions and display messages or instructions
        if [ -n "$post_download_required" ] && [ "$post_download_type" != "none" ]; then
            post_download
        fi
    done
}

# MARK: runner_manage()
# Configure the download_manage function for wine runners
runner_manage() {
    # We'll want to instruct the user on how to use the downloaded runner
    # Valid options are "none" or "configure-wine"
    post_download_type="configure-wine"

    # Use indirect expansion to point download_sources
    # to the runner_sources array set at the top of the script
    declare -n download_sources=runner_sources

    # Get directories so we know where the wine prefix is
    getdirs

    # Set variables for the latest default runner
    set_latest_default_runner
    # Sanity check
    if [ "$?" -eq 1 ]; then
        message error "Could not fetch the latest default wine runner.  The Github API may be down or rate limited."
        return 1
    fi

    # Set the download directory for wine runners
    download_dir="$wine_prefix/runners"

    # Configure the text displayed in the menus
    download_menu_heading="Proton Runners"
    download_menu_description="The runners listed below are Proton/Proton-GE builds created for Falcon BMS"
    download_menu_height="320"

    # Set the string sed will match against when editing the launch script
    # This will be used to detect the appropriate variable and replace its value
    # with the path to the downloaded item
    post_download_sed_string="export proton_path="
    # Set the value of the above variable that will be restored after a runner is deleted
    # In this case, we want to revert to the configured default runner
    post_delete_restore_value="${download_dir}/${default_runner}"

    # Call the download_manage function with the above configuration
    # The argument passed to the function is used for special handling
    # and displayed in the menus and dialogs.
    download_manage "runner"
}

# MARK: collect_external_proton_runners()
# Detect Proton installs provided by Steam or the OS so they can be selected
# without being managed or deleted by this helper.
collect_external_proton_runners() {
    unset external_proton_paths
    unset external_proton_names
    unset external_proton_labels

    declare -A _seen_external_proton_paths
    unset _steam_library_roots

    _steam_library_file_candidates=(
        "$HOME/.steam/root/steamapps/libraryfolders.vdf"
        "$HOME/.steam/steam/steamapps/libraryfolders.vdf"
        "$HOME/.steam/debian-installation/steamapps/libraryfolders.vdf"
        "${XDG_DATA_HOME:-$HOME/.local/share}/Steam/steamapps/libraryfolders.vdf"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/libraryfolders.vdf"
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/libraryfolders.vdf"
        "$HOME/snap/steam/common/.local/share/Steam/steamapps/libraryfolders.vdf"
        "$HOME/snap/steam/common/Steam/steamapps/libraryfolders.vdf"
    )

    for _library_file in "${_steam_library_file_candidates[@]}"; do
        if [ ! -f "$_library_file" ]; then
            continue
        fi

        while IFS='' read -r _library_root; do
            if [ -z "$_library_root" ] || [ ! -d "$_library_root" ]; then
                continue
            fi
            _library_root="$(readlink -f "$_library_root" 2>/dev/null || printf '%s' "$_library_root")"
            if [ -z "${_seen_external_proton_paths[$_library_root]+x}" ]; then
                _steam_library_roots+=("$_library_root")
                _seen_external_proton_paths[$_library_root]=1
            fi
        done < <(
            grep -E '"path"[[:space:]]+"[^"]+"' "$_library_file" |
                sed -E 's/.*"path"[[:space:]]+"([^"]+)".*/\1/'
        )
    done

    unset _seen_external_proton_paths
    declare -A _seen_external_proton_paths

    _collect_external_proton_candidate() {
        _candidate_path="$1"
        _candidate_source="$2"

        if [ -z "$_candidate_path" ] || [ ! -d "$_candidate_path" ] || [ ! -x "$_candidate_path/proton" ]; then
            return 0
        fi

        _candidate_realpath="$(readlink -f "$_candidate_path" 2>/dev/null || printf '%s' "$_candidate_path")"
        if [ -n "${_seen_external_proton_paths[$_candidate_realpath]+x}" ]; then
            return 0
        fi

        _candidate_name="$(basename "$_candidate_realpath")"
        case "$_candidate_name" in
            *[Pp]roton*|GE-Proton*|UMU-Proton*)
                ;;
            *)
                return 0
                ;;
        esac

        _seen_external_proton_paths[$_candidate_realpath]=1
        external_proton_paths+=("$_candidate_realpath")
        external_proton_names+=("$_candidate_name")
        external_proton_labels+=("$_candidate_name ($_candidate_source)")
    }

    _steam_scan_roots=(
        "$HOME/.steam/root/compatibilitytools.d"
        "$HOME/.steam/root/steamapps/common"
        "$HOME/.steam/steam/compatibilitytools.d"
        "$HOME/.steam/steam/steamapps/common"
        "$HOME/.steam/debian-installation/compatibilitytools.d"
        "$HOME/.steam/debian-installation/steamapps/common"
        "${XDG_DATA_HOME:-$HOME/.local/share}/Steam/compatibilitytools.d"
        "${XDG_DATA_HOME:-$HOME/.local/share}/Steam/steamapps/common"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common"
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d"
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/common"
        "$HOME/snap/steam/common/.local/share/Steam/compatibilitytools.d"
        "$HOME/snap/steam/common/.local/share/Steam/steamapps/common"
        "$HOME/snap/steam/common/Steam/compatibilitytools.d"
        "$HOME/snap/steam/common/Steam/steamapps/common"
    )
    for _steam_library_root in "${_steam_library_roots[@]}"; do
        _steam_scan_roots+=("$_steam_library_root/compatibilitytools.d")
        _steam_scan_roots+=("$_steam_library_root/steamapps/common")
    done

    for _scan_root in "${_steam_scan_roots[@]}"; do
        if [ ! -d "$_scan_root" ]; then
            continue
        fi
        for _candidate in "$_scan_root"/*; do
            [ -d "$_candidate" ] || continue
            _collect_external_proton_candidate "$_candidate" "Steam"
        done
    done

    _heroic_scan_roots=(
        "$HOME/.config/heroic/tools/proton"
        "$HOME/.config/Heroic/tools/proton"
        "$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic/tools/proton"
        "$HOME/.var/app/com.heroicgameslauncher.hgl/config/Heroic/tools/proton"
        "$HOME/.var/app/com.heroicgameslauncher.hgl/data/heroic/tools/proton"
        "$HOME/.var/app/com.heroicgameslauncher.hgl/data/Heroic/tools/proton"
        "$HOME/snap/heroic/common/.config/heroic/tools/proton"
        "$HOME/snap/heroic/common/.config/Heroic/tools/proton"
    )

    for _scan_root in "${_heroic_scan_roots[@]}"; do
        if [ ! -d "$_scan_root" ]; then
            continue
        fi
        for _candidate in "$_scan_root"/*; do
            [ -d "$_candidate" ] || continue
            _collect_external_proton_candidate "$_candidate" "Heroic"
        done
    done

    _os_scan_roots=(
        "/usr/share/steam/compatibilitytools.d"
        "/usr/local/share/steam/compatibilitytools.d"
        "/usr/share/Steam/compatibilitytools.d"
        "/usr/lib/steam/compatibilitytools.d"
        "/usr/lib64/steam/compatibilitytools.d"
        "/usr/share/games/steam/compatibilitytools.d"
        "/usr/local/share/games/steam/compatibilitytools.d"
        "/usr/lib/games/steam/compatibilitytools.d"
        "/usr/lib64/games/steam/compatibilitytools.d"
        "/usr/libexec/steam/compatibilitytools.d"
        "/usr/libexec/games/steam/compatibilitytools.d"
        "/usr/share/steam/steamapps/common"
        "/usr/lib/steam/steamapps/common"
        "/usr/lib64/steam/steamapps/common"
        "/usr/share/games/steam/steamapps/common"
        "/usr/lib/games/steam/steamapps/common"
        "/usr/lib64/games/steam/steamapps/common"
        "/usr/libexec/steam/steamapps/common"
        "/usr/libexec/games/steam/steamapps/common"
        "/var/lib/flatpak/app/com.valvesoftware.Steam/current/active/files/extra/compatibilitytools.d"
        "/var/lib/flatpak/app/com.valvesoftware.Steam/current/active/files/extra/steamapps/common"
        "/var/lib/snapd/hostfs/usr/share/steam/compatibilitytools.d"
        "/var/lib/snapd/hostfs/usr/lib/steam/compatibilitytools.d"
    )

    for _scan_root in "${_os_scan_roots[@]}"; do
        if [ ! -d "$_scan_root" ]; then
            continue
        fi
        for _candidate in "$_scan_root"/*; do
            [ -d "$_candidate" ] || continue
            _collect_external_proton_candidate "$_candidate" "OS"
        done
    done

    unset -f _collect_external_proton_candidate
}

# MARK: select_existing_proton_runner()
# Select a Steam/OS-provided Proton runner without downloading or deleting it.
select_existing_proton_runner() {
    if [ -z "$1" ]; then
        debug_print exit "Script error: The select_existing_proton_runner function expects an index argument. Aborting."
    elif [ -z "${external_proton_paths[$1]}" ]; then
        debug_print exit "Script error: Invalid external Proton runner index in select_existing_proton_runner(). Aborting."
    fi

    selected_external_proton_path="${external_proton_paths[$1]}"
    selected_external_proton_label="${external_proton_labels[$1]}"

    if [ ! -x "$selected_external_proton_path/proton" ]; then
        message warning "The selected Proton runner is no longer available:\n\n$selected_external_proton_path"
        return 1
    fi

    install_dir="${install_dir:-$wine_prefix}"
    mkdir -p "$install_dir"
    echo "$selected_external_proton_path" > "$install_dir/current_runner"
    chmod 644 "$install_dir/current_runner" 2>/dev/null || true

    if ! create_or_update_launch_script; then
        message error "Unable to update the launch script for the selected Proton runner."
        return 1
    fi

    if [ -n "$wine_prefix" ] && [ -d "$wine_prefix" ]; then
        create_desktop_files
        refresh_desktop_execs
    fi

    message info "Launch environment updated to use:\n\n$selected_external_proton_label\n$selected_external_proton_path"
}

# MARK: select_existing_proton_runner_menu()
# Present Steam/OS-provided Proton runners in a dedicated submenu.
select_existing_proton_runner_menu() {
    collect_external_proton_runners
    get_current_runner

    if [ "${#external_proton_paths[@]}" -eq 0 ]; then
        message info "No Steam or OS-provided Proton runners were detected."
        return 0
    fi

    menu_text_zenity="Select an existing Proton runner to use:"
    menu_text_terminal="Select an existing Proton runner to use:"
    menu_text_height="320"
    menu_type="radiolist"
    cancel_label="Go Back"
    goback="Return to the Proton management menu"
    unset menu_options
    unset menu_actions
    unset menu_default_choice

    for (( i=0; i<${#external_proton_paths[@]}; i++ )); do
        if [ "$current_runner_path" = "${external_proton_paths[i]}" ]; then
            menu_option_text="${external_proton_labels[i]} (in use)"
            menu_default_choice="${external_proton_labels[i]}"
        else
            menu_option_text="${external_proton_labels[i]}"
        fi

        menu_options+=("$menu_option_text")
        menu_actions+=("select_existing_proton_runner $i")
    done

    menu_options+=("$goback")
    menu_actions+=(":")

    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"
    if [ "$menu_height" -gt "$menu_height_max" ]; then
        menu_height="$menu_height_max"
    fi

    menu
}

# MARK: proton_manage()
# Configure the download_manage function specifically for Proton GE runners
proton_manage() {
    post_download_type="configure-proton"

    # Use a small local sources array that points to GE-Proton only
    proton_sources=("GE-Proton" "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases")
    declare -n download_sources=proton_sources

    # Get directories so we know where the wine prefix is
    getdirs

    set_latest_default_runner
    if [ "$?" -eq 1 ]; then
        message error "Could not fetch the latest default Proton runner. The Github API may be down or rate limited."
        return 1
    fi

    # Set the download directory for proton runners
    download_dir="$wine_prefix/runners"

    # Configure the text displayed in the menus
    download_menu_heading="Proton GE"
    download_menu_description="The Proton GE builds listed below can be downloaded and used as the prefix runner"
    download_menu_height="320"

    # Preselect the currently active runner if one exists, otherwise fallback to
    # the preferred default version in the download menu. This value comes
    # from the top-level `PROTON_DEFAULT_VERSION` variable.
    get_current_runner
    if [ -n "$current_runner_basename" ]; then
        menu_default_choice="$current_runner_basename"
    else
        menu_default_choice="$PROTON_DEFAULT_VERSION"
    fi

    # This will match the proton_path variable in the launch script
    post_download_sed_string="export proton_path="
    post_delete_restore_value="${download_dir}/${default_runner}"

    download_manage "proton"

    # Clear the default selection to avoid affecting other menus
    unset menu_default_choice
}

# MARK: download_select_install()
# List available items for download. Called by download_manage()
#
# The following variables are expected to be set before calling this function:
# - download_sources (array)
# - download_type (string)
# - download_dir (string)
download_select_install() {
    # This function expects an element number for the sources array to be passed in as an argument
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The download_select_install function expects a numerical argument. Aborting."
    fi

    # Sanity checks
    if [ "${#download_sources[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'download_sources' was not set before calling the download_select_install function. Aborting."
    elif [ -z "$download_type" ]; then
        debug_print exit "Script error: The string 'download_type' was not set before calling the download_select_install function. Aborting."
    elif [ -z "$download_dir" ]; then
        debug_print exit "Script error: The string 'download_dir' was not set before calling the download_select_install function. Aborting."
    fi

    # Store info from the selected contributor
    contributor_name="${download_sources[$1]}"
    contributor_url="${download_sources[$1+1]}"

    # For runners, check GlibC version against runner requirements
    if [ "$download_type" = "runner" ] && { [ "$contributor_name" = "TKG" ] || [ "$contributor_name" = "RawFox" ] || [ "$contributor_name" = "Mactan" ]; }; then
        glibc_fail="false"
        required_glibc="2.38"

        # Check the system glibc
        if [ -x "$(command -v ldd)" ]; then
            system_glibc="$(ldd --version | awk '/ldd/{print $NF}')"
        else
            system_glibc="0 (Not installed)"
        fi

        # Sort the versions and check if the installed glibc is smaller
        if [ "$required_glibc" != "$system_glibc" ] &&
        [ "$system_glibc" = "$(printf "%s\n%s" "$system_glibc" "$required_glibc" | sort -V | head -n1)" ]; then
            glibc_fail="true"
        fi

        # Display a warning message
        if [ "$glibc_fail" = "true" ]; then
            message warning "Your glibc version is incompatible with the selected runner\n\nSystem glibc: ${system_glibc}\nMinimum required glibc: $required_glibc"
            return 1
        fi
    fi

    # Check the provided contributor url to make sure we know how to handle it
    # To add new sources, add them here and handle in the if statement
    # just below and in the download_install function
    case "$contributor_url" in
        https://api.github.com/*)
            download_url_type="github"
            ;;
        https://gitlab.com/api/v4/projects/*)
            download_url_type="gitlab"
            ;;
        *)
            debug_print exit "Script error:  Unknown api/url format in ${download_type}_sources array. Aborting."
            ;;
    esac

    # Set the search keys we'll use to parse the api for the download url
    # To add new sources, handle them here, in the if statement
    # just above, and in the download_install function
    if [ "$download_url_type" = "github" ]; then
        # Which json key are we looking for?
        search_key="browser_download_url"
        # Optional: Only match urls containing a keyword
        match_url_keyword=""
        # Optional: Filter out game-specific builds by keyword
        # Format for grep extended regex (ie: "word1|word2|word3")
        if [ "$download_type" = "runner" ] && [ "$contributor_name" = "GloriousEggroll" ]; then
            filter_keywords="lol|diablo"
        elif [ "$download_type" = "runner" ] && [ "$contributor_name" = "Kron4ek" ]; then
            filter_keywords="x86|wow64"
        else
            filter_keywords="oh hi there. this is just placeholder text. how are you today?"
        fi
        # Add a query string to the url
        query_string="?per_page=$max_download_items"
    elif [ "$download_url_type" = "gitlab" ]; then
        # Which json key are we looking for?
        search_key="direct_asset_url"
        # Only match urls containing a keyword
        match_url_keyword="releases"
        # Optional: Filter out game-specific builds by keyword
        # Format for grep extended regex (ie: "word1|word2|word3")
        filter_keywords="oh hi there. this is just placeholder text. how are you today?"
        # Add a query string to the url
        query_string="?per_page=$max_download_items"
    else
        debug_print exit "Script error:  Unknown api/url format in ${download_type}_sources array. Aborting."
    fi

    # Fetch a list of versions from the selected contributor
    unset download_versions
    # Save raw API output to a temp file for debugging/fallbacks
    api_dump="$tmp_dir/${contributor_name//[^a-zA-Z0-9]/_}-api.json"
    curl -s "$contributor_url$query_string" -o "$api_dump"

    # Parse the list of asset basenames from the saved API dump
    if [ -n "$match_url_keyword" ]; then
        parse_cmd="grep -Eo \"\\\"$search_key\\\": ?\\\"[^\\\"]+\\\"\" \"$api_dump\" | grep \"$match_url_keyword\" | cut -d '\\"' -f4 | cut -d '?' -f1 | xargs -n1 basename | grep -viE \"$filter_keywords\""
    else
        parse_cmd="grep -Eo \"\\\"$search_key\\\": ?\\\"[^\\\"]+\\\"\" \"$api_dump\" | cut -d '\\"' -f4 | cut -d '?' -f1 | xargs -n1 basename | grep -viE \"$filter_keywords\""
    fi
    while IFS='' read -r line; do
        download_versions+=("$line")
    done < <(eval "$parse_cmd")
    # Note: match from search_key until " or EOL (Handles embedded commas and escaped quotes). Cut out quotes and gitlab's extraneous query strings.

    # Sanity check
    if [ "${#download_versions[@]}" -eq 0 ]; then
        # Attempt a fallback: extract release tag names from the API if asset parsing failed
        debug_print continue "No assets parsed from API; attempting fallback to release tags for $contributor_name"
        api_dump="$tmp_dir/${contributor_name//[^a-zA-Z0-9]/_}-api.json"
        curl -s "$contributor_url$query_string" -o "$api_dump"
        if [ -f "$api_dump" ]; then
            # Fallback: extract asset 'name' fields (archive filenames) from the API dump
            while IFS='' read -r asset_name; do
                download_versions+=("$asset_name")
            done < <(grep -Eo '"name": ?"[^"]+"' "$api_dump" | cut -d '"' -f4 | grep -Ei '\.tar\.gz$|\.tgz$|\.tar\.xz$|\.tar\.zst$' | grep -viE "$filter_keywords")
        fi
    fi

    if [ "${#download_versions[@]}" -eq 0 ]; then
        message warning "No $download_type versions were found.  The $download_url_type API may be down or rate limited."
        return 1
    fi

    # Deduplicate by basename (strip extensions) while preserving order.
    # Prefer more modern compressed formats when multiple extensions exist for the same basename.
    if [ "${#download_versions[@]}" -gt 1 ]; then
        declare -A _seen_base
        declare -A _seen_index
        declare -A _seen_ext
        unset _unique_download_versions
        # preference weights: higher = more preferred
        declare -A _pref=( [zst]=4 [xz]=3 [gz]=2 [tgz]=1 )
        for _dv in "${download_versions[@]}"; do
            # determine basename and extension token
            if [[ "$_dv" == *.tar.zst ]]; then
                _base="${_dv%.tar.zst}"
                _ext="zst"
            elif [[ "$_dv" == *.tar.xz ]]; then
                _base="${_dv%.tar.xz}"
                _ext="xz"
            elif [[ "$_dv" == *.tar.gz ]]; then
                _base="${_dv%.tar.gz}"
                _ext="gz"
            elif [[ "$_dv" == *.tgz ]]; then
                _base="${_dv%.tgz}"
                _ext="tgz"
            else
                _base="$_dv"
                _ext=""
            fi

            if [ -z "${_seen_base[$_base]+x}" ]; then
                _unique_download_versions+=("$_dv")
                _seen_base[$_base]=1
                _seen_index[$_base]=$((${#_unique_download_versions[@]}-1))
                _seen_ext[$_base]="$_ext"
            else
                # If current extension is more preferred than stored, replace the stored entry
                stored_ext="${_seen_ext[$_base]}"
                curr_pref=${_pref[$_ext]:-0}
                stored_pref=${_pref[$stored_ext]:-0}
                if [ "$curr_pref" -gt "$stored_pref" ]; then
                    idx=${_seen_index[$_base]}
                    _unique_download_versions[$idx]="$_dv"
                    _seen_ext[$_base]="$_ext"
                fi
            fi
        done
        download_versions=("${_unique_download_versions[@]}")
    fi

    # Configure the menu
    if [ "$download_type" = "proton" ]; then
        menu_text_zenity="Select the Proton runner you want to use:"
        menu_text_terminal="Select the Proton runner you want to use:"
    else
        menu_text_zenity="Select the $download_type you want to install:"
        menu_text_terminal="Select the $download_type you want to install:"
    fi
    menu_text_height="320"
    menu_type="radiolist"
    goback="Return to the $download_type management menu"
    unset menu_options
    unset menu_actions

    # Iterate through the versions, check if they are installed,
    # and add them to the menu options
    # To add new file extensions, handle them here and in
    # the download_install function

    if [ "$download_type" = "proton" ]; then
        get_current_runner
    fi

    for (( i=0, num_download_items=0; i<${#download_versions[@]} && num_download_items<max_download_items; i++ )); do

        # Get the file name minus the extension
        case "${download_versions[i]}" in
            *.sha*sum | *.ini | *.txt)
                # Ignore hashes and configs
                continue
                ;;
            *.tar.gz)
                download_basename="$(basename "${download_versions[i]}" .tar.gz)"
                ;;
            *.tgz)
                download_basename="$(basename "${download_versions[i]}" .tgz)"
                ;;
            *.tar.xz)
                download_basename="$(basename "${download_versions[i]}" .tar.xz)"
                ;;
            *.tar.zst)
                download_basename="$(basename "${download_versions[i]}" .tar.zst)"
                ;;
            *)
                # Print a warning and move on to the next item
                debug_print continue "Warning: Unknown archive filetype in download_select_install() function. Offending String: ${download_versions[i]}"
                continue
                ;;
        esac

        # Build the menu item
        unset menu_option_text
        if [ "$download_type" = "proton" ]; then
            if [ "$current_runner_path" = "${download_dir}/${download_basename}" ]; then
                menu_option_text="$download_basename (in use)"
            elif [ -d "${download_dir}/${download_basename}" ]; then
                menu_option_text="$download_basename (downloaded)"
            else
                # The file is not installed
                menu_option_text="$download_basename"
            fi
        else
            if [ -d "${download_dir}/${download_basename}" ] && [ "$download_type" = "runner" ] && [ "$current_runner_basename" = "$download_basename" ]; then
                menu_option_text="$download_basename    [in-use]"
            elif [ -d "${download_dir}/${download_basename}" ]; then
                menu_option_text="$download_basename    [installed]"
            else
                # The file is not installed
                menu_option_text="$download_basename"
            fi
        fi

        # Add the file names to the menu
        menu_options+=("$menu_option_text")
        menu_actions+=("download_install $i")

        # Increment the added items counter
        num_download_items="$(($num_download_items+1))"
    done

    # Complete the menu by adding the option to go back to the previous menu
    menu_options+=("$goback")
    menu_actions+=(":") # no-op

    # Calculate the total height the menu should be
    # menu_option_height = pixels per menu option
    # #menu_options[@] = number of menu options
    # menu_text_height = height of the title/description text
    # menu_text_height_zenity4 = added title/description height for libadwaita bigness
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

# MARK: download_install()
# Download and install the selected item. Called by download_select_install()
#
# Expects one numerical argument, an index number for the array "download_versions"
#
# The following variables are expected to be set before calling this function:
# - download_versions (array)
# - contributor_url (string)
# - download_url_type (string)
# - download_type (string)
# - download_dir (string)
download_install() {
    # This function expects an index number for the array
    # download_versions to be passed in as an argument
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The download_install function expects a numerical argument. Aborting."
    fi

    # Sanity checks
    if [ "${#download_versions[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'download_versions' was not set before calling the download_install function. Aborting."
    elif [ -z "$contributor_url" ]; then
        debug_print exit "Script error: The string 'contributor_url' was not set before calling the download_install function. Aborting."
    elif [ -z "$download_url_type" ]; then
        debug_print exit "Script error: The string 'download_url_type' was not set before calling the download_install function. Aborting."
    elif [ -z "$download_type" ]; then
        debug_print exit "Script error: The string 'download_type' was not set before calling the download_install function. Aborting."
    elif [ -z "$download_dir" ]; then
        debug_print exit "Script error: The string 'download_dir' was not set before calling the download_install function. Aborting."
    fi

    # Get the filename including file extension
    download_filename="${download_versions[$1]}"

    # Get the selected item name minus the file extension
    # To add new file extensions, handle them here and in
    # the download_select_install function
    case "$download_filename" in
        *.tar.gz)
            if [ ! -x "$(command -v gzip)" ]; then
                message error "gzip does not appear to be installed. Unable to extract the requested archive."
                return 1
            fi
            download_basename="$(basename "$download_filename" .tar.gz)"
            ;;
        *.tgz)
            if [ ! -x "$(command -v gzip)" ]; then
                message error "gzip does not appear to be installed. Unable to extract the requested archive."
                return 1
            fi
            download_basename="$(basename "$download_filename" .tgz)"
            ;;
        *.tar.xz)
            if [ ! -x "$(command -v xz)" ]; then
                message error "xz does not appear to be installed. Unable to extract the requested archive."
                return 1
            fi
            download_basename="$(basename "$download_filename" .tar.xz)"
            ;;
        *.tar.zst)
            if [ ! -x "$(command -v zstd)" ]; then
                message error "zstd does not appear to be installed. Unable to extract the requested archive."
                return 1
            fi
            download_basename="$(basename "$download_filename" .tar.zst)"
            ;;
        *)
            debug_print exit "Script error: Unknown archive filetype in download_install function. Aborting."
            ;;
    esac

    # Check if the item is already installed
    # Trigger post-download actions to reconfigure the launch script then skip the rest of the redownload process
    if [ -d "${download_dir}/${download_basename}" ]; then
        debug_print continue "The selected $download_type is already installed. Skipping download."

        # Store the final name of the downloaded item
        downloaded_item_name="$download_basename"
        # Mark success for triggering post-download actions
        post_download_required="installed"

        return 0
    fi

    # Set the search keys we'll use to parse the api for the download url
    # To add new sources, handle them here and in the
    # download_select_install function
    if [ "$download_url_type" = "github" ]; then
        # Which json key are we looking for?
        search_key="browser_download_url"
        # Add a query string to the url
        query_string="?per_page=$max_download_items"
    elif [ "$download_url_type" = "gitlab" ]; then
        # Which json key are we looking for?
        search_key="direct_asset_url"
        # Add a query string to the url
        query_string="?per_page=$max_download_items"
    else
        debug_print exit "Script error:  Unknown api/url format in ${download_type}_sources array. Aborting."
    fi

    # Get the selected download url
    download_url="$(curl -s "$contributor_url$query_string" | grep -Eo "\"$search_key\": ?\"[^\"]+\"" | grep "$download_filename" | cut -d '"' -f4 | cut -d '?' -f1 | sed 's|/-/blob/|/-/raw/|')"

    # Sanity check
    if [ -z "$download_url" ]; then
        message warning "Could not find the requested ${download_type}.  The $download_url_type API may be down or rate limited."
        return 1
    fi

    # Download the item to the tmp directory
    download_file "$download_url" "$download_filename" "$download_type"

    # Sanity check
    if [ ! -f "$tmp_dir/$download_filename" ]; then
        # Something went wrong with the download and the file doesn't exist
        message error "Something went wrong and the requested $download_type file could not be downloaded!"
        debug_print continue "Download failed! File not found: $tmp_dir/$download_filename"
        return 1
    fi

    # Show a zenity pulsating progress bar
    progress_bar start "Installing ${download_type}. Please wait..."
    progress_update "Starting extraction of ${download_filename}..."

    # Extract the archive to the tmp directory
    debug_print continue "Extracting $download_type into $tmp_dir/$download_basename..."
    mkdir "$tmp_dir/$download_basename" && tar -xf "$tmp_dir/$download_filename" -C "$tmp_dir/$download_basename"

    progress_update "Extraction finished; inspecting contents..."
    # Check the contents of the extracted archive to determine the
    # directory structure we must create upon installation
    num_dirs=0
    num_files=0
    for extracted_item in "$tmp_dir/$download_basename"/*; do
        if [ -d "$extracted_item" ]; then
            num_dirs="$(($num_dirs+1))"
            extracted_dir="$(basename "$extracted_item")"
        elif [ -f "$extracted_item" ]; then
            num_files="$(($num_files+1))"
        fi
    done

    # Create the correct directory structure and install the item
    if [ "$num_dirs" -eq 0 ] && [ "$num_files" -eq 0 ]; then
        # Sanity check
        message warning "The downloaded archive is empty. There is nothing to do."
    elif [ "$num_dirs" -eq 1 ] && [ "$num_files" -eq 0 ]; then
        # If the archive contains only one directory, install that directory
        # We rename it to the name of the archive in case it is different
        # so we can easily detect installed items in download_select_install()
        debug_print continue "Installing $download_type into ${download_dir}/${download_basename}..."

        # Copy the directory to the destination
        mkdir -p "$download_dir" && cp -r "${tmp_dir}/${download_basename}/${extracted_dir}" "${download_dir}/${download_basename}"

        # Store the final name of the downloaded item
        downloaded_item_name="$download_basename"
        # Mark success for triggering post-download actions
        post_download_required="installed"
    elif [ "$num_dirs" -gt 1 ] || [ "$num_files" -gt 0 ]; then
        # If the archive contains more than one directory or
        # one or more files, we must create a subdirectory
        debug_print continue "Installing $download_type into ${download_dir}/${download_basename}..."

        # Copy the directory to the destination
        mkdir -p "${download_dir}/${download_basename}" && cp -r "$tmp_dir"/"$download_basename"/* "$download_dir"/"$download_basename"

        # Store the final name of the downloaded item
        downloaded_item_name="$download_basename"
        # Mark success for triggering post-download actions
        post_download_required="installed"
    else
        # Some unexpected combination of directories and files
        debug_print exit "Script error:  Unexpected archive contents in download_install function. Aborting"
    fi

    progress_bar stop # Stop the zenity progress window

    # Cleanup tmp download
    debug_print continue "Cleaning up ${tmp_dir}/${download_filename}..."
    rm --interactive=never "${tmp_dir:?}/${download_filename}"
    rm -r --interactive=never "${tmp_dir:?}/${download_basename}"

    return 0
}

# MARK: download_select_delete()
# List installed items for deletion. Called by download_manage()
#
# The following variables are expected to be set before calling this function:
# - download_type (string)
# - download_dir (string)
download_select_delete() {
    # Sanity checks
    if [ -z "$download_type" ]; then
        debug_print exit "Script error: The string 'download_type' was not set before calling the download_select_delete function. Aborting."
    elif [ -z "$download_dir" ]; then
        debug_print exit "Script error: The string 'download_dir' was not set before calling the download_select_delete function. Aborting."
    fi

    # Configure the menu
    menu_text_zenity="Select the $download_type(s) you want to remove:"
    menu_text_terminal="Select the $download_type you want to remove:"
    menu_text_height="320"
    menu_type="checklist"
    goback="Return to the $download_type management menu"
    unset installed_items
    unset installed_item_names
    unset menu_options
    unset menu_actions

    # Find all installed items in the download destination
    if [ -d "$download_dir" ]; then
        for item in "$download_dir"/*; do
            if [ -d "$item" ]; then
                installed_item_names+=("$(basename "$item")")
                installed_items+=("$item")
            fi
        done
    fi

    # Create menu options for the installed items
    for (( i=0; i<"${#installed_items[@]}"; i++ )); do
        # Build the menu item
        unset menu_option_text
        # Special handling for runners currently in use
        if { [ "$download_type" = "runner" ] || [ "$download_type" = "proton" ]; } && [ "$current_runner_path" = "${installed_items[i]}" ]; then
            menu_option_text="${installed_item_names[i]}    [in-use]"
        else
            # Everything else
            menu_option_text="${installed_item_names[i]}"
        fi


        menu_options+=("$menu_option_text")
        menu_actions+=("download_delete $i")
    done

    # Print a message and return if no installed items were found
    if [ "${#menu_options[@]}" -eq 0 ]; then
        message info "No installed ${download_type}s found."
        return 0
    fi

    # Complete the menu by adding the option to go back to the previous menu
    menu_options+=("$goback")
    menu_actions+=(":") # no-op

    # Calculate the total height the menu should be
    # menu_option_height = pixels per menu option
    # #menu_options[@] = number of menu options
    # menu_text_height = height of the title/description text
    # menu_text_height_zenity4 = added title/description height for libadwaita bigness
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

# MARK: download_delete()
# Uninstall the selected item(s). Called by download_select_install()
# Accepts array index numbers as an argument
#
# The following variables are expected to be set before calling this function:
# - download_type (string)
# - installed_items (array)
# - installed_item_names (array)
download_delete() {
    # This function expects at least one index number for the array installed_items to be passed in as an argument
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The download_delete function expects an argument. Aborting."
    fi

    # Sanity checks
    if [ -z "$download_type" ]; then
        debug_print exit "Script error: The string 'download_type' was not set before calling the download_delete function. Aborting."
    elif [ "${#installed_items[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'installed_items' was not set before calling the download_delete function. Aborting."
    elif [ "${#installed_item_names[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'installed_item_names' was not set before calling the download_delete function. Aborting."
    fi

    # Capture arguments and format a list of items
    item_to_delete=("$@")
    unset list_to_delete
    unset deleted_item_names
    for (( i=0; i<"${#item_to_delete[@]}"; i++ )); do
        list_to_delete+="\n${installed_items[${item_to_delete[i]}]}"
    done

    if message question "Are you sure you want to delete the following ${download_type}(s)?\n$list_to_delete"; then

        unset post_delete_required

        # Loop through the arguments
        for (( i=0; i<"${#item_to_delete[@]}"; i++ )); do
            rm -r --interactive=never "${installed_items[${item_to_delete[i]}]}"
            debug_print continue "Deleted ${installed_items[${item_to_delete[i]}]}"

            # If we just deleted the currently used runner, we need to trigger post-delete to update the launch script
            if { [ "$download_type" = "runner" ] || [ "$download_type" = "proton" ]; } && [ "${installed_items[${item_to_delete[i]}]}" = "$current_runner_path" ]; then
                post_delete_required="true"
            fi

            # Store the names of deleted items for post_download() processing
            deleted_item_names+=("${installed_item_names[${item_to_delete[i]}]}")
        done
        # Mark success for triggering post-deletion actions
        if [ "$post_delete_required" = "true" ]; then
            post_download_required="deleted"
        fi
    fi
}

# MARK: post_download()
# Perform post-download actions or display a message/instructions
#
# The following variables are expected to be set before calling this function:
# - post_download_type (string. "none", "configure-wine")
# - post_download_sed_string (string. For type configure-wine)
# - post_delete_restore_value (string. For type configure-wine)
# - post_download_required (string. Set automatically in install/delete functions)
# - downloaded_item_name (string. For installs only. Set automatically in download_install function)
# - deleted_item_names (array. For deletions only. Set automatically in download_delete function)
# - download_dir (string)
#
# Details for post_download_sed_string:
# This is the string sed will match against when editing configs or files
# For the wine install, it replaces values in the default launch script
# with the appropriate paths and values after installation.
post_download() {
    # Sanity checks
    if [ -z "$post_download_type" ]; then
        debug_print exit "Script error: The string 'post_download_type' was not set before calling the post_download function. Aborting."
    elif { [ -z "$post_download_sed_string" ] && { [ "$post_download_type" = "configure-wine" ] || [ "$post_download_type" = "configure-proton" ]; }; }; then
        debug_print exit "Script error: The string 'post_download_sed_string' was not set before calling the post_download function. Aborting."
    elif { [ -z "$post_delete_restore_value" ] && { [ "$post_download_type" = "configure-wine" ] || [ "$post_download_type" = "configure-proton" ]; }; }; then
        debug_print exit "Script error: The string 'post_delete_restore_value' was not set before calling the post_download function. Aborting."
    elif [ -z "$download_dir" ]; then
        debug_print exit "Script error: The string 'download_dir' was not set before calling the post_download function. Aborting."
    fi

    # Return if we don't have anything to do
    if [ "$post_download_type" = "none" ]; then
        return 0
    fi

    # Ensure launch script exists before attempting sed-based updates
    install_dir="${install_dir:-$wine_prefix}"
    create_or_update_launch_script || true

    # Handle the appropriate post-download actions
    if [ "$post_download_type" = "configure-wine" ]; then

        # We handle installs and deletions differently for wine-style runners
        if [ "$post_download_required" = "installed" ] && [ "$download_type" = "runner" ]; then
            debug_print continue "Updating \"${post_download_sed_string}\" variable in launch script ${wine_prefix}/${wine_launch_script_name}..."
            sed -i "s|^${post_download_sed_string}.*|${post_download_sed_string}\"${wine_prefix}/runners/${downloaded_item_name}/bin\"|" "$wine_prefix/$wine_launch_script_name"
            message info "Wine Runner installation complete!"
        elif [ "$post_download_required" = "deleted" ] && [ "$download_type" = "runner" ]; then
            if [ ! -d "${download_dir}/${default_runner}" ]; then
                message info "The Wine runner currently used by your launch script has been deleted!\n\nThe default Wine runner will now be downloaded and installed."
                download_wine
                if [ "$?" -eq 1 ]; then
                    message warning "Something went wrong while installing ${default_runner}!\n\nYou will need to edit your launch script's \"${post_download_sed_string}\" variable manually."
                    return 1
                fi
            else
                message info "The Wine runner currently used by your launch script has been deleted!\n\nYour launch script will be updated to use the default Wine runner."
            fi
            debug_print continue "Updating \"${post_download_sed_string}\" variable in launch script ${wine_prefix}/${wine_launch_script_name}..."
            sed -i "s#^${post_download_sed_string}.*#${post_download_sed_string}\"${post_delete_restore_value}\"#" "$wine_prefix/$wine_launch_script_name"
            message info "Your launch script has been updated!"
        else
            debug_print exit "Script error: Unknown post_download_required value in post_download function. Aborting."
        fi
    elif [ "$post_download_type" = "configure-proton" ]; then

        # Handle installs and deletions for Proton-style runners
        if [ "$post_download_required" = "installed" ] && { [ "$download_type" = "runner" ] || [ "$download_type" = "proton" ]; }; then
            debug_print continue "Updating \"${post_download_sed_string}\" variable in launch script ${wine_prefix}/${wine_launch_script_name}..."
            # Point proton_path at the installed runner directory
            sed -i "s|^${post_download_sed_string}.*|${post_download_sed_string}\"${wine_prefix}/runners/${downloaded_item_name}\"|" "$wine_prefix/$wine_launch_script_name"
            message info "Proton Runner installation complete!"
            # Persist the selected runner in the install directory for stable detection
            install_dir="${install_dir:-$wine_prefix}"
            if [ -n "$install_dir" ]; then
                mkdir -p "$install_dir"
                echo "${install_dir:-$wine_prefix}/runners/${downloaded_item_name}" > "$install_dir/current_runner"
                chmod 644 "$install_dir/current_runner" 2>/dev/null || true
            fi
            # Regenerate .desktop files so Exec lines prefer the newly installed Proton runner
            if [ -n "$wine_prefix" ] && [ -d "$wine_prefix" ]; then
                debug_print continue "Regenerating .desktop files to use the new Proton runner..."
                create_desktop_files
                # Also refresh any existing desktop files so previously-created
                # shortcuts are updated to use the selected Proton binary.
                refresh_desktop_execs
                message info "Launch environment updated to use the selected Proton runner."
            fi
        elif [ "$post_download_required" = "deleted" ] && { [ "$download_type" = "runner" ] || [ "$download_type" = "proton" ]; }; then
            if [ ! -d "${download_dir}/${default_runner}" ]; then
                message info "The Proton runner currently used by your launch script has been deleted!\n\nThe default runner will now be downloaded and installed."
                download_wine
                if [ "$?" -eq 1 ]; then
                    message warning "Something went wrong while installing ${default_runner}!\n\nYou will need to edit your launch script's \"${post_download_sed_string}\" variable manually."
                    return 1
                fi
            else
                message info "The Proton runner currently used by your launch script has been deleted!\n\nYour launch script will be updated to use the default runner."
            fi
            debug_print continue "Updating \"${post_download_sed_string}\" variable in launch script ${wine_prefix}/${wine_launch_script_name}..."
            sed -i "s#^${post_download_sed_string}.*#${post_download_sed_string}\"${post_delete_restore_value}\"#" "$wine_prefix/$wine_launch_script_name"
            message info "Your launch script has been updated!"
            # Update persisted current runner to the restore value
            install_dir="${install_dir:-$wine_prefix}"
            if [ -n "$install_dir" ]; then
                mkdir -p "$install_dir"
                echo "${post_delete_restore_value}" > "$install_dir/current_runner"
                chmod 644 "$install_dir/current_runner" 2>/dev/null || true
            fi
            if [ -n "$wine_prefix" ] && [ -d "$wine_prefix" ]; then
                create_desktop_files
                refresh_desktop_execs
            fi
        else
            debug_print exit "Script error: Unknown post_download_required value in post_download function. Aborting."
        fi
    else
            debug_print exit "Script error: Unknown post_download_type value in post_download function. Aborting."
    fi
}

# MARK: download_file()
# Download a file to the tmp directory
# Expects three arguments: The download URL, file name, and download type
download_file() {
    # This function expects three string arguments
    if [ "$#" -lt 3 ]; then
        printf "\nScript error:  The download_file function expects three arguments. Aborting.\n"
        read -n 1 -s -p "Press any key..."
        exit 0
    fi

    # Capture the arguments and encode spaces in urls
    download_url="${1// /%20}"
    download_filename="$2"
    download_type="$3"

    # Download the item to the tmp directory
    debug_print continue "Downloading $download_url into $tmp_dir/$download_filename..."
    progress_update "Downloading ${download_type} (${download_filename})..."
    if [ "$use_zenity" -eq 1 ]; then
        # Format the curl progress bar for zenity
        mkfifo "$tmp_dir/lugpipe"
        cd "$tmp_dir" && curl -#L "$download_url" -o "$download_filename" > "$tmp_dir/lugpipe" 2>&1 & curlpid="$!"
        stdbuf -oL tr '\r' '\n' < "$tmp_dir/lugpipe" | \
        grep --line-buffered -ve "100" | grep --line-buffered -o "[0-9]*\.[0-9]" | \
        (
            trap 'kill "$curlpid"; trap - ERR' ERR
            zenity --progress --auto-close --title="Falcon BMS Linux Helper" --text="Downloading ${download_type}.  This might take a moment.\n" 2>/dev/null
        )

        if [ "$?" -eq 1 ]; then
            # User clicked cancel
            debug_print continue "Download aborted. Removing $tmp_dir/$download_filename..."
            progress_update "Download cancelled by user."
            rm --interactive=never "${tmp_dir:?}/$download_filename"
            rm --interactive=never "${tmp_dir:?}/lugpipe"
            return 1
        fi
        rm --interactive=never "${tmp_dir:?}/lugpipe"
        progress_update "Download complete: ${download_filename}"
    else
        # Standard curl progress bar
        (cd "$tmp_dir" && curl -#L "$download_url" -o "$download_filename")
        progress_update "Download complete: ${download_filename}"
    fi
}

############################################################################
######## end download functions ############################################
############################################################################

############################################################################
######## begin maintenance functions #######################################
############################################################################

# MARK: maintenance_menu()
# Show maintenance/troubleshooting options
maintenance_menu() {
    # Loop the menu until the user selects quit
    looping_menu="true"
    while [ "$looping_menu" = "true" ]; do
        # Fetch wine prefix
        if [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
            maint_prefix="$(cat "$conf_dir/$conf_subdir/$wine_conf")"
        else
            maint_prefix="Not configured"
        fi

        # Configure the menu
        menu_text_zenity="<b><big>Game Maintenance and Troubleshooting</big>\n\nBMS Wiki: $bms_wiki\n\nWine prefix:</b> $maint_prefix"
        menu_text_terminal="Game Maintenance and Troubleshooting\n\nBMS Wiki: $bms_wiki\n\nWine prefix: $maint_prefix"
        menu_text_height="320"
        menu_type="radiolist"

        # Configure the menu options
        prefix_msg="Target a different Falcon BMS installation"
        launcher_msg="Update/Repair launch script"
        launchscript_msg="Edit launch script"
        config_msg="Open Wine prefix configuration"
        controllers_msg="Open Wine controller configuration"
        protontricks_msg="Open Protontricks package manager"
        powershell_msg="Install PowerShell into Wine prefix"
        opentrack_msg="Install OpenTrack for Windows"
        bms_launcher_msg="Update/Re-install Falcon BMS"
        dirs_msg="Display Helper and Falcon BMS directories"
        reset_msg="Reset Helper configs"
        quit_msg="Return to the main menu"

        # Set the options to be displayed in the menu
        menu_options=("$prefix_msg" "$launcher_msg" "$config_msg" "$controllers_msg" "$protontricks_msg" "$powershell_msg" "$opentrack_msg" "$dirs_msg" "$reset_msg" "$quit_msg")
        # Set the corresponding functions to be called for each of the options
        menu_actions=("switch_prefix" "update_launch_script" "call_launch_script config" "call_launch_script controllers" "launch_protontricks" "install_powershell" "install_opentrack_windows" "display_dirs" "reset_helper" "menu_loop_done")

        # Calculate the total height the menu should be
        # menu_option_height = pixels per menu option
        # #menu_options[@] = number of menu options
        # menu_text_height = height of the title/description text
        # menu_text_height_zenity4 = added title/description height for libadwaita bigness
        menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"

       # Set the label for the cancel button
       cancel_label="Go Back"

        # Call the menu function.  It will use the options as configured above
        menu
    done
}

# MARK: install_opentrack_windows()
# Download the latest OpenTrack Windows installer and launch it in the target prefix
install_opentrack_windows() {
    opentrack_repo="opentrack/opentrack"
    opentrack_api_url="https://api.github.com/repos/${opentrack_repo}/releases/latest"
    opentrack_release_page="https://github.com/${opentrack_repo}/releases"

    getdirs
    if [ "$?" -eq 1 ]; then
        message warning "Unable to install OpenTrack."
        return 1
    fi

    get_current_runner
    wine_bin=""
    wineserver_bin=""
    if [ -n "$launcher_winepath" ] && [ -x "$launcher_winepath/wine" ]; then
        wine_bin="$launcher_winepath/wine"
        if [ -x "$launcher_winepath/wineserver" ]; then
            wineserver_bin="$launcher_winepath/wineserver"
        fi
    else
        wine_bin="$(command -v wine 2>/dev/null || true)"
        wineserver_bin="$(command -v wineserver 2>/dev/null || true)"
    fi

    if [ -z "$wine_bin" ] || [ ! -x "$wine_bin" ]; then
        message error "Unable to locate a usable wine binary for this install.\n\nConfigure a Proton runner first or install Wine on the host system."
        return 1
    fi

    progress_bar start "Checking latest OpenTrack release. Please wait..."
    progress_update "Querying OpenTrack releases from GitHub..."

    opentrack_api_dump="$tmp_dir/opentrack-latest-release.json"
    if ! curl -sL "$opentrack_api_url" -o "$opentrack_api_dump"; then
        progress_bar stop
        message error "Unable to query the latest OpenTrack release from GitHub.\n\n$opentrack_release_page"
        return 1
    fi

    opentrack_download_url="$(grep -Eo '"browser_download_url": ?"[^"]+"' "$opentrack_api_dump" | cut -d '"' -f4 | cut -d '?' -f1 | grep -E -- '-win32-setup\.exe$' | head -n 1)"
    if [ -z "$opentrack_download_url" ]; then
        progress_bar stop
        message error "Unable to locate a '*-win32-setup.exe' asset in the latest OpenTrack release.\n\n$opentrack_release_page"
        return 1
    fi
    opentrack_download_name="$(basename "$opentrack_download_url")"
    progress_bar stop

    if ! download_file "$opentrack_download_url" "$opentrack_download_name" "OpenTrack installer"; then
        return 1
    fi

    message info "The latest OpenTrack Windows installer has been downloaded.\n\nIt will now be run silently inside the targeted Wine prefix:\n$wine_prefix\n\nIf Falcon BMS is currently running, close it first."

    export WINEPREFIX="$wine_prefix"
    export WINEDEBUG="${WINEDEBUG:--all}"
    if [ -n "$wineserver_bin" ] && [ -x "$wineserver_bin" ]; then
        export WINESERVER="$wineserver_bin"
    fi

    debug_print continue "Launching OpenTrack installer ${tmp_dir}/${opentrack_download_name} with /silent in prefix ${wine_prefix} using ${wine_bin}..."
    "$wine_bin" "$tmp_dir/$opentrack_download_name" /silent
    exit_code="$?"

    if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 126 ] || [ "$exit_code" -eq 127 ] || [ "$exit_code" -eq 130 ]; then
        message warning "The OpenTrack installer exited with code $exit_code. See terminal output for details."
        return 1
    fi

    message info "OpenTrack silent install finished. If installation succeeded, the launcher can now auto-start it from your Falcon BMS prefix."
    return 0
}

# MARK: switch_prefix()
# Target the Helper at a different Falcon BMS prefix/installation
switch_prefix() {
    # Check if the config file exists
    if [ -f "$conf_dir/$conf_subdir/$wine_conf" ] && [ -f "$conf_dir/$conf_subdir/$game_conf" ]; then
        getdirs
        # Above will return code 3 if the user had to select new directories. This can happen if the stored directories are now invalid.
        # We check this so we don't prompt the user to set directories twice here.
        if [ "$?" -ne 3 ] && message question "The Helper is currently targeting this Falcon BMS install\nWould you like to change it?\n\n$wine_prefix"; then
            reset_helper "switchprefix"
            # Prompt the user for a new set of game paths
            getdirs
        fi
    else
        # Prompt the user for game paths
        getdirs
    fi
}

# MARK: update_launch_script()
# Update the game launch script if necessary
update_launch_script() {
    getdirs

    if [ "$?" -eq 1 ]; then
        # User cancelled getdirs or there was an error
        message warning "Unable to update launch script."
        return 0
    fi

    install_dir="${wine_prefix}"

    # Backup old launcher if present
    if [ -f "$wine_prefix/$wine_launch_script_name" ]; then
        cp "$wine_prefix/$wine_launch_script_name" "$wine_prefix/$(basename "$wine_launch_script_name" .sh).bak"
    fi

    if ! create_or_update_launch_script; then
        message error "Unable to generate the launch script.\n\n$wine_prefix/$wine_launch_script_name"
        return 1
    fi

    # Ensure desktop files are repaired to point to the launch script
    create_desktop_files needed
    refresh_desktop_execs

    helper_update_message=""
    case "$sync_mfd_joystick_status" in
        updated)
            helper_update_message="\n\nThe adjacent MFD helper script was updated as well:\n$sync_mfd_joystick_path"
            ;;
        current)
            helper_update_message="\n\nThe adjacent MFD helper script is already current:\n$sync_mfd_joystick_path"
            ;;
        failed)
            helper_update_message="\n\nThe adjacent MFD helper script was detected but could not be updated:\n$sync_mfd_joystick_path"
            ;;
    esac

    message info "Your game launch script has been updated/repaired.\n\nPath:\n$wine_prefix/$wine_launch_script_name$helper_update_message"
}

# MARK: edit_launch_script()
# Edit the launch script
edit_launch_script() {
    # Get/Set directory paths
    getdirs
    if [ "$?" -eq 1 ]; then
        # User cancelled and wants to return to the main menu
        # or there was an error
        return 0
    fi

    # Make sure the launch script exists
    if [ ! -f "$wine_prefix/$wine_launch_script_name" ]; then
        message error "Unable to find $wine_prefix/$wine_launch_script_name"
        return 1
    fi

    # Open the launch script in the user's preferred editor
    if [ -x "$(command -v xdg-open)" ]; then
        xdg-open "$wine_prefix/$wine_launch_script_name"
    else
        message error "xdg-open is not installed.\nYou may open the launch script manually:\n\n$wine_prefix/$wine_launch_script_name"
    fi
}

# MARK: call_launch_script()
# Call our launch script and pass it the given command line argument
call_launch_script() {
    # This function expects a string to be passed in as an argument
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The call_launch_script function expects an argument. Aborting."
    fi

    launch_arg="$1"

    # Get/Set directory paths
    getdirs
    if [ "$?" -eq 1 ]; then
        # User cancelled and wants to return to the main menu
        # or there was an error
        return 0
    fi

    # Make sure the launch script exists
    if [ ! -f "$wine_prefix/$wine_launch_script_name" ]; then
        message error "Unable to find $wine_prefix/$wine_launch_script_name"
        return 1
    fi

    # Check if the launch script is the correct version
    current_launcher_ver="$(grep "^# version:" "$wine_prefix/$wine_launch_script_name" | awk '{print $3}')"
    req_launcher_ver="1.13"

    if [ "$req_launcher_ver" != "$current_launcher_ver" ] &&
       [ "$current_launcher_ver" = "$(printf "%s\n%s" "$current_launcher_ver" "$req_launcher_ver" | sort -V | head -n1)" ]; then
        message error "Your launch script is out of date!\nPlease update your launch script before proceeding."
        return 1
    fi

    # Launch a wine shell using the launch script
    "$wine_prefix/$wine_launch_script_name" "$launch_arg"
}

# MARK: launch_protontricks()
# Open protontricks GUI for the currently targeted Falcon BMS prefix
launch_protontricks() {
    # Resolve target prefix
    getdirs
    if [ "$?" -eq 1 ]; then
        message warning "Unable to open protontricks."
        return 1
    fi

    # Resolve proton runner from the selected install
    proton_runner=""
    if [ -f "$wine_prefix/current_runner" ]; then
        proton_runner="$(sed -n '1p' "$wine_prefix/current_runner" | tr -d '\r')"
    fi

    # Fallback to launch script value when current_runner file is missing
    if [ -z "$proton_runner" ] && [ -f "$wine_prefix/$wine_launch_script_name" ]; then
        proton_runner="$(grep -e '^export proton_path=' -e '^proton_path=' "$wine_prefix/$wine_launch_script_name" | awk -F '=' '{print $2}' | tr -d '"')"
        proton_runner="$(echo "$proton_runner" | sed -e 's/^ *"//' -e 's/" *$//' -e 's/^ *//; s/ *$//')"
    fi

    if [ -z "$proton_runner" ] || [ ! -x "$proton_runner/proton" ]; then
        message warning "No valid Proton runner is configured for this install.\n\nSet a Proton runner first from 'Manage Proton Runners'."
        return 1
    fi

    # Launch package manager in GUI mode for this target prefix.
    # protontricks --gui always opens the Steam app picker first, so use
    # winetricks directly with the selected Proton environment.
    export WINEPREFIX="$wine_prefix"
    export STEAM_COMPAT_DATA_PATH="$wine_prefix"
    export PROTONPATH="$proton_runner"
    export UMU_ID=0
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$proton_runner}"

    launcher_winepath=""
    if [ -x "$proton_runner/files/bin/wine" ]; then
        launcher_winepath="$proton_runner/files/bin"
    elif [ -x "$proton_runner/bin/wine" ]; then
        launcher_winepath="$proton_runner/bin"
    fi

    if [ -z "$launcher_winepath" ]; then
        message error "Unable to locate wine binaries in the selected Proton runner:\n\n$proton_runner"
        return 1
    fi

    winetricks_bin="$(command -v winetricks 2>/dev/null || true)"
    if [ -z "$winetricks_bin" ] || [ ! -x "$winetricks_bin" ]; then
        message error "winetricks is required to open the package manager GUI.\n\nPlease install winetricks and retry."
        return 1
    fi

    export WINE="$launcher_winepath/wine"
    export WINESERVER="$launcher_winepath/wineserver"

    debug_print continue "Launching package manager for prefix: $wine_prefix"
    "$winetricks_bin" --gui
    exit_code="$?"

    if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 130 ] || [ "$exit_code" -eq 126 ]; then
        message warning "Package manager exited with code $exit_code. See terminal output for details."
        return 1
    fi

    return 0
}

# MARK: install_powershell()
# Install powershell verb into the game's wine prefix
install_powershell() {
    # Download protontricks
    download_protontricks

    # Abort if the protontricks download failed
    if [ "$?" -eq 1 ]; then
        message error "Unable to install PowerShell without protontricks. Aborting."
        return 1
    fi

    # Update directories
    getdirs

    if [ "$?" -eq 1 ]; then
        # User cancelled getdirs or there was an error
        message warning "Unable to install powershell."
        return 1
    fi

    # Get the current wine runner from the launch script
    get_current_runner
    if [ "$?" -ne 1 ]; then
        export WINE="$launcher_winepath/wine"
        export WINESERVER="$launcher_winepath/wineserver"
    fi
    # Set the correct wine prefix
    export WINEPREFIX="$wine_prefix"

    # Show a zenity pulsating progress bar
    progress_bar start "Installing PowerShell. Please wait..."
    progress_update "Installing PowerShell into ${wine_prefix}..."

    # Install powershell
    debug_print continue "Installing PowerShell into ${wine_prefix}..."
    "$protontricks_bin" -q powershell

    exit_code="$?"
    if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 130 ] || [ "$exit_code" -eq 126 ]; then
        progress_bar stop # Stop the zenity progress window
        message warning "PowerShell could not be installed. See terminal output for details."
    else
        progress_bar stop # Stop the zenity progress window
        message info "PowerShell operation complete. See terminal output for details."
    fi
}

# MARK: reinstall_bms_launcher()
# Download and re-install the latest Falcon BMS into the wine prefix
# MARK: build_bms_installer_args()
# Build installer argument array for public/internal variants.
build_bms_installer_args() {
    installer_args=("/S")

    # Keep installer behavior consistent across public/internal builds.
    installer_args+=("/noshort")

    if [ "${use_16k_tiles:-}" = "1" ]; then
        installer_args+=("/16k")
    fi

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

reinstall_bms_launcher() {
    # Update directories
    getdirs

    if [ "$?" -eq 1 ]; then
        # User cancelled getdirs or there was an error
        message error "Unable to install or update the Falcon BMS."
        return 1
    fi

    download_bms_installer
    # Abort if the download failed
    if [ "$?" -eq 1 ]; then
        message error "Unable to install or update the Falcon BMS."
        return 1
    fi

    # Get the current wine runner from the launch script
    get_current_runner
    if [ "$?" -ne 1 ]; then
        export WINE="$launcher_winepath/wine"
        export WINESERVER="$launcher_winepath/wineserver"
    else
        # Default to system wine
        launcher_winepath="$(command -v wine | xargs dirname)"
        launcher_winepath="${launcher_winepath:-/usr/bin}" # default to /usr/bin if still empty
    fi

    # Set the correct wine prefix
    export WINEPREFIX="$wine_prefix"

    # Show a zenity pulsating progress bar
    progress_bar start "Installing Falcon BMS. Please wait..."
    progress_update "Running Falcon BMS installer..."

    # Guard against a stalled installer process.
    launcher_timeout_seconds="${BMS_INSTALLER_TIMEOUT_SECONDS:-7200}"

    # Run the installer
    debug_print continue "Installing Falcon BMS. Please wait; this will take a moment..."
    reinstall_installer_path=""
    if [ -n "$selected_bms_installer" ]; then
        reinstall_installer_path="$selected_bms_installer"
    else
        reinstall_installer_path="$SCRIPT_DIR/$bms_installer"
    fi

    if ! build_bms_installer_args; then
        progress_bar stop
        return 1
    fi

    if [ -x "$(command -v timeout)" ] && [ -n "$launcher_timeout_seconds" ]; then
        timeout --foreground "$launcher_timeout_seconds" "$launcher_winepath"/wine "$reinstall_installer_path" "${installer_args[@]}"
    else
        "$launcher_winepath"/wine "$reinstall_installer_path" "${installer_args[@]}"
    fi

    exit_code="$?"
    if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 58 ] || [ "$exit_code" -eq 124 ]; then
        # User cancelled or there was an error
        "$launcher_winepath"/wineserver -k # Kill all wine processes
        progress_bar stop # Stop the zenity progress window
        if [ "$exit_code" -eq 124 ]; then
            message error "Installation timed out after ${launcher_timeout_seconds} seconds.\n\nThis usually means the installer is waiting on a hidden dialog or got stuck.\nCheck terminal output for details."
        else
            message error "Installation aborted. See terminal output for details."
        fi
        return 1
    fi

    # Stop the zenity progress window
    progress_bar stop

    # Kill the wine process after installation
    "$launcher_winepath"/wineserver -k

    message info "Falcon BMS installation complete!"
}

# MARK: display_dirs()
# Display all directories currently used by this helper and Falcon BMS
display_dirs() {
    dirs_list="\n"

    # Helper configs and keybinds
    if [ -d "$conf_dir/$conf_subdir" ]; then
        dir_path="$conf_dir/$conf_subdir"
        if [ "$use_zenity" -eq 1 ]; then
            dirs_list+="Helper configuration:\n<a href='file://$dir_path'>$dir_path</a>\n\n"
        else
            dirs_list+="Helper configuration:\n$dir_path\n\n"
        fi
    fi

    # Wine prefix
    if [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
        dir_path="$(cat "$conf_dir/$conf_subdir/$wine_conf")"
        if [ "$use_zenity" -eq 1 ]; then
            dirs_list+="Wine prefix:\n<a href='file://$dir_path'>$dir_path</a>\n\n"
        else
            dirs_list+="Wine prefix:\n$dir_path\n\n"
        fi
    fi

    # Falcon BMS installation
    if [ -f "$conf_dir/$conf_subdir/$game_conf" ]; then
        dir_path="$(cat "$conf_dir/$conf_subdir/$game_conf")"
        if [ "$use_zenity" -eq 1 ]; then
            dirs_list+="Falcon BMS game directory:\n<a href='file://$dir_path'>$dir_path</a>\n\n"
        else
            dirs_list+="Falcon BMS game directory:\n$dir_path\n\n"
        fi
    fi

    # Format the info header
    message_heading="These directories are currently being used by this Helper and Falcon BMS"
    if [ "$use_zenity" -eq 1 ]; then
        message_heading="<b>$message_heading</b>"
    fi

    message info "$message_heading\n$dirs_list"
}

# MARK: display_wiki()
# Display the BMS Wiki
display_wiki() {
    # Display a message containing the URL
    message info "See the Wiki for our Quick-Start Guide, Troubleshooting,\nand Performance Tuning Recommendations:\n\n$bms_wiki"
}

# MARK: reset_helper()
# Delete the helper's config directory
reset_helper() {
    if [ "$1" = "switchprefix" ]; then
        # This gets called by the switch_prefix and install_game functions
        # We only want to delete configs related to the game path in order to target a different game install
        debug_print continue "Deleting $conf_dir/$conf_subdir/{$wine_conf,$game_conf}..."
        rm --interactive=never "${conf_dir:?}/$conf_subdir/"{"$wine_conf","$game_conf"}
    elif message question "All config files will be deleted from:\n\n$conf_dir/$conf_subdir\n\nDo you want to proceed?"; then
        # Called normally by the user, wipe all the things!
        debug_print continue "Deleting $conf_dir/$conf_subdir/*.conf..."
        rm --interactive=never "${conf_dir:?}/$conf_subdir/"*.conf
        message info "The Helper has been reset!"
        # Terminate the script after a user-requested reset so the interface closes
        exit 0
    fi
    # Also wipe path variables so the reset takes immediate effect
    wine_prefix=""
    game_path=""
}

# MARK: uninstall_bms()
# Remove Falcon BMS installation, desktop files, and icon
uninstall_bms() {
    # Prompt for directories (will use saved values if present)
    getdirs
    if [ "$?" -eq 1 ]; then
        # User cancelled
        return 0
    fi

    if [ -z "$wine_prefix" ]; then
        message error "No Falcon BMS installation targeted."
        return 1
    fi

    install_dir="$wine_prefix"
    prefix_desktop_file="$install_dir/$bms_desktop_basename"
    localshare_desktop_file="${data_dir}/applications/$bms_desktop_basename"
    home_desktop_file="${XDG_DESKTOP_DIR:-$HOME/Desktop}/$bms_desktop_basename"
    legacy_localshare_desktop_file="${data_dir}/applications/Falcon BMS.desktop"
    legacy_home_desktop_file="${XDG_DESKTOP_DIR:-$HOME/Desktop}/Falcon BMS.desktop"
    legacy_prefix_desktop_file="$install_dir/Falcon BMS.desktop"
    icon_file="${data_dir}/icons/hicolor/256x256/apps/bms-launcher.png"

    if ! message question "This will permanently delete the Falcon BMS installation at:\n\n$install_dir\n\nand remove desktop shortcuts and icon. Continue?"; then
        return 0
    fi

    # Try to stop wine processes
    if [ -x "$(command -v wineserver)" ]; then
        wineserver -k 2>/dev/null || true
    fi

    # Remove the installation folder
    if [ -d "$install_dir" ]; then
        rm -r --interactive=never "$install_dir"
    fi

    # Remove desktop files and icon
    rm -f -- "$prefix_desktop_file" "$localshare_desktop_file" "$home_desktop_file"
    # Also remove legacy shortcut names used before mode-specific desktop files,
    # but only if we're in public mode (legacy files use public mode name "Falcon BMS.desktop")
    if [ "$bms_mode" = "public" ]; then
        rm -f -- "$legacy_prefix_desktop_file" "$legacy_localshare_desktop_file" "$legacy_home_desktop_file"
    fi
    rm -f -- "$icon_file"

    # Update desktop database
    if [ -x "$(command -v update-desktop-database)" ]; then
        update-desktop-database "${data_dir}/applications" 2>/dev/null || true
    fi

    # Remove saved config entries for wine prefix and game path
    rm -f -- "${conf_dir:?}/$conf_subdir/$wine_conf" "${conf_dir:?}/$conf_subdir/$game_conf"
    # Clean up config dir if it only contains firstrun.conf
    cleanup_conf_if_only_firstrun

    message info "Falcon BMS has been uninstalled."
    # Terminate the script interface after successful uninstall
    exit 0
}

############################################################################
######## end maintenance functions #########################################
############################################################################

############################################################################
######## begin dxvk functions ##############################################
############################################################################

# MARK: dxvk_menu()
# Menu to select and install a dxvk into the wine prefix
dxvk_menu() {
    # Configure the menu
    menu_text_zenity="<b><big>Manage Your DXVK Version</big>\n\nSelect which DXVK you'd like to update or install</b>\n\nYou may choose from the following options:"
    menu_text_terminal="Manage Your DXVK Version\n\nSelect which DXVK you'd like to update or install\nYou may choose from the following options:"
    menu_text_height="300"
    menu_type="radiolist"

    # Configure the menu options
    standard_msg="Update or Switch to Standard DXVK"
    async_msg="Update or Switch to Async DXVK"
    nvapi_msg="Add or Update DXVK-NVAPI"
    quit_msg="Return to the main menu"

    # Set the options to be displayed in the menu
    menu_options=("$standard_msg" "$async_msg" "$nvapi_msg" "$quit_msg")
    # Set the corresponding functions to be called for each of the options
    menu_actions=("install_dxvk standard" "install_dxvk async" "install_dxvk nvapi" "menu_loop_done")

    # Calculate the total height the menu should be
    # menu_option_height = pixels per menu option
    # #menu_options[@] = number of menu options
    # menu_text_height = height of the title/description text
    # menu_text_height_zenity4 = added title/description height for libadwaita bigness
    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"

    # Set the label for the cancel button
    cancel_label="Go Back"

    # Call the menu function.  It will use the options as configured above
    menu
}

# MARK: install_dxvk()
# Entry function to install or update DXVK in the wine prefix
#
# Requires one argument to specify which type of dxvk to install
# Supports "standard", "async", "nvapi"
install_dxvk() {
    # Sanity checks
    if [ "$#" -lt 1 ]; then
        debug_print exit "Script error: The install_dxvk function expects one argument. Aborting."
    fi

    # Update directories
    getdirs

    if [ "$?" -eq 1 ]; then
        # User cancelled getdirs or there was an error
        message warning "Unable to update dxvk."
        return 1
    fi

    # Get the current wine runner from the launch script
    get_current_runner
    if [ "$?" -ne 1 ]; then
        export WINE="$launcher_winepath/wine"
        export WINESERVER="$launcher_winepath/wineserver"
    fi
    # Set the correct wine prefix
    export WINEPREFIX="$wine_prefix"

    if [ "$1" = "standard" ]; then
        install_standard_dxvk
    elif [ "$1" = "async" ]; then
        install_async_dxvk
    elif [ "$1" = "nvapi" ]; then
        install_dxvk_nvapi
    else
        debug_print exit "Script error: Unknown argument in install_dxvk function: $1. Aborting."
    fi
}

# MARK: install_standard_dxvk()
# Install or update standard dxvk in the wine prefix
#
# Expects that getdirs has already been called
# Expects that the env vars WINE, WINESERVER, and WINEPREFIX are already set
install_standard_dxvk() {
    # Download protontricks
    download_protontricks

    # Abort if the protontricks download failed
    if [ "$?" -eq 1 ]; then
        message error "Unable to update DXVK without protontricks. Aborting."
        return 1
    fi

    # Show a zenity pulsating progress bar
    progress_bar start "Updating DXVK. Please wait..."
    progress_update "Updating DXVK in ${wine_prefix}..."
    debug_print continue "Updating DXVK in ${wine_prefix}..."

    # Update dxvk
    "$protontricks_bin" -f dxvk

    exit_code="$?"
    if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 130 ] || [ "$exit_code" -eq 126 ]; then
        progress_bar stop # Stop the zenity progress window
        message warning "DXVK could not be installed. See terminal output for details."
    else
        progress_bar stop # Stop the zenity progress window
        message info "DXVK update complete. See terminal output for details."
    fi
}

# MARK: install_async_dxvk()
# Install or update async dxvk in the wine prefix
#
# Expects that getdirs has already been called
# Expects that the env vars WINE, WINESERVER, and WINEPREFIX are already set
install_async_dxvk() {
    # Sanity checks
    if [ ! -d "$wine_prefix/drive_c/windows/system32" ]; then
        message error "Unable to find the system32 directory in your Wine prefix! Your prefix may be broken.\n\n$wine_prefix/drive_c/windows/system32"
        return 1
    fi
    if [ ! -d "$wine_prefix/drive_c/windows/syswow64" ]; then
        message error "Unable to find the syswow64 directory in your Wine prefix! Your prefix may be broken.\n\n$wine_prefix/drive_c/windows/syswow64"
        return 1
    fi

    # Get the file download url
    # Assume the first item returned by the API is the latest version
    download_url="$(curl -sL "${dxvk_async_source}" | grep -Eo "\"direct_asset_url\": ?\"[^\"]+\"" | grep "releases" | grep -F ".tar.gz" | cut -d '"' -f4 | cut -d '?' -f1)"

    # Sanity check
    if [ -z "$download_url" ]; then
        message warning "Could not find the requested dxvk file.  The GitLab API may be down or rate limited."
        return 1
    fi

    # Get file name info
    download_filename="$(basename "$download_url")"
    download_basename="$(basename "$download_filename" .tar.gz)"

    # Download the item to the tmp directory
    download_file "$download_url" "$download_filename" "DXVK"

    # Sanity check
    if [ ! -f "$tmp_dir/$download_filename" ]; then
        # Something went wrong with the download and the file doesn't exist
        message error "Something went wrong and the requested DXVK file could not be downloaded!"
        debug_print continue "Download failed! File not found: $tmp_dir/$download_filename"
        return 1
    fi

    # Show a zenity pulsating progress bar
    progress_bar start "Updating DXVK. Please wait..."
    progress_update "Extracting DXVK and preparing files..."

    # Extract the archive to the tmp directory
    debug_print continue "Extracting DXVK into $tmp_dir/$download_basename..."
    tar -xf "$tmp_dir/$download_filename" -C "$tmp_dir"

    # Make sure the expected directories exist
    if [ ! -d "$tmp_dir/$download_basename/x64" ] || [ ! -d "$tmp_dir/$download_basename/x32" ]; then
        progress_bar stop # Stop the zenity progress window
        message warning "Unexpected file structure in the extracted DXVK. The file may be corrupt."
        return 1
    fi

    # Install the dxvk into the wine prefix
    debug_print continue "Copying DXVK dlls into ${wine_prefix}..."
    cp "$tmp_dir"/"$download_basename"/x64/*.dll "$wine_prefix/drive_c/windows/system32"
    cp "$tmp_dir"/"$download_basename"/x32/*.dll "$wine_prefix/drive_c/windows/syswow64"

    
    # Make sure we can locate the launch script
    if [ ! -f "$wine_prefix/$wine_launch_script_name" ]; then
        progress_bar stop # Stop the zenity progress window
        message warning "Unable to find launch script!\n$wine_prefix/$wine_launch_script_name\n\nTo enable async, set the environment variable: DXVK_ASYNC=1"
        return 0
    fi
    # Check if the DXVK_ASYNC variable is commented out in the launch script
    if ! grep -q "^#export DXVK_ASYNC=" "$wine_prefix/$wine_launch_script_name" && ! grep -q "^export DXVK_ASYNC=1" "$wine_prefix/$wine_launch_script_name"; then
        progress_bar stop # Stop the zenity progress window
        if message question "Could not find the DXVK_ASYNC environment variable in your launch script! It may be out of date.\n\nWould you like to try updating your launch script?"; then
            # Try updating the launch script
            update_launch_script

            # Check if the update was successful and we now have the env var
            if ! grep -q "^#export DXVK_ASYNC=" "$wine_prefix/$wine_launch_script_name"; then
                message warning "Could not find the DXVK_ASYNC environment variable in your launch script! The update may have failed.\n\nTo enable async, set the environment variable: DXVK_ASYNC=1"
                return 0
            fi
        else
            message warning "To enable async, set the environment variable: DXVK_ASYNC=1"
            return 0
        fi
    fi

    # Modify the launch script to uncomment the DXVK_ASYNC variable unless it's already uncommented
    if ! grep -q "^export DXVK_ASYNC=1" "$wine_prefix/$wine_launch_script_name"; then
        debug_print continue "Updating DXVK_ASYNC env var in launch script ${wine_prefix}/${wine_launch_script_name}..."
        sed -i "s|^#export DXVK_ASYNC=.*|export DXVK_ASYNC=1|" "$wine_prefix/$wine_launch_script_name"
    fi

    progress_bar stop # Stop the zenity progress window
    message info "DXVK update complete."
}

# MARK: install_dxvk_nvapi()
# Install or update dxvk-nvapi in the wine prefix
#
# Expects that getdirs has already been called
# Expects that the env vars WINE, WINESERVER, and WINEPREFIX are already set
install_dxvk_nvapi() {
    # Download protontricks
    download_protontricks next

    # Abort if the protontricks download failed
    if [ "$?" -eq 1 ]; then
        message error "Unable to install dxvk_nvapi without protontricks. Aborting."
        return 1
    fi

    # Show a zenity pulsating progress bar
    progress_bar start "Installing DXVK-NVAPI. Please wait..."
    progress_update "Installing DXVK-NVAPI..."
    debug_print continue "Installing DXVK-NVAPI in ${wine_prefix}..."

    # Update dxvk
    "$protontricks_bin" -f dxvk_nvapi

    exit_code="$?"
    if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 130 ] || [ "$exit_code" -eq 126 ]; then
        progress_bar stop # Stop the zenity progress window
        message warning "DXVK-NVAPI could not be installed. See terminal output for details."
    else
        progress_bar stop # Stop the zenity progress window
        message info "DXVK-NVAPI update complete. See terminal output for details."
    fi
}

############################################################################
######## end dxvk functions ################################################
############################################################################

# MARK: install_game()
# Install the game with Wine
install_game() {
    # Call the preflight check and confirm the user is ready to proceed
    preflight_check "wine"
    if [ "$?" -eq 1 ]; then
        # There were errors
        install_question="Before proceeding, be sure all Preflight Checks have passed!\n\nPlease refer to our Quick Start Guide:\n$bms_wiki\n\nAre you ready to continue?"
    else
        # No errors
        install_question="Before proceeding, please refer to our Quick Start Guide:\n$bms_wiki\n\nAll Preflight Checks have passed\nAre you ready to continue?"
    fi
    if ! message question "$install_question"; then
        return 1
    fi

    # Get the install path from the user
    if message question "Would you like to use the default install path?\n\n$bms_default_install_path"; then
        # Set the default install path
        install_dir="$bms_default_install_path"
    else
        if [ "$use_zenity" -eq 1 ]; then
            message info "On the next screen, select your Falcon BMS install location"

            # Get the install path from the user
            while true; do
                install_dir="$(zenity --file-selection --directory --title="Choose your Falcon BMS install directory" --filename="$HOME/" 2>/dev/null)"

                if [ "$?" -eq -1 ]; then
                    message error "An unexpected error has occurred. The Helper is unable to proceed."
                    return 1
                elif [ -z "$install_dir" ]; then
                    # User clicked cancel or something else went wrong
                    message warning "Installation cancelled."
                    return 1
                fi

                # Make sure we're not installing over an existing prefix
                if [ -d "$install_dir/$bms_dirname" ]; then
                    message warning "A directory named \"$bms_dirname\" already exists!\nPlease choose a different install location.\n\n$install_dir"
                    continue
                fi

                # Add the wine prefix subdirectory to the install path
                install_dir="$install_dir/$bms_dirname"

                break
            done
        else
            # No Zenity, use terminal-based menus
            clear
            # Get the install path from the user
            printf "Enter the desired Falcon BMS install path (case sensitive)\nie. %s\n\n" "$bms_default_install_path"
            while read -rp "Install path: " install_dir; do
                if [ -z "$install_dir" ]; then
                    printf "Invalid directory. Please try again.\n\n"
                elif [ ! -d "$install_dir" ]; then
                    if message question "That directory does not exist.\nWould you like it to be created for you?\n"; then
                        break
                    fi
                else
                    break
                fi
            done
        fi
    fi

    # Create the game path
    mkdir -p "$install_dir"

    # EAC doesn't like >10.0 wine or wow64 wine (all new wines are wow64)
    # Until EAC fixes itself, we need to force a working runner for everyone
    # The below is commented out in hopes that it can be restored in the future

    # If we can't use the system wine, we'll need to have the user select a custom wine runner to use
    #wine_path="$(command -v wine | xargs dirname)"

    #if [ "$system_wine_ok" = "false" ]; then
    #debug_print continue "Your system Wine does not meet the minimum requirements for Falcon BMS!"
    #debug_print continue "A custom wine runner will be automatically downloaded and used."

    #debug_print continue "Installing a custom wine runner..."

    #download_dir="$install_dir/runners"

    # Install the default wine runner into the prefix
    #download_wine
    # Make sure the wine download worked
    #if [ "$?" -eq 1 ]; then
    #    message error "Something went wrong while installing ${default_runner}!\nGame installation cannot proceed."
    #    return 1
    #fi

    #wine_path="$install_dir/runners/$downloaded_item_name/bin"
    #fi #### Note: End of previous if statement commented out due to new EAC requirements

    # Runner download/check moved to after installer selection to simplify first-run flow

    # Download protontricks and abort if it fails
    download_protontricks
    if [ "$?" -eq 1 ]; then
        message error "Unable to install Falcon BMS without protontricks. Aborting."
        cleanup_conf_if_only_firstrun
        return 1
    fi

    if [ "$bms_mode" != "internal" ]; then
        choose_falcon4_source
        if [ "$?" -eq 1 ]; then
            cleanup_conf_if_only_firstrun
            return 1
        fi

        if [ "$falcon4_source" = "gog" ]; then
            download_gog_installer
            if [ "$?" -eq 1 ]; then
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

    download_bms_installer
    # Abort if the download failed
    if [ "$?" -eq 1 ]; then
        message error "Unable to install Falcon BMS. Aborting."
        cleanup_conf_if_only_firstrun
        return 1
    fi

    # Ensure a runner is available in the new prefix. If none exists, offer to download the default runner.
    download_dir="$install_dir/runners"
    mkdir -p "$download_dir"
    found_runner=0
    for d in "$download_dir"/*; do
        if [ -d "$d" ]; then
            found_runner=1
            break
        fi
    done
    if [ "$found_runner" -eq 0 ]; then
        if message question "No runner was found in the new prefix at:\n\n$download_dir\n\nWould you like to download the default runner now?"; then
            # download_wine will install the default runner into $download_dir
            download_dir="$download_dir"
            download_wine
            if [ "$?" -eq 1 ]; then
                message error "Failed to download the default runner. Installation cannot proceed."
                cleanup_conf_if_only_firstrun
                return 1
            fi
            # Persist the installed runner so menus and desktop icons detect it
            if [ -n "${downloaded_item_name:-}" ]; then
                install_dir="${install_dir:-$wine_prefix}"
                mkdir -p "$install_dir"
                echo "${install_dir}/runners/${downloaded_item_name}" > "$install_dir/current_runner"
                chmod 644 "$install_dir/current_runner" 2>/dev/null || true
            fi
        else
            message error "A runner is required to proceed. Aborting installation."
            cleanup_conf_if_only_firstrun
            return 1
        fi
    fi

    # Create a temporary log file
    tmp_install_log="$(mktemp --suffix=".log" -t "bmshelper-install-XXX")"
    debug_print continue "Installation log file created at $tmp_install_log"

    # Configure the wine prefix environment
    #export WINE="$wine_path/wine"
    #export WINESERVER="$wine_path/wineserver"
    export WINEPREFIX="$install_dir"

    # Timeouts for long-running install stages (override via environment if needed).
    prefix_setup_timeout_seconds="${BMS_PREFIX_SETUP_TIMEOUT_SECONDS:-5400}"
    installer_timeout_seconds="${BMS_INSTALLER_TIMEOUT_SECONDS:-7200}"

    # Show a zenity pulsating progress bar
    progress_bar start "Preparing Wine prefix and installing Falcon BMS. Please wait..."
    progress_update "Preparing Wine prefix..."

    # Create the new prefix and install required runtime components.
    progress_update "Installing required components into the Wine prefix..."
    debug_print continue "Installing required components into the Wine prefix. Please wait; this will take a moment..."

    # Let the game installer handle .NET 4.8.1 by default.
    # Set BMS_PREINSTALL_DOTNET48=1 only if you explicitly want helper-side dotnet48 preinstall.
    prefix_components=(corefonts tahoma lucida verdana dxvk powershell win11)
    if [ "${BMS_PREINSTALL_DOTNET48:-0}" = "1" ]; then
        prefix_components+=(dotnet48)
    fi

    if [ -x "$(command -v timeout)" ] && [ -n "$prefix_setup_timeout_seconds" ]; then
        timeout --foreground "$prefix_setup_timeout_seconds" "$protontricks_bin" -q "${prefix_components[@]}" >"$tmp_install_log" 2>&1
    else
        "$protontricks_bin" -q "${prefix_components[@]}" >"$tmp_install_log" 2>&1
    fi

    exit_code="$?"
    if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 130 ] || [ "$exit_code" -eq 126 ] || [ "$exit_code" -eq 124 ]; then
        # 126 = permission denied (ie. noexec on /tmp)
        wineserver -k # Kill all wine processes
        progress_bar stop # Stop the zenity progress window
        if [ "$exit_code" -eq 124 ]; then
            message warning "Wine prefix preparation timed out after ${prefix_setup_timeout_seconds} seconds.\n\nThe install log was written to\n$tmp_install_log\n\nThis usually means a hidden installer dialog blocked automation."
        fi
        if message question "Wine prefix creation failed. Aborting installation.\nThe install log was written to\n$tmp_install_log\n\nDo you want to delete\n${install_dir}?"; then
            debug_print continue "Deleting $install_dir..."
            rm -r --interactive=never "$install_dir"
        fi
        cleanup_conf_if_only_firstrun
        return 1
    fi

    # Add registry key that prevents wine from creating unnecessary file type associations
    wine reg add "HKEY_CURRENT_USER\Software\Wine\FileOpenAssociations" /v Enable /d N /f >>"$tmp_install_log" 2>&1

    # Fix oversized fonts in the WPF / MahApps.Metro .NET Launcher
    progress_update "Applying display scaling and font fixes..."
    debug_print continue "Downloading and installing original Segoe UI fonts..."
    curl -sL "https://github.com/mrbvrz/segoe-ui-linux/archive/refs/heads/master.tar.gz" | tar -xz -C "$tmp_dir"
    cp "$tmp_dir"/segoe-ui-linux-master/font/*.ttf "$install_dir/drive_c/windows/Fonts/" 2>/dev/null || true
    
    wine reg add "HKEY_CURRENT_USER\Control Panel\Desktop" /v LogPixels /t REG_DWORD /d 96 /f >>"$tmp_install_log" 2>&1


    if [ "$falcon4_source" = "steam" ]; then
        # Create Falcon 4.0 target directory in the Proton/Wine C: drive,
        # then mirror files from the Steam installation.
        steam_target_dir="$install_dir/drive_c/Falcon 4.0"
        progress_update "Copying Steam Falcon 4.0 files into the Wine prefix..."
        debug_print continue "Copying Steam Falcon 4.0 files from $steam_falcon4_dir to $steam_target_dir"
        mkdir -p "$steam_target_dir" >>"$tmp_install_log" 2>&1
        cp -a "$steam_falcon4_dir"/. "$steam_target_dir"/ >>"$tmp_install_log" 2>&1
        copy_exit_code="$?"
        if [ "$copy_exit_code" -ne 0 ] || [ ! -f "$steam_target_dir/falcon4.exe" ]; then
            wineserver -k
            progress_bar stop
            message error "Failed to copy Steam Falcon 4.0 files into the Wine prefix.\nThe install log was written to\n$tmp_install_log"
            cleanup_conf_if_only_firstrun
            return 1
        fi

        progress_update "Applying Falcon 4.0 registry keys..."
        apply_falcon4_registry_key >>"$tmp_install_log" 2>&1
        if [ "$?" -ne 0 ]; then
            wineserver -k
            progress_bar stop
            message error "Falcon 4.0 registry initialization failed.\nThe install log was written to\n$tmp_install_log"
            cleanup_conf_if_only_firstrun
            return 1
        fi
    elif [ "$falcon4_source" = "gog" ]; then
        # Run the Falcon 4.0 GoG installer
        debug_print continue "Installing Falcon 4.0. Please wait; this will take a moment..."
        progress_update "Running Falcon 4.0 GoG installer..."
        if [ -n "$selected_gog_installer" ]; then
            wine "$selected_gog_installer" /VERYSILENT /NOICONS >>"$tmp_install_log" 2>&1
        else
            wine "$SCRIPT_DIR/$gog_installer" /VERYSILENT /NOICONS >>"$tmp_install_log" 2>&1
        fi
    else
        debug_print continue "Internal mode selected: skipping Falcon 4.0 install/source requirements."
    fi

    # Run the Falcon BMS installer
    debug_print continue "Installing Falcon BMS. Please wait; this will take a moment..."
    progress_update "Running Falcon BMS installer..."
    # Build installer arguments suitable for the selected release type.
    if ! build_bms_installer_args; then
        wineserver -k
        progress_bar stop
        cleanup_conf_if_only_firstrun
        return 1
    fi
    
    debug_print continue "Falcon BMS selected arguments: ${installer_args[*]}"

    if [ -n "$selected_bms_installer" ]; then
        if [ -x "$(command -v timeout)" ] && [ -n "$installer_timeout_seconds" ]; then
            timeout --foreground "$installer_timeout_seconds" wine "$selected_bms_installer" "${installer_args[@]}" >>"$tmp_install_log" 2>&1
        else
            wine "$selected_bms_installer" "${installer_args[@]}" >>"$tmp_install_log" 2>&1
        fi
    else
        if [ -x "$(command -v timeout)" ] && [ -n "$installer_timeout_seconds" ]; then
            timeout --foreground "$installer_timeout_seconds" wine "$SCRIPT_DIR/$bms_installer" "${installer_args[@]}" >>"$tmp_install_log" 2>&1
        else
            wine "$SCRIPT_DIR/$bms_installer" "${installer_args[@]}" >>"$tmp_install_log" 2>&1
        fi
    fi

    exit_code="$?"
    if [ "$exit_code" -eq 1 ] || [ "$exit_code" -eq 58 ] || [ "$exit_code" -eq 124 ]; then
        # User cancelled or there was an error
        wineserver -k # Kill all wine processes
        progress_bar stop # Stop the zenity progress window
        if [ "$exit_code" -eq 124 ]; then
            message warning "Falcon BMS installer timed out after ${installer_timeout_seconds} seconds.\n\nThe install log was written to\n$tmp_install_log"
        fi
        if message question "Installation aborted. The install log was written to\n$tmp_install_log\n\nDo you want to delete\n${install_dir}?"; then
            debug_print continue "Deleting $install_dir..."
            rm -r --interactive=never "$install_dir"
        fi
        cleanup_conf_if_only_firstrun
        return 0
    fi

    # Stop the zenity progress window
    progress_bar stop

    # Kill the wine process after installation
    wineserver -k

    # Save the install location to the Helper's config files
    reset_helper "switchprefix"
    wine_prefix="$install_dir"
    if [ -d "$wine_prefix/$default_install_path" ]; then
        game_path="$wine_prefix/$default_install_path/$bms_base_dir"
    fi
    getdirs

    # Verify that we have an installed game path
    if [ -z "$game_path" ]; then
        message error "Something went wrong during installation. Unable to locate the expected game path. Aborting."
        return 1
    fi

    # Copy game launch script to the wine prefix root directory
    debug_print continue "Copying game launch script to ${install_dir}..."

    # Generate or refresh the per-prefix launcher script
    if ! create_or_update_launch_script; then
        message warning "Failed to generate launch script at $install_dir/$wine_launch_script_name"
    fi
    installed_launch_script="$install_dir/$wine_launch_script_name"

    # Copy/refresh the bundled Falcon BMS icon in the local icon theme.
    if ! ensure_bms_icon_installed; then
        debug_print continue "Warning: unable to install or refresh desktop icon from $bms_icon"
    fi

    # Create .desktop files
    # Remove any GOG-created Falcon 4.0 desktop shortcuts that the GoG installer may have placed
    remove_gog_falcon4_desktop

    create_desktop_files

    debug_print continue "Installation finished"
    message info "Installation has finished. The install log was written to $tmp_install_log\n\nTo start the Falcon BMS, use the following .desktop files:\n     $home_desktop_file\n     $localshare_desktop_file\n\nOr run the following launch script:\n     $installed_launch_script\n\nIMPORTANT!\nThe Falcon BMS will offer to install the game into C:\\\Program Files\\\...\nDo not change the default path!"
}

# MARK: create_desktop_files()
# Create .desktop files for the RSI Launcher
# The default behavior is to overwite any existing .desktop files
#
# This function takes one optional string argument:
# "needed" will only create necessary desktop files that don't exist
create_desktop_files() {
    # Sanity checks
    if [ -z "$wine_prefix" ]; then
        debug_print exit "Script error: The string 'wine_prefix' was not set before calling the create_desktop_files function. Aborting."
    fi

    # $HOME/Games/Falcon-BMS/<desktop file>
    prefix_desktop_file="$install_dir/$bms_desktop_basename"
    # $HOME/.local/share/applications/<desktop file>
    localshare_desktop_file="${data_dir}/applications/$bms_desktop_basename"
    # $HOME/Desktop/<desktop file>
    home_desktop_file="${XDG_DESKTOP_DIR:-$HOME/Desktop}/$bms_desktop_basename"

    create_localshare_file="true"
    create_home_file="true"
    # If the "needed" argument is passed, only create missing desktop files.
    if [ "$1" = "needed" ]; then
        if [ -f "$localshare_desktop_file" ]; then
            create_localshare_file="false"
        fi
        if [ -f "$home_desktop_file" ]; then
            create_home_file="false"
        fi
    fi

    debug_print continue "Creating ${prefix_desktop_file}..."
    # The backup .desktop file in the prefix directory will always be created so it's up to date
    # Use the configured base dir (public vs internal) when building Exec/Path
    escaped_base_dir="$(echo "$bms_base_dir" | sed "s/\\\\/\\\\\\\\/g; s/'/\\'"/g)"

    # Ensure install_dir is set (fallback to wine_prefix)
    install_dir="${install_dir:-$wine_prefix}"

    if ! ensure_bms_icon_installed; then
        debug_print continue "Warning: unable to install or refresh desktop icon from $bms_icon"
    fi

    desktop_icon_value="bms-launcher"
    if [ -n "$install_dir" ] && [ -s "$install_dir/bms-launcher.png" ]; then
        desktop_icon_value="$install_dir/bms-launcher.png"
    fi

    # Ensure launch script exists and is up to date
    create_or_update_launch_script || true

    # $HOME/Games/Falcon-BMS/<desktop file>
    prefix_desktop_file="$install_dir/$bms_desktop_basename"

    # Detect configured runner (prefer Proton) from persisted file or the launch script and prefer its proton binary
    runner_exec="wine"
    launch_script=""
    if [ -n "$wine_prefix" ] && [ -d "$wine_prefix" ]; then
        if [ -n "$wine_launch_script_name" ] && [ -f "$wine_prefix/$wine_launch_script_name" ]; then
            launch_script="$wine_prefix/$wine_launch_script_name"
        else
            for f in "$wine_prefix"/*; do
                if [ -f "$f" ] && (grep -q -e '^export proton_path=' -e '^proton_path=' "$f" 2>/dev/null || grep -q -e '^export wine_path=' -e '^wine_path=' "$f" 2>/dev/null); then
                    launch_script="$f"
                    break
                fi
            done
        fi
    fi
    if [ -n "$launch_script" ]; then
        # Prefer proton_path if available, otherwise fall back to wine_path
        launcher_path="$(grep -e '^export proton_path=' -e '^proton_path=' "$launch_script" | awk -F '=' '{print $2}' | tr -d '"')"
        if [ -z "$launcher_path" ]; then
            launcher_path="$(grep -e '^export wine_path=' -e '^wine_path=' "$launch_script" | awk -F '=' '{print $2}' | tr -d '"')"
        fi
        launcher_path="$(echo "$launcher_path" | sed -e 's/^ *"//' -e 's/" *$//' -e 's/^ *//; s/ *$//')"
        if [ -n "$launcher_path" ] && [ -x "$launcher_path/proton" ]; then
            runner_exec="$launcher_path/proton"
        elif [ -n "$launcher_path" ] && [ -x "$launcher_path/wine" ]; then
            runner_exec="$launcher_path/wine"
        fi
    fi

    # If a persisted current runner file exists in the install dir, prefer it
    if [ -f "$install_dir/current_runner" ]; then
        persisted_runner="$(sed -n '1p' "$install_dir/current_runner" | tr -d '\r')"
        if [ -n "$persisted_runner" ] && [ -x "$persisted_runner/proton" ]; then
            runner_exec="$persisted_runner/proton"
        elif [ -n "$persisted_runner" ] && [ -x "$persisted_runner/wine" ]; then
            runner_exec="$persisted_runner/wine"
        fi
    fi

    # Desktop entries now launch through the generated prefix script
    exec_line="Exec=\"$install_dir/$wine_launch_script_name\""

    echo "[Desktop Entry]
Name=$bms_base_dir Launcher
Type=Application
Comment=$bms_base_dir
Keywords=Falcon BMS,Simulation,Flight,Game;
Terminal=false
StartupNotify=true
Categories=Game;
StartupWMClass=FalconBMS_Alternative_Launcher.exe
$exec_line
Path=$install_dir/drive_c/$bms_base_dir/Launcher/
Icon=$desktop_icon_value" > "$prefix_desktop_file"

    if [ "$create_localshare_file" = "true" ] || [ "$create_home_file" = "true" ]; then
        debug_print continue "Creating missing system .desktop files (if needed)..."

        # Copy the new desktop file to ~/.local/share/applications
        if [ "$create_localshare_file" = "true" ]; then
            mkdir -p "${data_dir}/applications"
            cp "$prefix_desktop_file" "$localshare_desktop_file"
        fi

        # Copy the new desktop file to the user's desktop directory
        if [ "$create_home_file" = "true" ]; then
            if [ -d "$(dirname "$home_desktop_file")" ]; then
                cp "$prefix_desktop_file" "$home_desktop_file"
            fi
        fi

        # Update the .desktop file database if the command is available
        if [ -x "$(command -v update-desktop-database)" ]; then
            debug_print continue "Running update-desktop-database..."
            update-desktop-database "${data_dir}/applications"
        fi

        # Check if the desktop files were created successfully
        if [ "$create_home_file" = "true" ] && [ ! -f "$home_desktop_file" ]; then
            # Desktop file couldn't be created
            message warning "Warning: The .desktop file could not be created!\n\n${home_desktop_file}"
        fi
        if [ "$create_localshare_file" = "true" ] && [ ! -f "$localshare_desktop_file" ]; then
            # Desktop file couldn't be created
            message warning "Warning: The .desktop file could not be created!\n\n${localshare_desktop_file}"
        fi
    fi
}

# MARK: remove_gog_falcon4_desktop()
# Remove desktop shortcuts created by the GOG Falcon 4.0 installer (if present)
remove_gog_falcon4_desktop() {
    home_desktop_dir="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
    localshare_dir="${data_dir}/applications"
    install_dir_safe="${install_dir:-}" # may be empty in some contexts

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

# MARK: set_latest_default_runner()
# Resolve the latest default runner from runner_sources and keep only archive
# formats supported by download_install().
set_latest_default_runner() {
    # Prefer GE-Proton as the default source for new installs.
    # Fallback to the first source if GE-Proton is not present.
    default_runner_source=0
    default_runner_file=""
    default_runner=""

    for (( i=0; i<"${#runner_sources[@]}"; i=i+2 )); do
        if [ "${runner_sources[i]}" = "GE-Proton" ]; then
            default_runner_source="$i"
            break
        fi
    done

    # runner_sources stores pairs: description url
    default_runner_name="${runner_sources[$default_runner_source]}"
    default_runner_api="${runner_sources[$default_runner_source+1]}"

    if [ -z "$default_runner_api" ]; then
        return 1
    fi

    # Parse downloadable assets and keep supported archive formats only.
    # Exclude checksums and text sidecar files.
    # Prefer PROTON_DEFAULT_VERSION if it exists in the release list, else fallback to latest.
    while IFS= read -r asset; do
        case "$asset" in
            *.tar.gz|*.tgz|*.tar.xz|*.tar.zst)
                if [ -z "$default_runner_file" ]; then
                    default_runner_file="$asset" # store the first available (latest) as fallback
                fi
                # Check if the asset matches the PROTON_DEFAULT_VERSION
                if echo "$asset" | grep -q "${PROTON_DEFAULT_VERSION}"; then
                    default_runner_file="$asset" # override with the requested version
                    break                        # break early as we found the preferred
                fi
                ;;
        esac
    done < <(
        curl -s "${default_runner_api}?per_page=${max_download_items:-50}" |
            grep -Eo '"browser_download_url": ?"[^"]+"' |
            cut -d '"' -f4 |
            cut -d '?' -f1 |
            xargs -n1 basename |
            grep -viE 'sha|sum|txt|\.ini$'
    )

    if [ -z "$default_runner_file" ]; then
        return 1
    fi

    case "$default_runner_file" in
        *.tar.gz)
            default_runner="$(basename "$default_runner_file" .tar.gz)"
            ;;
        *.tgz)
            default_runner="$(basename "$default_runner_file" .tgz)"
            ;;
        *.tar.xz)
            default_runner="$(basename "$default_runner_file" .tar.xz)"
            ;;
        *.tar.zst)
            default_runner="$(basename "$default_runner_file" .tar.zst)"
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

# MARK: download_wine()
# Download a default wine runner for use by the installer
# Expects download_dir to be set before calling
download_wine() {
    if [ -z "$download_dir" ]; then
        debug_print exit "Script error: The string 'download_dir' was not set before calling the download_wine function. Aborting."
    fi

    # Set variables for the latest default runner
    set_latest_default_runner
    # Sanity check
    if [ "$?" -eq 1 ]; then
        message error "Could not fetch the latest default wine runner.  The Github API may be down or rate limited."
        return 1
    fi

    # Set up variables needed for the download functions, quick and dirty
    # For more details, see their usage in the download_select_install and download_install functions
    declare -n download_sources=runner_sources
    download_type="runner"
    download_versions=("$default_runner_file")
    contributor_name="${download_sources[$default_runner_source]}"
    contributor_url="${download_sources[$default_runner_source+1]}"
    case "$contributor_url" in
        https://api.github.com/*)
            download_url_type="github"
            ;;
        https://gitlab.com/api/v4/projects/*)
            download_url_type="gitlab"
            ;;
        *)
            debug_print exit "Script error:  Unknown api/url format in ${download_type}_sources array. Aborting."
            ;;
    esac

    # Call the download_install function with the above options to install the default wine runner
    download_install 0

    if [ "$?" -eq 1 ]; then
        return 1
    fi
}

## Winetricks removed: protontricks is used instead. See download_protontricks().

# MARK: download_protontricks()
# Resolve protontricks to the OS-installed binary.
# Kept as a compatibility wrapper for existing callers.
download_protontricks() {
    protontricks_bin="$(command -v protontricks 2>/dev/null || true)"
    if [ -z "$protontricks_bin" ] || [ ! -x "$protontricks_bin" ]; then
        message error "Unable to locate protontricks. Please install protontricks and retry."
        return 1
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
select_steam_falcon4_install() {
    local default_dir="$HOME/.steam/steam/steamapps/common/Falcon 4.0"
    local selected_dir=""

    if [ "$use_zenity" -eq 1 ]; then
        selected_dir="$(zenity --file-selection --directory --title="Select Steam Falcon 4.0 directory" --filename="$default_dir/" 2>/dev/null)"
        if [ -z "$selected_dir" ]; then
            message error "No Steam Falcon 4.0 directory selected. Aborting installation."
            return 1
        fi
    else
        printf "Enter your Steam Falcon 4.0 directory\nExample: %s\n\n" "$default_dir"
        read -rp "Directory path: " selected_dir
        if [ -z "$selected_dir" ]; then
            message error "No Steam Falcon 4.0 directory provided. Aborting installation."
            return 1
        fi
    fi

    if [ ! -d "$selected_dir" ] || [ ! -f "$selected_dir/falcon4.exe" ]; then
        message error "Invalid Steam Falcon 4.0 directory. Expected to find falcon4.exe in:\n$selected_dir\n\nInstallation cancelled."
        return 1
    fi

    steam_falcon4_dir="$selected_dir"
    return 0
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

    if message question "Do you have Falcon 4.0 installed from Steam?\n\nSelect 'No' to use the default GOG installer flow."; then
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
    if [ -z "$WINEPREFIX" ] || [ ! -d "$WINEPREFIX/drive_c" ]; then
        message error "Unable to apply Falcon 4.0 registry key: Wine prefix is not ready."
        return 1
    fi

    local falcon4_reg_file="$WINEPREFIX/drive_c/falcon_4.reg"
    cat > "$falcon4_reg_file" << 'EOF'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\MicroProse]

[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\MicroProse\\Falcon]

[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\MicroProse\\Falcon\\4.0]
"baseDir"="C:\\Falcon 4.0"
"misctexDir"="C:\\Falcon 4.0\\terrdata\\misctex"
"movieDir"="C:\\Falcon 4.0"
"objectDir"="C:\\Falcon 4.0\\terrdata\\objects"
"theaterDir"="C:\\Falcon 4.0\\terrdata\\korea"

[HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\MicroProse\\Falcon\\4.0\\MPR]
"MPRDetect3Dx"=dword:00000001
"MPRDetectCPU"=dword:00000001
"MPRDetectMMX"=dword:00000001
"MPRDetectXMM"=dword:00000001
EOF

    wine regedit /S "C:\\falcon_4.reg"
    local reg_exit_code="$?"
    rm -f "$falcon4_reg_file" 2>/dev/null || true

    if [ "$reg_exit_code" -ne 0 ]; then
        message error "Failed to apply Falcon 4.0 registry keys."
        return 1
    fi

    return 0
}

# MARK: download_gog_installer()
# Opens browser for GOG download, waits for the installer to appear in Downloads, then runs it
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
        zenity --info --no-wrap --text="Please locate the GOG Falcon 4.0 installer (setup_falcon_4_2.0.0.1.exe)" --title="Falcon BMS Helper" 2>/dev/null
    else
        printf "Please locate the GOG Falcon 4.0 installer (setup_falcon_4_2.0.0.1.exe)\n"
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
        if ! echo "$bn" | grep -qi "setup_falcon_4_2.0.0.1"; then
            message warning "Selected file does not appear to be the GOG launcher: $bn (Attempt $attempts of 3)"
            continue
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
# Opens browser for GOG download, waits for the installer to appear in Downloads, then runs it
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
    # Prompt the user to select the Falcon BMS installer file
    # show an informational popup once before the first prompt
    if [ -x "$(command -v zenity)" ]; then
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
    # Public: Falcon BMS_4.38.<X>_Full_Setup(.exe)
    # Internal: Falcon BMS_4.38.<X>_Internal_Full_Setup(.exe)
    if echo "$bn" | grep -Eq "^Falcon BMS_4\.38\.[0-9]+_Internal_Full_Setup(\.exe)?$"; then
        detected_type="internal"
    elif echo "$bn" | grep -Eq "^Falcon BMS_4\.38\.[0-9]+_Full_Setup(\.exe)?$"; then
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
            if [ $? -ne 0 ]; then
                bms_key=""
            fi
        else
            printf "Enter internal installation key (optional): "
            read -r bms_key
        fi
        bms_key="$(echo "$bms_key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [ -z "$bms_key" ]; then
            message error "Internal installer key is required for internal Falcon BMS installs."
            cleanup_conf_if_only_firstrun
            return 1
        fi
    fi
    # Don't show a popup on successful selection to reduce interruptions
    debug_print continue "Falcon BMS installer selected: $selected_bms_installer (use_16k_tiles=$use_16k_tiles bms_key=$bms_key)"
    return 0
}

# MARK: get_latest_release()
# Get the latest release version of a repo. Expects "user/repo_name" as input
# Credits for this go to https://gist.github.com/lukechilds/a83e1d7127b78fef38c2914c4ececc3c
get_latest_release() {
    # Sanity check
    if [ "$#" -lt 1 ]; then
        debug_print exit "Script error: The get_latest_release function expects one argument. Aborting."
    fi

    curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
        grep '"tag_name":' |                                            # Get tag line
        sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

# MARK: format_urls()
# Format some URLs for Zenity
format_urls() {
    if [ "$use_zenity" -eq 1 ]; then
        releases_url="<a href='$releases_url'>$releases_url</a>"
        bms_wiki="<a href='$bms_wiki'>$bms_wiki</a>"
    fi
}

# MARK: quit()
quit() {
    exit 0
}


############################################################################
######## MAIN ##############################################################
############################################################################

# MARK: MAIN
# Zenity availability/version check
use_zenity=0
# Initialize some variables
menu_option_height="0"
menu_text_height_zenity4="0"
menu_height_max="0"
if [ -x "$(command -v zenity)" ]; then
    if zenity --version >/dev/null; then
        use_zenity=1
        zenity_version="$(zenity --version)"

        # Zenity 4.0.0 uses libadwaita, which changes fonts/sizing
        # Add pixels to each menu option depending on the version of zenity in use
        # used to dynamically determine the height of menus
        # menu_text_height_zenity4 = Add extra pixels to the menu title/description height for libadwaita bigness
        if [ "$zenity_version" != "4.0.0" ] && 
            [ "$zenity_version" = "$(printf "%s\n%s" "$zenity_version" "4.0.0" | sort -V | head -n1)" ]; then
            # zenity 3.x menu sizing
            menu_option_height="26"
            menu_text_height_zenity4="0"
            menu_height_max="400"
        else
            # zenity 4.x+ menu sizing
            menu_option_height="26"
            menu_text_height_zenity4="0"
            menu_height_max="800"
        fi
    else
        # Zenity is broken
        debug_print continue "Zenity failed to start. Falling back to terminal menus"
    fi
fi

# Check if this is the user's first run of the Helper
if [ -f "$conf_dir/$conf_subdir/$firstrun_conf" ]; then
    is_firstrun="$(cat "$conf_dir/$conf_subdir/$firstrun_conf")"
fi
if [ "$is_firstrun" != "false" ]; then
    is_firstrun="true"
fi

# Format some URLs for Zenity if the Helper was not invoked with command-line arguments (handle those separately below)
if [ "$#" -eq 0 ]; then
    format_urls
fi

# Check if a newer verison of the script is available
#latest_version="$(get_latest_release "$repo")"

# Sort the versions and check if the installed Helper is smaller
#if [ "$latest_version" != "$current_version" ] &&
#   [ "$current_version" = "$(printf "%s\n%s" "$current_version" "$latest_version" | sort -V | head -n1)" ]; then
#
#    message info "The latest version of the BMS Helper is $latest_version\nYou are using $current_version\n\nYou can download new releases here:\n$releases_url"
#fi

# MARK: Cmdline arguments
# If invoked with command line arguments, process them and exit
if [ "$#" -gt 0 ]; then
    while [ "$#" -gt 0 ]
    do
        # Victor_Tramp expects the spanish inquisition.
        case "$1" in
            --help | -h )
                printf "Falcon BMS Linux Users Group Helper Script
Usage: bms-helper <options>
  -p, --preflight-check         Run system optimization checks
  -i, --install                 Install Falcon BMS
  -u, --update-launch-script    Update/Repair the game launch script
  -e, --edit-launch-script      Edit the game launch script
  -c, --wine-config             Launch winecfg for the game's prefix
  -j, --wine-controllers        Launch Wine controllers configuration
  -d, --show-directories        Show all Falcon BMS and Helper directories
  -w, --show-wiki               Show the BMS Wiki
  -x, --reset-helper            Delete saved bms-helper configs
  -g, --no-gui                  Use terminal menus instead of a Zenity GUI
  -v, --version                 Display version info and exit
"
                exit 0
                ;;
            --preflight-check | -p )
                cargs+=("preflight_check")
                ;;
            --install | -i )
                cargs+=("install_game")
                ;;
            --update-launch-script | -u )
                cargs+=("update_launch_script")
                ;;
            --edit-launch-script | -e )
                cargs+=("edit_launch_script")
                ;;
            --wine-config | -c )
                cargs+=("call_launch_script config")
                ;;
            --wine-controllers | -j )
                cargs+=("call_launch_script controllers")
                ;;
            --show-directories | -d )
                cargs+=("display_dirs")
                ;;
            --show-wiki | -w )
                cargs+=("display_wiki")
                ;;
            --reset-helper | -x )
                cargs+=("reset_helper")
                ;;
            --no-gui | -g )
                # If zenity is unavailable, it has already been set to 0
                # and this setting has no effect
                use_zenity=0
                ;;
            --version | -v )
                printf "BMS Helper %s\n" "$current_version"
                exit 0
                ;;
            * )
                printf "%s: Invalid option '%s'\n" "$0" "$1"
                exit 0
                ;;
        esac
        # Shift forward to the next argument and loop again
        shift
    done

    # Format some URLs for Zenity
    format_urls

    # Call the requested functions and exit
    if [ "${#cargs[@]}" -gt 0 ]; then
        cmd_line="true"
        for (( x=0; x<"${#cargs[@]}"; x++ )); do
            ${cargs[x]}
        done
        exit 0
    fi
fi

# Set up the main menu heading
menu_heading_zenity="<b><big>Welcome Pilot!</big>\n\nThis tool is provided by the Falcon BMS</b>\nFor help, see our wiki: $bms_wiki"
menu_heading_terminal="Welcome Pilot!\n\nThis tool is provided by the Falcon BMS\nFor help, see our wiki: $bms_wiki"

# MARK: First Run
# First run
firstrun_message="It looks like this is your first time running the Helper\n\nWould you like to run the Preflight Check and install Falcon BMS?"
if [ "$use_zenity" -eq 1 ]; then
    firstrun_message="$menu_heading_zenity\n\n$firstrun_message"
else
    firstrun_message="$menu_heading_terminal\n\n$firstrun_message"
fi
if [ "$is_firstrun" = "true" ]; then
    if message question "$firstrun_message"; then
        install_game
    fi
    # Store the first run state for subsequent launches
    if [ ! -d "$conf_dir/$conf_subdir" ]; then
        mkdir -p "$conf_dir/$conf_subdir"
    fi
    echo "false" > "$conf_dir/$conf_subdir/$firstrun_conf"
fi

# MARK: Main Menu
# Loop the main menu until the user selects quit
while true; do
    # Configure the menu
    menu_text_zenity="$menu_heading_zenity"
    menu_text_terminal="$menu_heading_terminal"
    menu_text_height="300"
    menu_type="radiolist"

    # Configure the menu options
    preflight_msg="Preflight Check (System Optimization)"
    # If an installation is detected, offer Uninstall instead of Install
    # Detect whether a valid installation exists. Check multiple sources:
    # 1) saved gamedir.conf points to an existing directory
    # 2) saved wine prefix (winedir.conf) contains the expected game base dir
    # 3) the default install path exists
    installed="false"
    if [ -f "$conf_dir/$conf_subdir/$game_conf" ]; then
        saved_game_path="$(cat "$conf_dir/$conf_subdir/$game_conf")"
        if [ -n "$saved_game_path" ] && [ -d "$saved_game_path" ]; then
            installed="true"
        fi
    fi
    if [ "$installed" = "false" ] && [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
        saved_wine_prefix="$(cat "$conf_dir/$conf_subdir/$wine_conf")"
        if [ -n "$saved_wine_prefix" ] && [ -d "$saved_wine_prefix/drive_c/$bms_base_dir" ]; then
            installed="true"
        fi
    fi
    if [ "$installed" = "false" ] && [ -d "$bms_default_install_path" ]; then
        installed="true"
    fi

    if [ "$installed" = "true" ]; then
        install_msg_wine="Remove Falcon BMS"
        install_action="uninstall_bms"
    else
        install_msg_wine="Install Falcon BMS"
        install_action="install_game"
    fi
    #runners_msg_wine="Manage Wine Runners"
    dxvk_msg_wine="Manage DXVK"
    maintenance_msg="Maintenance and Troubleshooting"
    #randomizer_msg="Get a random Penguin's Falcon BMS referral code"
    quit_msg="Quit"

    # Set the options to be displayed in the menu
    proton_msg="Manage Proton Runners"
    menu_options=("$preflight_msg" "$install_msg_wine" "$proton_msg" "$maintenance_msg" "$quit_msg")
    # Set the corresponding functions to be called for each of the options
    menu_actions=("preflight_check" "$install_action" "proton_manage" "maintenance_menu" "quit")

    # Calculate the total height the menu should be
    # menu_option_height = pixels per menu option
    # #menu_options[@] = number of menu options
    # menu_text_height = height of the title/description text
    # menu_text_height_zenity4 = added title/description height for libadwaita bigness
    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"

    # Set the label for the cancel button
    cancel_label="Quit"

    # Call the menu function.  It will use the options as configured above
    menu
done
