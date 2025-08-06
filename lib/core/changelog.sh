
# Function to clean up duplicate changelog entries
function clean_changelog() {
    local changelog_file="$1"

    if [ ! -f "$changelog_file" ]; then
        echo "Error: Changelog file $changelog_file not found"
        return 1
    fi

    local temp_file="/tmp/changelog_temp_$$"
    local temp_section="/tmp/changelog_section_$$"
    touch "$temp_file" "$temp_section"

    # Initialize variables
    local current_version=""
    local current_date=""
    local first_section=1

    while read line; do
        # Version header (##)
        if echo "$line" | grep -q "^##[[:space:]]"; then
            # Process previous section if exists
            if [ ! -z "$current_version" ]; then
                if [ "$first_section" = 1 ]; then
                    first_section=0
                else
                    echo "" >> "$temp_file"
                fi
                echo "$current_version" >> "$temp_file"
                echo "$current_date" >> "$temp_file"
                echo "" >> "$temp_file"
                # Get unique bullet points while preserving order
                perl -ne 'print unless $seen{$_}++' "$temp_section" >> "$temp_file"
                : > "$temp_section"
            fi
            current_version="$line"

        # Date line (DD Month YYYY) or (DD Month YYYY (Weekday))
        elif echo "$line" | grep -q "^[0-9]\{1,2\}[[:space:]][A-Za-z]\+[[:space:]][0-9]\{4\}\([[:space:]]\([[:space:]]*([A-Za-z]\+)[[:space:]]*\)\)\?$"; then
            current_date="$line"

        # Bullet points
        # Bullet points
        elif echo "$line" | grep -q "^-[[:space:]]"; then
            echo "$line" | sed 's/^- - /- /' | sed 's/^-  /- /' >> "$temp_section"
        fi
    done < "$changelog_file"

    # Process the last section
    if [ ! -z "$current_version" ]; then
        if [ "$first_section" = 0 ]; then
            echo "" >> "$temp_file"
        fi
        echo "$current_version" >> "$temp_file"
        echo "$current_date" >> "$temp_file"
        echo "" >> "$temp_file"
        perl -ne 'print unless $seen{$_}++' "$temp_section" >> "$temp_file"
    fi

    # Replace original file with deduplicated content
    cat "$temp_file" > "$changelog_file"

    # Clean up temporary files
    rm -f "$temp_section" "$temp_file"
}

changelog=$(git log "$last_tag"..HEAD --pretty=format:"%B" |
grep -vEi '^(ncl|Merge|Bump|Fixing merge conflicts)' |
awk '
function indent(line) {
    print "- " line
}
BEGIN { commit = "" }
/^$/ {
    if (commit != "") {
        n = split(commit, lines, "\n")
        gsub(/^[A-Z]+-[0-9]+\s+/, "", lines[1])  # Strip JIRA ticket
        indent(lines[1])
        for (i = 2; i <= n; i++) {
            if (lines[i] != "") {
                print "\t" lines[i]
            }
        }
        commit = ""
    }
    next
}
{
    commit = commit $0 "\n"
}
END {
    if (commit != "") {
        n = split(commit, lines, "\n")
        gsub(/^[A-Z]+-[0-9]+\s+/, "", lines[1])  # Strip JIRA ticket
        indent(lines[1])
        for (i = 2; i <= n; i++) {
            if (lines[i] != "") {
                print "\t" lines[i]
            }
        }
    }
}')




    # Internal changelog — full unformatted messages
    changelog_internal=$(git log "$last_tag"..HEAD --pretty=format:"%B" \
    | sed -E 's/^[0-9a-f]+ \([^)]+\) //; s/^[0-9a-f]+ //' \
    | grep -vEi '^(ncl|Merge|Bump|Fixing merge conflicts)' \
    | sed 's/^/- /')

    if [ -z "$changelog" ]; then
        print_info "No changelog to add"
    else
        if [ -f "$changelogpath/$changelog_name" ]; then
            if [ "$(head -n 1 "$changelogpath/$changelog_name" | sed 's/## //' | cut -d. -f1,2)" == "$(echo $newversion | cut -d. -f1,2)" ]; then
                if [ "$(sed -n '2p' "$changelogpath/$changelog_name")" == "$humandate" ]; then
                    sed_inplace '1,3d' "$changelogpath/$changelog_name"
                    echo -e "## $newversion\n$humandate\n\n$changelog\n$(cat "$changelogpath/$changelog_name")" > "$changelogpath/$changelog_name"
                else
                    echo -e "## $newversion\n$humandate\n\n$changelog\n\n$(cat "$changelogpath/$changelog_name")" > "$changelogpath/$changelog_name"
                fi
            else
                echo -e "## $newversion\n$humandate\n\n$changelog\n\n$(cat "$changelogpath/$changelog_name")" > "$changelogpath/$changelog_name"
            fi
            print_success "Updated changelog in $changelogpath/$changelog_name"
        else
            echo -e "## $newversion\n$humandate\n\n$changelog" > "$changelogpath/$changelog_name"
            print_success "Created changelog in $changelogpath/$changelog_name"
        fi
    fi

    if [ -z "$changelog_internal" ]; then
        print_info "No internal changelog to add"
    elif [ -f "$changelogpath/$changelog_internal_name" ]; then
        if [ "$(head -n 1 "$changelogpath/$changelog_internal_name" | sed 's/## //' | cut -d. -f1,2)" == "$(echo $newversion | cut -d. -f1,2)" ]; then
            if [ "$(sed -n '2p' "$changelogpath/$changelog_internal_name")" == "$longhumandate" ]; then
                sed_inplace '1,3d' "$changelogpath/$changelog_internal_name"
                echo -e "## $newversion\n$longhumandate\n\n$changelog_internal\n$(cat "$changelogpath/$changelog_internal_name")" > "$changelogpath/$changelog_internal_name"
            else
                echo -e "## $newversion\n$longhumandate\n\n$changelog_internal\n\n$(cat "$changelogpath/$changelog_internal_name")" > "$changelogpath/$changelog_internal_name"
            fi
        else
            echo -e "## $newversion\n$longhumandate\n\n$changelog_internal\n\n$(cat "$changelogpath/$changelog_internal_name")" > "$changelogpath/$changelog_internal_name"
        fi
        print_success "Updated changelog in $changelogpath/$changelog_internal_name"
    else
        print_info "Internal changelog $changelogpath/$changelog_internal_name does not exist, skipping"
    fi
}
