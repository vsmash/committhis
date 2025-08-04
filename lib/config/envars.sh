# Environment variables are now loaded with secure priority system above

# Secure environment variable loading with priority order
load_environment_variables() {
    local project_env=".env.maiass"

    # Priority 1: Project-specific env file
    if [[ -f "$project_env" ]]; then
        print_info "Loading project configuration from ${BCyan}$project_env${Color_Off}" "debug"
        source "$project_env"
    fi

    # Priority 2: Secure storage (cross-platform)
    load_secure_variables

    # Priority 3: System environment (already exported by shell, nothing to load)
}

# Load sensitive variables from secure storage
load_secure_variables() {
    local secure_vars=("MAIASS_AI_TOKEN" "MAIASS_SUBSCRIPTION_ID")
    local token_prompted=0

    for var in "${secure_vars[@]}"; do
        # Check if we should prefer secure storage over environment variable
        local prefer_secure=false
        if [[ "$var" == "MAIASS_AI_TOKEN" && -n "${!var}" ]]; then
            # Check if the existing token looks invalid
            if [[ "${!var}" =~ ^invalid_|^test_|_test$ ]] || [[ "${!var}" == "DISABLED" ]]; then
                prefer_secure=true
                print_debug "DEBUG: Environment token appears invalid, checking secure storage" "debug"
            fi
        fi
        
        # Skip if already set with valid token (unless we want to prefer secure storage)
        if [[ -n "${!var}" && "$prefer_secure" != "true" ]]; then
            continue  # already set via .env or env var
        fi

        local value=""
        if [[ "$OSTYPE" == "darwin"* ]]; then
            value=$(security find-generic-password -s "maiass" -a "$var" -w 2>/dev/null)
        elif command -v secret-tool >/dev/null 2>&1; then
            value=$(secret-tool lookup service maiass key "$var" 2>/dev/null)
        fi

        if [[ -n "$value" ]]; then
            export "$var"="$value"
            if [[ "$prefer_secure" == "true" ]]; then
                print_debug "DEBUG: Replaced invalid environment token with secure storage token" "debug"
            else
                print_debug "DEBUG: Loaded $var from secure storage" "debug"
            fi
        elif [[ "$var" == "MAIASS_AI_TOKEN" && -z "$value" && -z "${!var}" && "$token_prompted" -eq 0 ]]; then
            # Handle missing AI token - check if we should automatically create anonymous subscription
            if [[ ! -t 0 ]]; then
                print_warning "AI token not found and terminal is not interactive. Please set MAIASS_AI_TOKEN environment variable."
                continue
            fi

            # Check if automatic anonymous subscription is enabled (check env var directly)
            if [[ "${MAIASS_AI_INVALID_TOKEN_CHOICES:-}" == "false" ]]; then
                # Check if we already tried to create anonymous subscription this session
                if [[ "$_MAIASS_ANON_ATTEMPTED" != "true" ]]; then
                    print_info "No AI token found. Automatically creating anonymous subscription..."
                    export _MAIASS_ANON_ATTEMPTED="true"
                    
                    # We need to call the anonymous subscription function, but it's in ai.sh
                    # For now, just mark that we need to handle this in the AI module
                    export _MAIASS_NEED_ANON_TOKEN="true"
                    export MAIASS_AI_TOKEN=""  # Set empty to trigger AI module handling
                else
                    print_warning "Anonymous subscription already attempted this session. AI features will be disabled."
                    export MAIASS_AI_TOKEN="DISABLED"
                fi
            else
                # Original manual token entry behavior
                print_warning "No AI token found in secure storage."
                echo -e "To get started, you'll need an AI token for commit message generation."
                echo -e "Please enter your AI token (input will be hidden): "

                # Read token with hidden input
                if read -s token; then
                    if [[ -z "$token" ]]; then
                        print_warning "No token provided. AI features will be disabled."
                        token="DISABLED"
                    fi

                    # Store the token
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        security add-generic-password -a "$var" -s "maiass" -w "$token" -U
                    elif command -v secret-tool >/dev/null 2>&1; then
                        echo -n "$token" | secret-tool store --label="MAIASS AI Token" service maiass key "$var"
                    fi

                    export MAIASS_AI_TOKEN="$token"
                    print_success "AI token stored successfully."
                    token_prompted=1
                else
                    print_warning "Failed to read token. AI features will be disabled."
                    export MAIASS_AI_TOKEN="DISABLED"
                fi
            fi
        fi
    done
}
# Store sensitive variables in secure storage
store_secure_variable() {
    local var_name="$1"
    local var_value="$2"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "$var_value" | security add-generic-password -U -s "maiass" -a "$var_name" -w - 2>/dev/null
    elif command -v secret-tool >/dev/null 2>&1; then
        echo -n "$var_value" | secret-tool store --label="MAIASS $var_name" service maiass key "$var_name"
    else
        print_warning "No secure storage backend available"
        return 1
    fi
}

# Remove sensitive variables from secure storage
remove_secure_variable() {
    local var_name="$1"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        security delete-generic-password -s "maiass" -a "$var_name" 2>/dev/null
    elif command -v secret-tool >/dev/null 2>&1; then
        # No direct delete with secret-tool; need to use keyring CLI or let user handle it
        print_warning "Removing secrets from Linux keyrings requires manual intervention"
    else
        print_warning "No secure storage backend available"
        return 1
    fi
}


