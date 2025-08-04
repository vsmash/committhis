#!/bin/bash

# Test the retry mechanism for AI suggestions
# This script simulates the scenario where an invalid token triggers anonymous subscription creation

echo "=== Testing AI Retry Mechanism ==="

# Set up environment
export MAIASS_VERBOSITY=debug
export MAIASS_AI_MODE=ask
export MAIASS_AI_TOKEN=invalid_token_test  # This will trigger the error handling
export MAIASS_HOST=http://localhost:8787

# Source the required files
source lib/config/envars.sh
source lib/config/colours.sh  
source lib/core/logger.sh
source lib/utils/utils.sh
source lib/core/ai.sh

echo "Testing with invalid token: $MAIASS_AI_TOKEN"
echo "This should trigger the error handling flow..."
echo ""

# Create a simple git repo with changes to test
git add -A >/dev/null 2>&1

# Test the get_ai_commit_suggestion function directly
echo "=== Direct function test ==="
if result=$(get_ai_commit_suggestion); then
    echo "SUCCESS: Function returned with output: '$result'"
    exit 0
else
    echo "FAILED: Function returned error code $?"
    exit 1
fi
