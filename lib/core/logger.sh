
supports_unicode() {
  case "$OSTYPE" in
    msys*|cygwin*|win32)
      [[ -n "$WT_SESSION" || "$TERM_PROGRAM" == "vscode" ]] && return 0
      return 1
      ;;
    *)
      [[ "$LANG" =~ UTF-8 || "$LC_ALL" =~ UTF-8 ]] && return 0
      return 1
      ;;
  esac
}
export unicode_supported=supports_unicode








# Color and style definitions
# Bold colors (for emphasis and important messages)
BCyan='\033[1;36m'      # Bold Cyan
BRed='\033[1;31m'       # Bold Red
BGreen='\033[1;32m'     # Bold Green
BBlue='\033[1;34m'      # Bold Blue
BYellow='\033[1;33m'    # Bold Yellow
BPurple='\033[1;35m'    # Bold Purple
BWhite='\033[1;37m'     # Bold White
BMagenta='\033[1;35m'   # Bold Magenta
BAqua='\033[1;96m'      # Bold Aqua
BSoftPink='\033[38;5;218m' # Bold Soft Pink
BNavy='\033[1;34m'      # Bold Navy
BGrey='\033[1;35m'      # Bold Grey

# Regular colors (for standard messages)
Cyan='\033[0;36m'       # Cyan
Red='\033[0;31m'        # Red
Green='\033[0;32m'      # Green
Blue='\033[0;34m'       # Blue
Yellow='\033[0;33m'     # Yellow
Purple='\033[0;35m'     # Purple
White='\033[0;37m'      # White
Magenta='\033[0;35m'    # Magenta
Aqua='\033[0;96m'       # Aqua
SoftPink='\033[38;5;218m' # Soft Pink
Navy='\033[0;34m'       # Navy
Grey='\033[0;35m'      # Grey

# Special formatting
Color_Off='\033[0m'     # Text Reset
BWhiteBG='\033[47m'     # White Background
NC='\033[0m'

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
                echo -e "${BSoftPink}|)) ${Aqua}$message${Color_Off}"
            fi
            ;;
        "normal")
            # Show brief and normal messages
            if [[ "$level" == "brief" || "$level" == "normal" ]]; then
                echo -e "${BSoftPink}|)) ${Aqua}$message${Color_Off}"
            fi
            ;;
        "debug")
            # Show all messages, use bold for debug level messages
            if [[ "$level" == "debug" ]]; then
                echo -e "${BSoftPink}|)) ${Aqua}$message${Color_Off}"
            else
                echo -e "${BSoftPink}|)) ${Aqua}$message${Color_Off}"
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


print_debug(){
    local message="$1"
    # For backward compatibility, treat debug_mode=true as verbosity_level=debug
    if [[ "$debug_mode" == "true" && "$verbosity_level" != "debug" ]]; then
        # Only log this when not already in debug verbosity to avoid noise
        log_message "DEPRECATED: Using debug_mode=true is deprecated. Please use MAIASS_VERBOSITY=debug instead."
        # Treat as if verbosity_level is debug
        local effective_verbosity="debug"
    else
        local effective_verbosity="$verbosity_level"
    fi
    if [[ "$effective_verbosity" == "debug" ]]; then
        echo -e "${Color_Off}🐛$message${Color_Off}"
        log_message "DEBUG: $message"
    fi

}

# print line function with optional colour and character
print_line() {
    local color="${1:-BBlue}"
    local char="${2:-=}"
    local repeat="${3:-80}"
    echo -e "${color}${char:0:1}\${repeat}${Color_Off}"
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
