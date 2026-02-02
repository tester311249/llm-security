#!/usr/bin/env bash
# validate-schema.sh - Validate branch protection YAML schema
#
# This script validates that a branch protection configuration file
# contains all required fields and has correct data types.
#
# Usage: validate-schema.sh [config-file]
#
# Arguments:
#   config-file - Path to YAML/JSON config (default: .github/branch-protection.yml)
#
# Exit Codes:
#   0 - Schema validation passed
#   1 - Schema validation failed
#   2 - Error (missing tools, file not found, etc.)

set -euo pipefail

CONFIG_FILE="${1:-.github/branch-protection.yml}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Validating schema for: $CONFIG_FILE"
echo ""

# Check if file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Configuration file not found: $CONFIG_FILE${NC}"
    exit 2
fi

# Check if yq is installed for YAML files
if [[ "$CONFIG_FILE" =~ \.ya?ml$ ]] && ! command -v yq &> /dev/null; then
    echo -e "${RED}❌ yq is required for YAML parsing${NC}"
    echo "   Install: https://github.com/mikefarah/yq#install"
    exit 2
fi

# Check if jq is installed for JSON files
if [[ "$CONFIG_FILE" =~ \.json$ ]] && ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ jq is required for JSON parsing${NC}"
    echo "   Install: https://stedolan.github.io/jq/download/"
    exit 2
fi

VALIDATION_FAILED=false

# Helper function to get value from config
get_value() {
    local field=$1
    if [[ "$CONFIG_FILE" =~ \.ya?ml$ ]]; then
        yq eval "$field" "$CONFIG_FILE" 2>/dev/null || echo "null"
    else
        jq -r "$field" "$CONFIG_FILE" 2>/dev/null || echo "null"
    fi
}

# Validate syntax
echo "Step 1: Validating file syntax..."
if [[ "$CONFIG_FILE" =~ \.ya?ml$ ]]; then
    if ! yq eval '.' "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}❌ Invalid YAML syntax${NC}"
        exit 2
    fi
else
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        echo -e "${RED}❌ Invalid JSON syntax${NC}"
        exit 2
    fi
fi
echo -e "${GREEN}✅ Syntax valid${NC}"
echo ""

# Required fields
echo "Step 2: Checking required fields..."

REQUIRED_FIELDS=(
    ".branch_protection.branch"
    ".branch_protection.required_pull_request_reviews"
    ".branch_protection.required_pull_request_reviews.require_code_owner_reviews"
    ".branch_protection.required_pull_request_reviews.required_approving_review_count"
    ".branch_protection.enforce_admins"
    ".branch_protection.required_conversation_resolution"
    ".branch_protection.allow_force_pushes"
    ".branch_protection.allow_deletions"
)

for field in "${REQUIRED_FIELDS[@]}"; do
    value=$(get_value "$field")
    if [ "$value" = "null" ]; then
        echo -e "${RED}❌ Missing required field: $field${NC}"
        VALIDATION_FAILED=true
    else
        echo -e "${GREEN}✅ Found: $field${NC} = $value"
    fi
done
echo ""

# Validate boolean fields
echo "Step 3: Validating boolean fields..."

BOOLEAN_FIELDS=(
    ".branch_protection.required_pull_request_reviews.dismiss_stale_reviews"
    ".branch_protection.required_pull_request_reviews.require_code_owner_reviews"
    ".branch_protection.required_pull_request_reviews.require_last_push_approval"
    ".branch_protection.enforce_admins"
    ".branch_protection.required_conversation_resolution"
    ".branch_protection.allow_force_pushes"
    ".branch_protection.allow_deletions"
    ".branch_protection.block_creations"
    ".branch_protection.required_linear_history"
    ".branch_protection.lock_branch"
)

for field in "${BOOLEAN_FIELDS[@]}"; do
    value=$(get_value "$field")
    if [ "$value" != "null" ] && [ "$value" != "true" ] && [ "$value" != "false" ]; then
        echo -e "${RED}❌ $field must be boolean (true/false), got: $value${NC}"
        VALIDATION_FAILED=true
    else
        echo -e "${GREEN}✅ $field${NC}: $value"
    fi
done
echo ""

# Validate integer fields
echo "Step 4: Validating integer fields..."

REVIEW_COUNT=$(get_value ".branch_protection.required_pull_request_reviews.required_approving_review_count")
if [ "$REVIEW_COUNT" != "null" ]; then
    if ! [[ "$REVIEW_COUNT" =~ ^[0-9]+$ ]] || [ "$REVIEW_COUNT" -lt 1 ]; then
        echo -e "${RED}❌ required_approving_review_count must be an integer >= 1, got: $REVIEW_COUNT${NC}"
        VALIDATION_FAILED=true
    else
        echo -e "${GREEN}✅ required_approving_review_count${NC}: $REVIEW_COUNT"
    fi
fi
echo ""

# Validate string fields
echo "Step 5: Validating string fields..."

BRANCH=$(get_value ".branch_protection.branch")
if [ "$BRANCH" = "null" ] || [ -z "$BRANCH" ]; then
    echo -e "${RED}❌ branch must be a non-empty string${NC}"
    VALIDATION_FAILED=true
else
    echo -e "${GREEN}✅ branch${NC}: $BRANCH"
fi
echo ""

# Security best practices check
echo "Step 6: Checking security best practices..."

WARNINGS=0

REQUIRE_CODEOWNERS=$(get_value ".branch_protection.required_pull_request_reviews.require_code_owner_reviews")
if [ "$REQUIRE_CODEOWNERS" != "true" ]; then
    echo -e "${YELLOW}⚠️  Warning: require_code_owner_reviews is not enabled${NC}"
    ((WARNINGS++))
else
    echo -e "${GREEN}✅ Code owner reviews required${NC}"
fi

ENFORCE_ADMINS=$(get_value ".branch_protection.enforce_admins")
if [ "$ENFORCE_ADMINS" != "true" ]; then
    echo -e "${YELLOW}⚠️  Warning: enforce_admins is not enabled (admins can bypass rules)${NC}"
    ((WARNINGS++))
else
    echo -e "${GREEN}✅ Admin enforcement enabled${NC}"
fi

ALLOW_FORCE_PUSH=$(get_value ".branch_protection.allow_force_pushes")
if [ "$ALLOW_FORCE_PUSH" = "true" ]; then
    echo -e "${YELLOW}⚠️  Warning: Force pushes are allowed (potential security risk)${NC}"
    ((WARNINGS++))
else
    echo -e "${GREEN}✅ Force pushes disabled${NC}"
fi

ALLOW_DELETE=$(get_value ".branch_protection.allow_deletions")
if [ "$ALLOW_DELETE" = "true" ]; then
    echo -e "${YELLOW}⚠️  Warning: Branch deletions are allowed (potential security risk)${NC}"
    ((WARNINGS++))
else
    echo -e "${GREEN}✅ Branch deletions disabled${NC}"
fi

LINEAR_HISTORY=$(get_value ".branch_protection.required_linear_history")
if [ "$LINEAR_HISTORY" = "true" ]; then
    echo -e "${GREEN}✅ Linear history required${NC}"
fi

REQUIRED_CONVERSATIONS=$(get_value ".branch_protection.required_conversation_resolution")
if [ "$REQUIRED_CONVERSATIONS" = "true" ]; then
    echo -e "${GREEN}✅ Conversation resolution required${NC}"
fi

echo ""

# Final result
if [ "$VALIDATION_FAILED" = true ]; then
    echo -e "${RED}❌ Schema validation failed${NC}"
    exit 1
else
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}✅ Schema validation passed with $WARNINGS warning(s)${NC}"
    else
        echo -e "${GREEN}✅ Schema validation passed - all checks successful${NC}"
    fi
    exit 0
fi
