#!/bin/bash
# ---------------------------------------------------------------
# MAIASS (Modular AI-Assisted Semantic Savant) v4.8.2
# Intelligent Git workflow automation script
# Copyright (c) 2025 Velvary Pty Ltd
# All rights reserved.
# This function is part of the Velvary bash scripts library.
# Author: Mark Pottie <mark@velvary.com.au>
# ---------------------------------------------------------------

# first check for global values
[ -f "$HOME/.maiass.env" ] && source "$HOME/.maiass.env"


# if .env exists, source it and override globals
if [ -f .env ]; then
    source .env
fi

# devlog is my personal script for logging work in google sheets.
# if devlog is not a bash script, create an empty function to prevent errors
if [ -z "$(type -t devlog)" ]; then
    function devlog() {
        :
    }
fi


# Initialize debug mode early so it's available throughout the script
export debug_mode="${MAIASS_DEBUG:-false}"

# Initialize brevity and logging configuration
export verbosity_level="${MAIASS_VERBOSITY:=brief}"
export enable_logging="${MAIASS_LOGGING:=false}"
export log_file="${MAIASS_LOG_FILE:=maiass.log}"

# Initialize AI variables early so they're available when get_commit_message is called
export openai_mode="${MAIASS_OPENAI_MODE:-ask}"
export openai_token="${MAIASS_OPENAI_TOKEN:-}"
export openai_model="${MAIASS_OPENAI_MODEL:-gpt-4o}"
export openai_commit_message_style="${MAIASS_OPENAI_COMMIT_MESSAGE_STYLE:=bullet}"

# Initialize configurable version file system
export version_primary_file="${MAIASS_VERSION_PRIMARY_FILE:-}"
export version_primary_type="${MAIASS_VERSION_PRIMARY_TYPE:-}"
export version_primary_line_start="${MAIASS_VERSION_PRIMARY_LINE_START:-}"
export version_secondary_files="${MAIASS_VERSION_SECONDARY_FILES:-}"

# Color and style definitions
BCyan='\033[1;36m'      # Cyan
Color_Off='\033[0m'     # Text Reset
BRed='\033[1;31m'       # Red
BGreen='\033[1;32m'     # Green
BBlue='\033[1;34m'      # Blue
BYellow='\033[1;33m'    # Yellow
BPurple='\033[1;35m'    # Purple
BWhite='\033[1;37m'     # White



# Helper function to read version from a file based on type and line start
read_version_from_file() {
    local file="$1"
    local file_type="$2"
    local line_start="$3"
    local version=""

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    case "$file_type" in
        "json")
            # JSON file - look for "version" property
            if command -v jq >/dev/null 2>&1; then
                version=$(jq -r '.version' "$file" 2>/dev/null)
            else
                # Fallback method using grep and sed
                version=$(grep '"version"' "$file" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            fi
            ;;
        "txt")
            # Text file - look for line starting with specified prefix
            if [[ -n "$line_start" ]]; then
                version=$(grep "^${line_start}" "$file" | head -1 | sed "s/^${line_start}//" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            else
                # If no line start specified, assume entire file content is the version
                version=$(cat "$file" | tr -d '\n\r')
            fi
            ;;
        "pattern")
            # Pattern-based matching - extract version from regex pattern
            # line_start contains the pattern with {version} placeholder
            if [[ -n "$line_start" ]]; then
                # For PHP define statements, extract the version directly
                if [[ "$line_start" == *"define("* ]]; then
                    # Extract constant name from pattern
                    local const_name
                    const_name=$(echo "$line_start" | sed "s/.*define('\([^']*\)'.*/\1/" | sed "s/.*define(\"\([^\"]*\)\".*/\1/")
                    if [[ -n "$const_name" ]]; then
                        # Find the define line and extract version
                        version=$(grep "define('${const_name}'" "$file" | sed "s/.*'[^']*'[[:space:]]*,[[:space:]]*'\([^']*\)'.*/\1/")
                        if [[ -z "$version" ]]; then
                            version=$(grep "define(\"${const_name}\"" "$file" | sed "s/.*\"[^\"]*\"[[:space:]]*,[[:space:]]*\"\([^\"]*\)\".*/\1/")
                        fi
                    fi
                else
                    # Generic pattern matching - replace {version} with capture group
                    local search_pattern
                    search_pattern=$(echo "$line_start" | sed "s/{version}/\\([^'\"]*\\)/g")
                    version=$(sed -n "s/.*${search_pattern}.*/\1/p" "$file" | head -1)
                fi
            fi
            ;;
        *)
            print_error "Unsupported file type: $file_type"
            return 1
            ;;
    esac

    if [[ -n "$version" && "$version" != "null" ]]; then
        echo "$version"
        return 0
    else
        return 1
    fi
}

# Helper function to update version in a file based on type and line start
update_version_in_file() {
    local file="$1"
    local file_type="$2"
    local line_start="$3"
    local new_version="$4"

    if [[ ! -f "$file" ]]; then
        print_warning "File not found: $file"
        return 1
    fi

    case "$file_type" in
        "json")
            # JSON file - update "version" property
            if command -v jq >/dev/null 2>&1; then
                jq ".version = \"$new_version\"" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
            else
                # Fallback to sed
                sed_inplace "s/\"version\": \".*\"/\"version\": \"$new_version\"/" "$file"
            fi
            ;;
        "txt")
            # Text file - update line starting with specified prefix
            if [[ -n "$line_start" ]]; then
                # Use awk for more reliable pattern matching with literal strings
                awk -v prefix="$line_start" -v version="$new_version" '
                    index($0, prefix) == 1 { print prefix version; next }
                    { print }
                ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
            else
                # If no line start specified, replace entire file content
                echo "$new_version" > "$file"
            fi
            ;;
        "pattern")
            # Pattern-based replacement - replace version in regex pattern
            # line_start contains the pattern with {version} placeholder
            if [[ -n "$line_start" ]]; then
                # For PHP define statements, use a specific approach
                if [[ "$line_start" == *"define("* ]]; then
                    # Extract the constant name from the pattern
                    local const_name
                    const_name=$(echo "$line_start" | sed "s/.*define('\([^']*\)'.*/\1/" | sed "s/.*define(\"\([^\"]*\)\".*/\1/")
                    if [[ -n "$const_name" ]]; then
                        # Replace PHP define statement with new version
                        sed_inplace "s/define('${const_name}'[[:space:]]*,[[:space:]]*'[^']*')/define('${const_name}','${new_version}')/g" "$file"
                        sed_inplace "s/define(\"${const_name}\"[[:space:]]*,[[:space:]]*\"[^\"]*\")/define(\"${const_name}\",\"${new_version}\")/g" "$file"
                    fi
                else
                    # Generic pattern replacement - replace {version} with new version
                    local replacement_text
                    replacement_text=$(echo "$line_start" | sed "s/{version}/$new_version/g")
                    # Create a pattern to match the structure (replace {version} with wildcard)
                    local match_pattern
                    match_pattern=$(echo "$line_start" | sed "s/{version}/.*/g" | sed 's/[[\/.\*^$()+?{|]/\\&/g')
                    # Replace matching lines
                    sed_inplace "s/${match_pattern}/${replacement_text}/g" "$file"
                fi
            fi
            ;;
        *)
            print_error "Unsupported file type: $file_type"
            return 1
            ;;
    esac

    return 0
}

# Helper function to parse secondary version files configuration
parse_secondary_version_files() {
    local config="$1"
    local -a files_array

    if [[ -z "$config" ]]; then
        return 0
    fi

    # Split by pipe (|) to get individual file configurations
    IFS='|' read -ra files_array <<< "$config"

    for file_config in "${files_array[@]}"; do
        if [[ -n "$file_config" ]]; then
            # Split by colon (:) to get file:type:line_start
            IFS=':' read -ra config_parts <<< "$file_config"
            local file="${config_parts[0]}"
            local type="${config_parts[1]:-txt}"
            local line_start="${config_parts[2]:-}"

            if [[ -f "$file" ]]; then
                echo "$file:$type:$line_start"
            fi
        fi
    done
}

# sets value to $currentversion and newversion.
# usage: getVersion [major|minor|patch|specific_version]
# if the second argument is not set, bumps the patch version

# main script starts below the functions

# Print a decorated header
print_header() {
    echo -e "\n${BPurple}════════════════════════════════════════════════════════════════${Color_Off}"
    echo -e "${BBlue}                    $1 Version Bump Script${Color_Off}"
    echo -e "${BPurple}════════════════════════════════════════════════════════════════${Color_Off}\n"
}

# Print a section header
print_section() {
    echo -e "\n${BYellow}▶ $1${Color_Off}"
}

# Logging function - writes to log file if logging is enabled
log_message() {
    if [[ "$enable_logging" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$log_file"
    fi
}

# Print a success message
print_success() {
    echo -e "${BGreen}✔ $1${Color_Off}"
    log_message "SUCCESS: $1"
}

# Print an info message with verbosity level support
# Usage: print_info "message" [level]
# Levels: brief, normal, debug (default: normal)
print_info() {
    local message="$1"
    local level="${2:-normal}"

    # Always show if debug mode is true (backward compatibility)
    if [[ "$debug_mode" == "true" ]]; then
        echo -e "${BCyan}ℹ $message${Color_Off}"
        log_message "INFO: $message"
        return
    fi

    # Show based on verbosity level
    case "$verbosity_level" in
        "brief")
            # Only show essential messages in brief mode
            if [[ "$level" == "brief" ]]; then
                echo -e "${BCyan}ℹ $message${Color_Off}"
            fi
            ;;
        "normal")
            # Show brief and normal messages
            if [[ "$level" == "brief" || "$level" == "normal" ]]; then
                echo -e "${BCyan}ℹ $message${Color_Off}"
            fi
            ;;
        "debug")
            # Show all messages
            echo -e "${BCyan}ℹ $message${Color_Off}"
            ;;
    esac

    log_message "INFO: $message"
}

# Print a warning message
print_warning() {
    echo -e "${BYellow}⚠ $1${Color_Off}"
    log_message "WARNING: $1"
}

# Print an error message
print_error() {
    echo -e "${BRed}✘ $1${Color_Off}"
    log_message "ERROR: $1"
}

# Execute git command with verbosity-controlled output
# Usage: run_git_command "git command" [show_output_level]
# show_output_level: brief, normal, debug (default: normal)
run_git_command() {
    local git_cmd="$1"
    local show_level="${2:-normal}"

    # Always show if debug mode is true (backward compatibility)
    if [[ "$debug_mode" == "true" ]]; then
        eval "$git_cmd"
        return $?
    fi

    # Control output based on verbosity level
    case "$verbosity_level" in
        "brief")
            if [[ "$show_level" == "brief" ]]; then
                eval "$git_cmd"
            else
                eval "$git_cmd" >/dev/null 2>&1
            fi
            ;;
        "normal")
            if [[ "$show_level" == "debug" ]]; then
                eval "$git_cmd" >/dev/null 2>&1
            else
                eval "$git_cmd"
            fi
            ;;
        "debug")
            eval "$git_cmd"
            ;;
    esac

    return $?
}

# Print a section header (always shown regardless of verbosity)
print_section() {
    echo -e "\n${BWhite}▶ $1${Color_Off}"
    log_message "SECTION: $1"
}

# Check and handle .gitignore for log files
check_gitignore_for_logs() {
    if [[ "$enable_logging" != "true" ]]; then
        return 0
    fi

    local gitignore_file=".gitignore"
    local log_pattern_found=false

    # Check if .gitignore exists and contains log file patterns
    if [[ -f "$gitignore_file" ]]; then
        # Check for specific log file or *.log pattern
        if grep -q "^${log_file}$" "$gitignore_file" 2>/dev/null || \
           grep -q "^\*.log$" "$gitignore_file" 2>/dev/null || \
           grep -q "^\*\.log$" "$gitignore_file" 2>/dev/null; then
            log_pattern_found=true
        fi
    fi

    # If log file is not ignored, warn user and offer to add it
    if [[ "$log_pattern_found" == "false" ]]; then
        print_warning "Log file '$log_file' is not in .gitignore"
        echo -n "Add '$log_file' to .gitignore to avoid committing log files? [Y/n]: "
        read -r add_to_gitignore

        if [[ "$add_to_gitignore" =~ ^[Nn]$ ]]; then
            print_info "Continuing without adding to .gitignore" "brief"
        else
            # Add log file to .gitignore
            if [[ ! -f "$gitignore_file" ]]; then
                echo "# Log files" > "$gitignore_file"
                echo "$log_file" >> "$gitignore_file"
                print_success "Created .gitignore and added '$log_file'"
            else
                echo "" >> "$gitignore_file"
                echo "# MAIASS log file" >> "$gitignore_file"
                echo "$log_file" >> "$gitignore_file"
                print_success "Added '$log_file' to .gitignore"
            fi
        fi
    fi
}

# Get the latest version from git tags
# Returns the highest semantic version tag, or empty string if no tags found
get_latest_version_from_tags() {
    local latest_tag
    # Get all tags that match semantic versioning pattern, sort them, and get the latest
    latest_tag=$(git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    echo "$latest_tag"
}

# Check if a git branch exists locally
branch_exists() {
    local branch_name="$1"
    git show-ref --verify --quiet "refs/heads/$branch_name"
}

# Check if a git remote exists
remote_exists() {
    local remote_name="${1:-origin}"
    git remote | grep -q "^$remote_name$"
}

# Check if we can push to a remote (tests connectivity)
can_push_to_remote() {
    local remote_name="${1:-origin}"
    if ! remote_exists "$remote_name"; then
        return 1
    fi
    # Test if we can reach the remote (this is a dry-run)
    git ls-remote "$remote_name" >/dev/null 2>&1
}

# Cross-platform sed -i helper function with file existence check
# Usage: sed_inplace 'pattern' file
# Returns 0 if successful, 1 if file doesn't exist (non-fatal)
sed_inplace() {
    local pattern="$1"
    local file="$2"

    # Check if file exists - return silently if not (expected for diverse repos)
    if [ ! -f "$file" ]; then
        return 1
    fi

    if sed --version >/dev/null 2>&1; then
        # GNU sed (Linux)
        sed -i "$pattern" "$file"
    else
        # BSD sed (macOS)
        sed -i '' "$pattern" "$file"
    fi
}

# Perform merge operation between two branches with remote and PR support
perform_merge_operation() {
    local source_branch="$1"
    local target_branch="$2"

    if [[ -z "$source_branch" || -z "$target_branch" ]]; then
        print_error "Source and target branches must be specified"
        return 1
    fi

    # Note: Tags are created during version bump workflow, not during merge operations

    # Determine which pull request setting to use based on target branch
    local use_pullrequest="off"
    if [[ "$target_branch" == "$stagingbranch" ]]; then
        use_pullrequest="$staging_pullrequests"
    elif [[ "$target_branch" == "$masterbranch" ]]; then
        use_pullrequest="$master_pullrequests"
    fi

    # Handle pull requests vs direct merge
    if [[ "$use_pullrequest" == "on" ]] && can_push_to_remote "origin"; then
        print_info "Creating pull request for merge"

        # Ensure source branch is pushed
        git push --set-upstream origin "$source_branch" 2>/dev/null || git push origin "$source_branch"
        check_git_success

        # Create pull request URL
        if [[ "$REPO_PROVIDER" == "bitbucket" ]]; then
            open_url "https://bitbucket.org/$BITBUCKET_WORKSPACE/$BITBUCKET_REPO_SLUG/pull-requests/new?source=$source_branch&dest=$target_branch&title=Release%20${newversion:-merge}"
        elif [[ "$REPO_PROVIDER" == "github" ]]; then
            open_url "https://github.com/$GITHUB_OWNER/$GITHUB_REPO/compare/$target_branch...$source_branch?quick_pull=1&title=Release%20${newversion:-merge}"
        else
            print_warning "Unknown repository provider. Cannot create pull request URL."
        fi

        devlog "Created pull request for ${newversion:-merge}" "c" "${header:-devbump}" "${jira_ticket_number:-}"
    else
        # Direct merge
        print_info "Performing direct merge: $source_branch → $target_branch"

        git checkout "$target_branch"
        check_git_success

        # Pull latest changes if remote available
        if remote_exists "origin"; then
            # Check if current branch has upstream tracking
            if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
                git pull 2>/dev/null || print_warning "Could not pull latest changes (continuing anyway)"
            else
                # Try to set up tracking if remote branch exists
                if git ls-remote --heads origin "$target_branch" | grep -q "$target_branch"; then
                    print_info "Setting up tracking for $target_branch with origin/$target_branch"
                    git branch --set-upstream-to=origin/"$target_branch" "$target_branch"
                    git pull 2>/dev/null || print_warning "Could not pull latest changes (continuing anyway)"
                else
                    print_info "Remote branch origin/$target_branch doesn't exist - skipping pull"
                fi
            fi
        fi

        run_git_command "git merge '$source_branch'" "debug"
        check_git_success

        # Push to remote if available
        if can_push_to_remote "origin"; then
            # Check if current branch has upstream tracking, if not set it up
            if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
                print_info "Setting up upstream tracking for $target_branch"
                run_git_command "git push --set-upstream origin '$target_branch'" "debug"
            else
                run_git_command "git push" "debug"
            fi
            check_git_success
        fi

        print_success "Merged $source_branch into $target_branch"
        devlog "Merged $source_branch into $target_branch" "c" "${header:-devbump}" "${jira_ticket_number:-}"
    fi
}

# Compare two semantic version strings
# Returns 0 (true) if version1 > version2, 1 (false) otherwise
version_is_greater() {
    local version1="$1"
    local version2="$2"

    # Split versions into major.minor.patch components
    local v1_major
    local v1_minor
    local v1_patch
    local v2_major
    local v2_minor
    local v2_patch

    v1_major=$(echo "$version1" | cut -d. -f1)
    v1_minor=$(echo "$version1" | cut -d. -f2)
    v1_patch=$(echo "$version1" | cut -d. -f3)

    v2_major=$(echo "$version2" | cut -d. -f1)
    v2_minor=$(echo "$version2" | cut -d. -f2)
    v2_patch=$(echo "$version2" | cut -d. -f3)

    # Compare major version
    if [ "$v1_major" -gt "$v2_major" ]; then
        return 0  # version1 > version2
    elif [ "$v1_major" -lt "$v2_major" ]; then
        return 1  # version1 < version2
    fi

    # Major versions are equal, compare minor version
    if [ "$v1_minor" -gt "$v2_minor" ]; then
        return 0  # version1 > version2
    elif [ "$v1_minor" -lt "$v2_minor" ]; then
        return 1  # version1 < version2
    fi

    # Major and minor versions are equal, compare patch version
    if [ "$v1_patch" -gt "$v2_patch" ]; then
        return 0  # version1 > version2
    else
        return 1  # version1 <= version2
    fi
}


function getVersion(){
# ---------------------------------------------------------------
# Copyright (c) 2025 Velvary Pty Ltd
# All rights reserved.
# This function is part of the Velvary bash scripts library.
# Licensed under the End User License Agreement (eula.txt) provided with this software.
# Author: Mark Pottie <mark@velvary.com.au>
# ---------------------------------------------------------------
    local version_arg="$1"  # major, minor, patch, or specific version

    # Initialize global variables (compatible with older bash versions)
    version_source=""
    version_source_file=""
    version_source_type=""
    version_source_line_start=""
    currentversion=""
    newversion=""

    print_section "Determining Version Source"

    # Check for custom primary version file first
    if [[ -n "$version_primary_file" && -n "$version_primary_type" ]]; then
        print_info "Checking custom primary version file: $version_primary_file"
        if currentversion=$(read_version_from_file "$version_primary_file" "$version_primary_type" "$version_primary_line_start"); then
            print_info "Found custom primary version file: $version_primary_file - using as version source"
            version_source="custom_primary"
            version_source_file="$version_primary_file"
            version_source_type="$version_primary_type"
            version_source_line_start="$version_primary_line_start"
        else
            print_error "Could not read version from custom primary file: $version_primary_file"
            return 1
        fi
    # Fallback to package.json (legacy behavior)
    elif [ -f "${package_json_path}/package.json" ]; then
        local package_json_file="${package_json_path}/package.json"
        print_info "Found package.json at $package_json_file - using as version source"
        version_source="package.json"
        version_source_file="$package_json_file"
        version_source_type="json"
        version_source_line_start=""

        if currentversion=$(read_version_from_file "$package_json_file" "json" ""); then
            : # Success, currentversion is set
        else
            print_error "Could not read version from package.json. Exiting."
            return 1
        fi
    # Fallback to VERSION file (legacy behavior)
    elif [ -f "$version_file_path/VERSION" ]; then
        print_info "No package.json found - using VERSION file at $version_file_path/VERSION"
        version_source="VERSION"
        version_source_file="$version_file_path/VERSION"
        version_source_type="txt"
        version_source_line_start=""

        if currentversion=$(read_version_from_file "$version_file_path/VERSION" "txt" ""); then
            : # Success, currentversion is set
        else
            print_error "VERSION file is empty. Exiting."
            return 1
        fi
    else
        print_error "No version source found! Please create either:"
        if [[ -n "$version_primary_file" ]]; then
            print_error "  - Custom primary version file: $version_primary_file, or"
        fi
        print_error "  - package.json at $package_json_path/package.json with version field, or"
        print_error "  - VERSION file at $version_file_path/VERSION"
        return 1
    fi

    # Calculate new version based on argument
    if [ -z "$version_arg" ]; then
       print_info "No version specified, bumping patch version..."
       newversion=$(echo "$currentversion" | awk -F. '{$NF = $NF + 1;} 1' | sed 's/ /./g')
    else
        print_info "Setting version based on argument: $version_arg"
        if [ "$version_arg" == "major" ]; then
            newversion=$(echo "$currentversion" | awk -F. '{$1 = $1 + 1; $2 = 0; $3 = 0;} 1' | sed 's/ /./g')
        elif [ "$version_arg" == "minor" ]; then
            newversion=$(echo "$currentversion" | awk -F. '{$2 = $2 + 1; $3 = 0;} 1' | sed 's/ /./g')
        elif [ "$version_arg" == "patch" ]; then
            newversion=$(echo "$currentversion" | awk -F. '{$3 = $3 + 1;} 1' | sed 's/ /./g')
        else
            # Validate specific version format (X.Y.Z)
            if [[ ! "$version_arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                print_error "Invalid version format: $version_arg"
                print_error "Version must be in major.minor.patch format (e.g., 1.2.3)"
                return 1
            fi

            # Get latest version from git tags for comparison
            local latest_tag_version
            latest_tag_version=$(get_latest_version_from_tags)

            if [[ -n "$latest_tag_version" ]]; then
                print_info "Latest git tag version: $latest_tag_version"
                # Check if new version is greater than latest tag
                if ! version_is_greater "$version_arg" "$latest_tag_version"; then
                    print_error "Version $version_arg is lower than latest version $latest_tag_version"
                    echo "Would you like to:"
                    echo "1) Bump the patch version (${latest_tag_version} → $(echo "$latest_tag_version" | awk -F. '{$3 = $3 + 1;} 1' | sed 's/ /./g'))"
                    echo "2) Try entering another version number"
                    echo "3) Exit (default)"
                    read -p "$(echo -e ${BCyan}Enter choice [1/2/3]: ${Color_Off})" choice

                    case "$choice" in
                        1)
                            newversion=$(echo "$latest_tag_version" | awk -F. '{$3 = $3 + 1;} 1' | sed 's/ /./g')
                            print_success "Using patch bump: $newversion"
                            ;;
                        2)
                            read -p "$(echo -e ${BCyan}Enter new version: ${Color_Off})" new_input
                            if [[ -n "$new_input" ]]; then
                                # Recursively call getVersion with new input
                                getVersion "$new_input"
                                return $?
                            else
                                print_error "No version entered. Exiting."
                                return 1
                            fi
                            ;;
                        *)
                            print_error "Exiting."
                            return 1
                            ;;
                    esac
                fi
            else
                # No git tags exist yet - this is the first version tag
                print_info "No version tags found in repository"
                print_info "This will be the first version tag: $version_arg"
                # Compare against current version in file to ensure we're not going backwards
                if ! version_is_greater "$version_arg" "$currentversion"; then
                    print_warning "Specified version $version_arg is not greater than current file version $currentversion"
                    echo "Would you like to:"
                    echo "1) Use current file version and bump patch (${currentversion} → $(echo "$currentversion" | awk -F. '{$3 = $3 + 1;} 1' | sed 's/ /./g'))"
                    echo "2) Try entering another version number"
                    echo "3) Continue with $version_arg anyway"
                    echo "4) Exit (default)"
                    read -p "$(echo -e ${BCyan}Enter choice [1/2/3/4]: ${Color_Off})" choice

                    case "$choice" in
                        1)
                            newversion=$(echo "$currentversion" | awk -F. '{$3 = $3 + 1;} 1' | sed 's/ /./g')
                            print_success "Using file version patch bump: $newversion"
                            ;;
                        2)
                            read -p "$(echo -e ${BCyan}Enter new version: ${Color_Off})" new_input
                            if [[ -n "$new_input" ]]; then
                                # Recursively call getVersion with new input
                                getVersion "$new_input"
                                return $?
                            else
                                print_error "No version entered. Exiting."
                                return 1
                            fi
                            ;;
                        3)
                            print_info "Continuing with version $version_arg"
                            newversion="$version_arg"
                            ;;
                        *)
                            print_info "Exiting."
                            return 1
                            ;;
                    esac
                else
                    newversion="$version_arg"
                fi
            fi
        fi
    fi

    print_info "Version source: ${BWhite}$version_source${Color_Off}"
    print_info "Current version: ${BWhite}$currentversion${Color_Off}"
    print_success "New version: ${BWhite}$newversion${Color_Off}"
}

# Error handling for git operations
function check_git_success() {
    if [ $? -ne 0 ]; then
        print_error "Git operation failed"
        print_error "Please resolve any conflicts or issues before proceeding"
        exit 1
    fi
}


open_url() {
  local url="$1"
  # if MAIASS_BROWSER is empty, use the default browser
  if [ -z "$MAIASS_BROWSER" ]; then
    open "$url"
    return
  fi

  # Set defaults if variables are unset
  local browser="${MAIASS_BROWSER:-Google Chrome}"
  local profile="${MAIASS_BROWSER_PROFILE:-Default}"

  # Map known browser names to their app paths and binary paths
  local app_path=""
  local binary_path=""

  case "$browser" in
    "Brave Browser")
      app_path="/Applications/Google Chrome.app"
      binary_path="$app_path/Contents/MacOS/Brave Browser"
      ;;
    "Google Chrome")
      app_path="/Applications/Google Chrome.app"
      binary_path="$app_path/Contents/MacOS/Google Chrome"
      ;;
    "Firefox")
      app_path="/Applications/Firefox.app"
      binary_path="$app_path/Contents/MacOS/firefox"
      ;;
    "Savant")
      app_path="/Applications/Savant.app"
      binary_path="$app_path/Contents/MacOS/Savant"
      ;;
    "Safari")
      open -a "Safari" "$url"
      return
      ;;
    *)
      echo "Unsupported browser: $browser"
      return 1
      ;;
  esac

  # For browsers that support profiles via CLI
  if [[ "$browser" == "Firefox" ]]; then
    "$binary_path" -P "$profile" -no-remote "$url" &
  else
    "$binary_path" --profile-directory="$profile" "$url" &
  fi
}



# Function to clean up duplicate changelog entries
function clean_changelog() {
    local changelog_file="$1"

    if [ ! -f "$changelog_file" ]; then
        echo "Error: Changelog file $changelog_file not found"
        return 1
    fi

    local temp_file="/tmp/changelog_temp_$$"
    local temp_section="/tmp/changelog_section_$$"
    touch "$temp_file" "$temp_section"

    # Initialize variables
    local current_version=""
    local current_date=""
    local first_section=1

    while read line; do
        # Version header (##)
        if echo "$line" | grep -q "^##[[:space:]]"; then
            # Process previous section if exists
            if [ ! -z "$current_version" ]; then
                if [ "$first_section" = 1 ]; then
                    first_section=0
                else
                    echo "" >> "$temp_file"
                fi
                echo "$current_version" >> "$temp_file"
                echo "$current_date" >> "$temp_file"
                echo "" >> "$temp_file"
                # Get unique bullet points while preserving order
                perl -ne 'print unless $seen{$_}++' "$temp_section" >> "$temp_file"
                : > "$temp_section"
            fi
            current_version="$line"

        # Date line (DD Month YYYY) or (DD Month YYYY (Weekday))
        elif echo "$line" | grep -q "^[0-9]\{1,2\}[[:space:]][A-Za-z]\+[[:space:]][0-9]\{4\}\([[:space:]]\([[:space:]]*([A-Za-z]\+)[[:space:]]*\)\)\?$"; then
            current_date="$line"

        # Bullet points
        # Bullet points
        elif echo "$line" | grep -q "^-[[:space:]]"; then
            echo "$line" | sed 's/^- - /- /' | sed 's/^-  /- /' >> "$temp_section"
        fi
    done < "$changelog_file"

    # Process the last section
    if [ ! -z "$current_version" ]; then
        if [ "$first_section" = 0 ]; then
            echo "" >> "$temp_file"
        fi
        echo "$current_version" >> "$temp_file"
        echo "$current_date" >> "$temp_file"
        echo "" >> "$temp_file"
        perl -ne 'print unless $seen{$_}++' "$temp_section" >> "$temp_file"
    fi

    # Replace original file with deduplicated content
    cat "$temp_file" > "$changelog_file"

    # Clean up temporary files
    rm -f "$temp_section" "$temp_file"
}


function updateChangelog() {
    changelogpath=$1
    # if changelogpath is not set, set it to "."
    if [ -z "$changelogpath" ]; then
        changelogpath="."
    fi

    # find all the git messages since the last tag and print them
    # changelog=$(git log $(git describe --tags --abbrev=0)..HEAD --oneline \
    # changelog=$(git log $(git describe --tags --abbrev=0)..HEAD --pretty=format:"%s%n%b" \
    # Get commit messages and process them to handle multi-line commits properly
    # Use %B to get the full commit message with proper line breaks
    changelog=$(git log "$(git describe --tags --abbrev=0)"..HEAD --pretty=format:"%B" \
    | sed -E 's/^[0-9a-f]+ \([^)]+\) //; s/^[0-9a-f]+ //' \
    | sed -E 's/^[A-Z]+-[0-9]+ //' \
    | grep -vE '^(ncl|Merge|Bump|Fixing merge conflicts)' -i)

    # Process the changelog to handle multi-line commits properly
    changelog=$(echo "$changelog" | awk '
    BEGIN { in_commit = 0; commit_lines = ""; }
    /^$/ {
        if (in_commit && commit_lines != "") {
            # End of commit - process accumulated lines
            if (commit_lines ~ /^- /) {
                # Already has bullet points (AI commit) - add indentation to body lines
                n = split(commit_lines, lines, "\n")
                for (i = 1; i <= n; i++) {
                    if (lines[i] != "") {
                        if (i == 1) {
                            # First line (subject) - keep as main bullet
                            print lines[i]
                        } else {
                            # Body lines - add indentation
                            if (lines[i] ~ /^- /) {
                                print "\t" lines[i]
                            } else {
                                print "\t- " lines[i]
                            }
                        }
                    }
                }
            } else {
                # Manual commit - split lines and add bullets with indentation
                n = split(commit_lines, lines, "\n")
                for (i = 1; i <= n; i++) {
                    if (lines[i] != "") {
                        if (i == 1) {
                            # First line (subject) - main bullet
                            print "- " lines[i]
                        } else {
                            # Body lines - indented bullets
                            if (lines[i] ~ /^- /) {
                                print "\t" lines[i]
                            } else {
                                print "\t- " lines[i]
                            }
                        }
                    }
                }
            }
            commit_lines = ""
            in_commit = 0
        }
        next
    }
    {
        if (in_commit) {
            commit_lines = commit_lines "\n" $0
        } else {
            commit_lines = $0
            in_commit = 1
        }
    }
    END {
        if (in_commit && commit_lines != "") {
            # Process final commit
            if (commit_lines ~ /^- /) {
                # Already has bullet points (AI commit) - add indentation to body lines
                n = split(commit_lines, lines, "\n")
                for (i = 1; i <= n; i++) {
                    if (lines[i] != "") {
                        if (i == 1) {
                            # First line (subject) - keep as main bullet
                            print lines[i]
                        } else {
                            # Body lines - add indentation
                            if (lines[i] ~ /^- /) {
                                print " " lines[i]
                            } else {
                                print " - " lines[i]
                            }
                        }
                    }
                }
            } else {
                # Manual commit - split lines and add bullets with indentation
                n = split(commit_lines, lines, "\n")
                for (i = 1; i <= n; i++) {
                    if (lines[i] != "") {
                        if (i == 1) {
                            # First line (subject) - main bullet
                            print "- " lines[i]
                        } else {
                            # Body lines - indented bullets
                            if (lines[i] ~ /^- /) {
                                print "\t" lines[i]
                            } else {
                                print "\t- " lines[i]
                            }
                        }
                    }
                }
            }
        }
    }')

    # changelog_internal=$(git log $(git describe --tags --abbrev=0)..HEAD --pretty=format:"%h %s (%an)" \
    changelog_internal=$(git log "$(git describe --tags --abbrev=0)"..HEAD --pretty=format:"%h %s (%an)%n%B" \
    | sed -E 's/^[0-9a-f]+ \([^)]+\) //; s/^[0-9a-f]+ //' \
    | grep -vE '^(ncl|Merge|Bump|Fixing merge conflicts)' -i \
    | sed 's/^/- /')

    # prepend ** VERSION $newversion ** to the changelog
    # changelog="** VERSION $newversion **\n\n$changelog"

    # if changelog is just blank space or lines, don't add it
    if [ -z "$changelog" ]; then
    print_info "No changelog to add"
    else
    if [ -f "$changelogpath/$changelog_name" ]; then
        # if the first ## line is the same major and minor version as the new version replace it with the new version
            if [ "$(head -n 1 "$changelogpath/$changelog_name" | sed 's/## //' | cut -d. -f1,2)" == "$(echo $newversion | cut -d. -f1,2)" ]; then
                # if the second line is the same date as humandate
                if [ "$(sed -n '2p' "$changelogpath/$changelog_name")" == "$humandate" ]; then
                    # remove the first three lines
                    sed_inplace '1,3d' "$changelogpath/$changelog_name"
                    echo -e "## $newversion\n$humandate\n\n$changelog\n$(cat "$changelogpath/$changelog_name")" > "$changelogpath/$changelog_name"
                else
                    echo -e "## $newversion\n$humandate\n\n$changelog\n\n$(cat "$changelogpath/$changelog_name")" > "$changelogpath/$changelog_name"
                fi
            else
                    echo -e "## $newversion\n$humandate\n\n$changelog\n\n$(cat "$changelogpath/$changelog_name")" > "$changelogpath/$changelog_name"
            fi
        print_success "Updated changelog in $changelogpath/$changelog_name"
    else
        echo -e "## $newversion\n$humandate\n\n$changelog" > "$changelogpath/$changelog_name"
        print_success "Created changelog in $changelogpath/$changelog_name"
    fi
    fi

    # if changelog is just blank space or lines, don't add it
    if [ -z "$changelog_internal" ]; then
        print_info "No internal changelog to add"
    elif [ -f "$changelogpath/$changelog_internal_name" ]; then
        # Internal changelog exists, update it
        # if the first ## line is the same major and minor version as the new version replace it with the new version
        if [ "$(head -n 1 "$changelogpath/$changelog_internal_name" | sed 's/## //' | cut -d. -f1,2)" == "$(echo $newversion | cut -d. -f1,2)" ]; then
            # if the second line is the same date as longhumandate
            if [ "$(sed -n '2p' "$changelogpath/$changelog_internal_name")" == "$longhumandate" ]; then
                # remove the first three lines
                sed_inplace '1,3d' "$changelogpath/$changelog_internal_name"
                echo -e "## $newversion\n$longhumandate\n\n$changelog_internal\n$(cat "$changelogpath/$changelog_internal_name")" > "$changelogpath/$changelog_internal_name"
            else
                echo -e "## $newversion\n$longhumandate\n\n$changelog_internal\n\n$(cat "$changelogpath/$changelog_internal_name")" > "$changelogpath/$changelog_internal_name"
            fi
        else
            echo -e "## $newversion\n$longhumandate\n\n$changelog_internal\n\n$(cat "$changelogpath/$changelog_internal_name")" > "$changelogpath/$changelog_internal_name"
        fi
        print_success "Updated changelog in $changelogpath/$changelog_internal_name"
    else
        print_info "Internal changelog $changelogpath/$changelog_internal_name does not exist, skipping"
    fi

    clean_changelog "$changelogpath/$changelog_name"
    clean_changelog "$changelogpath/$changelog_internal_name"

}

function getBitbucketUrl(){
    print_section "Getting Bitbucket URL"
    REMOTE_URL=$(git remote get-url origin)
    if [[ "$REMOTE_URL" =~ bitbucket.org[:/]([^/]+)/([^/.]+) ]]; then
        WORKSPACE="${BASH_REMATCH[1]}"
        REPO="${BASH_REMATCH[2]}"
    else
        echo "Failed to extract workspace and repo from remote URL"
        exit 1
    fi
}

function bumpVersion() {
    # if $newversion is not set, exit with an error
    if [ -z "$newversion" ]; then
        print_error "No new version set. Exiting."
        exit 1
    fi

    # if $version_source is not set, exit with an error
    if [ -z "$version_source" ]; then
        print_error "No version source determined. Please run getVersion first. Exiting."
        exit 1
    fi

    print_section "Updating Version Numbers"

    # Update the primary version source first
    if [ "$version_source" = "custom_primary" ]; then
        print_info "Updating custom primary version source: $version_source_file..."
        was_executable=$(test -x "$version_source_file" && echo "yes" || echo "no")

        if update_version_in_file "$version_source_file" "$version_source_type" "$version_source_line_start" "$newversion"; then
            if [[ "$was_executable" == "yes" ]]; then
                chmod +x "$version_source_file"
                print_info "Restored +x on $version_source_file"
            fi
            print_success "Updated version to $newversion in $version_source_file"
        else
            print_error "Failed to update version in $version_source_file"
            exit 1
        fi
    elif [ "$version_source" = "package.json" ]; then
        print_info "Updating primary version source: package.json..."
        local package_json_file="${package_json_path}/package.json"
        if update_version_in_file "$package_json_file" "json" "" "$newversion"; then
            print_success "Updated version to $newversion in package.json"
        else
            print_error "Failed to update version in package.json"
            exit 1
        fi

        # Also update VERSION file if it exists (for compatibility)
        if [ -f "$version_file_path/VERSION" ]; then
            print_info "Updating VERSION file for compatibility..."
            if update_version_in_file "$version_file_path/VERSION" "txt" "" "$newversion"; then
                print_success "Updated version to $newversion in VERSION file"
            fi
        fi
    else
        # VERSION file is the primary source
        print_info "Updating primary version source: VERSION file..."
        if update_version_in_file "$version_file_path/VERSION" "txt" "" "$newversion"; then
            print_success "Updated version to $newversion in VERSION file"
        else
            print_error "Failed to update version in VERSION file"
            exit 1
        fi

        # Also update package.json if it exists (for compatibility)
        local package_json_file="${package_json_path}/package.json"
        if [ -f "$package_json_file" ]; then
            print_info "Updating package.json for compatibility..."
            if update_version_in_file "$package_json_file" "json" "" "$newversion"; then
                print_success "Updated version to $newversion in package.json"
            fi
        fi
    fi

    # Update secondary version files if configured
    if [[ -n "$version_secondary_files" ]]; then
        print_info "Updating secondary version files..."
        while IFS= read -r file_config; do
            if [[ -n "$file_config" ]]; then
                IFS=':' read -ra config_parts <<< "$file_config"
                local sec_file="${config_parts[0]}"
                local sec_type="${config_parts[1]:-txt}"
                local sec_line_start="${config_parts[2]:-}"
                # Track which files were executable before
                was_executable=$(test -x "$sec_file" && echo "yes" || echo "no")

                if update_version_in_file "$sec_file" "$sec_type" "$sec_line_start" "$newversion"; then
                    if [[ "$was_executable" == "yes" ]]; then
                        chmod +x "$sec_file"
                        print_info "Restored +x on $sec_file"
                    fi
                    print_success "Updated version to $newversion in $sec_file"
                else
                    print_warning "Failed to update version in $sec_file"
                fi
            fi
        done <<< "$(parse_secondary_version_files "$version_secondary_files")"
    fi

    # Update WordPress files if applicable (legacy support)
    if [[ -n "$wordpress_files_path" ]]; then
        if sed_inplace "s/Version: .*/Version: $newversion/" "$wordpress_files_path/style.css"; then
            print_success "Updated version in style.css"
        fi

        if sed_inplace "s/^define.*.$wpVersionConstant.*/define('$wpVersionConstant','$newversion');/" "$wordpress_files_path/functions.php"; then
            print_success "Updated version in functions.php"
        fi
    fi
}


function branchDetection() {
    print_section "Branch Detection"
    print_info "Currently on branch: ${BWhite}$branch_name${Color_Off}"
    # if we are on the master branch, advise user not to use this script for hot fixes
    if [ "$branch_name" == "$masterbranch" ]; then
        print_warning "You are currently on the $masterbranch branch"
        read -n 1 -s -p "$(echo -e ${BYellow}Do you want to continue on $developbranch? [y/N]${Color_Off} )" REPLY
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Operation cancelled by user"
            exit 1
        fi
    fi

    # if we are on the master or staging branch, switch to develop
    if [ "$branch_name" == "$masterbranch" ] || [ "$branch_name" == "$stagingbranch" ]; then
        print_info "Switching to $developbranch branch..."
        git checkout "$developbranch"
        check_git_success
        branch_name="$developbranch"
        print_success "Switched to $developbranch branch"

    fi
}

function get_ai_commit_message_style() {

  # Determine the OpenAI commit message style
  if [[ -n "$MAIASS_OPENAI_COMMIT_MESSAGE_STYLE" ]]; then
    openai_commit_style="$MAIASS_OPENAI_COMMIT_MESSAGE_STYLE"
    print_info "Using AI commit style from .env: $openai_commit_style" >&2
  elif [[ -f ".maiass.prompt" ]]; then
    openai_commit_style="custom"
    print_info "No style set in .env; using local prompt file: .maiass.prompt" >&2
  elif [[ -f "$HOME/.maiass.prompt" ]]; then
    openai_commit_style="global_custom"
    print_info "No style set in .env; using global prompt file: ~/.maiass.prompt" >&2
  else
    openai_commit_style="bullet"
    print_info "No style or prompt files found; defaulting to 'bullet'" >&2
  fi
  export openai_commit_style
}

# Function to get AI-generated commit message suggestion
function get_ai_commit_suggestion() {
  local git_diff
  local ai_prompt
  local api_response
  local suggested_message

bullet_prompt="Analyze the following git diff and create a commit message with bullet points. Format as:
'Brief summary title
  - feat: add user authentication
  - fix(api): resolve syntax error
  - docs: update README'

Use past tense verbs. No blank line between title and bullets. Keep concise.

Git diff:
\$git_diff"

conventional_prompt="Analyze the following git diff and suggest a commit message using conventional commit format (type(scope): description). Examples: 'feat: add user authentication', 'fix(api): resolve null pointer exception', 'docs: update README'. Keep it concise.

Git diff:
\$git_diff"

simple_prompt="Analyze the following git diff and suggest a concise, descriptive commit message. Keep it under 50 characters for the first line, with additional details on subsequent lines if needed.

Git diff:
\$git_diff"



  # Debug test - this should always show if debug is enabled
  if [[ "$debug_mode" == "true" ]]; then
    print_info "DEBUG: AI function called with debug_mode=$debug_mode" >&2
    print_info "DEBUG: MAIASS_DEBUG=$MAIASS_DEBUG" >&2
  fi

  # Get git diff for context
  git_diff=$(git diff --cached --no-color 2>/dev/null || git diff --no-color 2>/dev/null || echo "No changes detected")
  git_diff=$(echo "$git_diff" | tr -cd '\11\12\15\40-\176')
  [[ "$debug_mode" == "true" ]] && print_info "DEBUG: Git diff length: ${#git_diff} characters" >&2

  # Truncate diff if too long (API has token limits)
  if [[ ${#git_diff} -gt 8000 ]]; then
    git_diff="${git_diff:0:8000}...[truncated]"
    [[ "$debug_mode" == "true" ]] && print_info "DEBUG: Git diff truncated to 8000 characters" >&2
  fi
    print_info "DEBUG: prompt mode: $openai_commit_style" >&2
  get_ai_commit_message_style
  # Create AI prompt based on commit style
  case "$openai_commit_style" in
  "bullet")
    ai_prompt="${bullet_prompt//\$git_diff/$git_diff}"
    ;;
  "conventional")
    ai_prompt="${conventional_prompt//\$git_diff/$git_diff}"
    ;;
  "simple")
    ai_prompt="${simple_prompt//\$git_diff/$git_diff}"
    ;;
    "custom")
    if [[ -f ".maiass.prompt" ]]; then
      custom_prompt=$(<.maiass.prompt)
      if [[ -n "$custom_prompt" && "$custom_prompt" == *"\$git_diff"* ]]; then
        ai_prompt="${custom_prompt//\$git_diff/$git_diff}"
      else
        print_warning ".maiass.prompt is missing or does not include \$git_diff. Using Bullet format." >&2
        ai_prompt="${bullet_prompt//\$git_diff/$git_diff}"
      fi
    else
      print_warning "Style 'custom' selected but .maiass.prompt not found. Using Bullet format." >&2
      ai_prompt="${bullet_prompt//\$git_diff/$git_diff}"
    fi
    ;;
  "global_custom")
    if [[ -f "$HOME/.maiass.prompt" ]]; then
      custom_prompt=$(<"$HOME/.maiass.prompt")
      if [[ -n "$custom_prompt" && "$custom_prompt" == *"\$git_diff"* ]]; then
        ai_prompt="${custom_prompt//\$git_diff/$git_diff}"
      else
        print_warning "~/.maiass.prompt is missing or does not include \$git_diff. Using Bullet format." >&2
        ai_prompt="${bullet_prompt//\$git_diff/$git_diff}"
      fi
    else
      print_warning "Style 'global_custom' selected but ~/.maiass.prompt not found. Using Bullet format." >&2
      ai_prompt="${bullet_prompt//\$git_diff/$git_diff}"
    fi
    ;;

  *)
    print_warning "Unknown commit message style: '$openai_commit_style'. Skipping AI suggestion." >&2
    ai_prompt="${bullet_prompt//\$git_diff/$git_diff}"
    ;;
esac


  # Call OpenAI API
  [[ "$debug_mode" == "true" ]] && print_info "DEBUG: Calling OpenAI API with model: $openai_model" >&2
  [[ "$debug_mode" == "true" ]] && print_info "DEBUG: AI prompt style: $openai_commit_style" >&2

  # Build JSON payload using jq if available (handles escaping automatically)
  local json_payload
  if command -v jq >/dev/null 2>&1; then
    json_payload=$(jq -n --arg model "$openai_model" --arg prompt "$ai_prompt" '{
      "model": $model,
      "messages": [
        {"role": "system", "content": "You are a helpful assistant that writes concise, descriptive git commit messages based on code changes."},
        {"role": "user", "content": $prompt}
      ],
      "max_tokens": 150,
      "temperature": 0.7
    }')
  else
    # Simple fallback - replace quotes and newlines only
    local safe_prompt
    safe_prompt=$(printf '%s' "$ai_prompt" | sed 's/"/\\"/g' | tr '\n' ' ')
    json_payload='{"model":"'$openai_model'","messages":[{"role":"system","content":"You are a helpful assistant that writes concise, descriptive git commit messages based on code changes."},{"role":"user","content":"'$safe_prompt'"}],"max_tokens":150,"temperature":0.7}'
  fi

  [[ "$debug_mode" == "true" ]] && print_info "DEBUG: JSON payload length: ${#json_payload} characters" >&2

  api_response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $openai_token" \
    -d "$json_payload" 2>/dev/null)

  [[ "$debug_mode" == "true" ]] && print_info "DEBUG: API response length: ${#api_response} characters" >&2

  # Extract the suggested message from API response
  if [[ -n "$api_response" ]]; then
    # Check for API error first
    if echo "$api_response" | grep -q '"error"'; then
      error_msg=$(echo "$api_response" | grep -o '"message":"[^"]*"' | sed 's/"message":"//' | sed 's/"$//' | head -1)
      print_warning "OpenAI API Error: $error_msg"
      [[ "$debug_mode" == "true" ]] && print_info "DEBUG: Full error response: $api_response" >&2
      return 1
    fi

    [[ "$debug_mode" == "true" ]] && print_info "DEBUG: Attempting to parse JSON response" >&2

    # Try jq first if available (most reliable)
    if command -v jq >/dev/null 2>&1; then
      [[ "$debug_mode" == "true" ]] && print_info "DEBUG: Using jq for JSON parsing" >&2
      suggested_message=$(echo "$api_response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
      [[ "$debug_mode" == "true" ]] && print_info "DEBUG: jq result: '$suggested_message'" >&2
    fi

    # Fallback to sed parsing if jq not available or failed
    if [[ -z "$suggested_message" ]]; then
      [[ "$debug_mode" == "true" ]] && print_info "DEBUG: jq failed, trying sed parsing" >&2
      # Handle the actual OpenAI response structure with nested objects
      suggested_message=$(echo "$api_response" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p' | tail -1)
      [[ "$debug_mode" == "true" ]] && print_info "DEBUG: sed result: '$suggested_message'"
    fi

    # Last resort: simple grep approach
    if [[ -z "$suggested_message" ]]; then
      [[ "$debug_mode" == "true" ]] && print_info "DEBUG: sed failed, trying grep approach"
      suggested_message=$(echo "$api_response" | grep -o '"content":"[^"]*"' | sed 's/"content":"//' | sed 's/"$//' | tail -1)
      [[ "$debug_mode" == "true" ]] && print_info "DEBUG: grep result: '$suggested_message'"
    fi

    # Show raw API response if debug mode and parsing failed
    if [[ "$debug_mode" == "true" && -z "$suggested_message" ]]; then
      print_info "DEBUG: All parsing methods failed. Raw API response:"
      if [[ ${#api_response} -lt 1000 ]]; then
        print_info "$api_response"
      else
        print_info "${api_response:0:1000}...[truncated]"
      fi
    fi

    # Clean up escaped characters and markdown formatting
    suggested_message=$(echo "$suggested_message" | sed 's/\\n/\n/g' | sed 's/\\t/\t/g' | sed 's/\\\\/\\/g')

    # Remove markdown code blocks (triple backticks)
    suggested_message=$(echo "$suggested_message" | sed '/^```/d')

    # Clean up the message (remove leading/trailing whitespace)
    suggested_message=$(echo "$suggested_message" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

    [[ "$debug_mode" == "true" ]] && print_info "DEBUG: Final cleaned message: '$suggested_message'" >&2

    if [[ -n "$suggested_message" && "$suggested_message" != "null" ]]; then
      echo "$suggested_message"
      return 0
    else
      [[ "$debug_mode" == "true" ]] && print_info "DEBUG: No valid message extracted (empty or null)"
    fi
  else
    [[ "$debug_mode" == "true" ]] && print_info "DEBUG: Empty API response"
  fi

  # Return empty if AI suggestion failed
  return 1
}



function get_commit_message() {
  commit_message=""
  jira_ticket_number=""
  local ai_suggestion=""
  local use_ai=false

  # Extract Jira ticket number from branch name if present
  if [[ "$branch_name" =~ .*/([A-Z]+-[0-9]+) ]]; then
      jira_ticket_number="${BASH_REMATCH[1]}"
      print_info "Jira Ticket Number: ${BWhite}$jira_ticket_number${Color_Off}"
  fi

  # Handle AI commit message modes
  [[ "$debug_mode" == "true" ]] && print_info "DEBUG: openai_mode='$openai_mode', openai_token length=${#openai_token}"

  case "$openai_mode" in
    "ask")
      [[ "$debug_mode" == "true" ]] && print_info "DEBUG: AI mode is 'ask'"
      if [[ -n "$openai_token" ]]; then
        [[ "$debug_mode" == "true" ]] && print_info "DEBUG: Token available, showing AI prompt"
        read -n 1 -s -p "$(echo -e ${BYellow}Would you like to use AI to suggest a commit message? [y/N]${Color_Off} )" REPLY
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          [[ "$debug_mode" == "true" ]] && print_info "DEBUG: User chose to use AI"
          use_ai=true
        else
          [[ "$debug_mode" == "true" ]] && print_info "DEBUG: User declined AI (reply='$REPLY')"
        fi
      else
        [[ "$debug_mode" == "true" ]] && print_info "DEBUG: No token available for AI"
      fi
      ;;
    "autosuggest")
      [[ "$debug_mode" == "true" ]] && print_info "DEBUG: AI mode is 'autosuggest'"
      if [[ -n "$openai_token" ]]; then
        use_ai=true
      fi
      ;;
    "off"|*)
      [[ "$debug_mode" == "true" ]] && print_info "DEBUG: AI mode is 'off' or unknown: '$openai_mode'"
      use_ai=false
      ;;
  esac

  [[ "$debug_mode" == "true" ]] && print_info "DEBUG: use_ai=$use_ai"

  # Try to get AI suggestion if requested
  if [[ "$use_ai" == true ]]; then
    print_info "Getting AI commit message suggestion..." "brief"
    if ai_suggestion=$(get_ai_commit_suggestion); then
      print_success "AI suggested commit message:"
      echo -e "${BWhite}$ai_suggestion${Color_Off}"
      echo

      # Ask user if they want to use the AI suggestion
      read -n 1 -s -p "$(echo -e ${BCyan}Use this AI suggestion? [Y/n/e=edit]${Color_Off} )" REPLY
      echo

      case "$REPLY" in
        [Nn])
          print_info "AI suggestion declined, entering manual mode" "brief"
          use_ai=false
          ;;
        [Ee])
          print_info "Edit mode: You can modify the AI suggestion" "brief"
          echo -e "${BCyan}Current AI suggestion:${Color_Off}"
          echo -e "${BWhite}$ai_suggestion${Color_Off}"
          echo
          echo -e "${BCyan}Enter your modified commit message (press Enter three times when finished, or just Enter to keep AI suggestion):${Color_Off}"

          # Read multi-line input
          commit_message=""
          line_count=0
          empty_line_count=0
          while true; do
            read -r line
            if [[ -z "$line" ]]; then
              empty_line_count=$((empty_line_count + 1))
              if [[ $line_count -eq 0 && $empty_line_count -eq 1 ]]; then
                # First empty line with no input - use AI suggestion
                commit_message="$ai_suggestion"
                print_info "Using original AI suggestion"
                break
              elif [[ $empty_line_count -ge 2 ]]; then
                # Two consecutive empty lines (three Enter presses) - finish input
                break
              fi
              continue
            else
              # Reset empty line counter when we get non-empty input
              empty_line_count=0
            fi
            if [[ $line_count -gt 0 ]]; then
              commit_message+=$'\n'
            fi
            commit_message+="$line"
            ((line_count++))
          done
          ;;
        *)
          # Default: accept AI suggestion
          commit_message="$ai_suggestion"
          ;;
      esac
    else
      print_warning "AI suggestion failed, falling back to manual entry"
      use_ai=false
    fi
  fi

  # Manual commit message entry if AI not used or failed
  if [[ "$use_ai" == false && -z "$commit_message" ]]; then
    if [[ -n "$jira_ticket_number" ]]; then
      print_info "Enter a commit message ${BWhite}(Jira ticket $jira_ticket_number will be prepended)${Color_Off}"
    else
      print_info "Enter a commit message ${BWhite}(starting with Jira Ticket# when relevant)${Color_Off}"
      print_info "Please enter a ticket number or 'fix:' or 'feature:' or 'devops:' to start the commit message"
    fi

    echo -e "${BCyan}Enter ${BYellow}multiple lines${BCyan} (press Enter ${BYellow}three times${BCyan} to finish)${Color_Off}:"

    commit_message=""
    first_line=true
    empty_line_count=0
    while true; do
        read -r line
        # Check for empty line
        if [[ -z "$line" ]]; then
            empty_line_count=$((empty_line_count + 1))
            # Need two consecutive empty lines (three Enter presses) to finish
            if [[ $empty_line_count -ge 2 ]]; then
                break
            fi
            continue
        else
            # Reset empty line counter when we get non-empty input
            empty_line_count=0
        fi
        # Auto-prepend bullet point if line doesn't already start with one
        if [[ ! "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            line="- $line"
        fi

        if [[ "$first_line" == true ]]; then
            # First line is the subject - add it with double newline for proper git format
            commit_message+="$line"$'\n\n'
            first_line=false
        else
            # Subsequent lines are body - add with single newline
            commit_message+="$line"$'\n'
        fi
    done
    # Remove one trailing newline if present:
    commit_message="${commit_message%$'\n'}"
  fi

  # Prepend Jira ticket number if found and not already present
  if [[ -n "$jira_ticket_number" && ! "$commit_message" =~ ^$jira_ticket_number ]]; then
    commit_message="$jira_ticket_number $commit_message"
  fi

  # Abort if the commit message is still empty
  if [[ -z "$commit_message" ]]; then
      echo "Aborting commit due to empty commit message."
      exit 1
  fi

  # Export the commit message and jira ticket number for use by calling function
  export commit_message
  export jira_ticket_number
}



run_ai_commit_only() {
  echo "this feature is not yet supported"
}



# Check for uncommitted changes and offer to commit them
function checkUncommittedChanges(){
  print_section "Checking for Changes"
  # if there are uncommitted changes, ask if the user wants to commit them
  if [ -n "$(git status --porcelain)" ]; then
      print_warning "There are uncommitted changes in your working directory"
      read -n 1 -s -p "$(echo -e ${BYellow}Do you want to commit them? [y/N]${Color_Off} )" REPLY
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
          git add -A
          get_commit_message

          # Use git commit -F - to properly handle multi-line commit messages
          if [[ "$debug_mode" == "true" ]] || [[ "$verbosity_level" == "debug" ]]; then
            echo "$commit_message" | git commit -F -
          else
            echo "$commit_message" | git commit -F - >/dev/null 2>&1
          fi
          check_git_success
          tagmessage=$commit_message
          export tagmessage
          print_success "Changes committed successfully"
          # Sanitize commit message for CSV/Google Sheets compatibility
          local devlog_message="${commit_message%$}"
          devlog_message="${metlog_message//$'\n'/; }"
          devlog "$devlog_message" "c" "$header" "$jira_ticket_number"

          # set upstream
          if remote_exists "origin"; then
            run_git_command "git push --set-upstream origin '$branch_name'" "debug"
            check_git_success
          fi
      else
          print_error "Cannot proceed with uncommitted changes"
          exit 1
      fi
  fi
}

function changeManagement(){
  checkUncommittedChanges
}

function mergeDevelop() {
  local has_version_files="${1:-true}"  # Default to true for backward compatibility
  shift  # Remove the first argument so remaining args can be passed to getVersion

  print_section "Git Workflow"

  # Check if develop branch exists
  if ! branch_exists "$developbranch"; then
    print_warning "Branch '$developbranch' does not exist"
    print_info "Using simplified workflow on current branch: $branch_name"

    # Check if we have a remote for pulling latest changes
    if remote_exists "origin"; then
      print_info "Pulling latest changes from remote"
      git pull 2>/dev/null || print_warning "Could not pull from remote (continuing anyway)"
    else
      print_info "No remote found - working with local repository only"
    fi
  else
    # Standard develop branch workflow
    print_info "Using standard develop branch workflow"

    # Ensure we are on the 'develop' branch or merge into it
    if [ "$(git rev-parse --abbrev-ref HEAD)" != "$developbranch" ]; then
        print_info "Not on $developbranch branch"
        read -n 1 -s -p "$(echo -e ${BYellow}Do you want to merge $branch_name into $developbranch? [y/N]${Color_Off} )" REPLY
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git checkout "$developbranch"
            check_git_success

            # Pull from remote if available
            if remote_exists "origin"; then
              # Check if current branch has upstream tracking
              if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
                git pull
                check_git_success
              else
                # Try to set up tracking if remote branch exists
                if git ls-remote --heads origin "$developbranch" | grep -q "$developbranch"; then
                  print_info "Setting up tracking for $developbranch with origin/$developbranch"
                  git branch --set-upstream-to=origin/$developbranch "$developbranch"
                  check_git_success
                  git pull
                  check_git_success
                else
                  print_info "Remote branch $developbranch does not exist - skipping pull"
                fi
              fi
            else
              print_info "No remote found - skipping pull"
            fi

            git merge "$branch_name"
            check_git_success
            devlog "Merged $branch_name into $developbranch" "c" "$header" "$jira_ticket_number"
        else
            print_error "Cannot proceed without merging into $developbranch"
            exit 1
        fi
    else
        # Pull from remote if available
        if remote_exists "origin"; then
          git pull
          check_git_success
        else
          print_info "No remote found - skipping pull"
        fi
    fi
  fi

  # Only do version management if version files exist
  if [[ "$has_version_files" == "true" ]]; then
    # we are on $developbranch so we can update the changelog and version
    # bump the version
    getVersion "$@"
    # create a release branch
    git checkout -b "release/$newversion"
    check_git_success
    bumpVersion
    updateChangelog $changelog_path
    print_info "updateChanelog completed"
    # commit and tag the release
    git add -A
    check_git_success
    print_info "git added completed"
    git commit -m "Bumped version to $newversion"
    check_git_success

    # Create version tag if it doesn't already exist
    if git tag -l "$newversion" | grep -q "^$newversion$"; then
      print_warning "Tag $newversion already exists - skipping tag creation"
    else
      git tag -a "$newversion" -m "Release version $newversion"
      check_git_success
      print_success "Tagged release as $newversion"
    fi

    # push to origin if remote exists
    if remote_exists "origin"; then
      git push --set-upstream origin "release/$newversion"
      check_git_success
    else
      print_info "No remote found - skipping push of release branch"
    fi

    # merge release back to develop
    git checkout "$developbranch"
    check_git_success

    # Pull from remote if available
    if remote_exists "origin"; then
      # Check if current branch has upstream tracking
      if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        git pull
        check_git_success
      else
        # Try to set up tracking if remote branch exists
        if git ls-remote --heads origin "$developbranch" | grep -q "$developbranch"; then
          print_info "Setting up tracking for $developbranch with origin/$developbranch"
          git branch --set-upstream-to=origin/"$developbranch" "$developbranch"
          git pull
          check_git_success
        else
          print_info "Remote branch origin/$developbranch doesn't exist - skipping pull"
        fi
      fi
    else
      print_info "No remote found - skipping pull"
    fi

    git merge --no-ff "release/$newversion"
    check_git_success
    print_success "Merged release/$newversion back to $developbranch"

    # Push develop branch and tags if remote exists
    if remote_exists "origin"; then
      # Check if current branch has upstream tracking, if not set it up
      if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        print_info "Setting up upstream tracking for $developbranch"
        git push --set-upstream origin "$developbranch"
      else
        git push
      fi
      check_git_success
      git push --tags
      check_git_success
    else
      print_info "No remote found - skipping push of $developbranch and tags"
    fi

    # Return to original branch
    git checkout "$branch_name"
    check_git_success
    print_info "Returned to original branch: $branch_name"

    print_success "Bumped version to $newversion"
    # Only show merge success if develop branch exists
    if branch_exists "$developbranch"; then
      print_success "Merged $branch_name into $developbranch"
    else
      print_info "Completed workflow on current branch (no develop branch)"
    fi
  else
    # Just do the git workflow without version management
    print_info "Skipping version bump and changelog update (no version files)"
    # Only show merge success if develop branch exists
    if branch_exists "$developbranch"; then
      print_success "Merged $branch_name into $developbranch"
    else
      print_info "Completed workflow on current branch (no develop branch)"
    fi
  fi
}

function deployOptions() {
  # Check what branches are available and adapt options accordingly
  local has_develop has_staging has_master has_remote
  has_develop=$(branch_exists "$developbranch" && echo "true" || echo "false")
  has_staging=$(branch_exists "$stagingbranch" && echo "true" || echo "false")
  has_master=$(branch_exists "$masterbranch" && echo "true" || echo "false")
  has_remote=$(remote_exists "origin" && echo "true" || echo "false")

  print_info "What would you like to do?"

  # Build dynamic menu based on available branches
  local option_count=0
  local options=()

  if [[ "$has_develop" == "true" && "$has_staging" == "true" ]]; then
    ((option_count++))
    options["$option_count"]="merge_develop_to_staging"
    echo "$option_count) Merge $developbranch to $stagingbranch"
  fi

  if [[ "$has_staging" == "true" ]]; then
    ((option_count++))
    options["$option_count"]="merge_current_to_staging"
    echo "$option_count) Merge $branch_name to $stagingbranch"
  fi

  # Only show direct merge to master if no staging branch exists (proper Git Flow)
  if [[ "$has_master" == "true" && "$has_staging" == "false" ]]; then
    ((option_count++))
    options["$option_count"]="merge_to_master"
    if [[ "$has_develop" == "true" ]]; then
      echo "$option_count) Merge $developbranch to $masterbranch"
    else
      echo "$option_count) Merge $branch_name to $masterbranch"
    fi
  fi

  if [[ "$has_remote" == "true" ]]; then
    ((option_count++))
    options["$option_count"]="push_current"
    echo "$option_count) Push current branch to remote"
  fi

  ((option_count++))
  options["$option_count"]="do_nothing"
  echo "$option_count) Do nothing (finish here)"

  if [[ $option_count -eq 1 ]]; then
    print_warning "Limited options available due to repository structure"
  fi

  read -p "$(echo -e ${BCyan}Enter choice [1-$option_count, Enter for $option_count]: ${Color_Off})" choice

  # Default to "do nothing" if user just hits Enter
  if [[ -z "$choice" ]]; then
    choice="$option_count"  # "do nothing" is always the last option
  fi

  # Handle user choice based on available options
  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$option_count" ]]; then
    local selected_action="${options[$choice]}"

    case "$selected_action" in
      "merge_develop_to_staging")
        print_info "Merging $developbranch to $stagingbranch"
        perform_merge_operation "$developbranch" "$stagingbranch"
        ;;
      "merge_current_to_staging")
        print_info "Merging $branch_name to $stagingbranch"
        perform_merge_operation "$branch_name" "$stagingbranch"
        ;;
      "merge_to_master")
        local source_branch
        if [[ "$has_develop" == "true" ]]; then
          source_branch="$developbranch"
        else
          source_branch="$branch_name"
        fi
        print_info "Merging $source_branch to $masterbranch"
        perform_merge_operation "$source_branch" "$masterbranch"
        ;;
      "push_current")
        print_info "Pushing current branch to remote"
        if can_push_to_remote "origin"; then
          git push --set-upstream origin "$branch_name" 2>/dev/null || git push origin "$branch_name"
          check_git_success
          print_success "Pushed $branch_name to remote"
        else
          print_error "Cannot push to remote"
        fi
        ;;
      "do_nothing")
        print_info "No action selected - finishing here"
        ;;
      *)
        print_error "Invalid selection"
        ;;
    esac
  else
    print_error "Invalid choice. Please select a number between 1 and $option_count"
  fi

  git checkout "$branch_name"

  print_info "All done. You are on branch: ${BWhite}$branch_name${Color_Off}"

  # Clean up
  unset GIT_MERGE_AUTOEDIT
  unset tagmessage
}


# Function to load MAIASS_* variables from .env files
load_bumpscript_env() {
  local env_file=".env"

  # Check if .env file exists
  if [[ -f "$env_file" ]]; then
    print_info "Loading MAIASS_* variables from $env_file"

    # Read .env file and extract MAIASS_* variables
    while IFS='=' read -r key value; do
      # Skip comments and empty lines
      [[ "$key" =~ ^#.*$ ]] && continue
      [[ -z "$key" ]] && continue

      # Only process MAIASS_* variables
      if [[ "$key" =~ ^MAIASS_ ]]; then
        # Remove quotes from value if present
        value=$(echo "$value" | sed 's/^["'"'"']\|["'"'"']$//g')

        # Export the variable (this will override any existing env vars)
        export "$key"="$value"
        print_info "Set $key=$value"
      fi
    done < <(grep -E '^[^#]*=' "$env_file" 2>/dev/null || true)
  fi
}

# Function to set up branch and changelog variables with override logic
setup_bumpscript_variables() {
  # Branch name defaults with MAIASS_* overrides
  export developbranch="${MAIASS_DEVELOPBRANCH:-develop}"
  export stagingbranch="${MAIASS_STAGINGBRANCH:-staging}"
  export masterbranch="${MAIASS_MASTERBRANCH:-master}"

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
  export REPO_PROVIDER=""
  export BITBUCKET_WORKSPACE="${MAIASS_BITBUCKET_WORKSPACE:-}"
  export BITBUCKET_REPO_SLUG="${MAIASS_BITBUCKET_REPO_SLUG:-}"
  export GITHUB_OWNER="${MAIASS_GITHUB_OWNER:-}"
  export GITHUB_REPO="${MAIASS_GITHUB_REPO:-}"

  # Detect Bitbucket
  if [[ "$git_remote_url" =~ bitbucket\.org[:/]([^/]+)/([^/\.]+) ]]; then
    export REPO_PROVIDER="bitbucket"
    export BITBUCKET_WORKSPACE="${MAIASS_BITBUCKET_WORKSPACE:-${BASH_REMATCH[1]}}"
    export BITBUCKET_REPO_SLUG="${MAIASS_BITBUCKET_REPO_SLUG:-${BASH_REMATCH[2]}}"
  # Detect GitHub
  elif [[ "$git_remote_url" =~ github\.com[:/]([^/]+)/([^/\.]+) ]]; then
    export REPO_PROVIDER="github"
    export GITHUB_OWNER="${MAIASS_GITHUB_OWNER:-${BASH_REMATCH[1]}}"
    export GITHUB_REPO="${MAIASS_GITHUB_REPO:-${BASH_REMATCH[2]}}"
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
  export openai_mode="${MAIASS_OPENAI_MODE:-off}"
  export openai_token="${MAIASS_OPENAI_TOKEN:-}"
  export openai_model="${MAIASS_OPENAI_MODEL:-gpt-4o}"


  # Determine the OpenAI commit message style
  if [[ -n "$MAIASS_OPENAI_COMMIT_MESSAGE_STYLE" ]]; then
    openai_commit_style="$MAIASS_OPENAI_COMMIT_MESSAGE_STYLE"
    print_info "Using AI commit style from .env: $openai_commit_style"
  elif [[ -f ".maiass.prompt" ]]; then
    openai_commit_style="custom"
    print_info "No style set in .env; using local prompt file: .maiass.prompt"
  elif [[ -f "$HOME/.maiass.prompt" ]]; then
    openai_commit_style="global_custom"
    print_info "No style set in .env; using global prompt file: ~/.maiass.prompt"
  else
    openai_commit_style="bullet"
    print_info "No style or prompt files found; defaulting to 'bullet'"
  fi

  export openai_commit_style


  export debug_mode="${MAIASS_DEBUG:-false}"

  # Validate AI configuration - prevent ask/autosuggest modes without token
  if [[ "$openai_mode" == "ask" || "$openai_mode" == "autosuggest" ]]; then
    if [[ -z "$openai_token" ]]; then
      print_warning "AI commit message mode '$openai_mode' requires MAIASS_OPENAI_TOKEN"
      print_warning "Falling back to 'off' mode"
      export openai_mode="off"
    fi
  fi

  print_info "Integration configuration:"
  print_info "  Staging pull requests: $staging_pullrequests"
  print_info "  Master pull requests: $master_pullrequests"
  print_info "  AI commit messages: $openai_mode"
  if [[ "$openai_mode" != "off" && -n "$openai_token" ]]; then
    print_info "  AI model: $openai_model"
    print_info "  AI commit style: $openai_commit_style"
  fi
  if [[ "$REPO_PROVIDER" == "bitbucket" && -n "$BITBUCKET_WORKSPACE" ]]; then
    print_info "  Repository: Bitbucket ($BITBUCKET_WORKSPACE/$BITBUCKET_REPO_SLUG)"
  elif [[ "$REPO_PROVIDER" == "github" && -n "$GITHUB_OWNER" ]]; then
    print_info "  Repository: GitHub ($GITHUB_OWNER/$GITHUB_REPO)"
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

  echo -e "${BBlue}MAIASS (My AI Semantic Savant) - Intelligent Git Workflow Automation${Color_Off}\n"

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
  echo -e "  ${BGreen}2.${Color_Off} For AI features: Set ${BRed}MAIASS_OPENAI_TOKEN${Color_Off} environment variable"
  echo -e "  ${BGreen}3.${Color_Off} Everything else works with sensible defaults!\n"

  echo -e "${BWhite}WORKFLOW:${Color_Off}"
  echo -e "  ${BGreen}1.${Color_Off} Merge feature branch → develop"
  echo -e "  ${BGreen}2.${Color_Off} Create release/x.x.x branch from develop"
  echo -e "  ${BGreen}3.${Color_Off} Update version files and changelog on release branch"
  echo -e "  ${BGreen}4.${Color_Off} Commit and push release branch"
  echo -e "  ${BGreen}5.${Color_Off} Merge release branch back to develop"
  echo -e "  ${BGreen}6.${Color_Off} Return to original feature branch\n"

  echo -e "  ${BYellow}Git Flow Diagram:${Color_Off}"
  echo -e "    feature/xyz ──┐"
  echo -e "                  ├─→ develop ──→ release/1.2.3 ──┐"
  echo -e "    feature/abc ──┘                                ├─→ develop"
  echo -e "                                                    └─→ (tagged)\n"

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

  echo -e "${BYellow}💡 Most settings are OPTIONAL with sensible defaults!${Color_Off}"
  echo -e "${BYellow}   Only set these if you want to override the default behavior.${Color_Off}\n"

  echo -e "${BWhite}🤖 AI FEATURES:${Color_Off}"
  echo -e "  ${BRed}MAIASS_OPENAI_TOKEN${Color_Off}          Optional but ${BRed}REQUIRED${Color_Off} if you want AI commit messages"
  echo -e "  MAIASS_OPENAI_MODE           ${Gray}('ask')${Color_Off} 'off', 'autosuggest'"
  echo -e "  MAIASS_OPENAI_MODEL          ${Gray}('gpt-4o')${Color_Off} AI model to use"
  echo -e "  MAIASS_OPENAI_COMMIT_MESSAGE_STYLE  ${Gray}('bullet')${Color_Off} 'conventional', 'simple'\n"

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
  echo -e "                                   Supported: Chrome, Firefox, Safari, Brave, Savant"
  echo -e "  MAIASS_BROWSER_PROFILE       ${Gray}('Default')${Color_Off} Browser profile to use\n"

  echo -e "${BWhite}📁 CUSTOM VERSION FILES:${Color_Off}"
  echo -e "  ${BYellow}For projects with non-standard version file structures:${Color_Off}"
  echo -e "  MAIASS_VERSION_PRIMARY_FILE        Primary version file path"
  echo -e "  MAIASS_VERSION_PRIMARY_TYPE        ${Gray}('txt')${Color_Off} 'json' or 'txt' or 'pattern'"
  echo -e "  MAIASS_VERSION_PRIMARY_LINE_START  Line prefix for txt files"
  echo -e "  MAIASS_VERSION_SECONDARY_FILES     Secondary files (pipe-separated)\n"

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
  echo -e "  • ${BGreen}AI-powered commit messages${Color_Off} via OpenAI GPT"
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
  echo -e "  Configuration loaded from ${BCyan}.env${Color_Off} files in current directory."
  echo -e "  ${Gray}Most settings are optional with sensible defaults!${Color_Off}\n"

  echo -e "${BGreen}Ready to get started? Just run:${Color_Off} ${BCyan}maiass${Color_Off}"
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



      echo "MAIASS v$version"
      exit 0
      ;;
    -ai|--ai-only)
      run_ai_commit_only
      exit 0
      ;;
  esac
done

# Check for env var override
if [[ "$MAIASS_MODE" == "ai_only" ]]; then
  run_ai_commit_only
  exit 0
fi


[[ "${BASH_SOURCE[0]}" == "${0}" ]] && initialiseBump "$@"
