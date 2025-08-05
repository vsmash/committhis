
# Function to display help information
show_help() {
  # Define colors for help output
  local BBlue='\033[1;34m'
  local BWhite='\033[1;37m'
  local BGreen='\033[1;32m'
  local BYellow='\033[1;33m'
  local BRed='\033[1;31m'
  local BCyan='\033[1;36m'
  local Color_Off='\033[0m'
  local BLime='\033[1;32m'
  local Gray="\033[0;37m"  # Gray for default text

  echo -e "${BBlue}"
   cat <<-'EOF'
        ▄▄   ▄▄ ▄▄▄▄▄▄▄ ▄▄▄ ▄▄▄▄▄▄▄ ▄▄▄▄▄▄▄ ▄▄▄▄▄▄▄
       █  █▄█  █       █   █       █       █       █
       █       █   ▄   █   █   ▄   █  ▄▄▄▄▄█  ▄▄▄▄▄█
       █       █  █▄█  █   █  █▄█  █ █▄▄▄▄▄█ █▄▄▄▄▄
       █       █       █   █       █▄▄▄▄▄  █▄▄▄▄▄  █
       █ ██▄██ █   ▄   █   █   ▄   █▄▄▄▄▄█ █▄▄▄▄▄█ █
       █▄█   █▄█▄▄█ █▄▄█▄▄▄█▄▄█ █▄▄█▄▄▄▄▄▄▄█▄▄▄▄▄▄▄█
EOF
  echo -e "${BAqua}\n       Modular AI-Augmented Semantic Scribe\n${BYellow}\n       * AI Commit Messages\n${BLime}       * Intelligent Git Workflow Automation${Color_Off}\n"



  echo -e "${BWhite}DESCRIPTION:${Color_Off}"
  echo -e "  Automated version bumping and changelog management script that maintains"
  echo -e "  the develop branch as the source of truth for versioning. Integrates with"
  echo -e "  AI-powered commit messages and supports multi-repository workflows.\n"

  echo -e "${BWhite}USAGE:${Color_Off}"
  echo -e "  maiass [VERSION_TYPE] [OPTIONS]\n"
  echo -e "${BWhite}VERSION_TYPE:${Color_Off}"
  echo -e "  major          Bump major version (e.g., 1.2.3 → 2.0.0)"
  echo -e "  minor          Bump minor version (e.g., 1.2.3 → 1.3.0)"
  echo -e "  patch          Bump patch version (e.g., 1.2.3 → 1.2.4) ${Gray}[default]${Color_Off}"
  echo -e "  X.Y.Z          Set specific version number\n"
  echo -e "${BWhite}OPTIONS:${Color_Off}"
  echo -e "  -h, --help     Show this help message"
  echo -e "  -v, --version  Show version information\n"

  echo -e "${BWhite}QUICK START:${Color_Off}"
  echo -e "  ${BGreen}1.${Color_Off} Run ${BCyan}maiass${Color_Off} in your git repository"
  echo -e "  ${BGreen}2.${Color_Off} For AI features: Set ${BRed}MAIASS_AI_TOKEN${Color_Off} environment variable"
  echo -e "  ${BGreen}3.${Color_Off} Everything else works with sensible defaults!\n"

  echo -e "${BWhite}AI COMMIT INTELLIGENCE WORKFLOW:${Color_Off}"
  echo -e "MAIASS manages code changes in the following way:"
  echo -e "  ${BGreen}1.${Color_Off} Asks if you would like to commit your changes"
  echo -e "  ${BGreen}2.${Color_Off} If AI is available and switched in ask mode, asks if you'd like an ai suggestion"
  echo -e "  ${BGreen}3.${Color_Off} If yes or in autosuggest mode, suggests a commit mesage"
  echo -e "  ${BGreen}3.${Color_Off} You can use it or enter manual commit mode (multiline) at the prompt"
  echo -e "  ${BGreen}4.${Color_Off} Offers to merge to develop, which initiates the version and changelog workflow"
  echo -e "  ${BGreen}5.${Color_Off} If you just want ai commit suggestions and no further workflow, say no\n"

  echo -e "${BWhite}VERSION AND CHANGELOG WORKFLOW:${Color_Off}"
  echo -e "MAIASS manages version bumping and changelogging in the following way:"
  echo -e "  ${BGreen}1.${Color_Off} Merges feature branch → develop"
  echo -e "  ${BGreen}2.${Color_Off} Creates release/x.x.x branch from develop"
  echo -e "  ${BGreen}3.${Color_Off} Updates version files and changelog on release branch"
  echo -e "  ${BGreen}4.${Color_Off} Commits and pushes release branch"
  echo -e "  ${BGreen}5.${Color_Off} Merges release branch back to develop"
  echo -e "  ${BGreen}6.${Color_Off} Returns to original feature branch\n"



  echo -e "  ${BYellow}Git Flow Diagram:${Color_Off}"
  echo -e "${BAqua}    feature/xyz ──┐"
  echo -e "                  ├─→ develop ──→ release/1.2.3 ──┐"
  echo -e "    feature/abc ──┘                                ├─→ develop"
  echo -e "                                                    └─→ (tagged)\n${Color_Off}"

  echo -e "  ${BYellow}Note:${Color_Off} Script will not bump versions if develop branch requires"
  echo -e "  pull requests, as PR workflows are outside the scope of this script.\n"

  echo -e "${BWhite}EXAMPLES:${Color_Off}"
  echo -e "  maiass                         # Bump patch version with interactive prompts"
  echo -e "  maiass minor                   # Bump minor version"
  echo -e "  maiass major                   # Bump major version"
  echo -e "  maiass 2.1.0                   # Set specific version\n"

  echo -e "${BRed}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Color_Off}"
  echo -e "${BRed}                            CONFIGURATION (OPTIONAL)${Color_Off}"
  echo -e "${BRed}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Color_Off}\n"

  echo -e "${BWhite}🤖 AI FEATURES:${Color_Off}"
  echo -e "  ${BRed}MAIASS_AI_TOKEN${Color_Off}          Optional but ${BRed}REQUIRED${Color_Off} if you want AI commit messages"
  echo -e "  MAIASS_AI_MODE           ${Gray}('ask')${Color_Off} 'off', 'autosuggest'"
  echo -e "  MAIASS_AI_MODEL          ${Gray}('gpt-4o')${Color_Off} AI model to use"
  echo -e "  MAIASS_AI_COMMIT_MESSAGE_STYLE  ${Gray}('bullet')${Color_Off} 'conventional', 'simple'"
  echo -e "  MAIASS_AI_ENDPOINT       ${Gray}(default AI provider)${Color_Off} Custom AI endpoint\n"

  echo -e "${BWhite}📊 OUTPUT CONTROL:${Color_Off}"
  echo -e "  MAIASS_VERBOSITY             ${Gray}('brief')${Color_Off} 'normal', 'debug'"
  echo -e "  MAIASS_DEBUG                 ${Gray}('false')${Color_Off} 'true' for detailed output"
  echo -e "  MAIASS_ENABLE_LOGGING        ${Gray}('false')${Color_Off} 'true' to log to file"
  echo -e "  MAIASS_LOG_FILE              ${Gray}('maiass.log')${Color_Off} Log file path\n"
  echo -e "${BWhite}🌿 GIT WORKFLOW:${Color_Off}"
  echo -e "  MAIASS_DEVELOPBRANCH         ${Gray}('develop')${Color_Off} Override develop branch name"
  echo -e "  MAIASS_STAGINGBRANCH         ${Gray}('staging')${Color_Off} Override staging branch name"
  echo -e "  MAIASS_MASTERBRANCH          ${Gray}('master')${Color_Off} Override master branch name"
  echo -e "  MAIASS_STAGING_PULLREQUESTS  ${Gray}('on')${Color_Off} 'off' to disable staging pull requests"
  echo -e "  MAIASS_MASTER_PULLREQUESTS   ${Gray}('on')${Color_Off} 'off' to disable master pull requests\n"

  echo -e "${BWhite}🔗 REPOSITORY INTEGRATION:${Color_Off}"
  echo -e "  MAIASS_GITHUB_OWNER          ${Gray}(auto-detected)${Color_Off} Override GitHub owner"
  echo -e "  MAIASS_GITHUB_REPO           ${Gray}(auto-detected)${Color_Off} Override GitHub repo name"
  echo -e "  MAIASS_BITBUCKET_WORKSPACE   ${Gray}(auto-detected)${Color_Off} Override Bitbucket workspace"
  echo -e "  MAIASS_BITBUCKET_REPO_SLUG   ${Gray}(auto-detected)${Color_Off} Override Bitbucket repo slug\n"

  echo -e "${BWhite}🌐 BROWSER INTEGRATION:${Color_Off}"
  echo -e "  MAIASS_BROWSER               ${Gray}(system default)${Color_Off} Browser for URLs"
  echo -e "                                   Supported: Chrome, Firefox, Safari, Brave, Scribe"
  echo -e "  MAIASS_BROWSER_PROFILE       ${Gray}('Default')${Color_Off} Browser profile to use\n"

  echo -e "${BWhite}📁 CUSTOM VERSION FILES:${Color_Off}"
  echo -e "  ${BYellow}For projects with non-standard version file structures:${Color_Off}"
  echo -e "  MAIASS_VERSION_PRIMARY_FILE        Primary version file path"
  echo -e "  MAIASS_VERSION_PRIMARY_TYPE        ${Gray}('txt')${Color_Off} 'json', 'php' or 'txt' or 'pattern'"
  echo -e "  MAIASS_VERSION_PRIMARY_LINE_START  Line prefix for txt files"
  echo -e "  MAIASS_VERSION_SECONDARY_FILES     Secondary files (pipe-separated)"
  echo -e "  MAIASS_CHANGELOG_INTERNAL_NAME     alternate name for your internal changelog\n"

  echo -e "  ${BYellow}Examples:${Color_Off}"
  echo -e "    ${Gray}# WordPress theme with style.css version${Color_Off}"
  echo -e "    MAIASS_VERSION_PRIMARY_FILE=\"style.css\""
  echo -e "    MAIASS_VERSION_PRIMARY_TYPE=\"txt\""
  echo -e "    MAIASS_VERSION_PRIMARY_LINE_START=\"Version: \"\n"
  echo -e "    ${Gray}# PHP constant with pattern matching${Color_Off}"
  echo -e "    MAIASS_VERSION_PRIMARY_FILE=\"functions.php\""
  echo -e "    MAIASS_VERSION_PRIMARY_TYPE=\"pattern\""
  echo -e "    MAIASS_VERSION_PRIMARY_LINE_START=\"define('VERSION','{version}');\"\n"
  echo -e "${BRed}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Color_Off}"
  echo -e "${BRed}                               FEATURES & COMPATIBILITY${Color_Off}"
  echo -e "${BRed}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Color_Off}\n"

  echo -e "${BWhite}✨ KEY FEATURES:${Color_Off}"
  echo -e "  • ${BGreen}AI-powered commit messages${Color_Off} via AI integration"
  echo -e "  • ${BGreen}Automatic changelog generation${Color_Off} and management"
  echo -e "  • ${BGreen}Multi-repository support${Color_Off} (WordPress, Craft, bespoke projects)"
  echo -e "  • ${BGreen}Git workflow automation${Color_Off} (commit, tag, merge, push)"
  echo -e "  • ${BGreen}Intelligent version management${Color_Off} for diverse file structures"
  echo -e "  • ${BGreen}Jira ticket detection${Color_Off} from branch names\n"

  echo -e "${BWhite}🔄 REPOSITORY COMPATIBILITY:${Color_Off}"
  echo -e "  ${BYellow}Automatically adapts to your repository structure:${Color_Off}"
  echo -e "  ${BGreen}✓${Color_Off} Full Git Flow (develop → staging → master)"
  echo -e "  ${BGreen}✓${Color_Off} Simple workflow (feature → master)"
  echo -e "  ${BGreen}✓${Color_Off} Local-only repositories (no remote required)"
  echo -e "  ${BGreen}✓${Color_Off} Single branch workflows"
  echo -e "  ${BGreen}✓${Color_Off} Projects without version files (git-only mode)\n"

  echo -e "${BWhite}⚙️ SYSTEM REQUIREMENTS:${Color_Off}"
  echo -e "  ${BGreen}✓${Color_Off} Unix-like system (macOS, Linux, WSL)"
  echo -e "  ${BGreen}✓${Color_Off} Bash 3.2+ (macOS default supported)"
  echo -e "  ${BGreen}✓${Color_Off} Git command-line tools"
  echo -e "  ${BYellow}✓${Color_Off} jq (JSON processor) ${Gray}- required${Color_Off}\n"

  echo -e "  ${BYellow}Install jq:${Color_Off} ${Gray}brew install jq${Color_Off} (macOS) | ${Gray}sudo apt install jq${Color_Off} (Ubuntu)\n"

  echo -e "${BWhite}📝 CONFIGURATION:${Color_Off}"
  echo -e "  Global configuration loaded from ~/.maiass.env"
  echo -e "  Global overridden by Configuration loaded from ${BCyan}.env${Color_Off} files in current directory."
  echo -e "  ${Gray}Most settings are optional with sensible defaults!${Color_Off}\n"

  echo -e "${BGreen}Ready to get started? Just run:${Color_Off} ${BCyan}maiass${Color_Off}"
}


# Function to display help information for committhis
show_help_committhis() {
                      local BBlue='\033[1;34m'
                      local BWhite='\033[1;37m'
                      local BGreen='\033[1;32m'
                      local BYellow='\033[1;33m'
                      local BCyan='\033[1;36m'
                      local Color_Off='\033[0m'

                      echo -e "${BBlue}committhis - AI-powered Git commit message generator${Color_Off}"
                      echo
                      echo -e "${BWhite}Usage:${Color_Off}"
                      echo -e "  ${BGreen}committhis${Color_Off}"
                      echo
                      echo -e "${BWhite}Environment Configuration:${Color_Off}"
                      echo -e "  ${BCyan}MAIASS_AI_TOKEN${Color_Off}      Your AI API token (required)"
                      echo -e "  ${BCyan}MAIASS_AI_MODE${Color_Off}       Commit mode:"
                      echo -e "                                 ask (default), autosuggest, off"
                      echo -e "  ${BCyan}MAIASS_AI_COMMIT_MESSAGE_STYLE${Color_Off}"
                      echo -e "                                 Message style: bullet (default), conventional, simple"
                      echo -e "  ${BCyan}MAIASS_AI_ENDPOINT${Color_Off}   Custom AI endpoint (optional)"
                      echo
                      echo -e "${BWhite}Files (optional):${Color_Off}"
                      echo -e "  ${BGreen}.env${Color_Off}                     Can define the variables above"
                      echo -e "  ${BGreen}.maiass.prompt${Color_Off}           Custom AI prompt override"
                      echo
                      echo -e "committhis analyzes your staged changes and suggests an intelligent commit message."
                      echo -e "You can accept, reject, or edit it before committing."
                      echo
                      echo -e "This script does not manage versions, changelogs, or branches."
                    }
