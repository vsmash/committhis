

# Error handling for git operations
function check_git_success() {
    if [ $? -ne 0 ]; then
        print_error "Git operation failed"
        print_error "Please complete this process manually"
        print_info "You are currently on branch: $(git rev-parse --abbrev-ref HEAD)"
        exit 1
    fi
}


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

        logthis "Created pull request for ${newversion:-merge}"
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
        logthis "Merged $source_branch into $target_branch"
    fi
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



function branchDetection() {
    print_section "Branch Detection"
    echo -e "Currently on branch: ${BWhite}$branch_name${Color_Off}"
    # if we are on the master branch, advise user not to use this script for hot fixes
    # if on master or a release branch, advise the user
    if [[ "$branch_name" == "$masterbranch" || "$branch_name" == release/* || "$branch_name" == releases/* ]]; then
        print_warning "You are currently on the $branch_name branch"
        read -n 1 -s -p "$(echo -e ${BYellow}Do you want to continue on $developbranch? [y/N]${Color_Off} )" REPLY
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Operation cancelled by user"
            exit 1
        fi
    fi
    # if branch starts with release/ or releases/ offer do same as masterbranch



    # if we are on the master or staging branch, switch to develop
    if [ "$branch_name" == "$masterbranch" ] || [ "$branch_name" == "$stagingbranch" ]; then
        print_info "Switching to $developbranch branch..."
        git checkout "$developbranch"
        check_git_success
        branch_name="$developbranch"
        print_success "Switched to $developbranch branch"

    fi
}

