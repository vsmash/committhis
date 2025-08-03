
# sets value to $currentversion and newversion.
# usage: getVersion [major|minor|patch|specific_version]
# if the second argument is not set, bumps the patch version


# Helper function to read version from a file based on type and line start
read_version_from_file() {
    local file="$1"
    local file_type="$2"
    local line_start="$3"
    local version=""

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    case "$file_type" in
        "json")
            # JSON file - look for "version" property
            if command -v jq >/dev/null 2>&1; then
                version=$(jq -r '.version' "$file" 2>/dev/null)
            else
                # Fallback method using grep and sed
                version=$(grep '"version"' "$file" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            fi
            ;;
        "txt")
            # Text file - look for line starting with specified prefix
            if [[ -n "$line_start" ]]; then
                version=$(grep "^${line_start}" "$file" | head -1 | sed "s/^${line_start}//" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            else
                # If no line start specified, assume entire file content is the version
                version=$(cat "$file" | tr -d '\n\r')
            fi
            ;;
        "pattern")
            # Pattern-based matching - extract version from regex pattern
            # line_start contains the pattern with {version} placeholder
            if [[ -n "$line_start" ]]; then
                # For PHP define statements, extract the version directly
                if [[ "$line_start" == *"define("* ]]; then
                    # Extract constant name from pattern
                    local const_name
                    const_name=$(echo "$line_start" | sed "s/.*define('\([^']*\)'.*/\1/" | sed "s/.*define(\"\([^\"]*\)\".*/\1/")
                    if [[ -n "$const_name" ]]; then
                        # Find the define line and extract version
                        version=$(grep "define('${const_name}'" "$file" | sed "s/.*'[^']*'[[:space:]]*,[[:space:]]*'\([^']*\)'.*/\1/")
                        if [[ -z "$version" ]]; then
                            version=$(grep "define(\"${const_name}\"" "$file" | sed "s/.*\"[^\"]*\"[[:space:]]*,[[:space:]]*\"\([^\"]*\)\".*/\1/")
                        fi
                    fi
                else
                    # Generic pattern matching - replace {version} with capture group
                    local search_pattern
                    search_pattern=$(echo "$line_start" | sed "s/{version}/\\([^'\"]*\\)/g")
                    version=$(sed -n "s/.*${search_pattern}.*/\1/p" "$file" | head -1)
                fi
            fi
            ;;
        *)
            print_error "Unsupported file type: $file_type"
            return 1
            ;;
    esac

    if [[ -n "$version" && "$version" != "null" ]]; then
        echo "$version"
        return 0
    else
        return 1
    fi
}

# Helper function to update version in a file based on type and line start
update_version_in_file() {
    local file="$1"
    local file_type="$2"
    local line_start="$3"
    local new_version="$4"

    if [[ ! -f "$file" ]]; then
        print_warning "File not found: $file"
        return 1
    fi

    case "$file_type" in
        "json")
            # JSON file - update "version" property
            if command -v jq >/dev/null 2>&1; then
                jq ".version = \"$new_version\"" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
            else
                # Fallback to sed
                sed_inplace "s/\"version\": \".*\"/\"version\": \"$new_version\"/" "$file"
            fi
            ;;
        "txt")
            # Text file - update line starting with specified prefix
            if [[ -n "$line_start" ]]; then

                awk -v prefix="$line_start" -v version="$new_version" '
                  BEGIN { len = length(prefix) }
                  substr($0, 1, len) == prefix { print prefix version; next }
                  { print }
                ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
            else
                # If no line start specified, replace entire file content
                echo "$new_version" > "$file"
            fi
            ;;
        "pattern")
            # Pattern-based replacement - replace version in regex pattern
            # line_start contains the pattern with {version} placeholder
            if [[ -n "$line_start" ]]; then
                # For PHP define statements, use a specific approach
                if [[ "$line_start" == *"define("* ]]; then
                    # Extract the constant name from the pattern
                    local const_name
                    const_name=$(echo "$line_start" | sed "s/.*define('\([^']*\)'.*/\1/" | sed "s/.*define(\"\([^\"]*\)\".*/\1/")
                    if [[ -n "$const_name" ]]; then
                        # Replace PHP define statement with new version
                        sed_inplace "s/define('${const_name}'[[:space:]]*,[[:space:]]*'[^']*')/define('${const_name}','${new_version}')/g" "$file"
                        sed_inplace "s/define(\"${const_name}\"[[:space:]]*,[[:space:]]*\"[^\"]*\")/define(\"${const_name}\",\"${new_version}\")/g" "$file"
                    fi
                else
                    # Generic pattern replacement - replace {version} with new version
                    local replacement_text
                    replacement_text=$(echo "$line_start" | sed "s/{version}/$new_version/g")
                    # Create a pattern to match the structure (replace {version} with wildcard)
                    local match_pattern
                    match_pattern=$(echo "$line_start" | sed "s/{version}/.*/g" | sed 's/[[\/.\*^$()+?{|]/\\&/g')
                    # Replace matching lines
                    sed_inplace "s/${match_pattern}/${replacement_text}/g" "$file"
                fi
            fi
            ;;
        *)
            print_error "Unsupported file type: $file_type"
            return 1
            ;;
    esac

    return 0
}

# Helper function to parse secondary version files configuration
parse_secondary_version_files() {
    local config="$1"
    local -a files_array

    if [[ -z "$config" ]]; then
        return 0
    fi

    IFS='|' read -ra files_array <<< "$config"

    for file_config in "${files_array[@]}"; do
        if [[ -n "$file_config" ]]; then
            IFS=':' read -ra config_parts <<< "$file_config"
            local file="${config_parts[0]}"
            local type="${config_parts[1]:-txt}"
            local line_start="${config_parts[2]:-}"

            if [[ -f "$file" ]]; then
                echo "$file:$type:$line_start"
            else
                echo "Skipping $file (not found)" >&2
            fi
        fi
    done
}
