


function get_ai_commit_message_style() {

  # Determine the OpenAI commit message style
  if [[ -n "$MAIASS_AI_COMMIT_MESSAGE_STYLE" ]]; then
    ai_commit_style="$MAIASS_AI_COMMIT_MESSAGE_STYLE"
    print_info "Using AI commit style from .env: $ai_commit_style" >&2
  elif [[ -f ".maiass.prompt" ]]; then
    ai_commit_style="custom"
    print_info "No style set in .env; using local prompt file: .maiass.prompt" >&2
  elif [[ -f "$HOME/.maiass.prompt" ]]; then
    ai_commit_style="global_custom"
    print_info "No style set in .env; using global prompt file: ~/.maiass.prompt" >&2
  else
    ai_commit_style="bullet"
    print_info "No style or prompt files found; defaulting to 'bullet'" >&2
  fi
  export ai_commit_style
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
  # For backward compatibility, treat debug_mode=true as verbosity_level=debug
  if [[ "$debug_mode" == "true" && "$verbosity_level" != "debug" ]]; then
    # Only log this when not already in debug verbosity to avoid noise
    log_message "DEPRECATED: Using debug_mode=true is deprecated. Please use MAIASS_VERBOSITY=debug instead."
    print_info "DEBUG: AI function called with debug_mode=$debug_mode (deprecated, use MAIASS_VERBOSITY=debug instead)" "debug" >&2
    print_info "DEBUG: MAIASS_DEBUG=$MAIASS_DEBUG" "debug" >&2
  elif [[ "$verbosity_level" == "debug" ]]; then
    print_info "DEBUG: AI function called with verbosity_level=$verbosity_level" "debug" >&2
  fi

  # Get git diff for context
  git_diff=$(git diff --cached --no-color 2>/dev/null || git diff --no-color 2>/dev/null || echo "No changes detected")
  git_diff=$(echo "$git_diff" | tr -cd '\11\12\15\40-\176')
  print_debug "DEBUG: Git diff length: ${#git_diff} characters" >&2

  # Truncate diff if too long (API has token limits)
  if [[ ${#git_diff} -gt $ai_max_characters ]]; then
    git_diff="${git_diff:0:$ai_max_characters}...[truncated]"
    print_debug "DEBUG: Git diff truncated to $ai_max_characters characters" >&2
  fi
    print_info "DEBUG: prompt mode: $ai_commit_style" >&2
  get_ai_commit_message_style
  # Create AI prompt based on commit style
  case "$ai_commit_style" in
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
    print_warning "Unknown commit message style: '$ai_commit_style'. Skipping AI suggestion." >&2
    ai_prompt="${bullet_prompt//\$git_diff/$git_diff}"
    ;;
esac


  # Call OpenAI API
  print_debug "DEBUG: Calling OpenAI API with model: $ai_model" >&2
  print_debug "DEBUG: AI prompt style: $ai_commit_style" >&2
  print_debug "AI temperature: $ai_temperature"  >&2

  # Build JSON payload using jq if available (handles escaping automatically)
  local json_payload
  if command -v jq >/dev/null 2>&1; then
    json_payload=$(jq -n --arg model "$ai_model" --argjson temperature "$ai_temperature" --arg prompt "$ai_prompt" '{
      "model": $model,
      "messages": [
        {"role": "system", "content": "You are a helpful assistant that writes concise, descriptive git commit messages based on code changes."},
        {"role": "user", "content": $prompt}
      ],
      "max_tokens": 150,
      "temperature": $temperature
    }')
  else
    # Simple fallback - replace quotes and newlines only
    local safe_prompt
    safe_prompt=$(printf '%s' "$ai_prompt" | sed 's/"/\\"/g' | tr '\n' ' ')
    json_payload='{"model":"'$ai_model'","messages":[{"role":"system","content":"You are a helpful assistant that writes concise, descriptive git commit messages based on code changes."},{"role":"user","content":"'$safe_prompt'"}],"max_tokens":150,"temperature":'$ai_temperature'}'
  fi

  print_debug "DEBUG: JSON payload length: ${#json_payload} characters" >&2
  print_debug "DEBUG: endpoint: ${maiass_endpoint}" >&2
  api_response=$(curl -s -X POST "$maiass_endpoint" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ai_token" \
    -d "$json_payload" 2>/dev/null)

  print_debug "DEBUG: API response length: ${#api_response} characters" >&2
  # mask the api token


  print_debug "DEBUG: API token: $(mask_api_key "${ai_token}") " >&2

  print_debug "DEBUG: API response : ${api_response} " >&2
  # Extract the suggested message from API response
  if [[ -n "$api_response" ]]; then
    # Check for API error first
    if echo "$api_response" | grep -q '"error"'; then
      error_msg=$(echo "$api_response" | grep -o '"message":"[^"]*"' | sed 's/"message":"//' | sed 's/"$//' | head -1)
      print_warning "API Error: $error_msg"
      print_debug "DEBUG: Full error response: $api_response" >&2
      return 1
    fi

    print_debug "DEBUG: Attempting to parse JSON response" >&2

    # Try jq first if available (most reliable)
    if command -v jq >/dev/null 2>&1; then
      print_debug "DEBUG: Using jq for JSON parsing" >&2
      suggested_message=$(echo "$api_response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
      print_debug "DEBUG: jq result: '$suggested_message'" >&2

      # Extract token usage information if available
      local prompt_tokens completion_tokens total_tokens
      prompt_tokens=$(echo "$api_response" | jq -r '.usage.prompt_tokens // empty' 2>/dev/null)
      completion_tokens=$(echo "$api_response" | jq -r '.usage.completion_tokens // empty' 2>/dev/null)
      total_tokens=$(echo "$api_response" | jq -r '.usage.total_tokens // empty' 2>/dev/null)

       print_always "Total Tokens : ${total_tokens} " >&2
      # Display token usage if available (always show regardless of verbosity)
    fi

    # Fallback to sed parsing if jq not available or failed
    if [[ -z "$suggested_message" ]]; then
      print_debug "DEBUG: jq failed, trying sed parsing" >&2
      # Handle the actual AI response structure with nested objects
      suggested_message=$(echo "$api_response" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p' | tail -1)
      print_debug "DEBUG: sed result: '$suggested_message'"
    fi

    # Last resort: simple grep approach
    if [[ -z "$suggested_message" ]]; then
      print_debug "DEBUG: sed failed, trying grep approach"
      suggested_message=$(echo "$api_response" | grep -o '"content":"[^"]*"' | sed 's/"content":"//' | sed 's/"$//' | tail -1)
      print_debug "DEBUG: grep result: '$suggested_message'"
    fi

    # Show raw API response if debug mode and parsing failed
    if [[ "$debug_mode" == "true" && -z "$suggested_message" ]]; then
      print_debug "All parsing methods failed. Raw API response:"
      if [[ ${#api_response} -lt 1000 ]]; then
        print_debug "$api_response"
      else
        print_debug "${api_response:0:1000}...[truncated]"
      fi
    fi

    # Clean up escaped characters and markdown formatting
    suggested_message=$(echo "$suggested_message" | sed 's/\\n/\n/g' | sed 's/\\t/\t/g' | sed 's/\\\\/\\/g')

    # Remove markdown code blocks (triple backticks)
    suggested_message=$(echo "$suggested_message" | sed '/^```/d')

    # Clean up the message (remove leading/trailing whitespace)
    suggested_message=$(echo "$suggested_message" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

    print_debug "DEBUG: Final cleaned message: '$suggested_message'" >&2

    if [[ -n "$suggested_message" && "$suggested_message" != "null" ]]; then
      echo "$suggested_message"
      return 0
    else
      print_debug "DEBUG: No valid message extracted (empty or null)"
    fi
  else
    print_debug "DEBUG: Empty API response"
  fi

  # Return empty if AI suggestion failed
  return 1
}

