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
  echo "🎉 Thank you for using MAIASS!"
  echo ""
  
  # Check if we have a stored top-up URL from anonymous subscription
  if [[ -n "$MAIASS_TOPUP_URL" ]]; then
    echo "💳 Need more credits? Visit: $MAIASS_TOPUP_URL"
  # Fallback to simple method if MAIASS_TOPUP_ENDPOINT is set but no stored URL  
  elif [[ -n "$MAIASS_TOPUP_ENDPOINT" ]]; then
    local topup_url="$MAIASS_TOPUP_ENDPOINT"
    # Add subscription ID to path if available (new simple format)
    if [[ -n "$MAIASS_SUBSCRIPTION_ID" ]]; then
      topup_url="${topup_url}/${MAIASS_SUBSCRIPTION_ID}"
    fi
    echo "💳 Need more credits? Visit: $topup_url"
  fi
}