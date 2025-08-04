#!/bin/bash
# Test script for MAIASS Proxy functionality

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROXY_URL="${MAIASS_HOST:-http://localhost:8787}"
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

echo -e "${BLUE}=== MAIASS Proxy Test Script ===${NC}"
echo "Testing proxy at: $PROXY_URL"
echo ""

# Helper functions
run_test() {
    local test_name="$1"
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -e "${CYAN}Test $TEST_COUNT: $test_name${NC}"
}

pass_test() {
    local message="$1"
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "${GREEN}✓ $message${NC}"
}

fail_test() {
    local message="$1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "${RED}✗ $message${NC}"
}

warn_test() {
    local message="$1"
    echo -e "${YELLOW}⚠ $message${NC}"
}

# Generate machine fingerprint for tests
generate_test_fingerprint() {
    echo -n "$(uname -a)-$(whoami)-$(date +%Y%m%d)-test" | shasum -a 256 | cut -d' ' -f1
}

# Test 1: Check if proxy is running
run_test "Proxy connectivity"
HEALTH_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/health_response.txt "$PROXY_URL/v1/token" -X POST -H "Content-Type: application/json" -d '{}' 2>/dev/null)
HTTP_STATUS="${HEALTH_RESPONSE: -3}"
RESPONSE_BODY=$(cat /tmp/health_response.txt 2>/dev/null)

if [[ "$HTTP_STATUS" =~ ^[2-4][0-9][0-9]$ ]]; then
    pass_test "Proxy is responding (HTTP $HTTP_STATUS)"
else
    fail_test "Proxy not responding or returning error (HTTP $HTTP_STATUS)"
    echo "Response: $RESPONSE_BODY"
    echo -e "${RED}Cannot continue tests without proxy. Please start the proxy with: ./dev-proxy.sh${NC}"
    exit 1
fi

# Test 2: Test /v1/token endpoint (Anonymous subscription creation)
run_test "Anonymous subscription creation"
MACHINE_FINGERPRINT=$(generate_test_fingerprint)
echo "Using machine fingerprint: ${MACHINE_FINGERPRINT:0:16}..."

TOKEN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/token" \
    -H "Content-Type: application/json" \
    -d "{\"machine_fingerprint\":\"$MACHINE_FINGERPRINT\"}" 2>/dev/null)

TOKEN_STATUS=$(echo "$TOKEN_RESPONSE" | tail -n 1)
TOKEN_BODY=$(echo "$TOKEN_RESPONSE" | sed '$d')

echo "HTTP Status: $TOKEN_STATUS"
echo "Response: ${TOKEN_BODY:0:200}..."

if [[ "$TOKEN_STATUS" == "200" ]]; then
    # Parse the response
    if command -v jq >/dev/null 2>&1; then
        ANON_TOKEN=$(echo "$TOKEN_BODY" | jq -r '.token // empty')
        SUBSCRIPTION_ID=$(echo "$TOKEN_BODY" | jq -r '.subscription_id // empty')
        CREDITS=$(echo "$TOKEN_BODY" | jq -r '.credits_remaining // empty')
    else
        ANON_TOKEN=$(echo "$TOKEN_BODY" | grep -o '"token":"[^"]*"' | sed 's/"token":"//' | sed 's/"$//')
        SUBSCRIPTION_ID=$(echo "$TOKEN_BODY" | grep -o '"subscription_id":"[^"]*"' | sed 's/"subscription_id":"//' | sed 's/"$//')
        CREDITS=$(echo "$TOKEN_BODY" | grep -o '"credits_remaining":[0-9]*' | sed 's/"credits_remaining"://')
    fi
    
    if [[ -n "$ANON_TOKEN" && "$ANON_TOKEN" != "null" ]]; then
        pass_test "Anonymous token created: ${ANON_TOKEN:0:16}..."
        pass_test "Subscription ID: ${SUBSCRIPTION_ID:0:16}..."
        pass_test "Credits: $CREDITS"
    else
        fail_test "No token in response"
    fi
else
    fail_test "Token creation failed (HTTP $TOKEN_STATUS)"
    echo "Response: $TOKEN_BODY"
fi

# Test 3: Test duplicate subscription (should return existing)
run_test "Duplicate subscription handling"
DUPLICATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/token" \
    -H "Content-Type: application/json" \
    -d "{\"machine_fingerprint\":\"$MACHINE_FINGERPRINT\"}" 2>/dev/null)

DUPLICATE_STATUS=$(echo "$DUPLICATE_RESPONSE" | tail -n 1)
DUPLICATE_BODY=$(echo "$DUPLICATE_RESPONSE" | sed '$d')

if [[ "$DUPLICATE_STATUS" == "200" ]]; then
    if command -v jq >/dev/null 2>&1; then
        DUPLICATE_TOKEN=$(echo "$DUPLICATE_BODY" | jq -r '.token // empty')
    else
        DUPLICATE_TOKEN=$(echo "$DUPLICATE_BODY" | grep -o '"token":"[^"]*"' | sed 's/"token":"//' | sed 's/"$//')
    fi
    
    if [[ "$DUPLICATE_TOKEN" == "$ANON_TOKEN" ]]; then
        pass_test "Returned same token for duplicate request"
    else
        warn_test "Different token returned for same fingerprint"
    fi
else
    fail_test "Duplicate request failed (HTTP $DUPLICATE_STATUS)"
fi

# Test 4: Test invalid token request
run_test "Invalid token request (missing fingerprint)"
INVALID_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/token" \
    -H "Content-Type: application/json" \
    -d "{}" 2>/dev/null)

INVALID_STATUS=$(echo "$INVALID_RESPONSE" | tail -n 1)
INVALID_BODY=$(echo "$INVALID_RESPONSE" | sed '$d')

if [[ "$INVALID_STATUS" == "400" ]]; then
    pass_test "Correctly rejected request without machine fingerprint (HTTP 400)"
else
    fail_test "Should return 400 for missing fingerprint, got HTTP $INVALID_STATUS"
fi

# Test 5: Test AI endpoint without authentication
run_test "AI endpoint without authentication"
NO_AUTH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"test"}]}' 2>/dev/null)

NO_AUTH_STATUS=$(echo "$NO_AUTH_RESPONSE" | tail -n 1)

if [[ "$NO_AUTH_STATUS" == "401" ]]; then
    pass_test "Correctly rejected request without API key (HTTP 401)"
else
    fail_test "Should return 401 for missing auth, got HTTP $NO_AUTH_STATUS"
fi

# Test 6: Test AI endpoint with invalid token
run_test "AI endpoint with invalid token"
INVALID_TOKEN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer invalid_token_123" \
    -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"test"}]}' 2>/dev/null)

INVALID_TOKEN_STATUS=$(echo "$INVALID_TOKEN_RESPONSE" | tail -n 1)

if [[ "$INVALID_TOKEN_STATUS" == "403" ]]; then
    pass_test "Correctly rejected invalid token (HTTP 403)"
else
    fail_test "Should return 403 for invalid token, got HTTP $INVALID_TOKEN_STATUS"
fi

# Test 7: Test AI endpoint with anonymous token but missing fingerprint
if [[ -n "$ANON_TOKEN" ]]; then
    run_test "AI endpoint with anonymous token (missing fingerprint)"
    NO_FINGERPRINT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ANON_TOKEN" \
        -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"test"}]}' 2>/dev/null)

    NO_FINGERPRINT_STATUS=$(echo "$NO_FINGERPRINT_RESPONSE" | tail -n 1)
    NO_FINGERPRINT_BODY=$(echo "$NO_FINGERPRINT_RESPONSE" | sed '$d')

    if [[ "$NO_FINGERPRINT_STATUS" == "400" ]]; then
        pass_test "Correctly rejected anonymous token without fingerprint (HTTP 400)"
    else
        fail_test "Should return 400 for missing fingerprint, got HTTP $NO_FINGERPRINT_STATUS"
        echo "Response: ${NO_FINGERPRINT_BODY:0:200}..."
    fi

    # Test 8: Test AI endpoint with anonymous token and correct fingerprint
    run_test "AI endpoint with anonymous token and fingerprint"
    VALID_ANON_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ANON_TOKEN" \
        -H "X-Machine-Fingerprint: $MACHINE_FINGERPRINT" \
        -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"Hello, this is a test"}],"max_tokens":50}' 2>/dev/null)

    VALID_ANON_STATUS=$(echo "$VALID_ANON_RESPONSE" | tail -n 1)
    VALID_ANON_BODY=$(echo "$VALID_ANON_RESPONSE" | sed '$d')

    echo "HTTP Status: $VALID_ANON_STATUS"
    echo "Response: ${VALID_ANON_BODY:0:300}..."

    if [[ "$VALID_ANON_STATUS" == "200" ]]; then
        # Check if response contains OpenAI-like structure
        if echo "$VALID_ANON_BODY" | grep -q '"choices"' && echo "$VALID_ANON_BODY" | grep -q '"content"'; then
            pass_test "AI request with anonymous token successful"
            
            # Extract token usage if available
            if command -v jq >/dev/null 2>&1; then
                TOKENS_USED=$(echo "$VALID_ANON_BODY" | jq -r '.usage.total_tokens // empty' 2>/dev/null)
                TOKENS_REMAINING=$(echo "$VALID_ANON_BODY" | jq -r '.tokens_remaining // empty' 2>/dev/null)
                if [[ -n "$TOKENS_USED" && "$TOKENS_USED" != "null" ]]; then
                    pass_test "Tokens used: $TOKENS_USED"
                fi
                if [[ -n "$TOKENS_REMAINING" && "$TOKENS_REMAINING" != "null" ]]; then
                    pass_test "Tokens remaining: $TOKENS_REMAINING"
                fi
            fi
        else
            fail_test "Response doesn't contain expected AI structure"
        fi
    else
        fail_test "AI request failed (HTTP $VALID_ANON_STATUS)"
        
        # Try to extract error details
        if command -v jq >/dev/null 2>&1; then
            ERROR_MSG=$(echo "$VALID_ANON_BODY" | jq -r '.error.message // empty' 2>/dev/null)
            ERROR_CODE=$(echo "$VALID_ANON_BODY" | jq -r '.error.code // empty' 2>/dev/null)
            if [[ -n "$ERROR_MSG" && "$ERROR_MSG" != "null" ]]; then
                echo "Error: $ERROR_MSG"
            fi
            if [[ -n "$ERROR_CODE" && "$ERROR_CODE" != "null" ]]; then
                echo "Error Code: $ERROR_CODE"
            fi
        fi
    fi

    # Test 9: Test fingerprint mismatch
    run_test "AI endpoint with wrong fingerprint"
    WRONG_FINGERPRINT="wrong_fingerprint_test_123"
    WRONG_FINGERPRINT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ANON_TOKEN" \
        -H "X-Machine-Fingerprint: $WRONG_FINGERPRINT" \
        -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"test"}]}' 2>/dev/null)

    WRONG_FINGERPRINT_STATUS=$(echo "$WRONG_FINGERPRINT_RESPONSE" | tail -n 1)

    if [[ "$WRONG_FINGERPRINT_STATUS" == "403" ]]; then
        pass_test "Correctly rejected wrong fingerprint (HTTP 403)"
    else
        fail_test "Should return 403 for wrong fingerprint, got HTTP $WRONG_FINGERPRINT_STATUS"
    fi
else
    warn_test "Skipping anonymous token tests (no token created)"
fi

# Test 10: Test rate limiting (if implemented)
run_test "Basic rate limiting test"
echo "Making multiple rapid requests to test rate limiting..."

RATE_LIMIT_COUNT=0
for i in {1..5}; do
    RATE_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$PROXY_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer invalid_token" \
        -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"test"}]}' 2>/dev/null)
    
    if [[ "$RATE_RESPONSE" == "429" ]]; then
        RATE_LIMIT_COUNT=$((RATE_LIMIT_COUNT + 1))
    fi
    sleep 0.1
done

if [[ $RATE_LIMIT_COUNT -gt 0 ]]; then
    pass_test "Rate limiting detected ($RATE_LIMIT_COUNT/5 requests limited)"
else
    warn_test "No rate limiting detected (may not be implemented)"
fi

# Test 11: Test various HTTP methods
run_test "HTTP method validation"
GET_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null -X GET "$PROXY_URL/v1/chat/completions" 2>/dev/null)
if [[ "$GET_RESPONSE" == "405" ]]; then
    pass_test "Correctly rejected GET method (HTTP 405)"
else
    warn_test "GET method returned HTTP $GET_RESPONSE (expected 405)"
fi

# Test 12: Test malformed JSON
run_test "Malformed JSON handling"
MALFORMED_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer test_token" \
    -d '{"model":"gpt-3.5-turbo","messages":[{"role":"user","content":"test"}' 2>/dev/null)

MALFORMED_STATUS=$(echo "$MALFORMED_RESPONSE" | tail -n 1)
if [[ "$MALFORMED_STATUS" == "400" ]]; then
    pass_test "Correctly rejected malformed JSON (HTTP 400)"
else
    warn_test "Malformed JSON returned HTTP $MALFORMED_STATUS (expected 400)"
fi

# Cleanup
rm -f /tmp/health_response.txt

# Summary
echo ""
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "Total tests: $TEST_COUNT"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All tests passed! 🎉${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please check the proxy implementation.${NC}"
    exit 1
fi
