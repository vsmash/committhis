# GitHub Copilot Guidelines - MAIASS Project

This document provides essential information for GitHub Copilot when assisting with the MAIASS (Modular AI-Assisted Semantic Savant) project development.

## Project Overview

MAIASS is a Git workflow automation script that intelligently handles version bumping, changelog management, and AI-powered commit messages. It's written primarily in Bash and designed for Unix-like environments.

## Build/Configuration Instructions

### Local Development Setup

1. **Main Script**: `./maiass.sh` - Primary script for running MAIASS
2. **Development Alias**: `dma` - Symlink to `./maiass.sh` (development environment only)
3. **Installation**: Run `./install.sh` or use Homebrew: `brew tap vsmash/homebrew-maiass && brew install maiass`

### Key Dependencies
- Bash 3.2+ (macOS default bash works)
- Git command-line tools
- jq JSON processor
- Standard Unix utilities (grep, sed, awk)

### Environment Configuration

MAIASS uses environment variables from `.env` files (project-specific) and `.maiass.env` (global):

```bash
# Core configuration
export MAIASS_MASTERBRANCH="main"                    # Default: main
export MAIASS_VERSION_PRIMARY_FILE="package.json"    # Primary version file
export MAIASS_VERSION_PRIMARY_TYPE="json"            # File type: json, txt, php

# OpenAI integration
export MAIASS_AI_TOKEN="your-api-key"           # OpenAI API key
export MAIASS_AI_MODE="ask"                     # Modes: ask, autosuggest, off
export MAIASS_AI_MODEL="gpt-4o"                 # Default: gpt-4o
export MAIASS_AI_COMMIT_MESSAGE_STYLE="bullet"  # Styles: bullet, conventional, simple

# Output control
export MAIASS_VERBOSITY="brief"                     # Levels: brief, normal, debug
export MAIASS_LOGGING="true"                        # Enable logging
export MAIASS_LOG_FILE="maiass.log"                 # Log file location
```

## Code Architecture

### Critical Functions (maiass.sh)
- `mergeDevelop()` - Main workflow function (lines 1696-1869)
- `getVersion()` - Version detection and management (lines 562-739)
- `updateChangelog()` - Changelog generation (lines 871-1047)
- `get_ai_commit_suggestion()` - AI commit messages (lines 1211-1404)
- `bumpVersion()` - Version incrementing logic
- `handleGitOperations()` - Git workflow management

### Key Data Structures
- Version files: package.json, composer.json, VERSION, custom text files
- Branch patterns: main/master, develop, staging, feature/*, release/*
- Semantic versioning: MAJOR.MINOR.PATCH format

## Testing Information

### Running Tests
```bash
# Run the comprehensive test suite
./test_maiass.sh

# Manual testing with dry-run
./maiass.sh patch --dry-run

# Version detection test
./maiass.sh --version-only
```

### Test Coverage Areas
- Version file parsing (JSON, text, PHP)
- Branch detection and merge logic
- AI commit message generation
- Cross-platform compatibility
- Git workflow validation
- Environment variable handling

### Adding New Tests

Follow this pattern when adding tests to `test_maiass.sh`:

```bash
echo -e "\n${BLUE}Test X: Description of test${NC}"
# Setup test environment
export MAIASS_VARIABLE="test_value"

# Execute test
"$MAIASS_SCRIPT" command --flags

# Verify results
RESULT=$(grep "expected_pattern" target_file)
if [[ "$RESULT" == "expected_value" ]]; then
    echo -e "${GREEN}✓ Test passed${NC}"
else
    echo -e "${RED}✗ Test failed: Expected 'expected_value', got '$RESULT'${NC}"
fi
```

## Known Issues & Areas of Focus

### Current Issues
1. **Misleading Success Messages**: `mergeDevelop()` shows "Merged X into develop" even when no merge occurs
2. **Cross-platform Compatibility**: Windows support is untested
3. **Error Handling**: Some operations need better error recovery

### Critical Code Paths
- Git repository detection and validation
- Branch existence checking before merge operations
- Version file format detection and parsing
- OpenAI API error handling and retry logic

## Development Best Practices

### Code Style
- Use 2-space indentation for shell scripts
- Follow Bash best practices and proper error handling
- Include meaningful comments for complex logic
- Use descriptive variable names with MAIASS_ prefix

### Error Handling Pattern
```bash
if ! command_that_might_fail; then
    echo -e "${RED}Error: Operation failed${NC}" >&2
    return 1
fi
```

### Function Structure
```bash
function_name() {
    local param1="$1"
    local param2="$2"
    
    # Validation
    if [[ -z "$param1" ]]; then
        echo "Error: Missing required parameter" >&2
        return 1
    fi
    
    # Main logic
    # ...
    
    return 0
}
```

## Integration Points

### Supported Version File Types
- **JSON** (package.json, composer.json): Uses jq for parsing
- **Text** (VERSION, README.md): Pattern-based replacement
- **PHP** (WordPress themes/plugins): Regex-based updates

### Git Workflow Support
- **Git Flow**: feature → develop → staging → master
- **GitHub Flow**: feature → main  
- **Custom workflows**: Configurable branch names
- **Local-only**: Works without remotes

### AI Integration
- OpenAI GPT models for commit message generation
- Diff analysis for intelligent suggestions
- Configurable prompt styles and models
- Cost-conscious API usage patterns

## Debugging Guidelines

### Verbose Mode
```bash
export MAIASS_VERBOSITY="debug"
./maiass.sh patch
```

### Common Debug Scenarios
1. **Version Detection Issues**: Check file permissions and format
2. **Git Operation Failures**: Verify repository state and permissions
3. **AI API Problems**: Validate API key and network connectivity
4. **Branch Logic Errors**: Test with different Git states

### Logging
```bash
export MAIASS_LOGGING="true"
export MAIASS_LOG_FILE="/tmp/maiass.log"
```

## Security Considerations

- API keys should never be committed to repositories
- Use environment variables or .env files (add to .gitignore)
- Validate all user inputs, especially version numbers
- Sanitize Git branch names and commit messages

## Performance Notes

- AI API calls are the primary performance bottleneck
- Version file parsing is generally fast
- Git operations depend on repository size
- Consider caching for repeated version lookups

---

*This guideline is specifically for the MAIASS application located in the `maiass/` folder of the workspace.*
