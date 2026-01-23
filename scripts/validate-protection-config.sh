#!/bin/bash
# validate-protection-config.sh - Validate branch protection configuration
# This script performs comprehensive validation of branch-protection.json

set -e

CONFIG_FILE="${1:-config/branch-protection.json}"

echo "🔍 Branch Protection Configuration Validator"
echo "============================================="
echo ""

# Check if file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Configuration file not found: $CONFIG_FILE"
  exit 1
fi

echo "✅ Configuration file found: $CONFIG_FILE"
echo ""

# Validate JSON syntax
echo "📋 Step 1: Validating JSON syntax..."
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  echo "❌ Invalid JSON syntax"
  exit 1
fi
echo "✅ JSON syntax valid"
echo ""

# Check required fields
echo "📋 Step 2: Checking required fields..."
REQUIRED_FIELDS=(
  "required_pull_request_reviews"
  "required_pull_request_reviews.require_code_owner_reviews"
  "required_pull_request_reviews.required_approving_review_count"
  "enforce_admins"
  "required_conversation_resolution"
  "allow_force_pushes"
  "allow_deletions"
)

ALL_VALID=true
for field in "${REQUIRED_FIELDS[@]}"; do
  if jq -e ".$field" "$CONFIG_FILE" >/dev/null 2>&1; then
    VALUE=$(jq -r ".$field" "$CONFIG_FILE")
    echo "  ✅ $field: $VALUE"
  else
    echo "  ❌ Missing: $field"
    ALL_VALID=false
  fi
done

if [ "$ALL_VALID" = false ]; then
  echo ""
  echo "❌ Validation failed - missing required fields"
  exit 1
fi
echo ""

# Validate value types and ranges
echo "📋 Step 3: Validating field types and values..."

# Check review count is a number >= 1
REVIEW_COUNT=$(jq -r '.required_pull_request_reviews.required_approving_review_count' "$CONFIG_FILE")
if ! [[ "$REVIEW_COUNT" =~ ^[0-9]+$ ]] || [ "$REVIEW_COUNT" -lt 1 ]; then
  echo "  ❌ required_approving_review_count must be a number >= 1, got: $REVIEW_COUNT"
  exit 1
fi
echo "  ✅ required_approving_review_count: $REVIEW_COUNT"

# Check booleans
BOOL_FIELDS=(
  "required_pull_request_reviews.require_code_owner_reviews"
  "required_pull_request_reviews.dismiss_stale_reviews"
  "enforce_admins"
  "required_conversation_resolution"
  "allow_force_pushes"
  "allow_deletions"
)

for field in "${BOOL_FIELDS[@]}"; do
  VALUE=$(jq -r ".$field" "$CONFIG_FILE")
  if [ "$VALUE" != "true" ] && [ "$VALUE" != "false" ]; then
    echo "  ❌ $field must be boolean (true/false), got: $VALUE"
    exit 1
  fi
  echo "  ✅ $field: $VALUE"
done
echo ""

# Security best practices check
echo "📋 Step 4: Checking security best practices..."

REQUIRE_CODEOWNERS=$(jq -r '.required_pull_request_reviews.require_code_owner_reviews' "$CONFIG_FILE")
ENFORCE_ADMINS=$(jq -r '.enforce_admins' "$CONFIG_FILE")
ALLOW_FORCE_PUSH=$(jq -r '.allow_force_pushes' "$CONFIG_FILE")
ALLOW_DELETE=$(jq -r '.allow_deletions' "$CONFIG_FILE")

WARNINGS=0

if [ "$REQUIRE_CODEOWNERS" != "true" ]; then
  echo "  ⚠️  WARNING: require_code_owner_reviews is false"
  WARNINGS=$((WARNINGS + 1))
else
  echo "  ✅ Code owner reviews required"
fi

if [ "$ENFORCE_ADMINS" != "true" ]; then
  echo "  ⚠️  WARNING: enforce_admins is false (admins can bypass)"
  WARNINGS=$((WARNINGS + 1))
else
  echo "  ✅ Admin enforcement enabled"
fi

if [ "$ALLOW_FORCE_PUSH" = "true" ]; then
  echo "  ⚠️  WARNING: Force pushes are allowed (risk of history rewriting)"
  WARNINGS=$((WARNINGS + 1))
else
  echo "  ✅ Force pushes blocked"
fi

if [ "$ALLOW_DELETE" = "true" ]; then
  echo "  ⚠️  WARNING: Branch deletion is allowed"
  WARNINGS=$((WARNINGS + 1))
else
  echo "  ✅ Branch deletion blocked"
fi

echo ""
if [ $WARNINGS -gt 0 ]; then
  echo "⚠️  Validation passed with $WARNINGS warning(s)"
else
  echo "✅ All security best practices followed"
fi
echo ""

# Display final configuration
echo "📋 Step 5: Final configuration summary:"
echo "--------------------------------------"
jq '.' "$CONFIG_FILE"
echo ""

echo "============================================="
echo "✅ Validation completed successfully"
echo "============================================="
