#!/bin/bash
# ---------------------------------------------------------------
# MAIASS (Modular AI-Augmented Semantic Scribe) v4.12.10
# Intelligent Git workflow automation script
# Copyright (c) 2025 Velvary Pty Ltd
# All rights reserved.
# This function is part of the Velvary bash scripts library.
# Author: vsmash <670252+vsmash@users.noreply.github.com>
# ---------------------------------------------------------------

# Set script directory and project directory
# Get the script's directory, resolving any symlinks (cross-platform)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS uses BSD readlink which doesn't support -f
    SCRIPT_DIR="$( cd "$(dirname "$(readlink "${BASH_SOURCE[0]}" || echo "${BASH_SOURCE[0]}")")" && pwd )"
else
    # Linux uses GNU readlink which supports -f
    SCRIPT_DIR="$( cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd )"
fi
PROJECT_DIR="$(pwd)"

source "$SCRIPT_DIR/lib/core/logger.sh"
source "$SCRIPT_DIR/lib/config/envars.sh"

# Load environment variables with new priority system
load_environment_variables

export ignore_local_env="${MAIASS_IGNORE_LOCAL_ENV:=false}"

source "$SCRIPT_DIR/lib/utils/utils.sh"
source "$SCRIPT_DIR/lib/core/logger.sh"
source "$SCRIPT_DIR/lib/core/init.sh"
source "$SCRIPT_DIR/lib/core/version.sh"
source "$SCRIPT_DIR/lib/core/logger.sh"
source "$SCRIPT_DIR/lib/utils/helpers.sh"
source "$SCRIPT_DIR/lib/core/git.sh"

source "$SCRIPT_DIR/lib/core/changelog.sh"

source "$SCRIPT_DIR/lib/core/ai.sh"
source "$SCRIPT_DIR/lib/core/commit.sh"





generate_machine_fingerprint() {
    local components=()
    local has_real_hardware_info=0
    local fallback_used=0

    # Helper function to safely get command output with fallback
    safe_command() {
        local cmd="$1"
        local fallback="$2"
        local output
        output=$($cmd 2>/dev/null || echo "$fallback")
        # Clean up the output to be a single line
        echo "$output" | tr -d '\n' | tr -s ' ' ' '
    }

    # Get CPU info
    local cpu_info
    if [[ "$OSTYPE" == "darwin"* ]]; then
        cpu_info=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)
    else
        cpu_info=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^[ \t]*//' || uname -m)
    fi
    components+=("${cpu_info:-unknown_cpu}")

    # Get memory info
    local mem_info
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mem_info=$(sysctl -n hw.memsize 2>/dev/null || echo "unknown_mem")
    else
        mem_info=$(grep -m1 "MemTotal" /proc/meminfo 2>/dev/null || echo "unknown_mem")
    fi
    components+=("${mem_info}")

    # Get hardware info
    local hardware_info
    if [[ "$OSTYPE" == "darwin"* ]]; then
        hardware_info=$(system_profiler SPHardwareDataType 2>/dev/null | grep -E "Serial Number|Hardware UUID" | head -2 | tr '\n' ' ' || echo "unknown_hardware")
    else
        hardware_info=$(dmidecode -t system 2>/dev/null | grep -E "Serial Number|UUID" | head -2 | tr '\n' ' ' || echo "unknown_hardware")
    fi
    components+=("${hardware_info}")

    # Add architecture, username, and platform
    components+=("$(uname -m)")
    components+=("$(whoami 2>/dev/null || echo "unknown_user")")
    components+=("$(uname -s)")

    # Check if we have sufficient hardware info for security
    if [[ "${components[2]}" == *"unknown"* ]]; then
        has_real_hardware_info=0
        print_warning "WARNING: Using fallback fingerprint - hardware detection failed"
        print_warning "This may allow easier abuse. Consider checking system permissions."
    else
        has_real_hardware_info=1
    fi

    # Create a stable hash from all components
    local fingerprint_data
    fingerprint_data=$(printf "%s|" "${components[@]}" | tr -d '\n')

    # Debug output if in debug mode
    if [[ "$debug_mode" == "true" ]]; then
        print_info "DEBUG: Machine fingerprint components:" "debug"
        print_info "  CPU: ${components[0]}" "debug"
        print_info "  Memory: ${components[1]}" "debug"
        print_info "  Hardware: ${components[2]}" "debug"
        print_info "  Arch: ${components[3]}" "debug"
        print_info "  Username: ${components[4]}" "debug"
        print_info "  Platform: ${components[5]}" "debug"
        print_info "  HasRealHardwareInfo: $has_real_hardware_info" "debug"
    fi

    # Generate SHA-256 hash in base64
    local hash
    if command -v openssl >/dev/null 2>&1; then
        hash=$(printf "%s" "$fingerprint_data" | openssl dgst -sha256 -binary | openssl base64 | tr -d '\n')
    elif command -v sha256sum >/dev/null 2>&1; then
        hash=$(printf "%s" "$fingerprint_data" | sha256sum | cut -d' ' -f1 | xxd -r -p | base64 | tr -d '\n')
    else
        # Last resort fallback
        print_warning "SECURITY WARNING: Using minimal fallback fingerprint (no hashing tools available)"
        local fallback="$(uname -s)-$(uname -m)-$(whoami 2>/dev/null || echo "unknown")-FALLBACK"
        if command -v base64 >/dev/null 2>&1; then
            hash=$(printf "%s" "$fallback" | base64 | tr -d '\n')
        else
            # If even base64 is not available, just use the string as is
            hash="$fallback"
        fi
        fallback_used=1
    fi

    echo "$hash"
    return $fallback_used
}


# Function to set up branch and changelog variables with override logic
setup_bumpscript_variables() {

      # Initialize debug mode early so it's available throughout the script
      export debug_mode="${MAIASS_DEBUG:=false}"
      export autopush_commits="${MAIASS_AUTOPUSH_COMMITS:=false}"
      export brand="${MAIASS_BRAND:=MAIASS}"
      # Initialize brevity and logging configuration+6
      export verbosity_level="${MAIASS_VERBOSITY:=brief}"
      export enable_logging="${MAIASS_LOGGING:=false}"
      export log_file="${MAIASS_LOG_FILE:=maiass.log}"

      # Initialize AI variables early so they're available when get_commit_message is called
      export ai_mode="${MAIASS_AI_MODE:-ask}"
      export ai_token="${MAIASS_AI_TOKEN:-}"
      export ai_model="${MAIASS_AI_MODEL:=gpt-3.5-turbo}"
      export ai_temperature="${MAIASS_AI_TEMPERATURE:=0.7}"
      export ai_max_characters="${MAIASS_AI_MAX_CHARACTERS:=8000}"
      export ai_commit_message_style="${MAIASS_AI_COMMIT_MESSAGE_STYLE:=bullet}"
      export maiass_host="https://pound.maiass.net"
      export maiass_endpoint="${maiass_host}/v1/chat/completions"
      export maiass_tokenrequest="${maiass_host}/v1/token"

      # Initialize configurable version file system
      export version_primary_file="${MAIASS_VERSION_PRIMARY_FILE:-}"
      export version_primary_type="${MAIASS_VERSION_PRIMARY_TYPE:-}"
      export version_primary_line_start="${MAIASS_VERSION_PRIMARY_LINE_START:-}"
      export version_secondary_files="${MAIASS_VERSION_SECONDARY_FILES:-}"




  # Branch name defaults with MAIASS_* overrides
  export developbranch="${MAIASS_DEVELOPBRANCH:-develop}"
  export stagingbranch="${MAIASS_STAGINGBRANCH:-staging}"
  export masterbranch="${MAIASS_MASTERBRANCH:-main}"

  # Changelog defaults with MAIASS_* overrides
  export changelog_path="${MAIASS_CHANGELOG_PATH:-.}"
  export changelog_name="${MAIASS_CHANGELOG_NAME:-CHANGELOG.md}"
  export changelog_internal_name="${MAIASS_CHANGELOG_INTERNAL_NAME:-CHANGELOG_internal.md}"

  # Repository type (for future multi-repo support)
  export repo_type="${MAIASS_REPO_TYPE:-bespoke}"

  # Path configuration based on repository type
  case "$repo_type" in
    "wordpress-theme")
      # WordPress theme: repo root is the theme directory
      export version_file_path="${MAIASS_VERSION_PATH:-.}"
      export package_json_path="${MAIASS_PACKAGE_PATH:-.}"
      export wordpress_files_path="${MAIASS_WP_FILES_PATH:-.}"
      ;;
    "wordpress-plugin")
      # WordPress plugin: repo root is the plugin directory
      export version_file_path="${MAIASS_VERSION_PATH:-.}"
      export package_json_path="${MAIASS_PACKAGE_PATH:-.}"
      export wordpress_files_path="${MAIASS_WP_FILES_PATH:-.}"
      ;;
    "wordpress-site")
      # WordPress site: theme/plugin in subdirectory
      export version_file_path="${MAIASS_VERSION_PATH:-wp-content/themes/active-theme}"
      export package_json_path="${MAIASS_PACKAGE_PATH:-wp-content/themes/active-theme}"
      export wordpress_files_path="${MAIASS_WP_FILES_PATH:-wp-content/themes/active-theme}"
      ;;
    "craft")
      # Craft CMS: typically repo root
      export version_file_path="${MAIASS_VERSION_PATH:-.}"
      export package_json_path="${MAIASS_PACKAGE_PATH:-.}"
      export wordpress_files_path=""  # Not applicable for Craft
      ;;
    "bespoke")
      # Bespoke/custom apps: typically repo root
      export version_file_path="${MAIASS_VERSION_PATH:-.}"
      export package_json_path="${MAIASS_PACKAGE_PATH:-.}"
      export wordpress_files_path=""  # Not applicable for bespoke
      ;;
    *)
      # Default fallback
      export version_file_path="${MAIASS_VERSION_PATH:-.}"
      export package_json_path="${MAIASS_PACKAGE_PATH:-.}"
      export wordpress_files_path="${MAIASS_WP_FILES_PATH:-}"
      ;;
  esac

  print_info "Branch configuration:" "normal"
  print_info "  Develop: $developbranch" "normal"
  print_info "  Staging: $stagingbranch" "normal"
  print_info "  Master: $masterbranch" "normal"

  print_info "Changelog configuration:" "normal"
  print_info "  Path: $changelog_path" "normal"
  print_info "  Main changelog: $changelog_name" "normal"
  print_info "  Internal changelog: $changelog_internal_name" "normal"

  # Pull request configuration
  export staging_pullrequests="${MAIASS_STAGING_PULLREQUESTS:-on}"
  export master_pullrequests="${MAIASS_MASTER_PULLREQUESTS:-on}"

  # Auto-detect repository provider (GitHub/Bitbucket) and extract repo info from git remote
  local git_remote_url
  git_remote_url=$(git remote get-url origin 2>/dev/null || echo "")

  # Initialize repository variables
  export REPO_PROVIDER="${MAIASS_REPO_PROVIDER:-}"
  export BITBUCKET_WORKSPACE="${MAIASS_BITBUCKET_WORKSPACE:-}"
  export BITBUCKET_REPO_SLUG="${MAIASS_BITBUCKET_REPO_SLUG:-}"
  export GITHUB_OWNER="${MAIASS_GITHUB_OWNER:-}"
  export GITHUB_REPO="${MAIASS_GITHUB_REPO:-}"

  # Detect Bitbucket
resolved_host=$(ssh -G "${git_remote_url#*@}" 2>/dev/null | awk '/^hostname / { print $2 }')
if [[ "$git_remote_url" =~ @(.*bitbucket\.org)[:/]([^/]+)/([^/\.]+) ]]; then
  export REPO_PROVIDER="bitbucket"
  export BITBUCKET_WORKSPACE="${MAIASS_BITBUCKET_WORKSPACE:-${BASH_REMATCH[2]}}"
  export client=
elif [[ "$git_remote_url" =~ @(.*github\.com)[:/]([^/]+)/([^/\.]+) ]]; then
  export REPO_PROVIDER="github"
  export GITHUB_OWNER="${MAIASS_GITHUB_OWNER:-${BASH_REMATCH[2]}}"
  export GITHUB_REPO="${MAIASS_GITHUB_REPO:-${BASH_REMATCH[3]}}"
fi


  # Calculate WordPress version constant for themes/plugins
  if [[ "$repo_type" == "wordpress-theme" || "$repo_type" == "wordpress-plugin" ]]; then
    if [[ -n "$wordpress_files_path" ]]; then
      # Use the folder name (basename of the wordpress_files_path)
      local folder_name
      folder_name=$(basename "$wordpress_files_path")

      if [[ -n "$folder_name" && "$folder_name" != "." ]]; then
        # Convert folder name to constant format: uppercase, replace dashes with underscores
        local wp_constant
        wp_constant=$(echo "$folder_name" | tr '[:lower:]' '[:upper:]' | sed 's/-/_/g')
        export wpVersionConstant="${MAIASS_WP_VERSION_CONSTANT:-${wp_constant}_RELEASE_VERSION}"
      else
        # If wordpress_files_path is ".", use the current directory name
        local current_dir
        current_dir=$(basename "$(pwd)")
        local wp_constant
        wp_constant=$(echo "$current_dir" | tr '[:lower:]' '[:upper:]' | sed 's/-/_/g')
        export wpVersionConstant="${MAIASS_WP_VERSION_CONSTANT:-${wp_constant}_RELEASE_VERSION}"
      fi
    else
      export wpVersionConstant="${MAIASS_WP_VERSION_CONSTANT:-}"
    fi
  else
    export wpVersionConstant="${MAIASS_WP_VERSION_CONSTANT:-}"
  fi

  print_info "Repository type: $repo_type" "normal"
  print_info "Path configuration:" "normal"
  print_info "  Version file: $version_file_path" "normal"
  print_info "  Package.json: $package_json_path" "normal"
  if [[ -n "$wordpress_files_path" ]]; then
    print_info "  WordPress files: $wordpress_files_path" "normal"
  fi

  # AI commit message configuration
  export ai_mode="${MAIASS_AI_MODE:-off}"
  export ai_token="${MAIASS_AI_TOKEN:-}"
  export ai_model="${MAIASS_AI_MODEL:-gpt-3.5-turbo}"


  # Determine the AI commit message style
  if [[ -n "$MAIASS_AI_COMMIT_MESSAGE_STYLE" ]]; then
    ai_commit_style="$MAIASS_AI_COMMIT_MESSAGE_STYLE"
    print_info "Using AI commit style from .env: $ai_commit_style"
  elif [[ -f ".maiass.prompt" ]]; then
    ai_commit_style="custom"
    print_info "No style set in .env; using local prompt file: .maiass.prompt"
  elif [[ -f "$HOME/.maiass.prompt" ]]; then
    ai_commit_style="global_custom"
    print_info "No style set in .env; using global prompt file: ~/.maiass.prompt"
  else
    ai_commit_style="bullet"
    print_info "No style or prompt files found; defaulting to 'bullet'"
  fi

  export ai_commit_style


  export debug_mode="${MAIASS_DEBUG:-false}"

  # Validate AI configuration - prevent ask/autosuggest modes without token
  if [[ "$ai_mode" == "ask" || "$ai_mode" == "autosuggest" ]]; then
    if [[ -z "$ai_token" ]]; then
      print_warning "AI commit message mode '$ai_mode' requires MAIASS_AI_TOKEN"
      print_warning "Falling back to 'off' mode"
      export ai_mode="off"
    fi
  fi

  print_info "Integration configuration:"
  print_info "  Staging pull requests: $staging_pullrequests"
  print_info "  Master pull requests: $master_pullrequests"
  print_info "  AI commit messages: $ai_mode"
  if [[ "$ai_mode" != "off" && -n "$ai_token" ]]; then
    print_info "  AI model: $ai_model"
    print_info "  AI temperature: $ai_temperature"
    print_info "  AI Max commit characters: $ai_max_characters"
    print_info "  AI commit style: $ai_commit_style"
  fi
  if [[ "$REPO_PROVIDER" == "bitbucket" && -n "$BITBUCKET_WORKSPACE" ]]; then
    print_info "  Repository: Bitbucket ($BITBUCKET_WORKSPACE/$BITBUCKET_REPO_SLUG)"
    export client="$BITBUCKET_WORKSPACE"
    export project="$BITBUCKET_REPO_SLUG"
  elif [[ "$REPO_PROVIDER" == "github" && -n "$GITHUB_OWNER" ]]; then
    print_info "  Repository: GitHub ($GITHUB_OWNER/$GITHUB_REPO)"
    export client="$GITHUB_OWNER"
    export project="$GITHUB_REPO"
  fi
  if [[ -n "$wpVersionConstant" ]]; then
    print_info "  WordPress version constant: $wpVersionConstant"
  fi
}

# Function to check if we're in a git repository
check_git_repository() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    print_error "This directory is not a git repository!"
    print_error "Please run this script from within a git repository."
    exit 1
  fi

  # Get the repository root directory
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$git_root" ]]; then
    print_error "Unable to determine git repository root!"
    exit 1
  fi

  export git_root
  print_success "Git repository detected: $git_root"
}

function initialiseBump() {



  print_header "$header"
  print_info "This script will help you bump the version number and manage your git workflow" "brief"
  print_info "Press ${BWhite}ctrl+c${Color_Off} to abort at any time\n" "brief"

  # Load MAIASS_* variables from .env (these override environment variables)
  load_bumpscript_env

  # Set up all branch and changelog variables with proper defaults and overrides
  setup_bumpscript_variables

  # Check and handle .gitignore for log files if logging is enabled
  check_gitignore_for_logs

  # Ensure we're in a git repository
  check_git_repository

  export GIT_MERGE_AUTOEDIT=no
  tagmessage=$(git log -1 --pretty=%B)
  export tagmessage
  branch_name=$(git rev-parse --abbrev-ref HEAD)
  export branch_name
  humandate=$(date +"%d %B %Y")
  longhumandate=$(date +"%d %B %Y (%A)")
  export humandate
  export longhumandate




  branchDetection

  # Initialize path variables with default values for version file detection
  export package_json_path="${MAIASS_PACKAGE_PATH:-.}"
  export version_file_path="${MAIASS_VERSION_PATH:-.}"

  # Check if version files exist before running version management
  local has_version_files=false

  # Check for custom primary version file first
  if [[ -n "$version_primary_file" && -f "$version_primary_file" ]]; then
    has_version_files=true
  # Check for default version files
  elif [[ -f "${package_json_path}/package.json" ]] || [[ -f "${version_file_path}/VERSION" ]]; then
    has_version_files=true
  fi

  print_info "Verion primary file: ${BYellow}${version_primary_file}" debug
  echo
  print_info "has version files: ${BYellow}$has_version_files" debug


  # if $ai_commits_only exit 0
  if [[ "$ai_commits_only" == "true" ]]; then
    checkUncommittedChanges
    echo -e "${BAqua}Mode is commits only. \nWe are done and on $branch_name branch.\nThank you for using $brand${Color_Off}"
    exit 0
  fi

  if [[ "$has_version_files" == "true" ]]; then
    changeManagement
  else
    print_warning "No version files found (package.json or VERSION)"
    print_info "Skipping version bumping and changelog management"
    print_info "Will proceed with git workflow only\n"
    # Still check for uncommitted changes even without version files
    checkUncommittedChanges
  fi

  mergeDevelop "$has_version_files" "$@"
  deployOptions
}




# Function to display help information
show_help() {
  # Define colors for help output
  local BBlue='\033[1;34m'
  local BWhite='\033[1;37m'
  local BGreen='\033[1;32m'
  local BYellow='\033[1;33m'
  local BRed='\033[1;31m'
  local BCyan='\033[1;36m'
  local Gray='\033[0;37m'
  local Color_Off='\033[0m'
  local BLime='\033[1;32m'

  echo -e "${BBlue}"
   cat <<-'EOF'
        ▄▄   ▄▄ ▄▄▄▄▄▄▄ ▄▄▄ ▄▄▄▄▄▄▄ ▄▄▄▄▄▄▄ ▄▄▄▄▄▄▄
       █  █▄█  █       █   █       █       █       █
       █       █   ▄   █   █   ▄   █  ▄▄▄▄▄█  ▄▄▄▄▄█
       █       █  █▄█  █   █  █▄█  █ █▄▄▄▄▄█ █▄▄▄▄▄
       █       █       █   █       █▄▄▄▄▄  █▄▄▄▄▄  █
       █ ██▄██ █   ▄   █   █   ▄   █▄▄▄▄▄█ █▄▄▄▄▄█ █
       █▄█   █▄█▄▄█ █▄▄█▄▄▄█▄▄█ █▄▄█▄▄▄▄▄▄▄█▄▄▄▄▄▄▄█
EOF
  echo -e "${BAqua}\n       Modular AI-Augmented Semantic Scribe\n${BYellow}\n       * AI Commit Messages\n${BLime}       * Intelligent Git Workflow Automation${Color_Off}\n"



  echo -e "${BWhite}DESCRIPTION:${Color_Off}"
  echo -e "  Automated version bumping and changelog management script that maintains"
  echo -e "  the develop branch as the source of truth for versioning. Integrates with"
  echo -e "  AI-powered commit messages and supports multi-repository workflows.\n"

  echo -e "${BWhite}USAGE:${Color_Off}"
  echo -e "  maiass [VERSION_TYPE] [OPTIONS]\n"
  echo -e "${BWhite}VERSION_TYPE:${Color_Off}"
  echo -e "  major          Bump major version (e.g., 1.2.3 → 2.0.0)"
  echo -e "  minor          Bump minor version (e.g., 1.2.3 → 1.3.0)"
  echo -e "  patch          Bump patch version (e.g., 1.2.3 → 1.2.4) ${Gray}[default]${Color_Off}"
  echo -e "  X.Y.Z          Set specific version number\n"
  echo -e "${BWhite}OPTIONS:${Color_Off}"
  echo -e "  -h, --help     Show this help message"
  echo -e "  -v, --version  Show version information\n"

  echo -e "${BWhite}QUICK START:${Color_Off}"
  echo -e "  ${BGreen}1.${Color_Off} Run ${BCyan}maiass${Color_Off} in your git repository"
  echo -e "  ${BGreen}2.${Color_Off} For AI features: Set ${BRed}MAIASS_AI_TOKEN${Color_Off} environment variable"
  echo -e "  ${BGreen}3.${Color_Off} Everything else works with sensible defaults!\n"

  echo -e "${BWhite}AI COMMIT INTELLIGENCE WORKFLOW:${Color_Off}"
  echo -e "MAIASS manages code changes in the following way:"
  echo -e "  ${BGreen}1.${Color_Off} Asks if you would like to commit your changes"
  echo -e "  ${BGreen}2.${Color_Off} If AI is available and switched in ask mode, asks if you'd like an ai suggestion"
  echo -e "  ${BGreen}3.${Color_Off} If yes or in autosuggest mode, suggests a commit mesage"
  echo -e "  ${BGreen}3.${Color_Off} You can use it or enter manual commit mode (multiline) at the prompt"
  echo -e "  ${BGreen}4.${Color_Off} Offers to merge to develop, which initiates the version and changelog workflow"
  echo -e "  ${BGreen}5.${Color_Off} If you just want ai commit suggestions and no further workflow, say no\n"

  echo -e "${BWhite}VERSION AND CHANGELOG WORKFLOW:${Color_Off}"
  echo -e "MAIASS manages version bumping and changelogging in the following way:"
  echo -e "  ${BGreen}1.${Color_Off} Merges feature branch → develop"
  echo -e "  ${BGreen}2.${Color_Off} Creates release/x.x.x branch from develop"
  echo -e "  ${BGreen}3.${Color_Off} Updates version files and changelog on release branch"
  echo -e "  ${BGreen}4.${Color_Off} Commits and pushes release branch"
  echo -e "  ${BGreen}5.${Color_Off} Merges release branch back to develop"
  echo -e "  ${BGreen}6.${Color_Off} Returns to original feature branch\n"



  echo -e "  ${BYellow}Git Flow Diagram:${Color_Off}"
  echo -e "${BAqua}    feature/xyz ──┐"
  echo -e "                  ├─→ develop ──→ release/1.2.3 ──┐"
  echo -e "    feature/abc ──┘                                ├─→ develop"
  echo -e "                                                    └─→ (tagged)\n${Color_Off}"

  echo -e "  ${BYellow}Note:${Color_Off} Script will not bump versions if develop branch requires"
  echo -e "  pull requests, as PR workflows are outside the scope of this script.\n"

  echo -e "${BWhite}EXAMPLES:${Color_Off}"
  echo -e "  maiass                         # Bump patch version with interactive prompts"
  echo -e "  maiass minor                   # Bump minor version"
  echo -e "  maiass major                   # Bump major version"
  echo -e "  maiass 2.1.0                   # Set specific version\n"

  echo -e "${BRed}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Color_Off}"
  echo -e "${BRed}                            CONFIGURATION (OPTIONAL)${Color_Off}"
  echo -e "${BRed}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Color_Off}\n"

  echo -e "${BWhite}🤖 AI FEATURES:${Color_Off}"
  echo -e "  ${BRed}MAIASS_AI_TOKEN${Color_Off}          Optional but ${BRed}REQUIRED${Color_Off} if you want AI commit messages"
  echo -e "  MAIASS_AI_MODE           ${Gray}('ask')${Color_Off} 'off', 'autosuggest'"
  echo -e "  MAIASS_AI_MODEL          ${Gray}('gpt-4o')${Color_Off} AI model to use"
  echo -e "  MAIASS_AI_COMMIT_MESSAGE_STYLE  ${Gray}('bullet')${Color_Off} 'conventional', 'simple'"
  echo -e "  MAIASS_AI_ENDPOINT       ${Gray}(default AI provider)${Color_Off} Custom AI endpoint\n"

  echo -e "${BWhite}📊 OUTPUT CONTROL:${Color_Off}"
  echo -e "  MAIASS_VERBOSITY             ${Gray}('brief')${Color_Off} 'normal', 'debug'"
  echo -e "  MAIASS_DEBUG                 ${Gray}('false')${Color_Off} 'true' for detailed output"
  echo -e "  MAIASS_ENABLE_LOGGING        ${Gray}('false')${Color_Off} 'true' to log to file"
  echo -e "  MAIASS_LOG_FILE              ${Gray}('maiass.log')${Color_Off} Log file path\n"
  echo -e "${BWhite}🌿 GIT WORKFLOW:${Color_Off}"
  echo -e "  MAIASS_DEVELOPBRANCH         ${Gray}('develop')${Color_Off} Override develop branch name"
  echo -e "  MAIASS_STAGINGBRANCH         ${Gray}('staging')${Color_Off} Override staging branch name"
  echo -e "  MAIASS_MASTERBRANCH          ${Gray}('master')${Color_Off} Override master branch name"
  echo -e "  MAIASS_STAGING_PULLREQUESTS  ${Gray}('on')${Color_Off} 'off' to disable staging pull requests"
  echo -e "  MAIASS_MASTER_PULLREQUESTS   ${Gray}('on')${Color_Off} 'off' to disable master pull requests\n"

  echo -e "${BWhite}🔗 REPOSITORY INTEGRATION:${Color_Off}"
  echo -e "  MAIASS_GITHUB_OWNER          ${Gray}(auto-detected)${Color_Off} Override GitHub owner"
  echo -e "  MAIASS_GITHUB_REPO           ${Gray}(auto-detected)${Color_Off} Override GitHub repo name"
  echo -e "  MAIASS_BITBUCKET_WORKSPACE   ${Gray}(auto-detected)${Color_Off} Override Bitbucket workspace"
  echo -e "  MAIASS_BITBUCKET_REPO_SLUG   ${Gray}(auto-detected)${Color_Off} Override Bitbucket repo slug\n"

  echo -e "${BWhite}🌐 BROWSER INTEGRATION:${Color_Off}"
  echo -e "  MAIASS_BROWSER               ${Gray}(system default)${Color_Off} Browser for URLs"
  echo -e "                                   Supported: Chrome, Firefox, Safari, Brave, Scribe"
  echo -e "  MAIASS_BROWSER_PROFILE       ${Gray}('Default')${Color_Off} Browser profile to use\n"

  echo -e "${BWhite}📁 CUSTOM VERSION FILES:${Color_Off}"
  echo -e "  ${BYellow}For projects with non-standard version file structures:${Color_Off}"
  echo -e "  MAIASS_VERSION_PRIMARY_FILE        Primary version file path"
  echo -e "  MAIASS_VERSION_PRIMARY_TYPE        ${Gray}('txt')${Color_Off} 'json', 'php' or 'txt' or 'pattern'"
  echo -e "  MAIASS_VERSION_PRIMARY_LINE_START  Line prefix for txt files"
  echo -e "  MAIASS_VERSION_SECONDARY_FILES     Secondary files (pipe-separated)"
  echo -e "  MAIASS_CHANGELOG_INTERNAL_NAME     alternate name for your internal changelog\n"

  echo -e "  ${BYellow}Examples:${Color_Off}"
  echo -e "    ${Gray}# WordPress theme with style.css version${Color_Off}"
  echo -e "    MAIASS_VERSION_PRIMARY_FILE=\"style.css\""
  echo -e "    MAIASS_VERSION_PRIMARY_TYPE=\"txt\""
  echo -e "    MAIASS_VERSION_PRIMARY_LINE_START=\"Version: \"\n"
  echo -e "    ${Gray}# PHP constant with pattern matching${Color_Off}"
  echo -e "    MAIASS_VERSION_PRIMARY_FILE=\"functions.php\""
  echo -e "    MAIASS_VERSION_PRIMARY_TYPE=\"pattern\""
  echo -e "    MAIASS_VERSION_PRIMARY_LINE_START=\"define('VERSION','{version}');\"\n"
  echo -e "${BRed}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Color_Off}"
  echo -e "${BRed}                               FEATURES & COMPATIBILITY${Color_Off}"
  echo -e "${BRed}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Color_Off}\n"

  echo -e "${BWhite}✨ KEY FEATURES:${Color_Off}"
  echo -e "  • ${BGreen}AI-powered commit messages${Color_Off} via AI integration"
  echo -e "  • ${BGreen}Automatic changelog generation${Color_Off} and management"
  echo -e "  • ${BGreen}Multi-repository support${Color_Off} (WordPress, Craft, bespoke projects)"
  echo -e "  • ${BGreen}Git workflow automation${Color_Off} (commit, tag, merge, push)"
  echo -e "  • ${BGreen}Intelligent version management${Color_Off} for diverse file structures"
  echo -e "  • ${BGreen}Jira ticket detection${Color_Off} from branch names\n"

  echo -e "${BWhite}🔄 REPOSITORY COMPATIBILITY:${Color_Off}"
  echo -e "  ${BYellow}Automatically adapts to your repository structure:${Color_Off}"
  echo -e "  ${BGreen}✓${Color_Off} Full Git Flow (develop → staging → master)"
  echo -e "  ${BGreen}✓${Color_Off} Simple workflow (feature → master)"
  echo -e "  ${BGreen}✓${Color_Off} Local-only repositories (no remote required)"
  echo -e "  ${BGreen}✓${Color_Off} Single branch workflows"
  echo -e "  ${BGreen}✓${Color_Off} Projects without version files (git-only mode)\n"

  echo -e "${BWhite}⚙️ SYSTEM REQUIREMENTS:${Color_Off}"
  echo -e "  ${BGreen}✓${Color_Off} Unix-like system (macOS, Linux, WSL)"
  echo -e "  ${BGreen}✓${Color_Off} Bash 3.2+ (macOS default supported)"
  echo -e "  ${BGreen}✓${Color_Off} Git command-line tools"
  echo -e "  ${BYellow}✓${Color_Off} jq (JSON processor) ${Gray}- required${Color_Off}\n"

  echo -e "  ${BYellow}Install jq:${Color_Off} ${Gray}brew install jq${Color_Off} (macOS) | ${Gray}sudo apt install jq${Color_Off} (Ubuntu)\n"

  echo -e "${BWhite}📝 CONFIGURATION:${Color_Off}"
  echo -e "  Global configuration loaded from ~/.maiass.env"
  echo -e "  Global overridden by Configuration loaded from ${BCyan}.env${Color_Off} files in current directory."
  echo -e "  ${Gray}Most settings are optional with sensible defaults!${Color_Off}\n"

  echo -e "${BGreen}Ready to get started? Just run:${Color_Off} ${BCyan}maiass${Color_Off}"
}


# Function to display help information for committhis
show_help_committhis() {
                      local BBlue='\033[1;34m'
                      local BWhite='\033[1;37m'
                      local BGreen='\033[1;32m'
                      local BYellow='\033[1;33m'
                      local BCyan='\033[1;36m'
                      local Color_Off='\033[0m'

                      echo -e "${BBlue}committhis - AI-powered Git commit message generator${Color_Off}"
                      echo
                      echo -e "${BWhite}Usage:${Color_Off}"
                      echo -e "  ${BGreen}committhis${Color_Off}"
                      echo
                      echo -e "${BWhite}Environment Configuration:${Color_Off}"
                      echo -e "  ${BCyan}MAIASS_AI_TOKEN${Color_Off}      Your AI API token (required)"
                      echo -e "  ${BCyan}MAIASS_AI_MODE${Color_Off}       Commit mode:"
                      echo -e "                                 ask (default), autosuggest, off"
                      echo -e "  ${BCyan}MAIASS_AI_COMMIT_MESSAGE_STYLE${Color_Off}"
                      echo -e "                                 Message style: bullet (default), conventional, simple"
                      echo -e "  ${BCyan}MAIASS_AI_ENDPOINT${Color_Off}   Custom AI endpoint (optional)"
                      echo
                      echo -e "${BWhite}Files (optional):${Color_Off}"
                      echo -e "  ${BGreen}.env${Color_Off}                     Can define the variables above"
                      echo -e "  ${BGreen}.maiass.prompt${Color_Off}           Custom AI prompt override"
                      echo
                      echo -e "committhis analyzes your staged changes and suggests an intelligent commit message."
                      echo -e "You can accept, reject, or edit it before committing."
                      echo
                      echo -e "This script does not manage versions, changelogs, or branches."
                    }
# Parse command line arguments
for arg in "$@"; do
  case $arg in
    -h|--help)
      show_help
      exit 0
      ;;
    -v|--version)
      # Try to read version from package.json in script directory
      version="Unknown"
      # get the version from line 3 of this very file
      script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      script_file="${BASH_SOURCE[0]}"
      version=$(grep -m1 '^# MAIASS' "$script_file" | sed -E 's/.* v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
      echo "MIASS v$version"

      exit 0
      ;;
    -aihelp|--committhis-help)
      show_help_committhis
      exit 0
      ;;
    -aicv|--committhis-version)
      # Try to read version from package.json in script directory
      version="Unknown"
      # get the version from line 3 of this very file
      script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      script_file="${BASH_SOURCE[0]}"
      version=$(grep -m1 '^# MAIASS' "$script_file" | sed -E 's/.* v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

      echo "COMMITTHIS v$version"
      exit 0
      ;;
    -co|-c|--commits-only)
      export ai_commits_only=true
      ;;
    -ai-commits-only)
      export ai_commits_only=true
      export brand="committhis"
      ;;
  esac
done

# Check for env var override
if [[ "$MAIASS_MODE" == "ai_only" ]]; then
    export ai_commits_only=true
fi


[[ "${BASH_SOURCE[0]}" == "${0}" ]] && initialiseBump "$@"
