
mask_api_key() {
    local api_key="$1"

    # Check if key is empty or too short
    if [[ -z "$api_key" ]] || [[ ${#api_key} -lt 8 ]]; then
        echo "[INVALID_KEY]"
        return
    fi

    # Extract first 4 and last 4 characters using parameter expansion
    local first_four="${api_key:0:4}"
    local last_four="${api_key: -4}"

    echo "${first_four}****${last_four}"
}


escape_regex() {
  # Escapes all regex metacharacters
  echo "$1" | sed -e 's/[][\/.^$*+?(){}|]/\\&/g'
}
