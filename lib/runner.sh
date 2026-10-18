# shellcheck shell=bash
# bms-helper: Proton runner selection, download and removal.
# Sourced by bms-helper.sh; defines functions only.
#
# The runner of an install is stored as PROTONPATH in bms-launch.conf.

# MARK: runner_supported()
# True if the directory is a Proton runner the helper can use: GE-Proton,
# UMU-Proton or CachyOS Proton (they ship protonfixes with winetricks)
runner_supported() {
    [ -n "$1" ] && [ -x "$1/proton" ] && [ -d "$1/protonfixes" ]
}

# MARK: get_current_runner()
# Set current_runner_path/current_runner_basename (and proton_path) from the
# targeted install's launch settings
get_current_runner() {
    current_runner_path=""
    current_runner_basename=""

    getdirs || return 1

    current_runner_path="$(conf_get "$bms_conf" PROTONPATH)"
    if [ -n "$current_runner_path" ]; then
        current_runner_basename="$(basename "$current_runner_path")"
    fi
    proton_path="$current_runner_path"
    return 0
}

# MARK: set_runner()
# Make the targeted install use the given Proton runner
set_runner() {
    if ! runner_supported "$1"; then
        message error "This Proton runner can't be used by the Helper:\n\n$1\n\nUse GE-Proton, UMU-Proton or CachyOS Proton."
        return 1
    fi
    if bms_running; then
        message warning "Close Falcon BMS before changing its Proton runner."
        return 1
    fi

    proton_path="$1"
    [ -f "$bms_conf" ] || write_launch_conf_template "$bms_conf"
    conf_set "$bms_conf" PROTONPATH "$proton_path"
    install_launch_script
}

# MARK: choose_default_runner()
# Set proton_path to a usable runner for the targeted install: the newest one
# already downloaded, else the default GE-Proton download, else a supported
# runner installed on the system. Returns 1 if none could be found.
choose_default_runner() {
    proton_path=""
    download_dir="$bms_root/runners"

    for cdr_dir in $(find "$download_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V -r); do
        if runner_supported "$cdr_dir"; then
            proton_path="$cdr_dir"
            return 0
        fi
    done

    if download_wine && runner_supported "$download_dir/$downloaded_item_name"; then
        proton_path="$download_dir/$downloaded_item_name"
        return 0
    fi

    collect_external_proton_runners
    if [ "${#external_proton_paths[@]}" -gt 0 ]; then
        proton_path="${external_proton_paths[0]}"
        return 0
    fi
    return 1
}

# MARK: download_manage()
# Manage downloads. Called by a dedicated download type manage function, ie proton_manage()
#
# This function expects the following variables to be set:
#
# - The string download_sources is a formatted array containing the URLs
#   of items to download. It should be pointed to the appropriate
#   array set at the top of the script using indirect expansion.
#   See runner_sources at the top and proton_manage() for examples.
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
# See proton_manage() for a configuration example.
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
                menu_options+=("Select an installed Proton runner (GE / UMU / CachyOS)")
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

# MARK: collect_external_proton_runners()
# Detect supported Proton installs provided by Steam, Heroic or the OS so they
# can be selected without being managed or deleted by this helper.
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

        # Only GE-Proton style runners (GE, UMU, CachyOS) ship protonfixes and
        # winetricks, which umu and the helper rely on. Valve's Proton builds
        # don't, and don't work reliably outside Steam, so they are skipped.
        if ! runner_supported "$_candidate_path"; then
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

    set_runner "$selected_external_proton_path" || return 1

    message info "Launch environment updated to use:\n\n$selected_external_proton_label\n$selected_external_proton_path"
}

# MARK: select_existing_proton_runner_menu()
# Present Steam/OS-provided Proton runners in a dedicated submenu.
select_existing_proton_runner_menu() {
    collect_external_proton_runners
    get_current_runner

    if [ "${#external_proton_paths[@]}" -eq 0 ]; then
        message info "No supported Proton runners (GE-Proton, UMU-Proton, CachyOS Proton) were detected."
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

    # Get directories so we know where the install is
    getdirs || return 1

    set_latest_default_runner
    if [ "$?" -eq 1 ]; then
        message error "Could not fetch the latest default Proton runner. The Github API may be down or rate limited."
        return 1
    fi

    # Proton runners are downloaded into the install root
    download_dir="$bms_root/runners"

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
        if { [ "$download_type" = "runner" ] || [ "$download_type" = "proton" ]; } && [ "$contributor_name" = "GE-Proton" ]; then
            filter_keywords="lol|diablo"
            # GE-Proton also publishes aarch64 builds; hide them unless we're actually on aarch64
            if [ "$host_arch" != "aarch64" ]; then
                filter_keywords="${filter_keywords}|aarch64"
            fi
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
# Point the install at a newly downloaded runner, or replace a deleted one
#
# The following variables are expected to be set before calling this function:
# - post_download_type (string. "none", "configure-proton")
# - post_download_required (string. Set automatically in install/delete functions)
# - downloaded_item_name (string. For installs only. Set automatically in download_install function)
# - download_dir (string)
post_download() {
    if [ -z "$post_download_type" ]; then
        debug_print exit "Script error: The string 'post_download_type' was not set before calling the post_download function. Aborting."
    elif [ -z "$download_dir" ]; then
        debug_print exit "Script error: The string 'download_dir' was not set before calling the post_download function. Aborting."
    fi

    if [ "$post_download_type" = "none" ]; then
        return 0
    fi

    if [ "$post_download_required" = "installed" ]; then
        set_runner "${download_dir}/${downloaded_item_name}" || return 1
        message info "Falcon BMS will now use the Proton runner:\n\n${downloaded_item_name}"
    elif [ "$post_download_required" = "deleted" ]; then
        message info "The Proton runner used by Falcon BMS has been deleted!\n\nA replacement will now be selected."
        proton_path=""
        if ! choose_default_runner || ! set_runner "$proton_path"; then
            message warning "No replacement Proton runner could be set up.\n\nInstall one before launching Falcon BMS."
            return 1
        fi
        message info "Falcon BMS will now use the Proton runner:\n\n$(basename "$proton_path")"
    else
        debug_print exit "Script error: Unknown post_download_required value in post_download function. Aborting."
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
            grep -viE 'sha|sum|txt|\.ini$' |
            { [ "$host_arch" = "aarch64" ] && cat || grep -vi 'aarch64'; }
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
# Download the default Proton runner (GE-Proton) into download_dir
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
    # Keep the caller's download_type (ie. the Proton menu's "proton")
    download_wine_saved_type="$download_type"
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
    download_wine_rc="$?"
    download_type="$download_wine_saved_type"
    [ "$download_wine_rc" -ne 1 ]
}
