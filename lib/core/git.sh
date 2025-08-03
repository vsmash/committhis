

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

has_staged_changes() {
  [ -n "$(git diff --cached)" ]
}




has_uncommitted_changes() {
  [ -n "$(git status --porcelain)" ]
}




function changeManagement(){
  checkUncommittedChanges
}

function mergeDevelop() {
  local has_version_files="${1:-true}"  # Default to true for backward compatibility
  shift  # Remove the first argument so remaining args can be passed to getVersion

  print_section "Git Workflow"

  # Check for uncommitted changes first
  if has_uncommitted_changes; then
    print_warning "You have uncommitted changes."
    read -n 1 -s -p "$(echo -e ${BYellow}Do you want to commit them now? [y/N]${Color_Off} )" REPLY
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      handle_staged_commit
      # Check again if there are still uncommitted changes
      if has_uncommitted_changes; then
        print_error "Still have uncommitted changes. Please commit or stash them first."
        exit 1
      fi
    else
      print_error "Cannot proceed with uncommitted changes. Please commit or stash them first."
      exit 1
    fi
  fi

  # Get current branch name
  local current_branch=$(git rev-parse --abbrev-ref HEAD)

  # Check if we're already on develop or need to merge
  if [ "$current_branch" != "$developbranch" ]; then
    print_info "Not on $developbranch branch (currently on $current_branch)"
    read -n 1 -s -p "$(echo -e ${BYellow}Do you want to merge $current_branch into $developbranch? [y/N]${Color_Off} )" REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      print_error "Cannot proceed without merging into $developbranch"
      exit 1
    fi

    # Checkout develop and update it
    git checkout "$developbranch"
    check_git_success

    # Pull latest changes
    if remote_exists "origin"; then
      print_info "Pulling latest changes from $developbranch..."
      git pull origin "$developbranch"
      check_git_success
    fi

    # Merge the branch
    git merge --no-ff -m "Merge $current_branch into $developbranch" "$current_branch"
    check_git_success
    logthis "Merged $current_branch into $developbranch"
  else
    # On develop, just pull latest
    if remote_exists "origin"; then
      print_info "Pulling latest changes from $developbranch..."
      git pull origin "$developbranch"
      check_git_success
    fi
  fi

  # Only proceed with version management if version files exist and we're on develop
  if [[ "$has_version_files" == "true" && "$(git rev-parse --abbrev-ref HEAD)" == "$developbranch" ]]; then
    # Get the version bump type (major, minor, patch)
    local bump_type="${1:-patch}"  # Default to patch if not specified
    shift

    # Bump the version
    getVersion "$bump_type"

    # Determine if we should create a release branch and tag
    local create_release=true
    if [ "$bump_type" == "patch" ]; then
      read -n 1 -s -p "$(echo -e ${BYellow}This is a patch version. Create a release branch and tag? [y/N]${Color_Off} )" REPLY
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_release=true
      else
        create_release=false
      fi
    fi

    if [ "$create_release" == true ]; then
      # Create release branch
      git checkout -b "release/$newversion"
      check_git_success

      # Update version and changelog
      bumpVersion
      updateChangelog "$changelog_path"

      # Commit changes
      git add -A
      git commit -m "Bumped version to $newversion"
      check_git_success

      # Create tag
      if ! git tag -l "$newversion" | grep -q "^$newversion$"; then
        git tag -a "$newversion" -m "Release version $newversion"
        check_git_success
        print_success "Created release tag $newversion"
      else
        print_warning "Tag $newversion already exists"
      fi

      # Push the release branch and tag if remote exists
      if remote_exists "origin"; then
        git push -u origin "release/$newversion"
        git push origin "$newversion"
      fi

      # Go back to develop
      git checkout "$developbranch"
      check_git_success

      # Merge release branch into develop
      git merge --no-ff -m "Merge release/$newversion into $developbranch" "release/$newversion"
      check_git_success

      print_success "Merged release/$newversion into $developbranch"
      # Push develop
      if remote_exists "origin"; then
        git push origin "$developbranch"
      fi

      check_git_success
    else
      # For patch versions without release branch, update directly on develop
      print_info "Updating version and changelog directly on $developbranch..."
      bumpVersion
      updateChangelog "$changelog_path"

      # Commit changes
      git add -A
      git commit -m "Bump version to $newversion (no release)"
      check_git_success

      # Push changes if remote exists
      if remote_exists "origin"; then
        git push origin "$developbranch"
      fi

      print_success "Version updated to $newversion on $developbranch"
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


# function to show deploy options
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
  print_success "Thank you for using $brand."

  # Clean up
  unset GIT_MERGE_AUTOEDIT
  unset tagmessage
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
