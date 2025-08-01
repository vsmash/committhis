# BASHMAIASS Development Guidelines

This document provides essential information for developers working on the BASHMAIASS (Modular AI-Augmented Semantic Scribe) project.

## Build/Configuration Instructions

### Local Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/vsmash/bashmaiass.git
   cd bashmaiass
   ```

2. Development Scripts:
   - `./bashmaiass.sh` - Main script for running BASHMAIASS
   - `dma` - Development alternative to `./bashmaiass.sh` (symlink in development environment)
   
   > **Note:** `dma` is a symlink to `./bashmaiass.sh` in the development environment. It's not included in the repository documentation but works the same way as `./bashmaiass.sh`.

3. Environment Variables:
   BASHMAIASS uses several environment variables for configuration. The most important ones are:
   
   ```bash
   # Version management
   export BASHMAIASS_VERSION_PRIMARY_FILE="package.json"  # Primary file containing version
   export BASHMAIASS_VERSION_PRIMARY_TYPE="json"          # Type of primary version file
   
   # OpenAI integration (for AI-powered commit messages)
   export BASHMAIASS_AI_TOKEN="your-api-key"          # Your OpenAI API key
   export BASHMAIASS_AI_MODE="ask"                    # Mode for AI integration (ask, auto, off)
   
   # Verbosity
   export BASHMAIASS_VERBOSITY="brief"                    # Output verbosity (brief, normal, verbose)
   ```

## Testing Information

### Running Tests

BASHMAIASS includes a test script that verifies basic functionality:

```bash
# Run the test script
./test_bashmaiass.sh
```

The test script creates a temporary test environment and verifies:
1. Version detection
2. Patch version bumping
3. Setting specific versions

### Adding New Tests

When adding new tests to `test_bashmaiass.sh`:

1. Follow the existing pattern of creating isolated test environments
2. Use clear test descriptions with the echo statements
3. Include verification steps for each test
4. Clean up temporary files after tests complete

Example test structure:

```bash
echo -e "\n${BLUE}Test X: Description of test${NC}"
# Set environment variables for the test
export BASHMAIASS_VARIABLE="value"

# Run BASHMAIASS with specific parameters
"$BASHMAIASS_SCRIPT" parameter --flag

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
   export BASHMAIASS_VERBOSITY="verbose"
   ```

2. Use the `--dry-run` flag to see what would happen without making changes:
   ```bash
   ./bashmaiass.sh patch --dry-run
   ```

3. Check the version detection with:
   ```bash
   ./bashmaiass.sh --version-only
   ```

### Common Issues

- If version detection fails, verify that the primary version file exists and is correctly formatted
- For OpenAI integration issues, check that your API key is correctly set and has sufficient permissions
- If you encounter Git-related errors, ensure you're in a valid Git repository with proper permissions
