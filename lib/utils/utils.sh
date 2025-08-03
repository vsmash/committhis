
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




generate_machine_fingerprint() {
    local components=()
    local has_real_hardware_info=0
    local fallback_used=0

    # Helper function to safely get command output with fallback
    safe_command() {
        local cmd="$1"
        local fallback="$2"
        local output
        output=$($cmd 2>/dev/null || echo "$fallback")
        # Clean up the output to be a single line
        echo "$output" | tr -d '\n' | tr -s ' ' ' '
    }

    # Get CPU info
    local cpu_info
    if [[ "$OSTYPE" == "darwin"* ]]; then
        cpu_info=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)
    else
        cpu_info=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^[ \t]*//' || uname -m)
    fi
    components+=("${cpu_info:-unknown_cpu}")

    # Get memory info
    local mem_info
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mem_info=$(sysctl -n hw.memsize 2>/dev/null || echo "unknown_mem")
    else
        mem_info=$(grep -m1 "MemTotal" /proc/meminfo 2>/dev/null || echo "unknown_mem")
    fi
    components+=("${mem_info}")

    # Get hardware info
    local hardware_info
    if [[ "$OSTYPE" == "darwin"* ]]; then
        hardware_info=$(system_profiler SPHardwareDataType 2>/dev/null | grep -E "Serial Number|Hardware UUID" | head -2 | tr '\n' ' ' || echo "unknown_hardware")
    else
        hardware_info=$(dmidecode -t system 2>/dev/null | grep -E "Serial Number|UUID" | head -2 | tr '\n' ' ' || echo "unknown_hardware")
    fi
    components+=("${hardware_info}")

    # Add architecture, username, and platform
    components+=("$(uname -m)")
    components+=("$(whoami 2>/dev/null || echo "unknown_user")")
    components+=("$(uname -s)")

    # Check if we have sufficient hardware info for security
    if [[ "${components[2]}" == *"unknown"* ]]; then
        has_real_hardware_info=0
        print_warning "WARNING: Using fallback fingerprint - hardware detection failed"
        print_warning "This may allow easier abuse. Consider checking system permissions."
    else
        has_real_hardware_info=1
    fi

    # Create a stable hash from all components
    local fingerprint_data
    fingerprint_data=$(printf "%s|" "${components[@]}" | tr -d '\n')

    # Debug output if in debug mode
    if [[ "$debug_mode" == "true" ]]; then
        print_debug "  DEBUG: Machine fingerprint components:" "debug"
        print_debug "  CPU: ${components[0]}" "debug"
        print_debug "  Memory: ${components[1]}" "debug"
        print_debug "  Hardware: ${components[2]}" "debug"
        print_debug "  Arch: ${components[3]}" "debug"
        print_debug "  Username: ${components[4]}" "debug"
        print_debug "  Platform: ${components[5]}" "debug"
        print_debug "  HasRealHardwareInfo: $has_real_hardware_info" "debug"
    fi

    # Generate SHA-256 hash in base64
    local hash
    if command -v openssl >/dev/null 2>&1; then
        hash=$(printf "%s" "$fingerprint_data" | openssl dgst -sha256 -binary | openssl base64 | tr -d '\n')
    elif command -v sha256sum >/dev/null 2>&1; then
        hash=$(printf "%s" "$fingerprint_data" | sha256sum | cut -d' ' -f1 | xxd -r -p | base64 | tr -d '\n')
    else
        # Last resort fallback
        print_warning "SECURITY WARNING: Using minimal fallback fingerprint (no hashing tools available)"
        local fallback="$(uname -s)-$(uname -m)-$(whoami 2>/dev/null || echo "unknown")-FALLBACK"
        if command -v base64 >/dev/null 2>&1; then
            hash=$(printf "%s" "$fallback" | base64 | tr -d '\n')
        else
            # If even base64 is not available, just use the string as is
            hash="$fallback"
        fi
        fallback_used=1
    fi

    echo "$hash"
    return $fallback_used
}

