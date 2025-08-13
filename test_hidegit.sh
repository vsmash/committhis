#!/bin/bash

# Test script to demonstrate hidegit functionality
# This shows how git output is handled with hidegit=true vs hidegit=false

# Source the necessary libraries
source "$(dirname "$0")/lib/core/init.sh"
source "$(dirname "$0")/lib/core/git.sh"
source "$(dirname "$0")/lib/core/logger.sh"

echo "=== Testing hidegit functionality ==="
echo

# Test 1: hidegit=false (default behavior)
echo "1. Testing with hidegit=false (normal output):"
export hidegit="false"
export verbosity_level="normal"
export enable_logging="true"
export log_file="test_hidegit.log"

echo "Running: git status"
run_git_command "git status" "normal"
echo

# Test 2: hidegit=true (hidden output, but logged)
echo "2. Testing with hidegit=true (hidden output, logged to file):"
export hidegit="true"

echo "Running: git status (output should be hidden)"
run_git_command "git status" "normal"
echo "✓ Git command completed (output was hidden)"
echo

# Show what was logged
if [[ -f "test_hidegit.log" ]]; then
    echo "3. Contents logged to test_hidegit.log:"
    echo "---"
    tail -10 test_hidegit.log
    echo "---"
    echo
fi

echo "=== Test completed ==="
echo "To use hidegit in your workflow, set: export MAIASS_HIDEGIT=true"
echo "Or add MAIASS_HIDEGIT=true to your environment"
