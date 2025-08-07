
function updateChangelog() {
    changelogpath=$1
    [ -z "$changelogpath" ] && changelogpath="."

    # Determine changelog range from latest version entry in the changelog
    if [ -f "$changelogpath/$changelog_name" ]; then
        last_version=$(grep -m1 '^## ' "$changelogpath/$changelog_name" | sed 's/^## //')
        last_changelog_commit=$(git log -1 --format="%H" -S"## $last_version" -- "$changelogpath/$changelog_name")
    fi

    if [ -z "$last_changelog_commit" ]; then
        last_changelog_commit=$(git rev-list --max-parents=0 HEAD)
    fi

    log_range="$last_changelog_commit..HEAD"

        changelog=$(git log "$log_range" --pretty=format:"%B" |
        grep -vEi '^(ncl|Merge|Bump|Fixing merge conflicts)' |
        awk '
        BEGIN { commit = "" }
        /^$/ {
            if (commit != "") {
                n = split(commit, lines, "\n")
                lines[1] = gensub(/^\[?[A-Z]+-[0-9]+\]?[[:space:]:—-]+/, "", 1, lines[1])
                print "- " lines[1]
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
                lines[1] = gensub(/^\[?[A-Z]+-[0-9]+\]?[[:space:]:—-]+/, "", 1, lines[1])
                print "- " lines[1]
                for (i = 2; i <= n; i++) {
                    if (lines[i] != "") {
                        print "\t" lines[i]
                    }
                }
            }
        }')
        # remove double tabs
        changelog=$(echo "$changelog" | sed 's/\t\t/\t/g')
        remove $jira_ticket_number if $jira_ticket_number is not empty
        

        if [ -n "$jira_ticket_number" ]; then
            changelog=$(echo "$changelog" | sed 's/^$jira_ticket_number //g')
        fi
        
        changelog_internal=$(git log "$log_range" --pretty=format:"%an%n%B" |
            grep -vEi '^(ncl|Merge|Bump|Fixing merge conflicts)' |
            awk '
            BEGIN { commit = "" }
            /^$/ {
                if (commit != "") {
                    n = split(commit, lines, "\n")
                    author = lines[1]
                    subject = ""
                    for (j = 2; j <= n; j++) {
                        if (lines[j] != "") {
                            subject = lines[j]
                            break
                        }
                    }
                    print "- " author ": " subject
                    for (i = j + 1; i <= n; i++) {
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
                    author = lines[1]
                    subject = ""
                    for (j = 2; j <= n; j++) {
                        if (lines[j] != "") {
                            subject = lines[j]
                            break
                        }
                    }
                    print "- " author ": " subject
                    for (i = j + 1; i <= n; i++) {
                        if (lines[i] != "") {
                            print "\t" lines[i]
                        }
                    }
                }
            }')

        if [ -n "$jira_ticket_number" ]; then
            changelog=$(echo "$changelog" | sed 's/^$jira_ticket_number //g')
            changelog_internal=$(echo "$changelo_internal" | sed 's/^$jira_ticket_number //g')
        fi



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
