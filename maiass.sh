#!/bin/bash
# ---------------------------------------------------------------
# MAIASS (Modular AI-Augmented Semantic Scribe) v5.6.1
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

# Make main script path and version available to all sourced libs
export MAIASS_MAIN_SCRIPT="$SOURCE"
# Prefer explicit env override, else parse from script header comment, else 0.0.0
if [[ -z "${MAIASS_CLIENT_VERSION:-}" ]]; then
  parsed_ver=$(grep -m1 '^# MAIASS' "$SOURCE" | sed -E 's/.* v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
  export MAIASS_CLIENT_VERSION="${parsed_ver:-0.0.0}"
fi

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

  print_debug "Verion primary file: ${BYellow}${version_primary_file}${Color_Off}" 
  echo
  print_debug "has version files: ${BYellow}$has_version_files${Color_Off}" 


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
    --account-info)
      # Query account info from maiass-proxy
      api_key="${MAIASS_AI_TOKEN:-}"
      if [[ -z "$api_key" ]]; then
        print_warning "No API key found. Set MAIASS_AI_TOKEN or use --update-token." "always"
        exit 1
      fi
      # Determine client version from script header
      client_version=$(grep -m1 '^# MAIASS' "${BASH_SOURCE[0]}" | sed -E 's/.* v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
      [[ -z "$client_version" ]] && client_version="0.0.0"
      client_name="bashmaiass"
      # Use new /account-info endpoint (GET preferred)
      base_host="${MAIASS_AI_HOST:-${MAIASS_HOST:-http://localhost:8787}}"
      endpoint="${base_host}/account-info"
      echo "[INFO] Querying account info at: $endpoint" >&2
      response=$(curl -s -w "\nHTTP_STATUS:%{http_code}\n" \
        -H "Authorization: Bearer $api_key" \
        -H "X-Client-Name: $client_name" \
        -H "X-Client-Version: $client_version" \
        "$endpoint")
      http_status=$(echo "$response" | awk -F'HTTP_STATUS:' 'NF>1{print $2}' | tail -n1)
      response_body=$(echo "$response" | sed '/^HTTP_STATUS:/d')
      last_endpoint="$endpoint"
      last_status="$http_status"
      # If error or missing fields, try POST fallback
      if [[ -z "$response_body" || "$response_body" == *'error'* || "$http_status" == "404" ]]; then
        echo "[INFO] Retrying with POST to $endpoint" >&2
        response=$(curl -s -w "\nHTTP_STATUS:%{http_code}\n" -X POST "$endpoint" \
          -H "Content-Type: application/json" \
          -H "X-Client-Name: $client_name" \
          -H "X-Client-Version: $client_version" \
          -d "{\"api_key\":\"$api_key\"}")
        http_status=$(echo "$response" | awk -F'HTTP_STATUS:' 'NF>1{print $2}' | tail -n1)
        response_body=$(echo "$response" | sed '/^HTTP_STATUS:/d')
        last_endpoint="$endpoint (POST)"
        last_status="$http_status"
      fi
      # If still not JSON or 404, try versioned path
      if [[ -z "$response_body" || "$response_body" == *'Not Found'* ]]; then
        endpoint_v1="${base_host}/v1/account-info"
        echo "[INFO] Fallback to: $endpoint_v1" >&2
        response=$(curl -s -w "\nHTTP_STATUS:%{http_code}\n" \
          -H "Authorization: Bearer $api_key" \
          -H "X-Client-Name: $client_name" \
          -H "X-Client-Version: $client_version" \
          "$endpoint_v1")
        http_status=$(echo "$response" | awk -F'HTTP_STATUS:' 'NF>1{print $2}' | tail -n1)
        response_body=$(echo "$response" | sed '/^HTTP_STATUS:/d')
        last_endpoint="$endpoint_v1"
        last_status="$http_status"
        if [[ -z "$response_body" || "$response_body" == *'error'* || "$http_status" == "404" ]]; then
          echo "[INFO] Retrying with POST to $endpoint_v1" >&2
          response=$(curl -s -w "\nHTTP_STATUS:%{http_code}\n" -X POST "$endpoint_v1" \
            -H "Content-Type: application/json" \
            -H "X-Client-Name: $client_name" \
            -H "X-Client-Version: $client_version" \
            -d "{\"api_key\":\"$api_key\"}")
          http_status=$(echo "$response" | awk -F'HTTP_STATUS:' 'NF>1{print $2}' | tail -n1)
          response_body=$(echo "$response" | sed '/^HTTP_STATUS:/d')
          last_endpoint="$endpoint_v1 (POST)"
          last_status="$http_status"
        fi
      fi
      if command -v jq >/dev/null 2>&1; then
        if [[ "$response_body" =~ ^\{ ]]; then
          echo "$response_body" | jq --arg token "$api_key" --arg subid "${MAIASS_SUBSCRIPTION_ID:-}" '{
            token: $token,
            subscription_id: $subid,
            tokens_used: .tokens_used,
            tokens_remaining: .tokens_remaining,
            quota: .quota,
            subscription_type: .subscription_type,
            customer_email: .customer_email,
            status: .status
          }'
        else
          echo "[ERROR] Response is not valid JSON (status: ${last_status:-unknown}, endpoint: ${last_endpoint:-unknown}). Raw body:" >&2
          # Print raw body to stderr for debug
          if [[ -n "$response_body" ]]; then
            echo "$response_body" >&2
          else
            echo "(empty response body)" >&2
          fi
        fi
      else
        echo "[INFO] jq not found; printing raw response (status: ${last_status:-unknown}, endpoint: ${last_endpoint:-unknown})" >&2
        echo "$response_body"
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
