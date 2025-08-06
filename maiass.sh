#!/bin/bash
# ---------------------------------------------------------------
# MAIASS (Modular AI-Augmented Semantic Scribe) v5.5.35
# Intelligent Git workflow automation script
# Copyright (c) 2025 Velvary Pty Ltd
# All rights reserved.
# This function is part of the Velvary bash scripts library.
# Author: vsmash <670252+vsmash@users.noreply.github.com>
# ---------------------------------------------------------------
# Resolve this script’s real path even if symlinked
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_PATH="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# Detect libexec layout: in dev, lib is next to the script; in brew, it's nested
if [[ -d "$SCRIPT_PATH/lib/core" ]]; then
  LIBEXEC_DIR="$SCRIPT_PATH/lib"
else
  LIBEXEC_DIR="$SCRIPT_PATH/../libexec/lib"
fi
PROJECT_DIR="$(pwd)"

source "$LIBEXEC_DIR/core/logger.sh"
source "$LIBEXEC_DIR/config/envars.sh"

# Load environment variables with new priority system
load_environment_variables

export ignore_local_env="${MAIASS_IGNORE_LOCAL_ENV:=false}"

source "$LIBEXEC_DIR/utils/utils.sh"
source "$LIBEXEC_DIR/core/logger.sh"
source "$LIBEXEC_DIR/core/init.sh"
source "$LIBEXEC_DIR/core/version.sh"
source "$LIBEXEC_DIR/core/logger.sh"
source "$LIBEXEC_DIR/utils/helpers.sh"
source "$LIBEXEC_DIR/core/git.sh"

source "$LIBEXEC_DIR/core/changelog.sh"

source "$LIBEXEC_DIR/core/ai.sh"
source "$LIBEXEC_DIR/core/commit.sh"
source "$LIBEXEC_DIR/utils/help.sh"




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
  
  # Check and handle .gitignore for environment files
  check_gitignore_for_env

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
    echo -e "${BAqua}Mode is commits only. \nWe are done and on $branch_name branch.${Color_Off}"
    print_signoff_with_topup
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




# Parse command line arguments

# Token management switches
for arg in "$@"; do
  case $arg in
    -h|--help)
      show_help
      exit 0
      ;;
    -v|--version)
      version="Unknown"
      script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      script_file="${BASH_SOURCE[0]}"
      version=$(grep -m1 '^# MAIASS' "$script_file" | sed -E 's/.* v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
      echo "MIASS v$version"
      exit 0
      ;;
    --delete-token)
      print_info "Deleting stored AI token..." "always"
      remove_secure_variable "MAIASS_AI_TOKEN"
      print_success "AI token deleted from secure storage (if it existed)." "always"
      exit 0
      ;;
    --update-token)
      print_info "Updating stored AI token..." "always"
      remove_secure_variable "MAIASS_AI_TOKEN"
      echo -n "Enter new AI token: "
      read -s new_token
      echo
      if [[ -n "$new_token" ]]; then
        store_secure_variable "MAIASS_AI_TOKEN" "$new_token"
        print_success "New AI token stored securely." "always"
      else
        print_warning "No token entered. Nothing stored." "always"
      fi
      exit 0
      ;;
    -aihelp|--committhis-help)
      show_help_committhis
      exit 0
      ;;
    -aicv|--committhis-version)
      version="Unknown"
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
