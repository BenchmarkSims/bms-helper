#!/usr/bin/env bash

############################################################################
# Falcon BMS Linux installer and launcher helper
############################################################################
#
# This script is designed to help you run Falcon BMS on Linux.
#
# Please see the project's github repo for more information:
# https://github.com/BenchmarkSims/bms-helper
#
# Author: https://github.com/maxwaldorf
# Forked from and inspired by https://github.com/starcitizen-lug/lug-helper
#
# License: GPLv3.0
#
# This file holds the configuration, command line handling and menus; the
# functions live in lib/ (see AGENTS.md for an overview of the modules).
############################################################################

# Check if script is run as root
if [ "$(id -u)" -eq 0 ]; then
    echo "This script is not supposed to be run as root!"
    exit 1
fi

# Resolve symlinks so lib/ is found when the helper is linked into PATH
SCRIPT_DIR="$(cd -- "$(dirname -- "$(realpath -- "$0")")" && pwd)"

# MARK: notify_fatal()
# Report a startup error before the menu functions are available
notify_fatal() {
    printf "bms-helper.sh: %b\n" "$1" 1>&2
    if [ -x "$(command -v zenity)" ]; then
        zenity --error --width="420" --title="Falcon BMS Linux Helper" --text="$1" 2>/dev/null
    elif [ -x "$(command -v notify-send)" ]; then
        notify-send "bms-helper" "$1" --icon=dialog-warning
    fi
    exit 1
}

for lib_module in core config prefix runner desktop preflight downloads install maintenance apps controllers opentrack; do
    if [ ! -f "$SCRIPT_DIR/lib/$lib_module.sh" ]; then
        notify_fatal "The Helper's 'lib' folder is incomplete ($lib_module.sh is missing).\n\nPlease download and extract the full release again."
    fi
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/lib/$lib_module.sh"
done

# Check for dependencies. Each entry is "command:package"
required_commands=(
    curl:curl tar:tar awk:gawk sed:sed grep:grep find:findutils xargs:findutils
    mktemp:coreutils chmod:coreutils sort:coreutils basename:coreutils realpath:coreutils
    dirname:coreutils cut:coreutils numfmt:coreutils tr:coreutils readlink:coreutils
    cabextract:cabextract unzip:unzip
)
missing_packages=()
for required in "${required_commands[@]}"; do
    if [ ! -x "$(command -v "${required%%:*}")" ]; then
        case " ${missing_packages[*]} " in
            *" ${required#*:} "*) ;;
            *) missing_packages+=("${required#*:}") ;;
        esac
    fi
done
if [ "${#missing_packages[@]}" -gt 0 ]; then
    notify_fatal "One or more required packages were not found on this system.\nPlease install:\n$(printf -- '- %s\n' "${missing_packages[@]}")"
fi

######## Config ############################################################

wine_conf="winedir.conf"
game_conf="gamedir.conf"
firstrun_conf="firstrun.conf"

# Release type: public (default) or internal. Flipped by --internal or by
# the installer file name.
bms_mode="public"
set_bms_mode "$bms_mode"

# Default Proton GE version to preselect on first install. Change this
# to another version basename (example: "GE-Proton10-18") if you want
# a different default when the Proton list is shown for the first time.
PROTON_DEFAULT_VERSION="GE-Proton10-32"

# CPU architecture of this machine (ie. "x86_64", "aarch64"). Used to hide
# Proton runner builds (ie. GE-Proton's "-aarch64" assets) that can't run here.
host_arch="$(uname -m)"

# Paths to bundled icons
bms_icon="$SCRIPT_DIR/bms-launcher.png"
bms_icon_256="$SCRIPT_DIR/bms-launcher-256.png"

# Use XDG base directories if defined
if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]; then
    # shellcheck source=/dev/null
    source "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
fi
conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"

# umu-launcher copy downloaded by the helper when the system has none
umu_local_dir="$data_dir/bms-helper/umu"

# Static launcher installed into each install root (lib/bms-launcher.sh).
# Keep bms_launcher_version in sync with its "# version:" line.
bms_launcher_name="bms-launcher.sh"
bms_launcher_version="2.0"
# Install layout written to <install root>/.bms-helper (see lib/config.sh)
bms_layout_version="2"

# Native Linux OpenTrack (head tracking). Falcon BMS talks to it through
# OpenTrack's "Wine" output, whose bridge we run inside the Proton prefix.
# opentrack_build_ref pins the upstream commit used for source builds.
opentrack_build_ref="f009bb52cab7bf3884b8a9b3a326aa9ce84d6299"
opentrack_local_prefix="$data_dir/bms-helper/opentrack"
opentrack_bridge_name="opentrack-proton-bridge.sh"

# Physical Thrustmaster MFDs hidden from DirectInput while the MFD helper
# (tools/mfd-joystick.py) presents them as virtual devices
mfd_physical_names=("Thrustmaster F16 MFD 1" "Thrustmaster F16 MFD 2")

# Temporary directory
tmp_dir="$(mktemp -d -t "bmshelper.XXXXXXXXXX")"
trap 'rm -r --interactive=never "$tmp_dir"' EXIT

# Startup: detect existing internal config and offer to restart in internal mode
internal_conf_dir="$conf_dir/falcon-bms-internal"
has_internal_arg=0
for _arg in "$@"; do
    if [ "$_arg" = "--internal" ]; then
        has_internal_arg=1
        break
    fi
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

# Installer detection
# User can point to an installer with the environment variable `BMS_INSTALLER`
# or the command-line option `--installer /path/to/installer.exe`.
installer_path=""
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
if [ -z "$installer_path" ] && [ -n "$BMS_INSTALLER" ]; then
    installer_path="$BMS_INSTALLER"
fi
if [ -n "$installer_path" ]; then
    detect_installer_from_path "$installer_path"
fi

# URLs for downloading Proton runners
# Elements in this array must be added in quoted pairs of: "description" "url"
# The first string in the pair is expected to contain the runner description
# The second is expected to contain the api releases url
runner_sources=(
    "GE-Proton" "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases"
)

######## Requirements ######################################################

# Minimum amount of RAM in GiB
memory_required="8"
# Minimum amount of combined RAM + swap in GiB
memory_combined_required="16"
# Minimum vm.max_map_count (the default on most current distributions)
mapcount_required="1048576"

######## Links / Versions ##################################################

# Falcon 4.0 Installer on GoG
gog_url="https://www.gog.com/downloads/falcon_gold/61603"
gog_installer="setup_falcon_4_2.0.0.1.exe"
falcon4_source="gog"
steam_falcon4_dir=""

# Github repo and script version info
repo="BenchmarkSims/bms-helper"
releases_url="https://github.com/${repo}/releases"
current_version="v2.0"

############################################################################
######## MAIN ##############################################################
############################################################################

# MARK: MAIN
# Zenity availability/version check
use_zenity=0
menu_option_height="0"
menu_text_height_zenity4="0"
menu_height_max="0"
if [ -x "$(command -v zenity)" ]; then
    if zenity --version >/dev/null; then
        use_zenity=1
        zenity_version="$(zenity --version)"

        # Zenity 4.0.0 uses libadwaita, which changes fonts/sizing
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

# MARK: auto_migrate_install()
# Upgrade an install made by an older Helper as soon as the Helper starts,
# so users never have to find a menu option for it
auto_migrate_install() {
    am_root=""
    if [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
        am_root="$(cat "$conf_dir/$conf_subdir/$wine_conf")"
    elif is_bms_install "$bms_default_install_path"; then
        am_root="$bms_default_install_path"
    fi
    if [ -n "$am_root" ] && [ -d "$am_root/drive_c" ] && [ ! -d "$am_root/pfx/drive_c" ]; then
        getdirs >/dev/null
    fi
}

# MARK: Cmdline arguments
# If invoked with command line arguments, process them and exit
if [ "$#" -gt 0 ]; then
    while [ "$#" -gt 0 ]
    do
        case "$1" in
            --help | -h )
                printf "Falcon BMS Linux Helper
Usage: bms-helper <options>
  -p, --preflight-check         Run system optimization checks
  -i, --install                 Install Falcon BMS
  -u, --update-launch-script    Update/Repair the game launch script
  -e, --edit-launch-script      Edit the launch settings (bms-launch.conf)
  -c, --wine-config             Launch winecfg for the game's prefix
  -j, --wine-controllers        Launch Wine controllers configuration
  -l, --show-logs               Show the launch and install logs
  -d, --show-directories        Show all Falcon BMS and Helper directories
  -w, --show-wiki               Show the BMS Wiki
  -x, --reset-helper            Delete saved bms-helper configs
  -g, --no-gui                  Use terminal menus instead of a Zenity GUI
  -v, --version                 Display version info and exit
      --internal | --public     Select the Falcon BMS release type
      --installer <file>        Use this Falcon BMS installer
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
            --show-logs | -l )
                cargs+=("show_logs")
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
        shift
    done

    format_urls

    if [ "${#cargs[@]}" -gt 0 ]; then
        cmd_line="true"
        for (( x=0; x<"${#cargs[@]}"; x++ )); do
            ${cargs[x]}
        done
        exit 0
    fi
fi

format_urls

# Set up the main menu heading
menu_heading_zenity="<b><big>Welcome Pilot!</big>\n\nThis tool is provided by the Falcon BMS</b>\nFor help, see our wiki: $bms_wiki"
menu_heading_terminal="Welcome Pilot!\n\nThis tool is provided by the Falcon BMS\nFor help, see our wiki: $bms_wiki"

# MARK: First Run
firstrun_message="It looks like this is your first time running the Helper\n\nWould you like to run the Preflight Check and install Falcon BMS?"
if [ "$use_zenity" -eq 1 ]; then
    firstrun_message="$menu_heading_zenity\n\n$firstrun_message"
else
    firstrun_message="$menu_heading_terminal\n\n$firstrun_message"
fi
if [ "$is_firstrun" = "true" ] && ! is_bms_install "$bms_default_install_path"; then
    if message question "$firstrun_message"; then
        install_game
    fi
    mkdir -p "$conf_dir/$conf_subdir"
    echo "false" > "$conf_dir/$conf_subdir/$firstrun_conf"
fi

auto_migrate_install

# MARK: Main Menu
# Loop the main menu until the user selects quit
while true; do
    menu_text_zenity="$menu_heading_zenity"
    menu_text_terminal="$menu_heading_terminal"
    menu_text_height="300"
    menu_type="radiolist"

    # Offer Remove instead of Install when an installation is detected
    installed="false"
    menu_root=""
    if [ -f "$conf_dir/$conf_subdir/$wine_conf" ] && is_bms_install "$(cat "$conf_dir/$conf_subdir/$wine_conf")"; then
        installed="true"
        menu_root="$(cat "$conf_dir/$conf_subdir/$wine_conf")"
    elif is_bms_install "$bms_default_install_path"; then
        installed="true"
        menu_root="$bms_default_install_path"
    fi
    if [ "$installed" = "true" ]; then
        install_msg="Remove Falcon BMS"
        install_action="uninstall_bms"
    else
        install_msg="Install Falcon BMS"
        install_action="install_game"
    fi

    preflight_msg="Preflight Check (System Optimization)"
    proton_msg="Manage Proton Runners"
    controllers_msg="Controllers and Head Tracking"
    apps_msg="Manage & Install other Apps"
    maintenance_msg="Maintenance and Troubleshooting"
    about_msg="Help and About"
    quit_msg="Quit"

    menu_options=("$preflight_msg" "$install_msg")
    menu_actions=("preflight_check" "$install_action")

    # 16K terrain tiles entry, depending on what this install has
    menu_game_path="$menu_root/pfx/drive_c/$bms_base_dir"
    if [ "$installed" = "true" ] && [ -d "$menu_game_path" ]; then
        case "$(tiles_16k_state "$menu_game_path/Data/TerrData/Korea/NewTerrain/Photoreal/16K")" in
            none) tiles_menu_state="not installed" ;;
            partial) tiles_menu_state="incomplete" ;;
            installed) tiles_menu_state="installed" ;;
            disabled) tiles_menu_state="disabled" ;;
        esac
        menu_options+=("16K terrain tiles: $tiles_menu_state")
        menu_actions+=("tiles_16k_menu")
    fi

    menu_options+=("$proton_msg" "$controllers_msg" "$apps_msg" "$maintenance_msg" "$about_msg" "$quit_msg")
    menu_actions+=("proton_manage" "controllers_menu" "manage_apps_menu" "maintenance_menu" "display_about" "quit")

    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"
    cancel_label="Quit"
    menu
done
