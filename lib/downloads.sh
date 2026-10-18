# shellcheck shell=bash
# bms-helper: downloads from the public Falcon BMS servers: the latest
# installer and the 16K high resolution terrain tiles.
# Sourced by bms-helper.sh; defines functions only.
#
# Only public endpoints are used: the website API for release information
# and the three public CDNs, between which downloads are spread so the
# load is shared (each worker starts on its own mirror and falls back to
# the others).

bms_api_url="https://api.falcon-bms.com/api"
bms_cdn_mirrors=("https://cdn.falcon-bms.com" "https://cdn1.falcon-bms.com" "https://cdn2.falcon-bms.com")
# Same user agent as the official Falcon BMS downloader
bms_cdn_user_agent="bmsdownloader"
# Highest 16K tile number; missing numbers are gaps in the tile set
bms_16k_max_tile=1024

# MARK: cdn_fetch()
# Download one file from the CDNs, starting with the given mirror and
# trying the others on failure. Partial downloads resume.
# Usage: cdn_fetch <path on the CDN> <destination> [first mirror index]
# Returns 0 when downloaded, 4 when no mirror has the file, 1 on failure.
#
# The mirrors don't answer an unsatisfiable resume the same way (416 or
# 404), so a 404 to a resume is retried from scratch, and a file only
# counts as missing when every mirror answers 404.
cdn_fetch() {
    cf_count="${#bms_cdn_mirrors[@]}"
    cf_first="${3:-0}"
    cf_missing=0
    for (( cf_try=0; cf_try<cf_count; cf_try++ )); do
        cf_mirror="${bms_cdn_mirrors[$(( (cf_first + cf_try) % cf_count ))]}"
        for cf_mode in resume fresh; do
            if [ "$cf_mode" = "resume" ]; then
                [ -s "$2.part" ] || continue
                cf_resume=(-C -)
            else
                rm -f "$2.part"
                cf_resume=()
            fi
            cf_code="$(curl -sfL -A "$bms_cdn_user_agent" --connect-timeout 15 --retry 3 --retry-delay 5 \
                "${cf_resume[@]}" -o "$2.part" -w '%{http_code}' "$cf_mirror/$1" 2>/dev/null)"
            case "$cf_code" in
                200|206)
                    mv -f "$2.part" "$2"
                    return 0
                    ;;
                404|416)
                    [ "$cf_mode" = "resume" ] && continue
                    [ "$cf_code" = "404" ] && cf_missing=$(( cf_missing + 1 ))
                    break
                    ;;
                *)
                    # Network or server error: try the next mirror
                    break
                    ;;
            esac
        done
    done
    [ "$cf_missing" -eq "$cf_count" ] && rm -f "$2.part" && return 4
    return 1
}

# MARK: cdn_head()
# Print the HTTP status and size of a CDN file as "<code> <bytes>", asking
# the other mirrors before reporting it missing (a mirror may lag behind)
# Usage: cdn_head <path on the CDN> [first mirror index]
cdn_head() {
    ch_count="${#bms_cdn_mirrors[@]}"
    ch_result="000 0"
    for (( ch_try=0; ch_try<ch_count; ch_try++ )); do
        ch_mirror="${bms_cdn_mirrors[$(( (${2:-0} + ch_try) % ch_count ))]}"
        ch_result="$(curl -sIL -A "$bms_cdn_user_agent" -m 20 "$ch_mirror/$1" | tr -d '\r' |
            awk '/^HTTP/ {code=$2} tolower($1) == "content-length:" {len=$2} END {print (code ? code : "000"), len + 0}')"
        [ "${ch_result%% *}" = "200" ] && break
    done
    printf '%s\n' "$ch_result"
}

# MARK: cdn_download_jobs()
# Download every "<cdn path><TAB><destination>" line of a job file with one
# worker per mirror, showing the overall progress.
# Usage: cdn_download_jobs <job file> <progress text>
# Sets cdn_failed to the number of files that could not be downloaded.
# Returns 1 if the user cancelled.
cdn_download_jobs() {
    cdj_jobs="$1"
    cdj_total="$(grep -c . "$cdj_jobs")"
    cdj_progress="$tmp_dir/cdn-progress"
    : > "$cdj_progress"
    cdn_failed=0
    [ "$cdj_total" -gt 0 ] || return 0

    cdj_pids=()
    for (( cdj_k=0; cdj_k<"${#bms_cdn_mirrors[@]}"; cdj_k++ )); do
        (
            awk -v k="$cdj_k" -v n="${#bms_cdn_mirrors[@]}" '(NR - 1) % n == k' "$cdj_jobs" |
                while IFS=$'\t' read -r cdj_path cdj_dest; do
                    cdn_fetch "$cdj_path" "$cdj_dest" "$cdj_k"
                    echo "$? $cdj_path" >> "$cdj_progress"
                done
        ) &
        cdj_pids+=("$!")
    done

    cdj_cancelled=0
    if [ "$use_zenity" -eq 1 ]; then
        (
            while kill -0 "${cdj_pids[@]}" 2>/dev/null; do
                cdj_done="$(grep -c . "$cdj_progress")"
                echo "$(( cdj_done * 100 / cdj_total ))"
                echo "# $2 ($cdj_done / $cdj_total)"
                sleep 2
            done
            echo 100
        ) | zenity --progress --auto-close --width=420 --title="Falcon BMS Linux Helper" --text="$2" 2>/dev/null
        [ "${PIPESTATUS[1]}" -ne 0 ] && cdj_cancelled=1
    else
        while kill -0 "${cdj_pids[@]}" 2>/dev/null; do
            printf '\r%s: %s / %s ' "$2" "$(grep -c . "$cdj_progress")" "$cdj_total"
            sleep 2
        done
        printf '\n'
    fi

    if [ "$cdj_cancelled" -eq 1 ]; then
        kill "${cdj_pids[@]}" 2>/dev/null
        pkill -P "$$" curl 2>/dev/null
        wait "${cdj_pids[@]}" 2>/dev/null
        return 1
    fi
    wait "${cdj_pids[@]}"
    cdn_failed="$(grep -c '^1 ' "$cdj_progress")"
    return 0
}

# MARK: find_7z()
# Set sevenzip_bin to an installed 7-Zip; return 1 if there is none
find_7z() {
    sevenzip_bin="$(command -v 7zz || command -v 7z || command -v 7za)"
    [ -n "$sevenzip_bin" ]
}

# MARK: bms_latest_release()
# Ask the website API for the latest Falcon BMS release. Sets
# latest_series (ie. 4.38), latest_version (ie. 4.38.1) and
# latest_exe_sha256 (the installer's published SHA-256).
bms_latest_release() {
    command -v python3 >/dev/null 2>&1 || return 1
    blr_info="$(curl -sf -m 20 "$bms_api_url/updates?populate=*" | python3 -I -c '
import json, re, sys
releases = [u for u in json.load(sys.stdin).get("data", []) if u.get("latest")]
if not releases:
    sys.exit(1)
bases = [v for v in releases[0].get("versions", []) if v.get("type") == "base"]
if not bases:
    sys.exit(1)
base = max(bases, key=lambda v: [int(x) for x in re.findall(r"\d+", v["number"])])
sha = re.search(r"SHA256:\s*([0-9a-fA-F]{64})", base.get("hash") or "")
if not sha:
    sys.exit(1)
print(releases[0]["number"], ".".join(base["number"].split(".")[:3]), sha.group(1).lower())
' 2>/dev/null)" || return 1
    read -r latest_series latest_version latest_exe_sha256 <<< "$blr_info"
    [ -n "$latest_exe_sha256" ]
}

# MARK: download_latest_bms_installer()
# Download, extract and verify the latest public Falcon BMS installer into
# the given directory, reusing a verified copy from an earlier run. Sets
# selected_bms_installer. Expects bms_latest_release to have succeeded.
download_latest_bms_installer() {
    dli_dir="$1/Falcon BMS_${latest_version}_Full_Setup"
    dli_exe="$dli_dir/Falcon BMS_${latest_version}_Full_Setup.exe"
    mkdir -p "$dli_dir" || return 1

    if [ -f "$dli_exe" ] && [ -f "${dli_exe%.exe}.nsisbin" ] &&
       [ "$(sha256sum "$dli_exe" | cut -d ' ' -f1)" = "$latest_exe_sha256" ]; then
        debug_print continue "Using the already downloaded installer: $dli_exe"
        selected_bms_installer="$dli_exe"
        return 0
    fi

    if ! find_7z; then
        message error "7-Zip is needed to unpack the downloaded installer.\n\nInstall the '7zip' (or 'p7zip') package and try again."
        return 1
    fi

    # The installer is published as a split 7z archive (Base.7z.001, ...)
    progress_bar start "Looking up the Falcon BMS $latest_version installer..."
    dli_parts=()
    dli_bytes=0
    for (( dli_i=1; dli_i<1000; dli_i++ )); do
        dli_name="$(printf 'Base.7z.%03d' "$dli_i")"
        read -r dli_code dli_size <<< "$(cdn_head "BMS$latest_series/Base/$dli_name" "$dli_i")"
        case "$dli_code" in
            200) ;;
            404) break ;;
            *) progress_bar stop
               message error "The Falcon BMS download server could not be reached. Check your internet connection and try again."
               return 1 ;;
        esac
        dli_parts+=("$dli_name")
        dli_bytes=$(( dli_bytes + dli_size ))
    done
    progress_bar stop
    if [ "${#dli_parts[@]}" -eq 0 ]; then
        message error "No Falcon BMS $latest_version installer was found on the download servers."
        return 1
    fi

    # Room for the archive and the unpacked installer at the same time
    dli_need_gb=$(( dli_bytes * 2 / 1073741824 + 1 ))
    dli_free_gb="$(df -Pk "$dli_dir" | awk 'NR==2 {printf "%d", $4 / 1048576}')"
    if [ "$dli_free_gb" -lt "$dli_need_gb" ] &&
       ! message question "Downloading and unpacking the installer needs about ${dli_need_gb} GB, but only ${dli_free_gb} GB are free at:\n\n$dli_dir\n\nContinue anyway?"; then
        return 1
    fi

    dli_jobs="$tmp_dir/installer-jobs"
    : > "$dli_jobs"
    for dli_name in "${dli_parts[@]}"; do
        [ -f "$dli_dir/$dli_name" ] || printf '%s\t%s\n' "BMS$latest_series/Base/$dli_name" "$dli_dir/$dli_name" >> "$dli_jobs"
    done
    if ! cdn_download_jobs "$dli_jobs" "Downloading Falcon BMS $latest_version"; then
        message warning "Download cancelled. Starting the installation again resumes it."
        return 1
    fi
    if [ "$cdn_failed" -gt 0 ]; then
        message error "$cdn_failed part(s) of the installer could not be downloaded. Starting the installation again resumes the download."
        return 1
    fi

    progress_bar start "Unpacking the Falcon BMS installer..."
    "$sevenzip_bin" x -y -o"$dli_dir" "$dli_dir/Base.7z.001" > "$tmp_dir/7z.log" 2>&1
    dli_unpack="$?"
    progress_bar stop
    if [ "$dli_unpack" -ne 0 ] || [ ! -f "$dli_exe" ]; then
        message error "Unpacking the installer failed. The download may be damaged; delete\n$dli_dir\nand try again.\n\n$(tail -n 3 "$tmp_dir/7z.log")"
        return 1
    fi
    if [ "$(sha256sum "$dli_exe" | cut -d ' ' -f1)" != "$latest_exe_sha256" ]; then
        message error "The downloaded installer does not match the checksum published on falcon-bms.com, so it will not be used.\n\n$dli_exe"
        return 1
    fi
    # 7-Zip already verified the archive's checksums; the parts are no longer needed
    rm -f -- "${dli_parts[@]/#/$dli_dir/}"

    selected_bms_installer="$dli_exe"
    debug_print continue "Downloaded and verified $dli_exe"
    return 0
}

############################################################################
######## 16K high resolution terrain tiles #################################
############################################################################

# MARK: tiles_16k_dir()
# Print the 16K tiles directory of the targeted install
tiles_16k_dir() {
    printf '%s\n' "$game_path/Data/TerrData/Korea/NewTerrain/Photoreal/16K"
}

# MARK: download_16k_tiles()
# Download the missing 16K terrain tiles of the targeted install (it also
# completes an interrupted download)
download_16k_tiles() {
    dt_dir="$(tiles_16k_dir)"
    mkdir -p "$dt_dir" || return 1
    # Marks an unfinished download until every tile is in place
    touch "$dt_dir/.incomplete"

    dt_jobs="$tmp_dir/16k-jobs"
    : > "$dt_jobs"
    for (( dt_n=1; dt_n<=bms_16k_max_tile; dt_n++ )); do
        [ -f "$dt_dir/$dt_n.dds" ] || printf '%s\t%s\n' "16K/$dt_n.dds" "$dt_dir/$dt_n.dds" >> "$dt_jobs"
    done

    if ! cdn_download_jobs "$dt_jobs" "Downloading 16K terrain tiles"; then
        message warning "Download cancelled. Use '16K terrain tiles' > Repair in the main menu to resume it."
        return 1
    fi
    dt_count="$(find "$dt_dir" -maxdepth 1 -name '*.dds' | wc -l)"
    if [ "$cdn_failed" -gt 0 ]; then
        message warning "$cdn_failed tile(s) could not be downloaded ($dt_count installed).\n\nUse '16K terrain tiles' > Repair in the main menu to retry."
        return 1
    fi
    rm -f "$dt_dir/.incomplete"
    debug_print continue "16K terrain tiles installed: $dt_count"
    return 0
}

# MARK: tiles_16k_state()
# Print the state of the 16K tiles: none, partial, installed or disabled
# Usage: tiles_16k_state <16K directory>
tiles_16k_state() {
    if [ -f "$1/.incomplete" ] || compgen -G "$1/*.part" >/dev/null; then
        echo "partial"
    elif compgen -G "$1/*.dds" >/dev/null; then
        echo "installed"
    elif compgen -G "$1_disabled/*.dds" >/dev/null; then
        echo "disabled"
    else
        echo "none"
    fi
}

# MARK: tiles_16k_menu()
# Offer the 16K tiles actions that fit their current state
tiles_16k_menu() {
    getdirs || return 1
    if [ ! -d "$game_path" ]; then
        message error "Falcon BMS was not found in this install:\n\n$game_path"
        return 1
    fi

    tm_dir="$(tiles_16k_dir)"
    tm_state="$(tiles_16k_state "$tm_dir")"
    case "$tm_state" in
        none)
            tm_status="Not installed"
            menu_options=("Add the 16K tiles (about 27 GB download)")
            menu_actions=("install_16k_tiles")
            ;;
        partial)
            tm_status="Incomplete (the download was interrupted)"
            menu_options=("Repair: finish the download and replace damaged tiles" "Disable the 16K tiles" "Remove the 16K tiles")
            menu_actions=("install_16k_tiles" "disable_16k_tiles" "remove_16k_tiles")
            ;;
        installed)
            tm_status="Installed ($(find "$tm_dir" -maxdepth 1 -name '*.dds' | wc -l) tiles, $(du -sh "$tm_dir" 2>/dev/null | cut -f1))"
            menu_options=("Repair: replace damaged or missing tiles" "Disable the 16K tiles (keeps them on disk)" "Remove the 16K tiles")
            menu_actions=("install_16k_tiles" "disable_16k_tiles" "remove_16k_tiles")
            ;;
        disabled)
            tm_status="Disabled (kept on disk, not used by Falcon BMS)"
            menu_options=("Enable the 16K tiles" "Remove the 16K tiles")
            menu_actions=("enable_16k_tiles" "remove_16k_tiles")
            ;;
    esac
    menu_options+=("Return to the main menu")
    menu_actions+=(":")

    menu_text_zenity="<b><big>High resolution (16K) terrain tiles</big></b>\n\nKorea 16K tiles: $tm_status\nNot recommended with 12 GB of video memory or less."
    menu_text_terminal="High resolution (16K) terrain tiles\n\nKorea 16K tiles: $tm_status\nNot recommended with 12 GB of video memory or less."
    menu_text_height="300"
    menu_type="radiolist"
    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"
    cancel_label="Go Back"
    menu
}

# MARK: tiles_16k_busy()
# True (after telling the user) if Falcon BMS is running
tiles_16k_busy() {
    if bms_running; then
        message warning "Close Falcon BMS before changing the terrain tiles."
        return 0
    fi
    return 1
}

# MARK: install_16k_tiles()
# Add the 16K tiles, or repair them: tiles whose size differs from the
# server's are replaced, and missing ones are downloaded
install_16k_tiles() {
    getdirs || return 1
    tiles_16k_busy && return 1

    it_dir="$(tiles_16k_dir)"
    case "$(tiles_16k_state "$it_dir")" in
        disabled)
            message info "The 16K tiles are disabled. Enable them instead of downloading them again."
            return 0
            ;;
        none)
            it_free_gb="$(df -Pk "$game_path" | awk 'NR==2 {printf "%d", $4 / 1048576}')"
            if [ "$it_free_gb" -lt 28 ] &&
               ! message question "Only ${it_free_gb} GB are free; the tiles need about 27 GB.\n\nContinue anyway?"; then
                return 0
            fi
            ;;
        *)
            # All tiles have the same size; ask the server once
            it_sample="$(find "$it_dir" -maxdepth 1 -name '*.dds' -printf '%f\n' 2>/dev/null | head -n1)"
            if [ -n "$it_sample" ]; then
                progress_bar start "Checking the installed 16K tiles..."
                read -r it_code it_size <<< "$(cdn_head "16K/$it_sample")"
                if [ "$it_code" = "200" ] && [ "$it_size" -gt 0 ]; then
                    it_bad="$(find "$it_dir" -maxdepth 1 -name '*.dds' ! -size "${it_size}c" -print -delete | wc -l)"
                    debug_print continue "16K repair: removed $it_bad damaged tile(s)."
                fi
                progress_bar stop
                if [ "$it_code" != "200" ]; then
                    message error "The Falcon BMS download servers could not be reached. Check your internet connection and try again."
                    return 1
                fi
            fi
            ;;
    esac

    download_16k_tiles && message info "The 16K terrain tiles are installed and complete."
}

# MARK: disable_16k_tiles()
# Keep the 16K tiles on disk but hide them from Falcon BMS (16K -> 16K_disabled)
disable_16k_tiles() {
    getdirs || return 1
    tiles_16k_busy && return 1
    dis_dir="$(tiles_16k_dir)"
    if [ -e "${dis_dir}_disabled" ]; then
        message error "A disabled copy of the 16K tiles already exists:\n\n${dis_dir}_disabled\n\nRemove the 16K tiles first."
        return 1
    fi
    if mv -- "$dis_dir" "${dis_dir}_disabled"; then
        message info "The 16K terrain tiles are disabled. Falcon BMS now uses the standard tiles.\n\nEnable them again at any time without downloading."
    else
        message error "The 16K tiles could not be disabled."
        return 1
    fi
}

# MARK: enable_16k_tiles()
# Use previously disabled 16K tiles again (16K_disabled -> 16K)
enable_16k_tiles() {
    getdirs || return 1
    tiles_16k_busy && return 1
    en_dir="$(tiles_16k_dir)"
    if compgen -G "$en_dir/*.dds" >/dev/null; then
        message error "16K tiles are already active in:\n\n$en_dir"
        return 1
    fi
    rmdir "$en_dir" 2>/dev/null
    if mv -- "${en_dir}_disabled" "$en_dir"; then
        message info "The 16K terrain tiles are enabled again."
    else
        message error "The 16K tiles could not be enabled."
        return 1
    fi
}

# MARK: remove_16k_tiles()
# Delete the 16K tiles, active or disabled
remove_16k_tiles() {
    getdirs || return 1
    tiles_16k_busy && return 1
    rm_dir="$(tiles_16k_dir)"
    rm_size="$(du -shc "$rm_dir" "${rm_dir}_disabled" 2>/dev/null | tail -n1 | cut -f1)"
    if message question "Remove the 16K terrain tiles ($rm_size)?\n\nThey can be downloaded again at any time."; then
        rm -r --interactive=never -- "${rm_dir:?}" "${rm_dir:?}_disabled" 2>/dev/null
        if [ -e "$rm_dir" ] || [ -e "${rm_dir}_disabled" ]; then
            message error "Some 16K tiles could not be removed:\n\n$rm_dir"
            return 1
        fi
        message info "The 16K terrain tiles were removed."
    fi
}
