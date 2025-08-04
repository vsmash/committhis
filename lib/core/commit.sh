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
  print_debug "DEBUG: ai_mode='$ai_mode', ai_token length=${#ai_token}"

  case "$ai_mode" in
    "ask")
      print_debug "DEBUG: AI mode is 'ask'"
      if [[ -n "$ai_token" ]]; then
        print_debug "DEBUG: Token available, showing AI prompt"
        read -n 1 -s -p "$(echo -e ${BYellow}Would you like to use AI to suggest a commit message? [y/N]${Color_Off} )" REPLY
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          print_debug "DEBUG: User chose to use AI"
          use_ai=true
        else
          print_debug "DEBUG: User declined AI (reply='$REPLY')"
        fi
      else
        print_debug "DEBUG: No token available for AI"
      fi
      ;;
    "autosuggest")
      print_debug "DEBUG: AI mode is 'autosuggest'"
      if [[ -n "$ai_token" ]]; then
        use_ai=true
      fi
      ;;
    "off"|*)
      print_debug "DEBUG: AI mode is 'off' or unknown: '$ai_mode'"
      use_ai=false
      ;;
  esac

  print_debug "DEBUG: use_ai=$use_ai"

  # Try to get AI suggestion if requested
  if [[ "$use_ai" == true ]]; then
    print_info "Getting AI commit message suggestion..." "brief"
    
    if ai_suggestion=$(get_ai_commit_suggestion); then
      # Success - we got a valid AI suggestion
      print_success "AI suggested commit message:"
      # Only remove carriage returns, quotes are already handled in the AI function
      ai_suggestion="$(echo "$ai_suggestion" | sed 's/\r$//')"
      if [[ -n "$total_tokens" && "$total_tokens" != "null" && "$total_tokens" != "empty" ]]; then
        print_always "Token usage: ${total_tokens} total (${prompt_tokens:-0} prompt + ${completion_tokens:-0} completion)"
      fi

      echo -e "${BNavy}${BWhiteBG}$ai_suggestion${Color_Off}"
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
            # Subsequent lines are body - add with tab indent and single newline
            commit_message+="    $line"$'\n'

        fi
    done
    # Remove one trailing newline if present:
    commit_message="${commit_message%$'\n'}"
  fi
  internal_commit_message="[$(git config user.name)] $commit_message"
  # Prepend Jira ticket number if found and not already present
  if [[ -n "$jira_ticket_number" && ! "$commit_message" =~ ^$jira_ticket_number ]]; then
    commit_message="$jira_ticket_number $commit_message"
    internal_commit_message="$jira_ticket_number $internal_commit_message"
  fi
  # prepend with author of commit
  # Abort if the commit message is still empty
  if [[ -z "$commit_message" ]]; then
      echo "Aborting commit due to empty commit message."
      exit 1
  fi

  # Export the commit message and jira ticket number for use by calling function
  export internal_commit_message
  export commit_message
  export jira_ticket_number
}

run_ai_commit_only() {
  echo "this feature is not yet supported"
}



handle_staged_commit() {
          print_info "Staged changes detected:"
          git diff --cached --name-status

          get_commit_message
          # Use git commit -F - to properly handle multi-line commit messages

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
            echo "$commit_message" | git commit -F -
          else
            echo "$commit_message" | git commit -F - >/dev/null 2>&1
          fi


          check_git_success
          tagmessage=$commit_message
          export tagmessage
          print_success "Changes committed successfully"
          # Sanitize commit message for CSV/Google Sheets compatibility
          # Replace all newlines with semicolons and a space
          local devlog_message="${commit_message//$'\n'/; }"

          # Escape double quotes if needed
          devlog_message="${devlog_message//\"/\\\"}"
          logthis "${commit_message//$'\n'/; }"
          if remote_exists "origin"; then
            # y to push upstream
            read -n 1 -s -p "$(echo -e ${BYellow}Do you want to push this commit to remote? [y/N]${Color_Off} )" REPLY
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
              run_git_command "git push --set-upstream origin '$branch_name'" "debug"
              check_git_success
              echo -e "${BGreen}Commit pushed.${Color_Off}"
            fi
          else
            print_warning "No remote found."
          fi
}


offer_to_stage_changes() {
  print_warning "No staged changes found, but there are uncommitted changes."
  read -n 1 -s -p "$(echo -e ${BYellow}Do you want to stage all changes and commit? [y/N]${Color_Off} )" REPLY
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    git add -A
    handle_staged_commit
  else
    print_error "Aborting. No staged changes to commit."
    exit 1
  fi
}

check_git_commit_status() {
  print_section "Checking Git Status"
  if has_staged_changes; then
    handle_staged_commit
  elif has_uncommitted_changes; then
    offer_to_stage_changes
  else
    echo -e "${BGreen}Nothing to commit. Working directory clean.${Color_Off}"
    exit 0
  fi
}
# Check for uncommitted changes and offer to commit them
function checkUncommittedChanges(){
  print_section "Checking for Changes"
  # if there are uncommitted changes, ask if the user wants to commit them
  if [ -n "$(git status --porcelain)" ]; then
      print_warning "There are uncommitted changes in your working directory"
      read -n 1 -s -p "$(echo -e ${BYellow}Do you want to ${BRed}stage and commit${BYellow} them? [y/N]${Color_Off} )" REPLY
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
          git add -A
          handle_staged_commit
          # set upstream
      else
            if has_staged_changes; then
              handle_staged_commit
            fi
          if [[ $ai_commits_only == 'true' ]]; then
            echo -e "${BGreen}Commit process completed. Thank you for using $brand.${Color_Off}"
            exit 0
          else
            print_success "Commit process completed."
            print_error "Cannot proceed on release/changelog pipeline with uncommitted changes"
            print_success "Thank you for using $brand."
            exit 1
          fi
      fi
  else
    if has_staged_changes; then
      handle_staged_commit
    fi
    if [[ $ai_commits_only == 'true' ]]; then
      echo -e "${BGreen}No changes found. Thank you for using $brand.${Color_Off}"
      exit 0
    fi
  fi
}
