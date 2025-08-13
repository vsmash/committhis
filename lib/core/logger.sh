
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


supports_truecolor() { [[ "${COLORTERM:-}" == *truecolor* || "${COLORTERM:-}" == *24bit* ]]; }
supports_256color()  { local n; n=$(tput colors 2>/dev/null || echo 0); [ "$n" -ge 256 ]; }

export twofivesixcolor_supported=supports_256color
export truecolor_supported=supports_truecolor



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
BOrange='\033[1;38;2;255;165;0m'    # Bold Orange

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
Orange='\033[38;5;208m'   # Orange

# Special formatting
Color_Off='\033[0m'     # Text Reset
BWhiteBG='\033[47m'     # White Background
NC='\033[0m'

# Print a decorated header
print_header() {
    echo -e "\n${BPurple}════════════════════════════════════════════════════════════════${Color_Off}"
    echo -e "${BSoftPink}|))${BBlue}                 Welcome to MAIASS ${Color_Off}"
    echo -e "${BPurple}═══════════════════════════════════════════════════════════════${Color_Off}\n"
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
    echo -e "${Orange}⚠ $1${Color_Off}"
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

# print a line that has a gradient of colors from one to another. default to soft pink to burgundy
# use a unicode dash if unicode is supported or a regular dash if not
print_gradient_line() {
  # Defaults: soft pink -> burgundy
  local repeat="${1:-80}"
  local start_hex="${2:-#f7b2c4}"   # soft pink
  local end_hex="${3:-#6b0022}"     # burgundy
  local char reset

  # Prefer Unicode long dash
  char='═'
  reset="${Color_Off:-\\033[0m}"

  # Truecolor path (smoothest)
  if supports_truecolor; then
    local sh="${start_hex#\#}" eh="${end_hex#\#}"
    local r1=$((16#${sh:0:2})) g1=$((16#${sh:2:2})) b1=$((16#${sh:4:2}))
    local r2=$((16#${eh:0:2})) g2=$((16#${eh:2:2})) b2=$((16#${eh:4:2}))
    awk -v n="$repeat" -v c="$char" -v r1="$r1" -v g1="$g1" -v b1="$b1" -v r2="$r2" -v g2="$g2" -v b2="$b2" '
      BEGIN {
        for (i = 0; i < n; i++) {
          t = (n > 1) ? i / (n - 1) : 0
          r = int(r1 + (r2 - r1) * t + 0.5)
          g = int(g1 + (g2 - g1) * t + 0.5)
          b = int(b1 + (b2 - b1) * t + 0.5)
          printf("\033[38;2;%d;%d;%dm%s", r, g, b, c)
        }
        printf("\033[0m\n")
      }'
    return
  fi

  # 256-color fallback (blocky but decent)
  if supports_256color; then
    # Pink -> burgundy-ish palette
    local palette=(224 217 218 212 211 210 205 204 198 197 161 125 89 88 52)
    local total=${#palette[@]}
    local printed=0
    local per=$(( (repeat + total - 1) / total ))
    local spaces chunk code count
    while [ "$printed" -lt "$repeat" ]; do
      for code in "${palette[@]}"; do
        count=$(( repeat - printed ))
        [ "$count" -le 0 ] && break
        [ "$count" -gt "$per" ] && count="$per"
        printf "\033[38;5;%sm" "$code"
        spaces=$(printf "%*s" "$count" "")
        # replace spaces with the chosen char (works with multibyte replacement)
        printf "%s" "${spaces// /$char}"
        printed=$(( printed + count ))
      done
    done
    printf "\033[0m\n"
    return
  fi

  # Plain ASCII fallback
  local spaces=$(printf "%*s" "$repeat" "")
  printf "%s\n" "${spaces// /$char}"
}


# print line function with optional colour and character
print_line() {
    local color="${1:-$BBlue}"   # default to $BBlue if unset
    local char="${2:-=}"         # default to '='
    local repeat="${3:-80}"      # default to 80
    local line

    line=$(printf "%*s" "$repeat" "" | tr ' ' "$char")
    echo -e "${color}${line}${Color_Off}"
}

print_thanks() {
  local reset=$'\e[0m'
  # Soft pink -> burgundy across M A I A S S
  local -a cols=(218 211 205 198 161 88)
  local word="MAIASS"
  local colored=""

  for ((i=0; i<${#word}; i++)); do
    colored+=$'\e[38;5;'${cols[i]}m"${word:i:1}"
  done

  printf '\e[38;5;218m|)) %s Thank you for using %s%s! ✨\n' "$reset" "$colored" "$reset"
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
