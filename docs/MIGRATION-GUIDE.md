# Migration Guide: JSON to YAML Configuration

## Overview

This guide helps you migrate from the legacy JSON configuration (`config/branch-protection.json`) to the new YAML format (`.github/branch-protection.yml`).

## Why YAML?

> "Humans don't read JSON!" - Team Principle

**Benefits of YAML:**
- ✅ More readable and maintainable
- ✅ Supports comments for documentation
- ✅ Follows GitHub conventions (`.github/` directory)
- ✅ Better for version control (clearer diffs)
- ✅ Industry standard for configuration

## Migration Steps

### Step 1: Install yq

```bash
# macOS
brew install yq

# Linux
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Verify installation
yq --version
```

### Step 2: Convert Existing JSON to YAML

```bash
# Automatic conversion
yq eval -P config/branch-protection.json > .github/branch-protection.yml.tmp

# Wrap in branch_protection key
echo "branch_protection:" > .github/branch-protection.yml
yq eval -P config/branch-protection.json | sed 's/^/  /' >> .github/branch-protection.yml
```

### Step 3: Add Comments and Documentation

Edit `.github/branch-protection.yml` to add helpful comments:

```yaml
# Branch Protection Configuration
# This file defines the desired branch protection settings for the main branch
# Documentation: https://docs.github.com/en/rest/branches/branch-protection

branch_protection:
  # Target branch
  branch: main
  
  # Pull Request Reviews
  required_pull_request_reviews:
    # Dismiss stale approvals when new commits are pushed
    dismiss_stale_reviews: true
    
    # Require approval from code owners (defined in CODEOWNERS)
    require_code_owner_reviews: true
    
    # Number of required approving reviews
    required_approving_review_count: 2
  
  # Protection Settings
  
  # Enforce all configured restrictions for administrators
  enforce_admins: true
  
  # Require all conversations to be resolved before merging
  required_conversation_resolution: true
  
  # Allow force pushes (should be false for protected branches)
  allow_force_pushes: false
  
  # Allow branch deletions (should be false for protected branches)
  allow_deletions: false
  
  # Require linear history (no merge commits)
  required_linear_history: true
```

### Step 4: Validate the New Configuration

```bash
# Validate schema
./scripts/validate-schema.sh .github/branch-protection.yml

# Test conversion (check it produces valid JSON)
yq eval -o=json '.branch_protection' .github/branch-protection.yml | jq '.'

# Check for drift (should show no drift if converted correctly)
./scripts/repocheck owner/repo .github/branch-protection.yml
```

### Step 5: Update Workflows

The new workflow automatically detects and supports both formats:

```yaml
# Workflow automatically chooses:
# - .github/branch-protection.yml (preferred)
# - config/branch-protection.json (legacy fallback)
```

### Step 6: Update CODEOWNERS

Already done! The CODEOWNERS file now protects both:

```
/.github/branch-protection.yml @security-team
/config/branch-protection.json @security-team  # Legacy support
```

### Step 7: Create Migration PR

```bash
# Create branch
git checkout -b migrate-to-yaml-config

# Add new YAML file
git add .github/branch-protection.yml

# Commit
git commit -m "feat: migrate branch protection config to YAML

- Add .github/branch-protection.yml (replaces config/branch-protection.json)
- Improve readability with comments
- Follow GitHub conventions (.github/ directory)
- Maintain backward compatibility

Issue: #10
"

# Push and create PR
git push origin migrate-to-yaml-config
gh pr create --title "Migrate branch protection config to YAML" \
  --body "## Migration to YAML Configuration

This PR migrates branch protection configuration from JSON to YAML format.

### Changes
- ✅ Created \`.github/branch-protection.yml\` with comments
- ✅ Validated schema
- ✅ Tested with repocheck (no drift)
- ✅ Backward compatible (JSON still supported)

### Testing
\`\`\`bash
./scripts/validate-schema.sh .github/branch-protection.yml
./scripts/repocheck owner/repo .github/branch-protection.yml
\`\`\`

### Checklist
- [x] Schema validation passes
- [x] No configuration drift
- [x] Comments added for clarity
- [x] CODEOWNERS updated

### Migration Guide
See docs/MIGRATION-GUIDE.md for details.
"
```

### Step 8: Test PR Validation

The workflow will:
1. ✅ Validate YAML schema
2. 🔍 Check for drift against live configuration
3. 💬 Post comment with results
4. 🏷️ Add labels if needed

### Step 9: Merge and Verify

After PR approval:
1. Merge to main
2. Workflow will use YAML configuration
3. Verify with: `gh api repos/owner/repo/branches/main/protection`

### Step 10: (Optional) Remove Legacy JSON

After confirming YAML works:

```bash
# Create cleanup PR
git checkout -b remove-legacy-json-config
git rm config/branch-protection.json
git commit -m "chore: remove legacy JSON config

YAML configuration now fully adopted:
- .github/branch-protection.yml

Issue: #10
"
git push origin remove-legacy-json-config
gh pr create --title "Remove legacy JSON configuration"
```

## Comparison: JSON vs YAML

### Legacy JSON Format

```json
{
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 2
  },
  "enforce_admins": true,
  "required_conversation_resolution": true
}
```

**Issues:**
- ❌ No comments allowed
- ❌ Less readable
- ❌ Hard to understand context
- ❌ Not following GitHub conventions

### New YAML Format

```yaml
branch_protection:
  # Pull Request Reviews
  required_pull_request_reviews:
    # Dismiss stale approvals when new commits are pushed
    dismiss_stale_reviews: true
    
    # Require approval from code owners (defined in CODEOWNERS)
    require_code_owner_reviews: true
    
    # Number of required approving reviews
    required_approving_review_count: 2
  
  # Enforce all configured restrictions for administrators
  enforce_admins: true
  
  # Require all conversations to be resolved before merging
  required_conversation_resolution: true
```

**Benefits:**
- ✅ Comments explain each setting
- ✅ More readable structure
- ✅ Self-documenting
- ✅ Follows GitHub conventions

## Rollback Plan

If you need to rollback to JSON:

```bash
# Convert YAML back to JSON
yq eval -o=json '.branch_protection' .github/branch-protection.yml > config/branch-protection.json

# Verify JSON is valid
jq '.' config/branch-protection.json

# Commit and push
git add config/branch-protection.json
git commit -m "rollback: revert to JSON configuration"
git push
```

The workflow will automatically detect and use the JSON file.

## Troubleshooting

### "yq is required"
See Step 1 above for installation instructions.

### Conversion produces invalid YAML
```bash
# Check JSON is valid first
jq '.' config/branch-protection.json

# Try manual conversion with proper indentation
yq eval -P config/branch-protection.json
```

### Drift detected after migration
This is expected if you added/removed fields. Either:
1. Update YAML to match live config, or
2. Apply YAML config to update live settings

### Workflow uses wrong file
Priority order:
1. `.github/branch-protection.yml` (checked first)
2. `config/branch-protection.json` (fallback)

Delete or rename the JSON file if you want to force YAML usage.

## Best Practices

1. **Add comments** - Document why each setting exists
2. **Use consistent indentation** - 2 spaces (YAML standard)
3. **Test locally** - Run `validate-schema.sh` before committing
4. **Small PRs** - Migrate first, then make changes
5. **Keep JSON temporarily** - Remove only after confirming YAML works

## Multi-Repository Migration

For organizations with many repositories:

```bash
#!/bin/bash
# migrate-all-repos.sh

REPOS=(
  "org/repo1"
  "org/repo2"
  "org/repo3"
)

for repo in "${REPOS[@]}"; do
  echo "Migrating $repo..."
  
  # Clone repo
  gh repo clone "$repo" "/tmp/$repo"
  cd "/tmp/$repo"
  
  # Convert JSON to YAML
  if [ -f "config/branch-protection.json" ]; then
    mkdir -p .github
    echo "branch_protection:" > .github/branch-protection.yml
    yq eval -P config/branch-protection.json | sed 's/^/  /' >> .github/branch-protection.yml
    
    # Create PR
    git checkout -b migrate-to-yaml
    git add .github/branch-protection.yml
    git commit -m "feat: migrate branch protection config to YAML"
    git push origin migrate-to-yaml
    gh pr create --title "Migrate branch protection config to YAML" --body "Auto-generated migration from JSON to YAML"
    
    echo "✅ Created PR for $repo"
  else
    echo "⚠️  No JSON config found in $repo"
  fi
  
  cd -
done
```

## Success Criteria

After migration:
- ✅ `.github/branch-protection.yml` exists
- ✅ Schema validation passes
- ✅ No drift detected
- ✅ Comments added for clarity
- ✅ Workflow uses YAML file
- ✅ PR validation works
- ✅ Team can read and understand config

---

**Questions?** See [BRANCH-PROTECTION-GUIDE.md](BRANCH-PROTECTION-GUIDE.md) or create an issue.
