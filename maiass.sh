#!/bin/bash
# ---------------------------------------------------------------
# MAIASS (Modular AI-Augmented Semantic Scribe) v5.6.12
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
      # Helper: mask a sensitive token (show start and end only)
      mask_token() {
        local s="$1"; local n=${#s}
        if (( n <= 10 )); then echo "${s:0:1}***${s: -1}"; else echo "${s:0:6}***${s: -4}"; fi
      }

      # If JSON requested explicitly, print JSON (without exposing full token)
      if [[ "${MAIASS_ACCOUNT_INFO_JSON:-0}" == "1" ]]; then
        if command -v jq >/dev/null 2>&1 && [[ "$response_body" =~ ^\{ ]]; then
          echo "$response_body" | jq '{
            tokens_used: .tokens_used,
            tokens_remaining: .tokens_remaining,
            quota: .quota,
            subscription_type: .subscription_type,
            customer_email: .customer_email,
            status: .status
          }'
          exit 0
        else
          echo "[ERROR] JSON mode requested but response is not valid JSON (status: ${last_status:-unknown})." >&2
          [[ -n "$response_body" ]] && echo "$response_body" >&2
          exit 2
        fi
      fi

      # Human-readable summary (default)
      if command -v jq >/dev/null 2>&1 && [[ "$response_body" =~ ^\{ ]]; then
        # Extract fields safely
        tokens_used=$(echo "$response_body" | jq -r '.tokens_used // "-"')
        tokens_remaining=$(echo "$response_body" | jq -r '.tokens_remaining // "-"')
        quota=$(echo "$response_body" | jq -r '.quota // "-"')
        sub_type=$(echo "$response_body" | jq -r '.subscription_type // "-"')
        cust_email=$(echo "$response_body" | jq -r '.customer_email // "-"')
        status_field=$(echo "$response_body" | jq -r '.status // "-"')
      else
        # Fallback parsing when jq missing or non-JSON
        tokens_used="-"; tokens_remaining="-"; quota="-"; sub_type="-"; cust_email="-"; status_field="${last_status:-unknown}"
      fi

      masked_key=$(mask_token "$api_key")
      echo ""
      echo "Account Info"
      echo "------------"
      echo "API Token:        $masked_key"
      if [[ -n "${MAIASS_SUBSCRIPTION_ID:-}" ]]; then
        echo "Subscription ID:  ${MAIASS_SUBSCRIPTION_ID}"
      fi
      echo "Type:             ${sub_type}"
      echo "Email:            ${cust_email}"
      echo "Credits Used:     ${tokens_used}"
      echo "Credits Remaining:${tokens_remaining}"
      echo "Quota:            ${quota}"
      # Explain status codes clearly
      if [[ "${last_status:-}" == "403" || "$status_field" == "403" ]]; then
        echo "Status:          403 Forbidden"
        echo "Explanation:     Your token was rejected. Ensure it is correct, not expired, and associated with an active subscription."
      elif [[ "${last_status:-}" == "401" || "$status_field" == "401" ]]; then
        echo "Status:          401 Unauthorized"
        echo "Explanation:     Missing or invalid credentials. Try updating your token with '--update-token'."
      elif [[ "${last_status:-}" =~ ^2 && "${last_status:-}" != "" ]]; then
        echo "Status:          ${last_status} OK"
      else
        echo "Status:          ${last_status:-unknown}"
      fi
      echo ""
      exit 0
      
      ;;
    -aihelp|--committhis-help)
      echo "Usage: bma [options]"
      echo "Common options:"
      echo "  --account-info        Show your account status (masked token)"
      echo "  --update-token        Prompt to update and store your API token"
      echo "  --delete-token        Remove stored API token"
      echo "  -v, --version         Show version"
      echo "  -h, --help            Show help"
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
