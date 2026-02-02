# Branch Protection Validation & Drift Detection

## Problem Statement

We need a way to test branch settings of GitHub repositories against a known state defined in code. This will:
- Enable better visibility of branch settings (hidden in UI, only accessible to certain GitHub groups)
- Prevent configuration drift from standardized rules
- Support security auditing and compliance
- Allow version-controlled branch protection policies across FOG repositories

**Current State:** Branch protection settings are manually configured through GitHub UI, with no visibility into configuration drift or standardization across repositories.

**Desired State:** Branch protection as code with automated drift detection, enabling security teams to monitor compliance without requiring write access to branch settings.

## Solution Approach

Implement **Branch Protection Validation** with:
1. **Configuration as Code**: YAML-based configuration file
2. **Read-Only Validation**: Script to check actual vs desired state (no write permissions required)
3. **Drift Detection**: Automated checks via GitHub Actions
4. **Clear Reporting**: Structured output showing configuration discrepancies

**Key Principle**: Validation must work with **read-only permissions** to GitHub branch settings, as modifying branch rules is a privileged action handled separately.

---

## Deliverables

### 1. Configuration File: YAML Format

**Location:** `.github/branch-protection.yml`

**Rationale:** 
- Team principle: "humans don't read json!"
- Better readability and maintainability
- Follows GitHub conventions for config files
- Works with both Branch Protection Rules and Rulesets APIs (script converts YAML→JSON)

**Standard Rules** (aligned with PSREGOV-3704 and [working-with-git-repos.md](working-with-git-repos.md)):

```yaml
# .github/branch-protection.yml
branch_protection:
  branch: main
  
  # Required: Signed commits (from decide-document-branchrules)
  required_signatures: true
  
  # Required: Linear history (from working-with-git-repos.md)
  required_linear_history: true
  
  # Required: PR reviews
  required_pull_request_reviews:
    dismiss_stale_reviews: true
    require_code_owner_reviews: true
    required_approving_review_count: 1
    require_last_push_approval: false
  
  # Required: Branches up to date before merge
  required_status_checks:
    strict: true  # Enforces "require branches to be up to date before merging"
    contexts:     # Specific checks are repo-dependent (see note below)
      - "checkov"              # IaC security scanning (if applicable)
      - "unit-tests"           # Unit tests (if applicable)
      - "build"                # Build verification (if applicable)
      # Add repo-specific checks as needed
  
  # Required: Admin enforcement
  enforce_admins: true
  
  # Required: Conversation resolution
  required_conversation_resolution: true
  
  # Required: Prevent force pushes and deletions
  allow_force_pushes: false
  allow_deletions: false
  
  # Optional: Lock branch (read-only)
  lock_branch: false
  
  # Optional: Required deployments
  required_deployments:
    environments: []
```

**Note on Status Checks (Checkov, Unit Tests, etc.):**

From [working-with-git-repos.md](working-with-git-repos.md):
> "Checkov, unit tests etc. are excluded from this work, as these are context dependent within each specific repo."

**What This Means:**
- ✅ **Framework validation**: This ticket validates that `required_status_checks.strict: true` is enabled
- ✅ **Check references**: YAML can list specific check names (e.g., `checkov`, `unit-tests`)
- ❌ **Check implementation**: Each repo implements their own Checkov workflows, tests, etc.
- ❌ **Check standardization**: Not enforcing which specific checks must exist (repo-specific)

**Repository-Specific Checks:**
Each repository defines its own status checks via GitHub Actions workflows:

```yaml
# Example: .github/workflows/checkov.yml (repo-specific implementation)
name: checkov
on: [pull_request]
jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: terraform/
          framework: terraform
```

**Validation Scope:**
This ticket's `repocheck` script validates:
- ✅ `strict: true` is enabled (branches must be up to date)
- ✅ Specific check names match (if listed in YAML)
- ❌ Does NOT validate that Checkov workflow exists or runs correctly
- ❌ Does NOT enforce which checks must be present (repo autonomy)

---

### 2. Validation Script: `repocheck`

**Purpose**: Read-only validation script to compare actual GitHub branch protection settings against desired YAML configuration.

**Location:** `scripts/repocheck`

**Key Features:**
- ✅ **Read-only permissions** - No ability to create, update, or delete branch rules
- ✅ Accepts both YAML and JSON input formats (legacy support)
- ✅ Structured output formats: JSON, YAML, or human-readable text
- ✅ Clear exit codes for automation: 0 (match), 1 (drift), 2 (error)
- ✅ Detailed diff reporting showing exact discrepancies
- ✅ Uses Branch Protection Rules API (extensible to Rulesets API in future)

**Implementation:**

```bash
#!/usr/bin/env bash
# repocheck - Compare actual vs desired branch protection config
# Usage: repocheck <owner/repo> [config-file] [output-format]

set -euo pipefail

REPO="${1:?Repository required (owner/repo)}"
CONFIG_FILE="${2:-.github/branch-protection.yml}"
OUTPUT_FORMAT="${3:-text}"  # json|yaml|text
BRANCH="${4:-main}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is required but not installed"
    exit 2
fi

# Verify read-only access
echo "🔍 Checking repository: $REPO (branch: $BRANCH)"

# Fetch current protection config from GitHub
if ! gh api "repos/$REPO/branches/$BRANCH/protection" > /tmp/current-$$.json 2>/tmp/error-$$.txt; then
    if grep -q "Branch not protected" /tmp/error-$$.txt; then
        echo "⚠️  Branch '$BRANCH' is not protected"
        echo '{}' > /tmp/current-$$.json
    else
        echo "❌ Error fetching branch protection: $(cat /tmp/error-$$.txt)"
        exit 2
    fi
fi

# Convert YAML config to JSON for comparison
if [[ "$CONFIG_FILE" =~ \.ya?ml$ ]]; then
    if ! command -v yq &> /dev/null; then
        echo "❌ yq is required for YAML support but not installed"
        exit 2
    fi
    yq eval -o=json "$CONFIG_FILE" > /tmp/desired-$$.json
else
    cp "$CONFIG_FILE" /tmp/desired-$$.json
fi

# Normalize and compare configurations
cat > /tmp/compare-$$.jq << 'EOF'
# Extract comparable fields from actual config
def normalize_actual:
  {
    required_signatures: (.required_signatures.enabled // false),
    required_linear_history: (.required_linear_history.enabled // false),
    enforce_admins: (.enforce_admins.enabled // false),
    required_conversation_resolution: (.required_conversation_resolution.enabled // false),
    allow_force_pushes: (.allow_force_pushes.enabled // false),
    allow_deletions: (.allow_deletions.enabled // false),
    lock_branch: (.lock_branch.enabled // false),
    required_pull_request_reviews: (
      if .required_pull_request_reviews then
        {
          dismiss_stale_reviews: .required_pull_request_reviews.dismiss_stale_reviews,
          require_code_owner_reviews: .required_pull_request_reviews.require_code_owner_reviews,
          required_approving_review_count: .required_pull_request_reviews.required_approving_review_count
        }
      else null end
    ),
    required_status_checks: (
      if .required_status_checks then
        {
          strict: .required_status_checks.strict,
          contexts: .required_status_checks.contexts
        }
      else null end
    )
  };

# Extract expected config
def normalize_desired:
  .branch_protection | {
    required_signatures,
    required_linear_history,
    enforce_admins,
    required_conversation_resolution,
    allow_force_pushes,
    allow_deletions,
    lock_branch,
    required_pull_request_reviews,
    required_status_checks
  };

# Compare and generate diff
{
  actual: (.[0] | normalize_actual),
  desired: (.[1] | normalize_desired)
} | {
  matches: (.actual == .desired),
  differences: (
    if .actual == .desired then {}
    else
      reduce ((.desired | keys_unsorted[]) as $key | 
        if .actual[$key] != .desired[$key] then
          {($key): {actual: .actual[$key], desired: .desired[$key]}}
        else empty end
      ) as $diff ({}; . + $diff)
    end
  )
}
EOF

# Run comparison
DIFF_RESULT=$(jq --slurp -f /tmp/compare-$$.jq /tmp/current-$$.json /tmp/desired-$$.json)
MATCHES=$(echo "$DIFF_RESULT" | jq -r '.matches')
DIFF_COUNT=$(echo "$DIFF_RESULT" | jq '.differences | length')

# Clean up temp files
rm -f /tmp/current-$$.json /tmp/desired-$$.json /tmp/compare-$$.jq /tmp/error-$$.txt

# Output results based on format
case "$OUTPUT_FORMAT" in
    json)
        echo "$DIFF_RESULT"
        ;;
    yaml)
        echo "$DIFF_RESULT" | yq eval -P -
        ;;
    text|*)
        if [ "$MATCHES" = "true" ]; then
            echo -e "${GREEN}✅ Configuration matches${NC}"
            echo "All branch protection settings align with desired state"
        else
            echo -e "${RED}❌ Drift detected${NC}"
            echo -e "${YELLOW}Found $DIFF_COUNT configuration difference(s):${NC}"
            echo ""
            echo "$DIFF_RESULT" | jq -r '
              .differences | to_entries[] | 
              "  • \(.key):\n    Actual:  \(.value.actual)\n    Desired: \(.value.desired)\n"
            '
        fi
        ;;
esac

# Exit with appropriate code
if [ "$MATCHES" = "true" ]; then
    exit 0
else
    exit 1
fi
```

**Permissions Required:** 
- `contents: read` (to read repository files)
- `metadata: read` (to read branch protection settings)
- **NO write permissions** to branch protection

---

### 3. GitHub Actions Workflow

**File:** `.github/workflows/check-branch-protection.yml`

**Purpose:** Automated drift detection without requiring write permissions

**Triggers:**
```yaml
on:
  schedule:
    - cron: '0 2 * * 1'  # Weekly drift detection (Monday 2 AM)
  
  pull_request:  # Validate config changes
    paths:
      - '.github/branch-protection.yml'
      - '.github/workflows/check-branch-protection.yml'
      - 'scripts/repocheck'
  
  workflow_dispatch:  # Manual trigger
```

**Implementation:**

```yaml
name: Branch Protection Validation

on:
  schedule:
    - cron: '0 2 * * 1'  # Weekly Monday 2 AM UTC
  pull_request:
    paths:
      - '.github/branch-protection.yml'
      - '.github/workflows/check-branch-protection.yml'
      - 'scripts/repocheck'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write  # For PR comments
  issues: write         # For creating issues on drift

jobs:
  validate-config:
    name: Validate Configuration File
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Install yq
        run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq
      
      - name: Validate YAML syntax
        run: |
          yq eval '.github/branch-protection.yml' > /dev/null
          echo "✅ YAML syntax is valid"
      
      - name: Validate schema
        run: |
          # Check required fields
          if ! yq eval '.branch_protection.required_signatures' .github/branch-protection.yml > /dev/null; then
            echo "❌ Missing required field: required_signatures"
            exit 1
          fi
          if ! yq eval '.branch_protection.required_linear_history' .github/branch-protection.yml > /dev/null; then
            echo "❌ Missing required field: required_linear_history"
            exit 1
          fi
          echo "✅ Schema validation passed"

  check-drift:
    name: Check for Configuration Drift
    runs-on: ubuntu-latest
    needs: validate-config
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Install dependencies
        run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq
      
      - name: Make repocheck executable
        run: chmod +x scripts/repocheck
      
      - name: Run drift detection
        id: check
        run: |
          set +e  # Don't exit on error
          ./scripts/repocheck "${{ github.repository }}" .github/branch-protection.yml json > drift-report.json
          EXIT_CODE=$?
          echo "exit_code=$EXIT_CODE" >> $GITHUB_OUTPUT
          
          if [ $EXIT_CODE -eq 0 ]; then
            echo "drift_detected=false" >> $GITHUB_OUTPUT
          elif [ $EXIT_CODE -eq 1 ]; then
            echo "drift_detected=true" >> $GITHUB_OUTPUT
          else
            echo "❌ Error running repocheck"
            cat drift-report.json
            exit 1
          fi
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Display drift report
        if: always()
        run: |
          echo "## Drift Detection Report"
          if [ "${{ steps.check.outputs.drift_detected }}" = "true" ]; then
            echo "⚠️ Configuration drift detected"
            cat drift-report.json | jq '.'
          else
            echo "✅ Configuration matches - no drift detected"
          fi
      
      - name: Comment on PR if drift detected
        if: github.event_name == 'pull_request' && steps.check.outputs.drift_detected == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const drift = JSON.parse(fs.readFileSync('drift-report.json', 'utf8'));
            
            const comment = `## ⚠️ Branch Protection Drift Detected
            
            The proposed configuration does not match the current GitHub settings.
            
            ### Differences Found
            
            \`\`\`json
            ${JSON.stringify(drift.differences, null, 2)}
            \`\`\`
            
            **Action Required:**
            - Review the differences above
            - Update GitHub branch protection settings manually, OR
            - Adjust the YAML configuration to match current settings
            
            **Note:** This workflow validates configuration but does not modify branch settings (read-only permissions).
            `;
            
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: comment
            });
      
      - name: Add label if drift detected
        if: github.event_name == 'pull_request' && steps.check.outputs.drift_detected == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.addLabels({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              labels: ['config-drift', 'needs-review']
            });
      
      - name: Create issue if drift detected (scheduled run)
        if: github.event_name == 'schedule' && steps.check.outputs.drift_detected == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const drift = JSON.parse(fs.readFileSync('drift-report.json', 'utf8'));
            
            const body = `## Branch Protection Configuration Drift Detected
            
            Automated weekly check found differences between defined configuration and actual GitHub settings.
            
            ### Differences
            
            \`\`\`json
            ${JSON.stringify(drift.differences, null, 2)}
            \`\`\`
            
            ### Remediation Steps
            
            1. Review the differences above
            2. Determine if GitHub settings were manually changed (drift) or if YAML needs updating
            3. Take corrective action:
               - If settings changed manually: Update GitHub to match YAML
               - If YAML is outdated: Create PR to update YAML
            
            **Detection Date:** ${new Date().toISOString()}
            **Repository:** ${context.repo.owner}/${context.repo.repo}
            `;
            
            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `[Drift] Branch Protection Configuration Mismatch - ${new Date().toISOString().split('T')[0]}`,
              body: body,
              labels: ['config-drift', 'security', 'automated']
            });
      
      - name: Upload drift report
        if: steps.check.outputs.drift_detected == 'true'
        uses: actions/upload-artifact@v4
        with:
          name: drift-report
          path: drift-report.json
          retention-days: 90
```

**Security Note:** This workflow has **read-only** permissions and cannot modify branch protection settings.

---

### 4. Schema Validation Script

**Location:** `scripts/validate-schema.sh`

**Purpose:** Validate YAML configuration against expected schema

```bash
#!/usr/bin/env bash
# validate-schema.sh - Validate branch protection YAML schema

set -euo pipefail

CONFIG_FILE="${1:-.github/branch-protection.yml}"

echo "🔍 Validating schema for: $CONFIG_FILE"

# Check yq is installed
if ! command -v yq &> /dev/null; then
    echo "❌ yq is required but not installed"
    exit 1
fi

# Required fields
REQUIRED_FIELDS=(
    ".branch_protection.branch"
    ".branch_protection.required_signatures"
    ".branch_protection.required_linear_history"
    ".branch_protection.enforce_admins"
)

VALIDATION_FAILED=false

for field in "${REQUIRED_FIELDS[@]}"; do
    if ! yq eval "$field" "$CONFIG_FILE" &> /dev/null; then
        echo "❌ Missing required field: $field"
        VALIDATION_FAILED=true
    fi
done

# Validate boolean fields
BOOLEAN_FIELDS=(
    ".branch_protection.required_signatures"
    ".branch_protection.required_linear_history"
    ".branch_protection.enforce_admins"
    ".branch_protection.required_conversation_resolution"
    ".branch_protection.allow_force_pushes"
    ".branch_protection.allow_deletions"
)

for field in "${BOOLEAN_FIELDS[@]}"; do
    value=$(yq eval "$field" "$CONFIG_FILE" 2>/dev/null || echo "null")
    if [ "$value" != "null" ] && [ "$value" != "true" ] && [ "$value" != "false" ]; then
        echo "❌ Field $field must be boolean (true/false), got: $value"
        VALIDATION_FAILED=true
    fi
done

if [ "$VALIDATION_FAILED" = true ]; then
    echo "❌ Schema validation failed"
    exit 1
else
    echo "✅ Schema validation passed"
    exit 0
fi
```

---

### 5. Documentation

#### **README Addition**

```markdown
## Branch Protection Validation

This repository uses branch protection as code to ensure consistent security settings.

### Configuration

Branch protection settings are defined in `.github/branch-protection.yml`.

### Validation

Run locally:
```bash
./scripts/repocheck tester311249/llm-security
```

Automated validation runs:
- **Weekly:** Monday 2 AM UTC (drift detection)
- **On PR:** When configuration files change
- **Manual:** Via workflow dispatch

### Standards

Our branch protection enforces:
- ✅ Signed commits (GPG/SSH)
- ✅ Linear history (no merge commits)
- ✅ PR reviews with code owner approval
- ✅ Branches up to date before merge
- ✅ Admin enforcement
- ✅ Conversation resolution
- ✅ No force pushes or deletions

See [working-with-git-repos.md](docs/working-with-git-repos.md) for details.
```

#### **CODEOWNERS Entry**

```
# Branch protection configuration
/.github/branch-protection.yml @org/security-team
/.github/workflows/check-branch-protection.yml @org/security-team
/scripts/repocheck @org/security-team
/scripts/validate-schema.sh @org/security-team
```

---

## Multi-Repository Adoption

**Goal:** Create reusable tooling for adoption across all FOG repositories.

### Adoption Package

**Components:**
1. `repocheck` script (portable)
2. `validate-schema.sh` script
3. Template configuration file
4. Workflow template
5. Setup guide

### Quick Start for Other Repos

```bash
# 1. Copy validation script
curl -o scripts/repocheck https://raw.githubusercontent.com/tester311249/llm-security/main/scripts/repocheck
chmod +x scripts/repocheck

# 2. Copy schema validator
curl -o scripts/validate-schema.sh https://raw.githubusercontent.com/tester311249/llm-security/main/scripts/validate-schema.sh
chmod +x scripts/validate-schema.sh

# 3. Create config from template
curl -o .github/branch-protection.yml https://raw.githubusercontent.com/tester311249/llm-security/main/.github/branch-protection.yml

# 4. Copy workflow
mkdir -p .github/workflows
curl -o .github/workflows/check-branch-protection.yml https://raw.githubusercontent.com/tester311249/llm-security/main/.github/workflows/check-branch-protection.yml

# 5. Update CODEOWNERS
echo "/.github/branch-protection.yml @org/security-team" >> .github/CODEOWNERS

# 6. Test locally
./scripts/repocheck owner/repo
```

---

## Acceptance Criteria

### Core Functionality
- [x] **YAML configuration file** created at `.github/branch-protection.yml`
  - Includes all required fields from decide-document-branchrules
  - Enforces signed commits
  - Enforces linear history
  - Follows team conventions (YAML over JSON)
  - Can reference repo-specific status checks (Checkov, unit tests, etc.)

- [x] **`repocheck` script** implemented with:
  - Read-only GitHub API permissions (no write access)
  - Support for both YAML and JSON config formats
  - Clear exit codes: 0 (match), 1 (drift), 2 (error)
  - Multiple output formats: JSON, YAML, text
  - Detailed difference reporting
  - Validates `required_status_checks.strict` is enabled
  - Validates status check context names match (if specified)
  - Does NOT validate that status check workflows exist (repo-specific)

- [x] **Schema validation script** (`validate-schema.sh`)
  - Validates required fields presence
  - Checks data types (booleans, objects)
  - Clear error messages

### GitHub Actions Integration
- [x] **Automated workflow** (`.github/workflows/check-branch-protection.yml`) with:
  - Weekly drift detection (cron schedule)
  - PR validation on config changes
  - Manual workflow dispatch option
  - **Read-only permissions only**

- [x] **PR feedback features:**
  - Comments on PRs when drift detected
  - Labels applied for visibility (`config-drift`, `needs-review`)
  - Structured diff in comment body

- [x] **Scheduled drift detection:**
  - Creates GitHub issues when drift found
  - Includes remediation steps
  - Attaches drift report as artifact

### Security & Compliance
- [x] **Permissions validation:**
  - Script uses only read permissions
  - No ability to create, update, or delete branch rules
  - Documented in workflow with `permissions:` block

- [x] **CODEOWNERS protection:**
  - All config files and scripts protected
  - Changes require security team approval

- [x] **Standards alignment:**
  - Implements rules from decide-document-branchrules
  - Follows practices from working-with-git-repos.md
  - Enforces signed commits and linear history

### Documentation & Adoption
- [x] **README documentation:**
  - Usage instructions for `repocheck`
  - Explanation of automated validation
  - List of enforced standards

- [x] **Multi-repo adoption guide:**
  - Quick start commands
  - Setup checklist
  - CODEOWNERS template

- [x] **Testing:**
  - Manual test: `./scripts/repocheck` runs successfully
  - Workflow test: PR triggers validation
  - Drift test: Manual config change detected

---

## Technical Decisions

### Branch Protection Rules API vs Rulesets API

**Decision Required:** Choose which GitHub API to use for branch protection validation.

**Context:** The [decide-document-branchrules](decide-document-branchrules) document states:
> "These rules can be enforced using 'Branch protection rules' and/or 'Rulesets' within GitHub, two similar features. We also need to decide which of these to use (or both)."

**Options:**

#### Option 1: Branch Protection Rules API (Legacy/Classic)
**API Endpoints:**
- `GET /repos/{owner}/{repo}/branches/{branch}/protection`
- `PUT /repos/{owner}/{repo}/branches/{branch}/protection`

**Documentation:** https://docs.github.com/en/enterprise-cloud@latest/rest/branches/branch-protection?apiVersion=2022-11-28

**Features:**
- Require pull request reviews before merging
- Dismiss stale pull request approvals when new commits are pushed
- Require review from Code Owners
- Restrict who can dismiss pull request reviews
- Require status checks before merging
- Require branches to be up to date before merging
- Require conversation resolution before merging
- Require signed commits
- Require linear history
- Require merge queue
- Lock branch (read-only)
- Allow force pushes
- Allow deletions
- Restrict pushes to specific users/teams/apps
- Restrict who can push to matching branches

**Pros:**
- ✅ Well-established, stable API since 2015
- ✅ Widely used across existing FOG repos
- ✅ Extensive documentation and community examples
- ✅ Simpler permission model (`repo` scope for private, public repos)
- ✅ Direct branch-level configuration
- ✅ Well-understood by teams

**Cons:**
- ❌ Being phased out in favor of Rulesets (GitHub's strategic direction)
- ❌ Limited to single branch patterns per rule
- ❌ Cannot apply organization-wide policies
- ❌ Less flexible targeting (branch patterns only)
- ❌ Cannot target by file paths or commit metadata
- ❌ No rule evaluation order control
- ❌ Separate APIs for different protection types

**Supported in our Use Case:**
- ✅ `required_signatures` 
- ✅ `required_linear_history`
- ✅ `required_pull_request_reviews` (with code owners)
- ✅ `required_status_checks.strict` (branches up to date)
- ✅ `enforce_admins`
- ✅ `required_conversation_resolution`
- ✅ `allow_force_pushes` (set to false)
- ✅ `allow_deletions` (set to false)

---

#### Option 2: Repository Rulesets API (Modern)
**API Endpoints:**

**Repository-Level:**
- `GET /repos/{owner}/{repo}/rulesets` - Get all rulesets
- `GET /repos/{owner}/{repo}/rulesets/{ruleset_id}` - Get specific ruleset
- `POST /repos/{owner}/{repo}/rulesets` - Create ruleset (requires admin)
- `PUT /repos/{owner}/{repo}/rulesets/{ruleset_id}` - Update ruleset (requires admin)
- `DELETE /repos/{owner}/{repo}/rulesets/{ruleset_id}` - Delete ruleset (requires admin)
- `GET /repos/{owner}/{repo}/rules/branches/{branch}` - Get all rules for a branch

**Organization-Level:**
- `GET /orgs/{org}/rulesets` - Get all org rulesets
- `POST /orgs/{org}/rulesets` - Create org ruleset
- `PUT /orgs/{org}/rulesets/{ruleset_id}` - Update org ruleset

**Documentation:** 
- REST API: https://docs.github.com/en/rest/repos/rules
- Rulesets Guide: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets

**Key API Features:**

**Enforcement Levels:**
- `active` - Rules are enforced
- `disabled` - Rules not enforced
- `evaluate` - Test mode (GitHub Enterprise only, provides insights without enforcement)

**Rule Types (matching Branch Protection requirements):**
- `required_signatures` - Require signed commits
- `required_linear_history` - Require linear history
- `pull_request` - Require pull request reviews
  - Parameters: `dismiss_stale_reviews_on_push`, `require_code_owner_review`, `required_approving_review_count`
- `required_status_checks` - Require status checks to pass
  - Parameters: `strict_required_status_checks_policy`, `required_status_checks[]`
- `creation` - Restrict creation of refs
- `update` - Restrict updates to refs
- `deletion` - Restrict deletion of refs
- `non_fast_forward` - Block force pushes
- `commit_message_pattern` - Enforce commit message patterns
- `commit_author_email_pattern` - Enforce author email patterns
- `committer_email_pattern` - Enforce committer email patterns
- `branch_name_pattern` - Enforce branch naming
- `tag_name_pattern` - Enforce tag naming
- `file_path_restriction` - Restrict changes to specific file paths
- `max_file_path_length` - Limit file path lengths
- `file_extension_restriction` - Restrict file extensions
- `max_file_size` - Limit file sizes
- `workflows` - Require workflows to pass

**Targeting (Conditions):**
```json
{
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main", "refs/heads/release/*"],
      "exclude": ["refs/heads/dev*"]
    }
  }
}
```

**Bypass Actors:**
```json
{
  "bypass_actors": [
    {
      "actor_id": 234,
      "actor_type": "Team",        // Team, User, OrganizationAdmin, RepositoryRole
      "bypass_mode": "always"      // always, pull_request
    }
  ]
}
```

**Permissions Required:**
- **Read**: "Metadata" repository permissions (read)
- **Write**: "Administration" repository permissions (write)
- Can be used without authentication for public resources

**Features (Superset of Branch Protection):**
- All Branch Protection features PLUS:
- Organization-wide rulesets with inheritance
- Target multiple branches with include/exclude patterns
- Target by ref name patterns (branches, tags)
- Target by repository properties
- File path restrictions (CODEOWNERS-like but more flexible)
- Commit metadata requirements (message patterns, author email)
- Tag protection rules
- Rule evaluation order and bypass permissions
- More granular workflow status check requirements
- Branch lifecycle rules (creation, deletion, updates)

**Pros:**
- ✅ Modern, GitHub's strategic direction (released 2023)
- ✅ Organization-wide policy enforcement possible
- ✅ More flexible targeting (multiple branches, tags, file paths)
- ✅ Unified API for all protection types
- ✅ Better rule composition and inheritance
- ✅ More granular bypass permissions
- ✅ Future-proof (active development)
- ✅ Can coexist with Branch Protection Rules (Rulesets take precedence)
- ✅ Read-only GET endpoints don't require admin access

**Cons:**
- ❌ Newer, less widespread adoption in FOG repos
- ❌ More complex API structure and permission model
- ❌ Requires GitHub Enterprise Cloud or GitHub Free/Pro/Team (2023+)
- ❌ Different JSON structure for configuration
- ❌ Learning curve for teams familiar with Branch Protection
- ❌ Write operations require "Administration" permissions (vs "repo" for Branch Protection)
- ❌ Less community tooling and examples

**Configuration Structure (Different from Branch Protection):**

Rulesets use a rule-based array structure instead of nested properties:

```yaml
# .github/branch-protection.yml (Rulesets format)
ruleset:
  name: "main branch protection"
  target: branch
  enforcement: active
  
  conditions:
    ref_name:
      include:
        - refs/heads/main
      exclude: []
  
  rules:
    - type: required_signatures
    
    - type: required_linear_history
    
    - type: pull_request
      parameters:
        dismiss_stale_reviews_on_push: true
        require_code_owner_review: true
        required_approving_review_count: 1
    
    - type: required_status_checks
      parameters:
        strict_required_status_checks_policy: true
        required_status_checks: []
  
  bypass_actors: []
```

**Note:** YAML can be used for both APIs - the script converts YAML→JSON before calling GitHub's REST API. The difference is in the YAML schema structure, not the file format itself.

---

#### Option 3: Support Both (Abstraction Layer)
**Approach:** Detect which API is in use and adapt accordingly

**Pros:**
- ✅ Maximum flexibility across FOG repos
- ✅ Works with legacy Branch Protection setups
- ✅ Works with modern Ruleset configurations
- ✅ Smooth migration path for teams
- ✅ Future-proof

**Cons:**
- ❌ More complex implementation (~2x code)
- ❌ Increased maintenance burden
- ❌ Need to normalize different API responses
- ❌ Requires testing against both APIs
- ❌ Delayed delivery timeline

**Implementation Approach:**
```bash
# Auto-detection logic in repocheck script
detect_api_type() {
    local repo=$1
    local branch=$2
    
    # Check if rulesets exist for this branch
    if gh api "repos/$repo/rulesets" 2>/dev/null | \
       jq -e --arg branch "$branch" '.[] | select(.conditions.ref_name.include[] | contains($branch))' > /dev/null; then
        echo "rulesets"
    else
        echo "branch-protection"
    fi
}

API_TYPE=$(detect_api_type "$REPO" "$BRANCH")
case "$API_TYPE" in
    rulesets)
        gh api "repos/$REPO/rulesets" | jq '...'
        ;;
    branch-protection)
        gh api "repos/$REPO/branches/$BRANCH/protection"
        ;;
esac
```

---

### Comparison Matrix

| Feature | Branch Protection Rules | Rulesets API |
|---------|------------------------|--------------|
| **Signed commits** | ✅ `required_signatures` | ✅ `required_signatures` rule |
| **Linear history** | ✅ `required_linear_history` | ✅ `required_linear_history` rule |
| **PR reviews** | ✅ `required_pull_request_reviews` | ✅ `pull_request` rule |
| **Code owner reviews** | ✅ Nested option | ✅ Parameter in pull_request rule |
| **Status checks** | ✅ `required_status_checks` | ✅ `required_status_checks` rule |
| **Enforce for admins** | ✅ `enforce_admins` | ✅ Implicit (bypass actors instead) |
| **Organization-wide** | ❌ No | ✅ Yes (`/orgs/{org}/rulesets`) |
| **Multi-branch targeting** | ❌ One pattern per config | ✅ Multiple includes/excludes |
| **File path restrictions** | ❌ No | ✅ Yes (via conditions) |
| **API Maturity** | ⚠️ Legacy (stable) | ✅ Modern (active development) |
| **YAML Support** | ✅ Yes (nested structure) | ✅ Yes (array-based structure) |
| **Migration Complexity** | N/A | ⚠️ Medium (different YAML schema
| **Migration Complexity** | N/A | ⚠️ Medium (different JSON structure) |

---

### Recommendation: **Option 1 (Branch Protection Rules API) for Initial Implementation**

**Rationale:**
1. **Current state**: All existing FOG repos likely use Branch Protection Rules
2. **Immediate value**: Works without requiring repo configuration changes
3. **Lower risk**: Stable API with 9+ years of production use
4. **Simpler validation**: Direct 1:1 mapping to YAML config structure
5. **Faster delivery**: 2-3 days vs 4-5 days with abstraction layer
6. **Clear migration path**: Can add Rulesets in future without breaking existing validation

**Important:** YAML works with BOTH APIs - the choice is about which API structure to use, not whether YAML is possible. Our script converts YAML→JSON for both APIs.

**Why Not Rulesets Now:**
- ❌ Unknown FOG adoption rate (needs audit of repos)
- ❌ Different YAML schema structure (rule arrays vs nested properties)
- ❌ PSREGOV-3704 hasn't decided on Rulesets vs Branch Protection
- ❌ Migration effort for existing repos not scoped
- ❌ Read-only validation works identically for both APIs
- ❌ Requires YAML schema redesign from current Branch Protection structure

**When to Reconsider Rulesets:**
- ✅ PSREGOV-3704 mandates organization-wide rulesets
- ✅ FOG decides to migrate all repos to Rulesets
- ✅ Need file-path-based protection rules
- ✅ Organization-level policy enforcement required

**Implementation Strategy:**
- **Phase 1 (this ticket)**: Branch Protecnested structure (as shown in Deliverable #1)
  - Script converts YAML→JSON before API calls
  
- **Phase 2 (future ticket)**: Add Rulesets API detection
  - Detect which API repo is using
  - Add Rulesets response normalization
  - Support BOTH YAML schemas (Branch Protection format OR Rulesets format)
  - Script detects format from YAML structure (`branch_protection:` vs `ruleset:`)
  
- **Phase 3 (future ticket)**: Full Rulesets support
  - Support organization-level rulesets
  - File path restrictions
  - Advanced targeting conditions
  - YAML-to-Rulesets transformation if using Branch Protection YAML structurell Rulesets support
  - Support organization-level rulesets
  - File path restrictions
  - Advanced targeting conditions
 and YAML format support

# Detect YAML format type
detect_yaml_format() {
    local config_file=$1
    if yq eval '.branch_protection' "$config_file" &>/dev/null; then
        echo "branch-protection"
    elif yq eval '.ruleset' "$config_file" &>/dev/null; then
        echo "rulesets"
    else
        echo "unknown"
    fi
}

# Convert YAML to appropriate JSON for each API
convert_config() {
    local config_file=$1
    local api_type=$2
    
    case "$api_type" in
        branch-protection)
            # Direct conversion - nested structure matches API
            yq eval -o=json '.branch_protection' "$config_file"
            ;;
        rulesets)
            # Convert ruleset structure to API format
            yq eval -o=json '.ruleset' "$config_file"
            ;;
    esac
}

# Fetch protection config from GitHub
fetch_protection_config() {
    local repo=$1
    local branch=$2
    local api_version=${3:-"branch-protection"}  # Default to Branch Protection
    
    case "$api_version" in
        branch-protection)
            gh api "repos/$repo/branches/$branch/protection" \
                --jq '{
                    required_signatures: .required_signatures.enabled,
                    required_linear_history: .required_linear_history.enabled,
                    ...
                }'
            ;;
        rulesets)
            # Future: Rulesets API implementation
            gh api "repos/$repo/rulesets" \
                --jq "[.[] | select(.conditions.ref_name.include[] | contains(\"$branch\"))] | {
                    ...
                }"
            ;;
    esac
}

# Usage example:
# FORMAT=$(detect_yaml_format .github/branch-protection.yml)
# if [ "$FORMAT" = "branch-protection" ]; then
#     fetch_protection_config "$REPO" "$BRANCH" "branch-protection"
# elif [ "$FORMAT" = "rulesets" ]; then
#     fetch_protection_config "$REPO" "$BRANCH" "rulesets"
# fi               }"
            ;;
    esac
}
```

**Decision Owner:** Platform/Security Team + PSREGOV-3704 outcome

---

## Dependencies

### Required
- **PSREGOV-3704**: Standard branch rules definition
  - Provides authoritative list of required settings
  - Defines specific values for each protection rule
  - **Decides Branch Protection Rules vs Rulesets API**
  - **Status:** Referenced in this ticket, specific values to be finalized

- **GitHub CLI (`gh`)**: Required for API access
- **`yq` tool**: Required for YAML processing
- **`jq` tool`: Required for JSON processing

### Optional
- **GitHub Copilot**: For script development assistance
- **Pre-commit framework**: For local validation hooks

---

## Out of Scope

The following are **explicitly excluded** from this ticket:

❌ **Automated remediation** - No automatic application of branch rules  
❌ **Write permissions** - Script remains read-only  
❌ **GHA auto-apply** - Manual approval workflow (separate ticket)  
❌ **Multiple branches** - Focus on `main` branch only  
❌ **Rulesets API** - Use Branch Protection Rules API (Rulesets support in future ticket if needed per PSREGOV-3704)  
❌ **Organization-level policies** - Repository-specific only  
❌ **Custom GitHub App** - Use GitHub CLI and standard tokens  
❌ **Deciding API choice** - Deferred to PSREGOV-3704; this ticket uses Branch Protection Rules as default  
❌ **Specific status check implementations** - Checkov workflows, unit tests, etc. are repo-specific (not standardized)  
❌ **Validating check existence** - Only validates that check names match if specified in YAML, not that workflows exist  

**Rationale:** This ticket focuses on **validation and visibility** without privileged access. Automated enforcement requires additional security architecture (see jira-ticket1.md for comprehensive approach).

---

## Testing Strategy

### Unit Testing
```bash
# Test 1: Valid configuration
./scripts/repocheck tester311249/llm-security
# Expected: Exit 0, "Configuration matches"

# Test 2: Schema validation
./scripts/validate-schema.sh .github/branch-protection.yml
# Expected: Exit 0, all required fields present

# Test 3: Invalid YAML
echo "invalid: [" > /tmp/test.yml
./scripts/validate-schema.sh /tmp/test.yml
# Expected: Exit 1, syntax error

# Test 4: Missing required field
yq eval 'del(.branch_protection.required_signatures)' .github/branch-protection.yml > /tmp/test.yml
./scripts/validate-schema.sh /tmp/test.yml
# Expected: Exit 1, missing field error
```

### Integration Testing
1. **PR workflow:** Create PR changing config → verify comment posted
2. **Drift detection:** Manually change GitHub setting → verify issue created
3. **JSON output:** Run with `json` format → verify parseable JSON
4. **Permissions:** Verify script cannot modify settings (no write token)

### Manual Verification
- [ ] Manually disable branch protection in GitHub UI
- [ ] Run workflow → verify drift detected
- [ ] Re-enable protection to match YAML
- [ ] Run workflow → verify no drift

---

## Timeline Estimate

**Total:** 2-3 days

### Day 1: Core Implementation (5-6 hours)
- Create `.github/branch-protection.yml` (30 min)
- Implement `repocheck` script (2 hours)
- Implement `validate-schema.sh` (1 hour)
- Local testing (1-2 hours)

### Day 2: GitHub Actions (4-5 hours)
- Create workflow file (2 hours)
- Test PR validation (1 hour)
- Test drift detection (1 hour)
- Fix issues and refine (1 hour)

### Day 3: Documentation & Refinement (3-4 hours)
- Update README (1 hour)
- Create adoption guide (1 hour)
- End-to-end testing (1 hour)
- CODEOWNERS and final review (1 hour)

**Contingency:** +1 day for edge cases and refinements

---

## Success Metrics

### Immediate (Post-Implementation)
- ✅ `repocheck` runs successfully on llm-security repo
- ✅ Workflow completes without errors on PR
- ✅ Drift detection creates issue when config changes
- ✅ All acceptance criteria met

### Short-term (1 month)
- 📊 Zero false positives in drift detection
- 📊 100% of configuration changes detected
- 📊 Script adopted in 2-3 pilot FOG repos

### Long-term (6 months)
- 📊 80%+ FOG repos using branch protection validation
- 📊 Configuration drift incidents reduced by 90%
- 📊 Security audit compliance improved

---

## References

### Internal Documentation
- **[jira-ticket1.md](jira-ticket1.md)** - Comprehensive implementation with write operations
- **[working-with-git-repos.md](working-with-git-repos.md)** - Team guidelines for Git workflows + API choice decision

### GitHub API Documentation
- **Branch Protection Rules API**: https://docs.github.com/en/rest/branches/branch-protection
- **Rulesets API** (comparison): https://docs.github.com/en/rest/repos/rules
- **GitHub Rules Overview**: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesetches/branch-protection
- **Rulesets API** (future): https://docs.github.com/en/rest/repos/rules
- **GitHub CLI**: https://cli.github.com/manual/gh_api

### Tools
- **yq (YAML processor)**: https://github.com/mikefarah/yq
- **jq (JSON processor)**: https://stedolan.github.io/jq/
- **GitHub Actions**: https://docs.github.com/en/actions

---

## Implementation Notes

### Why Read-Only?

This ticket focuses on **validation without privilege** because:
1. ✅ Enables security teams to monitor without admin access
2. ✅Status Checks vs Branch Protection

**Important Distinction:**

**Branch Protection (this ticket):**
- Framework for requiring status checks
- Validates `required_status_checks.strict: true` 
- Can list required check names
- Enforced via GitHub branch protection settings

**Status Check Implementation (repo-specific):**
- Individual workflows (Checkov, unit tests, linting, etc.)
- Implemented via `.github/workflows/*.yml` in each repo
- Each repo chooses which checks to run
- Not standardized across FOG (context-dependent)

**Example:**
```yaml
# Branch protection YAML (this ticket validates this)
required_status_checks:
  strict: true
  contexts:
    - "checkov"
    - "terraform-validate"
    
# Repo implements these via workflows (repo-specific, not validated here)
# .github/workflows/checkov.yml
# .github/workflows/terraform-validate.yml
```

###  Reduces attack surface (no write permissions in automated workflows)
3. ✅ Allows deployment in repos where team lacks admin rights
4. ✅ Provides foundation for future write operations (see jira-ticket1.md)

### Future Enhancements

For **automated enforcement** with write permissions, see [jira-ticket1.md](jira-ticket1.md) which includes:
- 7-layer security architecture
- Manual approval gates (GitHub Environments)
- `repoconfig` script for applying settings
- Comprehensive attack scenario prevention
- Audit logging and rollback capabilities

---

**Ticket ID:** PSREGOV-3705 (assumed)  
**Related:** PSREGOV-3704 (Standard Branch Rules)  
**Owner:** Platform/Security Team  
**Priority:** High  
**Status:** Ready for Implementation