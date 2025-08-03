# GitHub Copilot Guidelines - Complete MAIASS Ecosystem

This document provides comprehensive guidance for GitHub Copilot when working across the entire MAIASS ecosystem workspace containing multiple related projects.

## Workspace Structure Overview

The workspace contains four interconnected projects:

```
/workspace
├── bashmaiass/                    # Core application - Bash-based Git workflow automation
├── homebrew-bashmaiass/          # Homebrew distribution formula and scripts  
├── maiass-proxy/             # Node.js API proxy for OpenAI subscriptions
└── testrepos/               # Sandbox repositories for testing MAIASS functionality
```

## Project Relationships

### maiass/ → Core Application
- **Language**: Bash shell script
- **Purpose**: Git workflow automation with AI-Augmented commit messages
- **Key Files**: `maiass.sh`, `install.sh`, `test_maiass.sh`
- **Dependencies**: Bash, Git, jq, standard Unix utilities

### homebrew-maiass/ → Distribution
- **Language**: Ruby (Homebrew formula)
- **Purpose**: Package MAIASS for Homebrew installation
- **Key Files**: `Formula/maiass.rb`, `updatemyass.sh`
- **Dependencies**: Homebrew ecosystem

### maiass-proxy/ → API Proxy Service
- **Language**: JavaScript/Node.js (Cloudflare Workers)
- **Purpose**: Proxy OpenAI API calls with subscription management
- **Key Files**: `src/index.js`, `package.json`, `wrangler.jsonc`
- **Dependencies**: Cloudflare Workers runtime, Vitest for testing

### testrepos/ → Testing Environment
- **Language**: Mixed (test scenarios)
- **Purpose**: Isolated environments for testing MAIASS functionality
- **Key Files**: Various repo types with different version management patterns
- **Dependencies**: Whatever MAIASS is being tested against

## Cross-Project Development Patterns

### Version Synchronization
When updating versions across the ecosystem:

1. **maiass/package.json** - Primary version source
2. **homebrew-maiass/Formula/maiass.rb** - Must match maiass version
3. **maiass-proxy/package.json** - Independent versioning
4. **testrepos/** - Test data, no versioning

### Development Workflow
```bash
# 1. Develop in maiass/
cd maiass/
./maiass.sh patch  # Use MAIASS to version itself

# 2. Test with testrepos/
cd ../testrepos/package-json-repo/
../../maiass/maiass.sh patch  # Test against sandbox

# 3. Update Homebrew formula
cd ../homebrew-maiass/
./updatemyass.sh  # Updates formula with latest version

# 4. Deploy proxy if API changes
cd ../maiass-proxy/
npm run deploy  # Deploy to Cloudflare Workers
```

## Environment Configuration

### Global Environment Variables
These affect the entire ecosystem:

```bash
# Core MAIASS configuration
export MAIASS_AI_TOKEN="your-key"           # For maiass/ and maiass-proxy/
export MAIASS_VERBOSITY="normal"                # Debugging across projects

# Development paths
export PATH="$PATH:/path/to/maiass"              # For testing unreleased versions
export MAIASS_TEST_REPOS="/path/to/testrepos"   # For automated testing
```

### Project-Specific Configuration

#### maiass/ Configuration
```bash
# Primary development environment
export MAIASS_MASTERBRANCH="main"
export MAIASS_VERSION_PRIMARY_FILE="package.json"
export MAIASS_AI_MODE="ask"
```

#### maiass-proxy/ Configuration  
```bash
# Cloudflare Workers environment
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_API_TOKEN="your-api-token"
```

#### homebrew-maiass/ Configuration
```bash
# Homebrew development
export HOMEBREW_GITHUB_API_TOKEN="your-token"   # For publishing
```

## Testing Strategy

### Comprehensive Testing Flow
1. **Unit Tests**: Each project has its own test suite
2. **Integration Tests**: Cross-project functionality
3. **End-to-End Tests**: Full workflow with testrepos/

### Testing Commands
```bash
# Test core application
cd maiass/ && ./test_maiass.sh

# Test proxy service
cd maiass-proxy/ && npm test

# Test Homebrew formula (local install)
cd homebrew-maiass/ && brew install --build-from-source ./Formula/maiass.rb

# Test against sandbox repos
cd testrepos/package-json-repo/ && maiass patch --dry-run
```

### Test Repository Patterns
The `testrepos/` folder contains various scenarios:

- **package-json-repo/**: Standard Node.js project
- **wordpress-plugin/**: WordPress plugin with custom version patterns  
- **simple-repo/**: Minimal Git repository
- **no-version-repo/**: Repository without version management

## API Integration Architecture

### OpenAI API Flow
```
maiass/ script
    ↓ (HTTP request)
maiass-proxy/ (Cloudflare Worker)
    ↓ (proxied request)
OpenAI API
    ↓ (response)
maiass-proxy/ (rate limiting, billing)
    ↓ (filtered response)  
maiass/ script
```

### Configuration Sync
- `maiass/` contains the AI prompt engineering
- `maiass-proxy/` handles authentication and rate limiting
- Both must stay synchronized for API compatibility

## Deployment Considerations

### Release Process
1. **Development**: Work in `maiass/` with feature branches
2. **Testing**: Validate against `testrepos/` scenarios
3. **Proxy Updates**: Deploy `maiass-proxy/` if API changes needed
4. **Distribution**: Update `homebrew-maiass/` formula
5. **Release**: Tag and publish from `maiass/`

### Rollback Strategy
- Keep previous versions in Homebrew formula history
- Maintain API compatibility in maiass-proxy for at least one major version
- Test rollback scenarios in testrepos/

## Security Model

### API Key Management
- **maiass/**: Reads from environment or .env files
- **maiass-proxy/**: Uses Cloudflare Workers secrets
- **Never commit keys to any repository**

### Cross-Origin Security
- maiass-proxy/ validates requests from authorized sources
- Rate limiting prevents abuse
- Audit logging for security monitoring

## Debugging Across Projects

### Debug Mode Activation
```bash
# Enable verbose logging across all projects
export MAIASS_VERBOSITY="debug"
export MAIASS_LOGGING="true" 
export NODE_ENV="development"  # For maiass-proxy
```

### Common Debug Scenarios

#### Issue: MAIASS not finding version files
```bash
# Check from maiass/
./maiass.sh --version-only

# Test in testrepos/
cd ../testrepos/package-json-repo/
../../maiass/maiass.sh --version-only
```

#### Issue: API proxy not responding
```bash
# Check proxy logs
cd maiass-proxy/
wrangler tail

# Test proxy directly
curl -X POST https://your-proxy.workers.dev/api/chat/completions
```

#### Issue: Homebrew formula outdated
```bash
# Update formula
cd homebrew-maiass/
./updatemyass.sh
brew uninstall maiass
brew install maiass  # Should get latest version
```

## Performance Optimization

### Caching Strategy
- **maiass/**: Cache version file parsing results
- **maiass-proxy/**: Implement response caching for identical requests
- **homebrew-maiass/**: Leverage Homebrew's built-in caching

### Resource Usage
- **maiass/**: Minimize external process calls
- **maiass-proxy/**: Optimize cold start times
- **testrepos/**: Keep test repositories small

## Code Quality Standards

### Bash (maiass/)
- Use `set -e` for error handling
- Validate all user inputs
- Follow shell scripting best practices
- Include comprehensive error messages

### JavaScript (maiass-proxy/)
- Use ES6+ features where appropriate
- Implement proper error handling
- Follow Cloudflare Workers best practices
- Include unit tests for all functions

### Ruby (homebrew-maiass/)
- Follow Homebrew formula conventions
- Test formula with various macOS versions
- Keep dependencies minimal

### General Across All Projects
- Consistent code formatting
- Meaningful commit messages (use MAIASS itself!)
- Comprehensive documentation
- Security-first development

## Monitoring & Maintenance

### Health Checks
- **maiass/**: Version detection accuracy
- **maiass-proxy/**: API response times and error rates  
- **homebrew-maiass/**: Installation success rates
- **testrepos/**: Test scenario coverage

### Update Cycles
- **Weekly**: Security updates and dependency bumps
- **Monthly**: Feature releases and improvements  
- **Quarterly**: Major version updates and architecture reviews

---

*This guideline covers the complete MAIASS ecosystem spanning all four workspace folders. Use this for understanding cross-project relationships and maintaining consistency across the entire system.*
