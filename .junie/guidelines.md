# MAIASS Development Guidelines

This document provides essential information for developers working on the MAIASS (Modular AI-Assisted Semantic Savant) project.

## Build/Configuration Instructions

### Local Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/vsmash/maiass.git
   cd maiass
   ```

2. Development Scripts:
   - `./maiass.sh` - Main script for running MAIASS
   - `dma` - Development alternative to `./maiass.sh` (symlink in development environment)
   
   > **Note:** `dma` is a symlink to `./maiass.sh` in the development environment. It's not included in the repository documentation but works the same way as `./maiass.sh`.

3. Environment Variables:
   MAIASS uses several environment variables for configuration. The most important ones are:
   
   ```bash
   # Version management
   export MAIASS_VERSION_PRIMARY_FILE="package.json"  # Primary file containing version
   export MAIASS_VERSION_PRIMARY_TYPE="json"          # Type of primary version file
   
   # OpenAI integration (for AI-powered commit messages)
   export MAIASS_AI_TOKEN="your-api-key"          # Your OpenAI API key
   export MAIASS_AI_MODE="ask"                    # Mode for AI integration (ask, auto, off)
   
   # Verbosity
   export MAIASS_VERBOSITY="brief"                    # Output verbosity (brief, normal, verbose)
   ```

## Testing Information

### Running Tests

MAIASS includes a test script that verifies basic functionality:

```bash
# Run the test script
./test_maiass.sh
```

The test script creates a temporary test environment and verifies:
1. Version detection
2. Patch version bumping
3. Setting specific versions

### Adding New Tests

When adding new tests to `test_maiass.sh`:

1. Follow the existing pattern of creating isolated test environments
2. Use clear test descriptions with the echo statements
3. Include verification steps for each test
4. Clean up temporary files after tests complete

Example test structure:

```bash
echo -e "\n${BLUE}Test X: Description of test${NC}"
# Set environment variables for the test
export MAIASS_VARIABLE="value"

# Run MAIASS with specific parameters
"$MAIASS_SCRIPT" parameter --flag

# Verify results
RESULT=$(grep "pattern" file)
if [[ "$RESULT" == "expected" ]]; then
    echo -e "${GREEN}✓ Test passed${NC}"
else
    echo -e "${RED}✗ Test failed${NC}"
fi
```

## Additional Development Information

### Code Style

- Shell scripts follow standard Bash best practices
- Use 2-space indentation for shell scripts
- Include comments for complex logic
- Use meaningful variable names

### Deployment Process

The project includes a deployment script (`scripts/dply.sh`) that handles:
- Merging from staging to main
- Ensuring the correct README for each target brand
- Pushing to multiple Git remotes

### Debugging Tips

1. Increase verbosity for more detailed output:
   ```bash
   export MAIASS_VERBOSITY="verbose"
   ```

2. Use the `--dry-run` flag to see what would happen without making changes:
   ```bash
   ./maiass.sh patch --dry-run
   ```

3. Check the version detection with:
   ```bash
   ./maiass.sh --version-only
   ```

### Common Issues

- If version detection fails, verify that the primary version file exists and is correctly formatted
- For OpenAI integration issues, check that your API key is correctly set and has sufficient permissions
- If you encounter Git-related errors, ensure you're in a valid Git repository with proper permissions
