


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

# Function to handle invalid API key errors with user options
function handle_invalid_api_key_error() {
  echo ""
  print_warning "❌ Invalid API Key" >&2
  echo ""
  print_info "Your MAIASS AI token is invalid or has expired." >&2
  
  # Check if we should automatically create anonymous subscription
  if [[ "$ai_invalid_token_choices" == "false" ]]; then
    # Check if we already tried to create anonymous subscription this session
    if [[ "$_MAIASS_ANON_ATTEMPTED" == "true" ]]; then
      print_warning "Anonymous subscription already attempted this session. Continuing without AI assistance." >&2
      export ai_mode="off"
      return 1
    fi
    
    print_info "Automatically creating anonymous subscription..." >&2
    export _MAIASS_ANON_ATTEMPTED="true"
    
    if create_anonymous_subscription; then
      print_info "Retrying AI commit message generation..." >&2
      echo ""
      # Return success to indicate retry should happen in calling context
      return 0
    else
      print_warning "Failed to create anonymous subscription. Continuing without AI assistance." >&2
      export ai_mode="off"
      return 1
    fi
  fi
  
  print_info "You have the following options:" >&2
  echo ""
  print_info "  ${BCyan}1.${Color_Off} Enter a new AI token" >&2
  print_info "  ${BCyan}2.${Color_Off} Continue without AI and enter commit message manually ${BYellow}[Default]${Color_Off}" >&2  
  print_info "  ${BCyan}3.${Color_Off} Get a new anonymous token (no email required)" >&2
  print_info "  ${BCyan}4.${Color_Off} Exit and configure token later" >&2
  echo ""
  print_info "💡 To get a token:" >&2
  print_info "   • Email signup: ${BBlue}https://pound.maiass.net/signup${Color_Off} (free trial)" >&2
  print_info "   • Anonymous: Option 3 above (machine fingerprint-based)" >&2
  echo ""
  
  # Only prompt if in interactive mode
  if [[ -t 0 ]]; then
    print_info "Please choose an option (1-4) [2]: " >&2
    read -r user_choice
    
    case "${user_choice:-2}" in
      1)
        echo ""
        print_info "Please enter your new AI token (input will be hidden): " >&2
        if read -s new_token; then
          if [[ -n "$new_token" && "$new_token" != "DISABLED" ]]; then
            # Store the new token securely
            if [[ "$OSTYPE" == "darwin"* ]]; then
              security add-generic-password -a "MAIASS_AI_TOKEN" -s "maiass" -w "$new_token" -U 2>/dev/null
            elif command -v secret-tool >/dev/null 2>&1; then
              echo -n "$new_token" | secret-tool store --label="MAIASS AI Token" service maiass key "MAIASS_AI_TOKEN"
            fi
            
            export MAIASS_AI_TOKEN="$new_token"
            export ai_token="$new_token"
            print_success "✅ New AI token stored successfully." >&2
            print_info "Retrying AI commit message generation..." >&2
            echo ""
            
            # Return success to indicate retry should happen in calling context
            return 0
          else
            print_warning "No valid token provided. Continuing without AI assistance." >&2
          fi
        else
          print_warning "Failed to read token. Continuing without AI assistance." >&2
        fi
        ;;
      2)
        print_info "Continuing without AI assistance. You'll be prompted to enter your commit message manually." >&2
        ;;
      3)
        echo ""
        print_info "Creating anonymous subscription..." >&2
        if create_anonymous_subscription; then
          print_info "Retrying AI commit message generation..." >&2
          echo ""
          # Return success to indicate retry should happen in calling context
          return 0
        else
          print_warning "Failed to create anonymous subscription. Continuing without AI assistance." >&2
        fi
        ;;
      4)
        print_info "Exiting. Configure your AI token with: export MAIASS_AI_TOKEN=\"your_token_here\"" >&2
        exit 1
        ;;
      *)
        print_warning "Invalid option. Continuing without AI assistance." >&2
        ;;
    esac
  else
    print_info "Non-interactive mode detected. Continuing without AI assistance." >&2
  fi
  
  # Set AI mode to off for this session to avoid repeated prompts
  export ai_mode="off"
}

# Function to create an anonymous subscription using machine fingerprint
function create_anonymous_subscription() {
  local machine_fingerprint
  local api_response
  local new_api_key
  local credits
  local top_up_url
  
  print_debug "DEBUG: ========== ANONYMOUS SUBSCRIPTION START ==========" >&2
  print_info "Generating machine fingerprint..." >&2
  
  # Generate machine fingerprint (use existing function from utils.sh)
  if command -v generate_machine_fingerprint >/dev/null 2>&1; then
    print_debug "DEBUG: Using generate_machine_fingerprint function" >&2
    machine_fingerprint=$(generate_machine_fingerprint)
  else
    print_debug "DEBUG: Using fallback machine fingerprint generation" >&2
    # Fallback fingerprint generation
    machine_fingerprint=$(echo -n "$(uname -a)-$(whoami)-$(date +%Y%m)" | shasum -a 256 | cut -d' ' -f1)
    print_debug "DEBUG: Using fallback machine fingerprint: ${machine_fingerprint:0:10}..." >&2
  fi
  
  if [[ -z "$machine_fingerprint" ]]; then
    print_warning "Failed to generate machine fingerprint." >&2
    return 1
  fi
  
  print_debug "DEBUG: Machine fingerprint: ${machine_fingerprint:0:10}..." >&2
  
  # Create JSON payload for anonymous subscription
  local json_payload
  if command -v jq >/dev/null 2>&1; then
    print_debug "DEBUG: Creating JSON payload with jq" >&2
    json_payload=$(jq -n --arg fingerprint "$machine_fingerprint" '{
      "machine_fingerprint": $fingerprint
    }')
  else
    print_debug "DEBUG: Creating JSON payload manually" >&2
    json_payload="{\"machine_fingerprint\":\"$machine_fingerprint\"}"
  fi
  
  print_debug "DEBUG: JSON payload: $json_payload" >&2
  print_info "Requesting anonymous subscription..." >&2
  
  # Call the anonymous subscription endpoint
  print_debug "DEBUG: Calling ${maiass_tokenrequest}" >&2
  api_response=$(curl -s -X POST "${maiass_tokenrequest}" \
    -H "Content-Type: application/json" \
    -d "$json_payload" 2>/dev/null)
  
  print_debug "DEBUG: Anonymous subscription response: $api_response" >&2
  
  if [[ -n "$api_response" ]]; then
    # Check for errors
    if echo "$api_response" | grep -q '"error"'; then
      local error_msg
      error_msg=$(echo "$api_response" | grep -o '"error":"[^"]*"' | sed 's/"error":"//' | sed 's/"$//' | head -1)
      print_warning "Failed to create anonymous subscription: $error_msg" >&2
      return 1
    fi
    
    # Extract the API key and other details
    if command -v jq >/dev/null 2>&1; then
      new_api_key=$(echo "$api_response" | jq -r '.token // .api_key // empty' 2>/dev/null)
      local subscription_id=$(echo "$api_response" | jq -r '.subscription_id // empty' 2>/dev/null)
      credits=$(echo "$api_response" | jq -r '.credits_remaining // .credits // empty' 2>/dev/null)
      top_up_url=$(echo "$api_response" | jq -r '.payment_url // .top_up_url // empty' 2>/dev/null)
    else
      new_api_key=$(echo "$api_response" | grep -o '"token":"[^"]*"' | sed 's/"token":"//' | sed 's/"$//' | head -1)
      if [[ -z "$new_api_key" ]]; then
        new_api_key=$(echo "$api_response" | grep -o '"api_key":"[^"]*"' | sed 's/"api_key":"//' | sed 's/"$//' | head -1)
      fi
      local subscription_id=$(echo "$api_response" | grep -o '"subscription_id":"[^"]*"' | sed 's/"subscription_id":"//' | sed 's/"$//' | head -1)
      credits=$(echo "$api_response" | grep -o '"credits_remaining":[0-9]*' | sed 's/"credits_remaining"://' | head -1)
      if [[ -z "$credits" ]]; then
        credits=$(echo "$api_response" | grep -o '"credits":[0-9]*' | sed 's/"credits"://' | head -1)
      fi
      top_up_url=$(echo "$api_response" | grep -o '"payment_url":"[^"]*"' | sed 's/"payment_url":"//' | sed 's/"$//' | head -1)
      if [[ -z "$top_up_url" ]]; then
        top_up_url=$(echo "$api_response" | grep -o '"top_up_url":"[^"]*"' | sed 's/"top_up_url":"//' | sed 's/"$//' | head -1)
      fi
    fi
    
    if [[ -n "$new_api_key" && "$new_api_key" != "null" ]]; then
      print_success "✅ Anonymous subscription created successfully!" >&2
      print_info "   API Key: $(mask_api_key "$new_api_key")" >&2
      print_info "   Credits: ${credits:-N/A}" >&2
      
      if [[ -n "$subscription_id" && "$subscription_id" != "null" ]]; then
        print_info "   Subscription ID: ${subscription_id:0:12}..." >&2
      fi
      
      if [[ -n "$top_up_url" && "$top_up_url" != "null" ]]; then
        print_info "   📱 Top-up URL: ${top_up_url:0:50}..." >&2
        print_info "   💡 Save this URL to add more credits later!" >&2
      fi
      
      # Store the token, subscription ID, and top-up URL securely
      if [[ "$OSTYPE" == "darwin"* ]]; then
        security add-generic-password -a "MAIASS_AI_TOKEN" -s "maiass" -w "$new_api_key" -U 2>/dev/null
        if [[ -n "$subscription_id" && "$subscription_id" != "null" ]]; then
          security add-generic-password -a "MAIASS_SUBSCRIPTION_ID" -s "maiass" -w "$subscription_id" -U 2>/dev/null
        fi
        if [[ -n "$top_up_url" && "$top_up_url" != "null" ]]; then
          security add-generic-password -a "MAIASS_TOPUP_URL" -s "maiass" -w "$top_up_url" -U 2>/dev/null
        fi
      elif command -v secret-tool >/dev/null 2>&1; then
        echo -n "$new_api_key" | secret-tool store --label="MAIASS AI Token" service maiass key "MAIASS_AI_TOKEN"
        if [[ -n "$subscription_id" && "$subscription_id" != "null" ]]; then
          echo -n "$subscription_id" | secret-tool store --label="MAIASS Subscription ID" service maiass key "MAIASS_SUBSCRIPTION_ID"
        fi
        if [[ -n "$top_up_url" && "$top_up_url" != "null" ]]; then
          echo -n "$top_up_url" | secret-tool store --label="MAIASS Top-up URL" service maiass key "MAIASS_TOPUP_URL"
        fi
      fi
      
      export MAIASS_AI_TOKEN="$new_api_key"
      export ai_token="$new_api_key"
      if [[ -n "$subscription_id" && "$subscription_id" != "null" ]]; then
        export MAIASS_SUBSCRIPTION_ID="$subscription_id"
      fi
      
      echo ""
      return 0
    else
      print_warning "Failed to extract API key from response." >&2
      return 1
    fi
  else
    print_warning "No response from anonymous subscription service." >&2
    return 1
  fi
}

# Function to handle quota exceeded errors
function handle_quota_exceeded_error() {
  local error_msg="$1"
  local payment_url="$2"
  local credits_remaining="$3"
  
  echo ""
  print_warning "💳 Quota Exceeded" >&2
  echo ""
  print_info "Your AI token quota has been exceeded." >&2
  if [[ -n "$error_msg" ]]; then
    print_info "Details: $error_msg" >&2
  fi
  if [[ -n "$credits_remaining" && "$credits_remaining" != "null" ]]; then
    print_info "Credits remaining: $credits_remaining" >&2
  fi
  echo ""
  print_info "You have the following options:" >&2
  echo ""
  print_info "  ${BCyan}1.${Color_Off} Continue without AI and enter commit message manually ${BYellow}[Default]${Color_Off}" >&2
  print_info "  ${BCyan}2.${Color_Off} Get a new anonymous token (fresh quota)" >&2
  print_info "  ${BCyan}3.${Color_Off} Enter a different AI token" >&2
  print_info "  ${BCyan}4.${Color_Off} Exit and manage your subscription" >&2
  echo ""
  print_info "💡 To manage your quota:" >&2
  
  # Use payment URL from proxy response if available, otherwise use stored subscription ID or fallback
  if [[ -n "$payment_url" && "$payment_url" != "null" ]]; then
    print_info "   • Add credits: ${BBlue}$payment_url${Color_Off}" >&2
  elif [[ -n "$MAIASS_SUBSCRIPTION_ID" ]]; then
    print_info "   • Add credits: ${BBlue}https://maiass.net/topup?sub=$MAIASS_SUBSCRIPTION_ID${Color_Off}" >&2
  else
    print_info "   • Visit: ${BBlue}https://pound.maiass.net/signup${Color_Off} for subscription options" >&2
  fi
  print_info "   • Anonymous tokens come with limited credits" >&2
  echo ""
  
  # Only prompt if in interactive mode
  if [[ -t 0 ]]; then
    print_info "Please choose an option (1-4) [1]: " >&2
    read -r user_choice
    
    case "${user_choice:-1}" in
      1)
        print_info "Continuing without AI assistance. You'll be prompted to enter your commit message manually." >&2
        ;;
      2)
        echo ""
        print_info "Creating new anonymous subscription..." >&2
        if create_anonymous_subscription; then
          print_info "Retrying AI commit message generation..." >&2
          echo ""
          # Return success to indicate retry should happen in calling context
          return 0
        else
          print_warning "Failed to create anonymous subscription. Continuing without AI assistance." >&2
        fi
        ;;
      3)
        echo ""
        print_info "Please enter your new AI token (input will be hidden): " >&2
        if read -s new_token; then
          if [[ -n "$new_token" && "$new_token" != "DISABLED" ]]; then
            # Store the new token securely
            if [[ "$OSTYPE" == "darwin"* ]]; then
              security add-generic-password -a "MAIASS_AI_TOKEN" -s "maiass" -w "$new_token" -U 2>/dev/null
            elif command -v secret-tool >/dev/null 2>&1; then
              echo -n "$new_token" | secret-tool store --label="MAIASS AI Token" service maiass key "MAIASS_AI_TOKEN"
            fi
            
            export MAIASS_AI_TOKEN="$new_token"
            export ai_token="$new_token"
            print_success "✅ New AI token stored successfully." >&2
            print_info "Retrying AI commit message generation..." >&2
            echo ""
            
            # Return success to indicate retry should happen in calling context
            return 0
          else
            print_warning "No valid token provided. Continuing without AI assistance." >&2
          fi
        else
          print_warning "Failed to read token. Continuing without AI assistance." >&2
        fi
        ;;
      4)
        print_info "Exiting. Visit https://pound.maiass.net to manage your subscription." >&2
        exit 1
        ;;
      *)
        print_warning "Invalid option. Continuing without AI assistance." >&2
        ;;
    esac
  else
    print_info "Non-interactive mode detected. Continuing without AI assistance." >&2
  fi
  
  # Set AI mode to off for this session to avoid repeated prompts
  export ai_mode="off"
}

# Function to get AI-generated commit message suggestion
function get_ai_commit_suggestion() {
  local git_diff
  local ai_prompt
  local api_response
  local suggested_message
  local retry_count=0
  local max_retries=2

  # Check if we need to create an anonymous token (set by envars.sh)
  if [[ "$_MAIASS_NEED_ANON_TOKEN" == "true" ]]; then
    print_debug "DEBUG: Anonymous token creation requested from environment loading" >&2
    
    # Clear the flag to prevent repeated attempts
    export _MAIASS_NEED_ANON_TOKEN=""
    
    if create_anonymous_subscription; then
      print_info "Anonymous subscription created successfully. Proceeding with AI commit suggestion..." >&2
      # Token should now be set, continue with normal flow
    else
      print_warning "Failed to create anonymous subscription. AI features will be disabled." >&2
      return 1
    fi
  fi

  # Main retry loop for handling authentication errors
  while [[ $retry_count -lt $max_retries ]]; do
    retry_count=$((retry_count + 1))
    print_debug "DEBUG: AI suggestion attempt $retry_count/$max_retries" >&2
    
    # Reset suggested_message for each attempt
    suggested_message=""
    
    if _make_ai_api_call; then
      # Success - return the result
      return 0
    else
      local exit_code=$?
      if [[ $exit_code -eq 2 && $retry_count -lt $max_retries ]]; then
        # Exit code 2 indicates retry should happen (new credentials available)
        print_debug "DEBUG: Retrying API call with new credentials..." >&2
        continue
      else
        # Real failure or max retries reached
        return 1
      fi
    fi
  done
  
  # If we get here, we've exhausted retries
  return 1
}

# Internal function to make the actual API call
function _make_ai_api_call() {
  local git_diff
  local ai_prompt
  local api_response
  local suggested_message

bullet_prompt="Analyze the following git diff and create a commit message with bullet points. Format as:
'Brief summary title
  - feat: add user authentication
  - fix(api): resolve syntax error
  - docs: update README'

Use past tense verbs. No blank line between title and bullets. Keep concise. Do not wrap the response in quotes.

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
    print_debug "DEBUG: AI function called with debug_mode=$debug_mode (deprecated, use MAIASS_VERBOSITY=debug instead)" "debug" >&2
    print_debug "DEBUG: MAIASS_DEBUG=$MAIASS_DEBUG" "debug" >&2
  elif [[ "$verbosity_level" == "debug" ]]; then
    print_debug "DEBUG: AI function called with verbosity_level=$verbosity_level" "debug" >&2
  fi

  # Debug: Show current AI configuration
  print_debug "DEBUG: ========== AI COMMIT SUGGESTION START ==========" >&2
  print_debug "DEBUG: ai_mode=$ai_mode" >&2
  print_debug "DEBUG: ai_token=${ai_token:0:10}${ai_token:+...}" >&2
  print_debug "DEBUG: maiass_host=$maiass_host" >&2
  print_debug "DEBUG: maiass_endpoint=$maiass_endpoint" >&2
  print_debug "DEBUG: ai_model=$ai_model" >&2
  print_debug "DEBUG: ai_temperature=$ai_temperature" >&2

  # Get git diff for context
  git_diff=$(git diff --cached --no-color 2>/dev/null || git diff --no-color 2>/dev/null || echo "No changes detected")
  git_diff=$(echo "$git_diff" | tr -cd '\11\12\15\40-\176')
  print_debug "DEBUG: Git diff length: ${#git_diff} characters" >&2

  # Truncate diff if too long (API has token limits)
  if [[ ${#git_diff} -gt $ai_max_characters ]]; then
    git_diff="${git_diff:0:$ai_max_characters}...[truncated]"
    print_debug "DEBUG: Git diff truncated to $ai_max_characters characters" >&2
  fi
    print_debug "DEBUG: prompt mode: $ai_commit_style" >&2
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
        print_warning "$HOME/.maiass.prompt is missing or does not include \$git_diff. Using Bullet format." >&2
        ai_prompt="${bullet_prompt//\$git_diff/$git_diff}"
      fi
    else
      print_warning "Style 'global_custom' selected but $HOME/.maiass.prompt not found. Using Bullet format." >&2
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
    # Ensure temperature is a number for jq
    local temp_num
    temp_num=$(echo "$ai_temperature" | grep -E '^[0-9]*\.?[0-9]+$' || echo "0.7")
    json_payload=$(jq -n --arg model "$ai_model" --argjson temperature "$temp_num" --arg prompt "$ai_prompt" '{
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
    json_payload='{"model":"'$ai_model'","messages":[{"role":"system","content":"You are a helpful assistant that writes concise, descriptive git commit messages based on code changes."},{"role":"user","content":"'$safe_prompt'"}],"max_tokens":150,"temperature":'${ai_temperature:-0.7}'}'
  fi

  print_debug "DEBUG: JSON payload length: ${#json_payload} characters" >&2
  print_debug "DEBUG: endpoint: ${maiass_endpoint}" >&2
  print_debug "DEBUG: About to make API call..." >&2
  
  # Make API call and capture both response and HTTP status
  local http_response
  print_debug "DEBUG: Executing curl to $maiass_endpoint" >&2
  print_debug "DEBUG: curl command: curl -s -w \"\\n%{http_code}\" -X POST \"$maiass_endpoint\" -H \"Content-Type: application/json\" -H \"Authorization: Bearer ${ai_token:0:10}...\" -d \"[JSON_PAYLOAD]\"" >&2
  
  # Check if this is an anonymous token and include machine fingerprint header
  local curl_headers=()
  curl_headers+=("-H" "Content-Type: application/json")
  curl_headers+=("-H" "Authorization: Bearer $ai_token")
  
  if [[ "$ai_token" == anon_* ]]; then
    print_debug "DEBUG: Anonymous token detected, adding machine fingerprint header" >&2
    # Generate the same machine fingerprint we used for subscription
    local machine_fingerprint
    if command -v generate_machine_fingerprint >/dev/null 2>&1; then
      machine_fingerprint=$(generate_machine_fingerprint)
    else
      machine_fingerprint=$(echo -n "$(uname -a)-$(whoami)-$(date +%Y%m)" | shasum -a 256 | cut -d' ' -f1)
    fi
    curl_headers+=("-H" "X-Machine-Fingerprint: $machine_fingerprint")
    print_debug "DEBUG: Added machine fingerprint header: ${machine_fingerprint:0:10}..." >&2
  fi
  
  http_response=$(curl -s -w "\n%{http_code}" -X POST "$maiass_endpoint" \
    "${curl_headers[@]}" \
    -d "$json_payload" 2>&1)
  
  local curl_exit_code=$?
  print_debug "DEBUG: curl exit code: $curl_exit_code" >&2
  
  print_debug "DEBUG: curl completed, processing response..." >&2
  
  # Split response and status code using more portable method
  local http_status
  http_status=$(echo "$http_response" | tail -n 1)
  local api_response
  # Use sed to remove last line instead of head -n -1 (which doesn't work on macOS)
  api_response=$(echo "$http_response" | sed '$d')
  
  print_debug "DEBUG: HTTP Status: $http_status" >&2
  print_debug "DEBUG: Response length: ${#api_response} characters" >&2
  print_debug "DEBUG: Raw API response: ${api_response:0:200}${api_response:+...}" >&2
  print_debug "DEBUG: Full curl response: $http_response" >&2
  
  print_debug "DEBUG: API token: $(mask_api_key "${ai_token}") " >&2

  # Extract the suggested message from API response
  if [[ -n "$api_response" ]]; then
    print_debug "DEBUG: Processing API response..." >&2
  else
    print_debug "DEBUG: Empty API response detected" >&2
    if [[ "$curl_exit_code" -ne 0 ]]; then
      print_error "curl command failed with exit code $curl_exit_code" >&2
      print_debug "DEBUG: Check if maiass-proxy is running at $maiass_endpoint" >&2
      return 1
    elif [[ "$http_status" == "000" ]]; then
      print_error "Connection failed - check if maiass-proxy is running at $maiass_endpoint" >&2
      return 1
    else
      print_warning "Empty response with HTTP status $http_status" >&2
    fi
  fi
  
  if [[ -n "$api_response" ]]; then
    print_debug "DEBUG: Processing API response..." >&2
    # Check HTTP status code first
    case "$http_status" in
      401)
        print_debug "DEBUG: HTTP 401 - Invalid API key" >&2
        if handle_invalid_api_key_error; then
          # Error handler indicates we should retry with new credentials
          return 2
        else
          return 1
        fi
        ;;
      402)
        print_debug "DEBUG: HTTP 402 - Quota exceeded" >&2
        # Extract payment URL and other details from 402 response
        local payment_url=""
        local credits_remaining=""
        if command -v jq >/dev/null 2>&1; then
          payment_url=$(echo "$api_response" | jq -r '.error.payment_url // empty' 2>/dev/null)
          credits_remaining=$(echo "$api_response" | jq -r '.error.credits_remaining // empty' 2>/dev/null)
        else
          payment_url=$(echo "$api_response" | grep -o '"payment_url":"[^"]*"' | sed 's/"payment_url":"//' | sed 's/"$//' | head -1)
          credits_remaining=$(echo "$api_response" | grep -o '"credits_remaining":[0-9]*' | sed 's/"credits_remaining"://' | head -1)
        fi
        print_debug "DEBUG: Extracted payment_url=$payment_url, credits_remaining=$credits_remaining" >&2
        if handle_quota_exceeded_error "Token quota exceeded (HTTP 402)" "$payment_url" "$credits_remaining"; then
          # Error handler indicates we should retry with new credentials
          return 2
        else
          return 1
        fi
        ;;
      403)
        print_debug "DEBUG: HTTP 403 - Forbidden" >&2
        # Check if this is an invalid API key error in disguise
        if echo "$api_response" | grep -q '"code":"invalid_api_key"'; then
          print_debug "DEBUG: HTTP 403 contains invalid_api_key error code" >&2
          if handle_invalid_api_key_error; then
            # Error handler indicates we should retry with new credentials
            return 2
          else
            return 1
          fi
        else
          print_warning "Access forbidden. Check your API key permissions." >&2
          print_debug "DEBUG: HTTP 403 response: $api_response" >&2
          return 1
        fi
        ;;
      429)
        print_debug "DEBUG: HTTP 429 - Rate limit exceeded" >&2
        print_warning "Rate limit exceeded. Please try again later." >&2
        print_debug "DEBUG: HTTP 429 response: $api_response" >&2
        return 1
        ;;
      5*)
        print_debug "DEBUG: HTTP $http_status - Server error" >&2
        print_warning "AI service temporarily unavailable (HTTP $http_status). Please try again later." >&2
        print_debug "DEBUG: HTTP $http_status response: $api_response" >&2
        return 1
        ;;
    esac
    
    # Check for API error in JSON response
    print_debug "DEBUG: Checking for JSON errors in response..." >&2
    if echo "$api_response" | grep -q '"error"'; then
      print_debug "DEBUG: Found error in JSON response" >&2
      error_msg=$(echo "$api_response" | grep -o '"message":"[^"]*"' | sed 's/"message":"//' | sed 's/"$//' | head -1)
      error_code=$(echo "$api_response" | grep -o '"code":"[^"]*"' | sed 's/"code":"//' | sed 's/"$//' | head -1)
      
      print_debug "DEBUG: JSON error_code=$error_code, error_msg=$error_msg" >&2
      
      # Handle specific error types
      case "$error_code" in
        "invalid_api_key")
          print_debug "DEBUG: JSON error - invalid_api_key" >&2
          if handle_invalid_api_key_error; then
            # Error handler indicates we should retry with new credentials
            return 2
          else
            return 1
          fi
          ;;
        "quota_exceeded"|"insufficient_quota"|"insufficient_credit")
          print_debug "DEBUG: JSON error - quota/credit issue" >&2
          # Extract payment URL and credits from error response
          local payment_url=""
          local credits_remaining=""
          if command -v jq >/dev/null 2>&1; then
            payment_url=$(echo "$api_response" | jq -r '.error.payment_url // empty' 2>/dev/null)
            credits_remaining=$(echo "$api_response" | jq -r '.error.credits_remaining // empty' 2>/dev/null)
          else
            payment_url=$(echo "$api_response" | grep -o '"payment_url":"[^"]*"' | sed 's/"payment_url":"//' | sed 's/"$//' | head -1)
            credits_remaining=$(echo "$api_response" | grep -o '"credits_remaining":[0-9]*' | sed 's/"credits_remaining"://' | head -1)
          fi
          if handle_quota_exceeded_error "$error_msg" "$payment_url" "$credits_remaining"; then
            # Error handler indicates we should retry with new credentials
            return 2
          else
            return 1
          fi
          ;;
        *)
          print_warning "API Error: $error_msg" >&2
          if [[ -n "$error_code" ]]; then
            print_debug "DEBUG: Error code: $error_code" >&2
          fi
          print_debug "DEBUG: Full error response: $api_response" >&2
          return 1
          ;;
      esac
    fi

    print_debug "DEBUG: Attempting to parse JSON response" >&2

    # Try jq first if available (most reliable)
    if command -v jq >/dev/null 2>&1; then
      print_debug "DEBUG: Using jq for JSON parsing" >&2
      suggested_message=$(echo "$api_response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
      print_debug "DEBUG: jq result: '$suggested_message'" >&2

      # Extract credit usage information from billing section if available
      local credits_used credits_remaining cost warning_msgs
      credits_used=$(echo "$api_response" | jq -r '.billing.credits_used // empty' 2>/dev/null)
      credits_remaining=$(echo "$api_response" | jq -r '.billing.credits_remaining // empty' 2>/dev/null)
      cost=$(echo "$api_response" | jq -r '.billing.cost // empty' 2>/dev/null)
      
      # Extract warning messages from messages array - get just the text field
      warning_msgs=$(echo "$api_response" | jq -r '.messages[]?.text // empty' 2>/dev/null)

      # Display credit usage and remaining balance
      if [[ -n "$credits_used" && "$credits_used" != "empty" && "$credits_used" != "null" ]]; then
        print_always "Credits used: ${credits_used}" >&2
        # Store for summary display
        export MAIASS_AI_CREDITS_USED="$credits_used"
      fi
      
      if [[ -n "$credits_remaining" && "$credits_remaining" != "empty" && "$credits_remaining" != "null" ]]; then
        print_always "Credits remaining: ${credits_remaining}" >&2
        # Store for summary display
        export MAIASS_AI_CREDITS_REMAINING="$credits_remaining"
      fi
      
      if [[ -n "$cost" && "$cost" != "empty" && "$cost" != "null" ]]; then
        print_debug "Cost: $${cost}" >&2
      fi
      
      # Store warning messages for later display (after commit message suggestion)
      if [[ -n "$warning_msgs" && "$warning_msgs" != "empty" && "$warning_msgs" != "null" ]]; then
        # Store warnings in a global variable for display in sign-off
        export MAIASS_AI_WARNINGS="$warning_msgs"
      fi
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

    # Remove extra quotes that might wrap the entire message
    suggested_message=$(echo "$suggested_message" | sed "s/^'\\(.*\\)'$/\\1/" | sed 's/^"\\(.*\\)"$/\\1/')

    # Clean up the message - remove leading empty lines and format bullet points
    # Remove leading empty lines
    suggested_message=$(printf '%s' "$suggested_message" | sed '/./,$!d')
    
    # Remove leading/trailing whitespace from each line and add proper formatting
    suggested_message=$(printf '%s' "$suggested_message" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    # Add tab before bullet points for proper indentation
    suggested_message=$(printf '%s' "$suggested_message" | sed 's/^[[:space:]]*-[[:space:]]*/\t- /')

    print_debug "DEBUG: Final cleaned message: '$suggested_message'" >&2
    print_debug "DEBUG: Message length: ${#suggested_message} characters" >&2
    print_debug "DEBUG: First 100 chars with visible newlines: $(printf '%q' "${suggested_message:0:100}")" >&2
    print_debug "DEBUG: Message validation: non-empty=$(test -n "$suggested_message" && echo "true" || echo "false"), not-null=$(test "$suggested_message" != "null" && echo "true" || echo "false")" >&2

    if [[ -n "$suggested_message" && "$suggested_message" != "null" ]]; then
      print_debug "DEBUG: Message validation passed, returning suggestion" >&2
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

