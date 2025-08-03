
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



# Compare two semantic version strings
# Returns 0 (true) if version1 > version2, 1 (false) otherwise
version_is_greater() {
    local version1="$1"
    local version2="$2"

    # Split versions into major.minor.patch components
    local v1_major
    local v1_minor
    local v1_patch
    local v2_major
    local v2_minor
    local v2_patch

    v1_major=$(echo "$version1" | cut -d. -f1)
    v1_minor=$(echo "$version1" | cut -d. -f2)
    v1_patch=$(echo "$version1" | cut -d. -f3)

    v2_major=$(echo "$version2" | cut -d. -f1)
    v2_minor=$(echo "$version2" | cut -d. -f2)
    v2_patch=$(echo "$version2" | cut -d. -f3)

    # Compare major version
    if [ "$v1_major" -gt "$v2_major" ]; then
        return 0  # version1 > version2
    elif [ "$v1_major" -lt "$v2_major" ]; then
        return 1  # version1 < version2
    fi

    # Major versions are equal, compare minor version
    if [ "$v1_minor" -gt "$v2_minor" ]; then
        return 0  # version1 > version2
    elif [ "$v1_minor" -lt "$v2_minor" ]; then
        return 1  # version1 < version2
    fi

    # Major and minor versions are equal, compare patch version
    if [ "$v1_patch" -gt "$v2_patch" ]; then
        return 0  # version1 > version2
    else
        return 1  # version1 <= version2
    fi
}


function getVersion(){
# ---------------------------------------------------------------
# Copyright (c) 2025 Velvary Pty Ltd
# All rights reserved.
# This function is part of the Velvary bash scripts library.
# Licensed under the End User License Agreement (eula.txt) provided with this software.
# ---------------------------------------------------------------
    local version_arg="$1"  # major, minor, patch, or specific version

    # Initialize global variables (compatible with older bash versions)
    version_source=""
    version_source_file=""
    version_source_type=""
    version_source_line_start=""
    currentversion=""
    newversion=""

    print_section "Determining Version Source"

    # Check for custom primary version file first
    if [[ -n "$version_primary_file" && -n "$version_primary_type" ]]; then
        print_info "Checking custom primary version file: $version_primary_file"
        if currentversion=$(read_version_from_file "$version_primary_file" "$version_primary_type" "$version_primary_line_start"); then
            print_info "Found custom primary version file: $version_primary_file - using as version source"
            version_source="custom_primary"
            version_source_file="$version_primary_file"
            version_source_type="$version_primary_type"
            version_source_line_start="$version_primary_line_start"
        else
            print_error "Could not read version from custom primary file: $version_primary_file"
            return 1
        fi
    # Fallback to package.json (legacy behavior)
    elif [ -f "${package_json_path}/package.json" ]; then
        local package_json_file="${package_json_path}/package.json"
        print_info "Found package.json at $package_json_file - using as version source"
        version_source="package.json"
        version_source_file="$package_json_file"
        version_source_type="json"
        version_source_line_start=""

        if currentversion=$(read_version_from_file "$package_json_file" "json" ""); then
            : # Success, currentversion is set
        else
            print_error "Could not read version from package.json. Exiting."
            return 1
        fi
    # Fallback to VERSION file (legacy behavior)
    elif [ -f "$version_file_path/VERSION" ]; then
        print_info "No package.json found - using VERSION file at $version_file_path/VERSION"
        version_source="VERSION"
        version_source_file="$version_file_path/VERSION"
        version_source_type="txt"
        version_source_line_start=""

        if currentversion=$(read_version_from_file "$version_file_path/VERSION" "txt" ""); then
            : # Success, currentversion is set
        else
            print_error "VERSION file is empty. Exiting."
            return 1
        fi
    else
        print_error "No version source found! Please create either:"
        if [[ -n "$version_primary_file" ]]; then
            print_error "  - Custom primary version file: $version_primary_file, or"
        fi
        print_error "  - package.json at $package_json_path/package.json with version field, or"
        print_error "  - VERSION file at $version_file_path/VERSION"
        return 1
    fi

    # Calculate new version based on argument
    if [ -z "$version_arg" ]; then
       print_info "No version specified, bumping patch version..."
       newversion=$(echo "$currentversion" | awk -F. '{$NF = $NF + 1;} 1' | sed 's/ /./g')
    else
        print_info "Setting version based on argument: $version_arg"
        if [ "$version_arg" == "major" ]; then
            newversion=$(echo "$currentversion" | awk -F. '{$1 = $1 + 1; $2 = 0; $3 = 0;} 1' | sed 's/ /./g')
        elif [ "$version_arg" == "minor" ]; then
            newversion=$(echo "$currentversion" | awk -F. '{$2 = $2 + 1; $3 = 0;} 1' | sed 's/ /./g')
        elif [ "$version_arg" == "patch" ]; then
            newversion=$(echo "$currentversion" | awk -F. '{$3 = $3 + 1;} 1' | sed 's/ /./g')
        else
            # Validate specific version format (X.Y.Z)
            if [[ ! "$version_arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                print_error "Invalid version format: $version_arg"
                print_error "Version must be in major.minor.patch format (e.g., 1.2.3)"
                return 1
            fi

            # Get latest version from git tags for comparison
            local latest_tag_version
            latest_tag_version=$(get_latest_version_from_tags)

            if [[ -n "$latest_tag_version" ]]; then
                print_info "Latest git tag version: $latest_tag_version"
                # Check if new version is greater than latest tag
                if ! version_is_greater "$version_arg" "$latest_tag_version"; then
                    print_error "Version $version_arg is lower than latest version $latest_tag_version"
                    echo "Would you like to:"
                    echo "1) Bump the patch version (${latest_tag_version} → $(echo "$latest_tag_version" | awk -F. '{$3 = $3 + 1;} 1' | sed 's/ /./g'))"
                    echo "2) Try entering another version number"
                    echo "3) Exit (default)"
                    read -p "$(echo -e ${BCyan}Enter choice [1/2/3]: ${Color_Off})" choice

                    case "$choice" in
                        1)
                            newversion=$(echo "$latest_tag_version" | awk -F. '{$3 = $3 + 1;} 1' | sed 's/ /./g')
                            print_success "Using patch bump: $newversion"
                            ;;
                        2)
                            read -p "$(echo -e ${BCyan}Enter new version: ${Color_Off})" new_input
                            if [[ -n "$new_input" ]]; then
                                # Recursively call getVersion with new input
                                getVersion "$new_input"
                                return $?
                            else
                                print_error "No version entered. Exiting."
                                return 1
                            fi
                            ;;
                        *)
                            print_error "Exiting."
                            return 1
                            ;;
                    esac
                fi
            else
                # No git tags exist yet - this is the first version tag
                print_info "No version tags found in repository"
                print_info "This will be the first version tag: $version_arg"
                # Compare against current version in file to ensure we're not going backwards
                if ! version_is_greater "$version_arg" "$currentversion"; then
                    print_warning "Specified version $version_arg is not greater than current file version $currentversion"
                    echo "Would you like to:"
                    echo "1) Use current file version and bump patch (${currentversion} → $(echo "$currentversion" | awk -F. '{$3 = $3 + 1;} 1' | sed 's/ /./g'))"
                    echo "2) Try entering another version number"
                    echo "3) Continue with $version_arg anyway"
                    echo "4) Exit (default)"
                    read -p "$(echo -e ${BCyan}Enter choice [1/2/3/4]: ${Color_Off})" choice

                    case "$choice" in
                        1)
                            newversion=$(echo "$currentversion" | awk -F. '{$3 = $3 + 1;} 1' | sed 's/ /./g')
                            print_success "Using file version patch bump: $newversion"
                            ;;
                        2)
                            read -p "$(echo -e ${BCyan}Enter new version: ${Color_Off})" new_input
                            if [[ -n "$new_input" ]]; then
                                # Recursively call getVersion with new input
                                getVersion "$new_input"
                                return $?
                            else
                                print_error "No version entered. Exiting."
                                return 1
                            fi
                            ;;
                        3)
                            print_info "Continuing with version $version_arg"
                            newversion="$version_arg"
                            ;;
                        *)
                            print_info "Exiting."
                            return 1
                            ;;
                    esac
                else
                    newversion="$version_arg"
                fi
            fi
        fi
    fi

    print_info "Version source: ${BWhite}$version_source${Color_Off}"
    print_info "Current version: ${BWhite}$currentversion${Color_Off}"
    print_success "New version: ${BWhite}$newversion${Color_Off}"
}

