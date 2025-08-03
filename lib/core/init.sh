export total_tokens=''
export completion_tokens=''
export prompt_tokens=''
export version_primary_file="${MAIASS_VERSION_PRIMARY_FILE:-}"
export version_primary_type="${MAIASS_VERSION_PRIMARY_TYPE:-}"
export version_primary_line_start="${MAIASS_VERSION_PRIMARY_LINE_START:-}"
export version_secondary_files="${MAIASS_VERSION_SECONDARY_FILES:-}"


# Function to load MAIASS_* variables from .env files
load_bumpscript_env() {
  local env_file=".env.maiass"

  if [[ -f "$env_file" ]]; then
    print_info "Loading MAIASS_* variables from $env_file"

    while IFS= read -r line || [[ -n "$line" ]]; do
      # Trim leading/trailing whitespace
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"

      # Skip blank lines and comments
      [[ -z "$line" || "$line" == \#* ]] && continue

      # Only process MAIASS_* assignments
      if [[ "$line" =~ ^MAIASS_ ]]; then
        local key="${line%%=*}"
        local value="${line#*=}"

        # Strip surrounding matching quotes with POSIX-safe cut
        if [[ "$value" == \"*\" && "$value" == *\" ]] || [[ "$value" == \'*\' && "$value" == *\' ]]; then
          value=$(echo "$value" | cut -c2- | rev | cut -c2- | rev)
        fi

        export "$key=$value"
        print_info "Set $key=$value"
      fi
    done < "$env_file"
  fi
}
