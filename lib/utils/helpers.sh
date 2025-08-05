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
    "Scribe")
      app_path="/Applications/Scribe.app"
      binary_path="$app_path/Contents/MacOS/Scribe"
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

# Generate sign-off message with optional top-up URL
print_signoff_with_topup() {
  echo ""
  
  # Read session data from temp file if it exists
  local credits_used credits_remaining ai_warnings ai_model
  if [[ -f "/tmp/maiass_session_data.tmp" ]]; then
    # Source the file to get variables
    while IFS='=' read -r key value; do
      case "$key" in
        "CREDITS_USED") credits_used="$value" ;;
        "CREDITS_REMAINING") credits_remaining="$value" ;;
        "AI_MODEL") ai_model="$value" ;;
      esac
    done < /tmp/maiass_session_data.tmp
    
    # Read AI warnings (handle multiline)
    if grep -q "AI_WARNINGS<<EOF" /tmp/maiass_session_data.tmp; then
      ai_warnings=$(sed -n '/AI_WARNINGS<<EOF/,/EOF/p' /tmp/maiass_session_data.tmp | sed '1d;$d')
    fi
  fi
  
  # Display credit summary if available from AI operations
  if [[ -n "$credits_used" || -n "$credits_remaining" ]]; then
    echo "📊 Credit Summary:"
    if [[ -n "$credits_used" ]]; then
      if [[ -n "$ai_model" ]]; then
        echo "   Credits used this session: $credits_used ($ai_model)"
      else
        echo "   Credits used this session: $credits_used"
      fi
    fi
    if [[ -n "$credits_remaining" ]]; then
      echo "   Credits remaining: $credits_remaining"
    fi
    echo ""
  fi
  
  # Display AI warning messages if any
  if [[ -n "$ai_warnings" ]]; then
    echo "⚠️  AI Service Notifications:"
    # Handle multiple warning messages
    while IFS= read -r warning_line; do
      if [[ -n "$warning_line" && "$warning_line" != "empty" && "$warning_line" != "null" ]]; then
        echo "   $warning_line"
      fi
    done <<< "$ai_warnings"
    echo ""
  fi
  
  echo "🎉 Thank you for using MAIASS!"
  echo ""
  
  # Debug: Check topup URL variables
  print_debug "DEBUG SIGNOFF: MAIASS_TOPUP_URL='${MAIASS_TOPUP_URL:-}'"
  print_debug "DEBUG SIGNOFF: maiass_topup_endpoint='${maiass_topup_endpoint:-}'"
  print_debug "DEBUG SIGNOFF: MAIASS_SUBSCRIPTION_ID='${MAIASS_SUBSCRIPTION_ID:-}'"
  
  # Check if we have a stored top-up URL from anonymous subscription
  if [[ -n "$MAIASS_TOPUP_URL" ]]; then
    echo "💳 Need more credits? Visit: $MAIASS_TOPUP_URL"
    print_debug "DEBUG SIGNOFF: Used MAIASS_TOPUP_URL"
  # Fallback to simple method if MAIASS_TOPUP_ENDPOINT or maiass_topup_endpoint is set but no stored URL  
  elif [[ -n "$MAIASS_TOPUP_ENDPOINT" || -n "$maiass_topup_endpoint" ]]; then
    local topup_url="${MAIASS_TOPUP_ENDPOINT:-$maiass_topup_endpoint}"
    # Add subscription ID to path if available (new simple format)
    if [[ -n "$MAIASS_SUBSCRIPTION_ID" ]]; then
      topup_url="${topup_url}/${MAIASS_SUBSCRIPTION_ID}"
      print_debug "DEBUG SIGNOFF: Using topup endpoint with subscription ID: $topup_url"
    else
      print_debug "DEBUG SIGNOFF: Using topup endpoint without subscription ID: $topup_url"
    fi
    echo "💳 Need more credits? Visit: $topup_url"
  else
    print_debug "DEBUG SIGNOFF: No topup URL variables set"
  fi
  
  # Clean up session data file
  if [[ -f "/tmp/maiass_session_data.tmp" ]]; then
    rm -f /tmp/maiass_session_data.tmp
  fi
}