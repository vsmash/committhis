export total_tokens=''
export completion_tokens=''
export prompt_tokens=''
export version_primary_file="${MAIASS_VERSION_PRIMARY_FILE:-}"
export version_primary_type="${MAIASS_VERSION_PRIMARY_TYPE:-}"
export version_primary_line_start="${MAIASS_VERSION_PRIMARY_LINE_START:-}"
export version_secondary_files="${MAIASS_VERSION_SECONDARY_FILES:-}"


# Function to load MAIASS_* variables from .env files
load_bumpscript_env() {
  local env_file=".env.maiass"

  if [[ -f "$env_file" ]]; then
    print_info "Loading MAIASS_* variables from $env_file"

    while IFS= read -r line || [[ -n "$line" ]]; do
      # Trim leading/trailing whitespace
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"

      # Skip blank lines and comments
      [[ -z "$line" || "$line" == \#* ]] && continue

      # Only process MAIASS_* assignments
      if [[ "$line" =~ ^MAIASS_ ]]; then
        local key="${line%%=*}"
        local value="${line#*=}"

        # Strip surrounding matching quotes with POSIX-safe cut
        if [[ "$value" == \"*\" && "$value" == *\" ]] || [[ "$value" == \'*\' && "$value" == *\' ]]; then
          value=$(echo "$value" | cut -c2- | rev | cut -c2- | rev)
        fi

        export "$key=$value"
        print_info "Set $key=$value"
      fi
    done < "$env_file"
  fi
}



# Function to set up branch and changelog variables with override logic
setup_bumpscript_variables() {

      # Initialize debug mode early so it's available throughout the script
      export debug_mode="${MAIASS_DEBUG:=false}"
      export autopush_commits="${MAIASS_AUTOPUSH_COMMITS:=false}"
      export brand="${MAIASS_BRAND:=MAIASS}"
      # Initialize brevity and logging configuration - set debug for testing
      export verbosity_level="${MAIASS_VERBOSITY:=debug}"
      export enable_logging="${MAIASS_LOGGING:=true}"
      export log_file="${MAIASS_LOG_FILE:=maiass.log}"

      # Initialize AI variables early so they're available when get_commit_message is called
      export ai_invalid_token_choices="${MAIASS_AI_INVALID_TOKEN_CHOICES:-false}"
      export ai_mode="${MAIASS_AI_MODE:-ask}"
      export ai_token="${MAIASS_AI_TOKEN:-}"
      export ai_model="${MAIASS_AI_MODEL:=gpt-3.5-turbo}"
      export ai_temperature="${MAIASS_AI_TEMPERATURE:=0.7}"
      export ai_max_characters="${MAIASS_AI_MAX_CHARACTERS:=8000}"
      export ai_commit_message_style="${MAIASS_AI_COMMIT_MESSAGE_STYLE:=bullet}"
      export maiass_host="${MAIASS_AI_HOST:-https://pound.maiass.net}"
      export maiass_endpoint="${maiass_host}/v1/chat/completions"
      export maiass_tokenrequest="${maiass_host}/v1/token"
      export maiass_validate_endpoint="${maiass_host}/v1/validate"
      # Legacy endpoints - proxy should provide payment URLs dynamically with subscription_id
      export maiass_register_endpoint="${MAIASS_REGISTER_ENDPOINT:-https://maiass.net/register}"
      export maiass_topup_endpoint="${MAIASS_TOPUP_ENDPOINT:-https://maiass.net/topup}"

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
      # Check if we're planning to create an anonymous token
      if [[ "$_MAIASS_NEED_ANON_TOKEN" == "true" ]]; then
        print_info "AI mode '$ai_mode' enabled - anonymous token will be created automatically"
      else
        print_warning "AI commit message mode '$ai_mode' requires MAIASS_AI_TOKEN"
        print_warning "Falling back to 'off' mode"
        export ai_mode="off"
      fi
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
