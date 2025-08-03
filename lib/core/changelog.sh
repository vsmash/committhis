
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


function updateChangelog() {
    changelogpath=$1
    # if changelogpath is not set, set it to "."
    if [ -z "$changelogpath" ]; then
        changelogpath="."
    fi

    # find all the git messages since the last tag and print them
    # changelog=$(git log $(git describe --tags --abbrev=0)..HEAD --oneline \
    # changelog=$(git log $(git describe --tags --abbrev=0)..HEAD --pretty=format:"%s%n%b" \
    # Get commit messages and process them to handle multi-line commits properly
    # Use %B to get the full commit message with proper line breaks
    changelog=$(git log "$(git describe --tags --abbrev=0)"..HEAD --pretty=format:"%B" \
    | sed -E 's/^[0-9a-f]+ \([^)]+\) //; s/^[0-9a-f]+ //' \
    | sed -E 's/^[A-Z]+-[0-9]+ //' \
    | grep -vE '^(ncl|Merge|Bump|Fixing merge conflicts)' -i)

    # Process the changelog to handle multi-line commits properly
    changelog=$(echo "$changelog" | awk '
    BEGIN { in_commit = 0; commit_lines = ""; }
    /^$/ {
        if (in_commit && commit_lines != "") {
            # End of commit - process accumulated lines
            if (commit_lines ~ /^- /) {
                # Already has bullet points (AI commit) - add indentation to body lines
                n = split(commit_lines, lines, "\n")
                for (i = 1; i <= n; i++) {
                    if (lines[i] != "") {
                        if (i == 1) {
                            # First line (subject) - keep as main bullet
                            print lines[i]
                        } else {
                            # Body lines - add indentation
                            if (lines[i] ~ /^- /) {
                                print "\t" lines[i]
                            } else {
                                print "\t- " lines[i]
                            }
                        }
                    }
                }
            } else {
                # Manual commit - split lines and add bullets with indentation
                n = split(commit_lines, lines, "\n")
                for (i = 1; i <= n; i++) {
                    if (lines[i] != "") {
                        if (i == 1) {
                            # First line (subject) - main bullet
                            print "- " lines[i]
                        } else {
                            # Body lines - indented bullets
                            if (lines[i] ~ /^- /) {
                                print "\t" lines[i]
                            } else {
                                print "\t- " lines[i]
                            }
                        }
                    }
                }
            }
            commit_lines = ""
            in_commit = 0
        }
        next
    }
    {
        if (in_commit) {
            commit_lines = commit_lines "\n" $0
        } else {
            commit_lines = $0
            in_commit = 1
        }
    }
    END {
        if (in_commit && commit_lines != "") {
            # Process final commit
            if (commit_lines ~ /^- /) {
                # Already has bullet points (AI commit) - add indentation to body lines
                n = split(commit_lines, lines, "\n")
                for (i = 1; i <= n; i++) {
                    if (lines[i] != "") {
                        if (i == 1) {
                            # First line (subject) - keep as main bullet
                            print lines[i]
                        } else {
                            # Body lines - add indentation
                            if (lines[i] ~ /^- /) {
                                print " " lines[i]
                            } else {
                                print " - " lines[i]
                            }
                        }
                    }
                }
            } else {
                # Manual commit - split lines and add bullets with indentation
                n = split(commit_lines, lines, "\n")
                for (i = 1; i <= n; i++) {
                    if (lines[i] != "") {
                        if (i == 1) {
                            # First line (subject) - main bullet
                            print "- " lines[i]
                        } else {
                            # Body lines - indented bullets
                            if (lines[i] ~ /^- /) {
                                print "\t" lines[i]
                            } else {
                                print "\t- " lines[i]
                            }
                        }
                    }
                }
            }
        }
    }')

    # changelog_internal=$(git log $(git describe --tags --abbrev=0)..HEAD --pretty=format:"%h %s (%an)" \
    # Using only %B to get the full commit message with proper line breaks, avoiding duplication
    changelog_internal=$(git log "$(git describe --tags --abbrev=0)"..HEAD --pretty=format:"%B" \
    | sed -E 's/^[0-9a-f]+ \([^)]+\) //; s/^[0-9a-f]+ //' \
    | grep -vE '^(ncl|Merge|Bump|Fixing merge conflicts)' -i \
    | sed 's/^/- /')

    # prepend ** VERSION $newversion ** to the changelog
    # changelog="** VERSION $newversion **\n\n$changelog"

    # if changelog is just blank space or lines, don't add it
    if [ -z "$changelog" ]; then
    print_info "No changelog to add"
    else
    if [ -f "$changelogpath/$changelog_name" ]; then
        # if the first ## line is the same major and minor version as the new version replace it with the new version
            if [ "$(head -n 1 "$changelogpath/$changelog_name" | sed 's/## //' | cut -d. -f1,2)" == "$(echo $newversion | cut -d. -f1,2)" ]; then
                # if the second line is the same date as humandate
                if [ "$(sed -n '2p' "$changelogpath/$changelog_name")" == "$humandate" ]; then
                    # remove the first three lines
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

    # if changelog is just blank space or lines, don't add it
    if [ -z "$changelog_internal" ]; then
        print_info "No internal changelog to add"
    elif [ -f "$changelogpath/$changelog_internal_name" ]; then
        # Internal changelog exists, update it
        # if the first ## line is the same major and minor version as the new version replace it with the new version
        if [ "$(head -n 1 "$changelogpath/$changelog_internal_name" | sed 's/## //' | cut -d. -f1,2)" == "$(echo $newversion | cut -d. -f1,2)" ]; then
            # if the second line is the same date as longhumandate
            if [ "$(sed -n '2p' "$changelogpath/$changelog_internal_name")" == "$longhumandate" ]; then
                # remove the first three lines
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

    clean_changelog "$changelogpath/$changelog_name"
    clean_changelog "$changelogpath/$changelog_internal_name"

}
