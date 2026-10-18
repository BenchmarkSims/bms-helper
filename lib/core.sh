# shellcheck shell=bash
# bms-helper: messages, menus, progress bars and privilege helpers.
# Sourced by bms-helper.sh; defines functions only.

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
