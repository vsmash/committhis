# Print a decorated header
print_header() {
    echo -e "\n${BPurple}════════════════════════════════════════════════════════════════${Color_Off}"
    echo -e "${BBlue}                    $1 MAIASS Script${Color_Off}"
    echo -e "${BPurple}════════════════════════════════════════════════════════════════${Color_Off}\n"
}

# Print a section header
print_section() {
    echo -e "\n${Yellow}▶ $1${Color_Off}"
}

# Logging function - writes to log file if logging is enabled
log_message() {
    if [[ "$enable_logging" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$log_file"
    fi
}

# Print a success message
print_success() {
    echo -e "${Green}✔ $1${Color_Off}"
    log_message "SUCCESS: $1"
}

# Print a message that's always shown regardless of verbosity level
print_always(){
  local message="$1"
  echo -e "${Aqua}ℹ $message${Color_Off}"
  log_message "INFO: $message"
}

# Print an info message with verbosity level support
# Usage: print_info "message" [level]
# Levels: brief, normal, debug (default: normal)
print_info() {
    local message="$1"
    local level="${2:-normal}"

    # For backward compatibility, treat debug_mode=true as verbosity_level=debug
    if [[ "$debug_mode" == "true" && "$verbosity_level" != "debug" ]]; then
        # Only log this when not already in debug verbosity to avoid noise
        log_message "DEPRECATED: Using debug_mode=true is deprecated. Please use MAIASS_VERBOSITY=debug instead."
        # Treat as if verbosity_level is debug
        local effective_verbosity="debug"
    else
        local effective_verbosity="$verbosity_level"
    fi

    # Show based on verbosity level
    case "$effective_verbosity" in
        "brief")
            # Only show essential messages in brief mode
            if [[ "$level" == "brief" ]]; then
                echo -e "${Cyan}ℹ $message${Color_Off}"
            fi
            ;;
        "normal")
            # Show brief and normal messages
            if [[ "$level" == "brief" || "$level" == "normal" ]]; then
                echo -e "${Cyan}ℹ $message${Color_Off}"
            fi
            ;;
        "debug")
            # Show all messages, use bold for debug level messages
            if [[ "$level" == "debug" ]]; then
                echo -e "${BCyan}ℹ $message${Color_Off}"
            else
                echo -e "${Cyan}ℹ $message${Color_Off}"
            fi
            ;;
    esac

    log_message "INFO: $message"
}

# Print a warning message
print_warning() {
    echo -e "${Yellow}⚠ $1${Color_Off}"
    log_message "WARNING: $1"
}

# Print an error message (using bold for emphasis as errors are important)
print_error() {
    echo -e "${BRed}✘ $1${Color_Off}"
    log_message "ERROR: $1"
}


# Print a section header (always shown regardless of verbosity)
print_section() {
    echo -e "\n${White}▶ $1${Color_Off}"
    log_message "SECTION: $1"
}


# devlog.sh is my personal script for logging work in google sheets.
# if devlog.sh is not a bash script, create an empty function to prevent errors
if [ -z "$(type -t devlog.sh)" ]; then
    function devlog.sh() {
        :
    }
fi


function logthis(){
    # shellcheck disable=SC1073
    debugmsg=$(devlog.sh "$1" "?" "${project:=MAIASSS}" "${client:=VVelvary1}" "${client:=VVelvary}" "${jira_ticket_number:=Ddevops}")
}
