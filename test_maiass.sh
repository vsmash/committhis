#!/bin/bash
# Simple test script for MAIASS functionality

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== MAIASS Test Script ===${NC}"
echo "This script tests basic MAIASS functionality"
echo

# Create a temporary test directory
TEST_DIR=$(mktemp -d)
echo -e "${BLUE}Creating test environment in ${TEST_DIR}${NC}"

# Initialize a git repository
cd "$TEST_DIR" || exit 1
git init
git config user.name "MAIASS Test"
git config user.email "test@example.com"

# Create a simple package.json with version
echo '{
  "name": "maiass-test",
  "version": "1.0.0",
  "description": "Test project for MAIASS"
}' > package.json

# Create a README.md file
echo "# MAIASS Test Project
Version: 1.0.0
" > README.md

# Initial commit
git add .
git commit -m "Initial commit"

# Test 1: Check if MAIASS can detect the version
echo -e "\n${BLUE}Test 1: Detecting version${NC}"
VERSION=$(maiass --version-only 2>/dev/null)
if [[ $? -eq 0 && -n "$VERSION" ]]; then
    echo -e "${GREEN}✓ MAIASS detected version: $VERSION${NC}"
else
    echo -e "${RED}✗ Failed to detect version${NC}"
fi

# Test 2: Bump patch version
echo -e "\n${BLUE}Test 2: Bumping patch version${NC}"
# Set environment variables for the test
export MAIASS_VERSION_PRIMARY_FILE="package.json"
export MAIASS_VERSION_PRIMARY_TYPE="json"
export MAIASS_VERSION_SECONDARY_FILES="README.md:txt:Version: "
export MAIASS_VERBOSITY="brief"
export MAIASS_OPENAI_MODE="off"

# Run MAIASS to bump patch version
maiass patch --no-push --no-tag

# Verify version was updated in package.json
NEW_VERSION=$(grep -o '"version": "[^"]*"' package.json | cut -d'"' -f4)
if [[ "$NEW_VERSION" == "1.0.1" ]]; then
    echo -e "${GREEN}✓ Package.json version updated to $NEW_VERSION${NC}"
else
    echo -e "${RED}✗ Package.json version not updated correctly: $NEW_VERSION${NC}"
fi

# Verify version was updated in README.md
README_VERSION=$(grep "Version:" README.md | cut -d' ' -f2)
if [[ "$README_VERSION" == "1.0.1" ]]; then
    echo -e "${GREEN}✓ README.md version updated to $README_VERSION${NC}"
else
    echo -e "${RED}✗ README.md version not updated correctly: $README_VERSION${NC}"
fi

# Test 3: Set specific version
echo -e "\n${BLUE}Test 3: Setting specific version${NC}"
maiass 2.0.0 --no-push --no-tag

# Verify version was updated in package.json
NEW_VERSION=$(grep -o '"version": "[^"]*"' package.json | cut -d'"' -f4)
if [[ "$NEW_VERSION" == "2.0.0" ]]; then
    echo -e "${GREEN}✓ Package.json version updated to $NEW_VERSION${NC}"
else
    echo -e "${RED}✗ Package.json version not updated correctly: $NEW_VERSION${NC}"
fi

# Verify version was updated in README.md
README_VERSION=$(grep "Version:" README.md | cut -d' ' -f2)
if [[ "$README_VERSION" == "2.0.0" ]]; then
    echo -e "${GREEN}✓ README.md version updated to $README_VERSION${NC}"
else
    echo -e "${RED}✗ README.md version not updated correctly: $README_VERSION${NC}"
fi

# Clean up
echo -e "\n${BLUE}Cleaning up test environment${NC}"
cd - > /dev/null
rm -rf "$TEST_DIR"

echo -e "\n${BLUE}Tests completed${NC}"
