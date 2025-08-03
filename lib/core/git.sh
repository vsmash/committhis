
# Execute git command with verbosity-controlled output
# Usage: run_git_command "git command" [show_output_level]
# show_output_level: brief, normal, debug (default: normal)
run_git_command() {
    local git_cmd="$1"
    local show_level="${2:-normal}"

    # For backward compatibility, treat debug_mode=true as verbosity_level=debug
    if [[ "$debug_mode" == "true" && "$verbosity_level" != "debug" ]]; then
        # Only log this when not already in debug verbosity to avoid noise
        log_message "DEPRECATED: Using debug_mode=true is deprecated. Please use MAIASS_VERBOSITY=debug instead."
        # Treat as if verbosity_level is debug
        local effective_verbosity="debug"
    else
        local effective_verbosity="$verbosity_level"
    fi

    # Control output based on verbosity level
    case "$effective_verbosity" in
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
