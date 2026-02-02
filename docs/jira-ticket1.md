# Branch Protection as Code - Testing & Validation

## Problem Statement

We need a way to test branch settings of GitHub repositories against a known state defined in code. This will:
- Enable better visibility of branch settings (hidden in UI, only accessible to certain GitHub groups)
- Prevent configuration drift
- Support security auditing and compliance
- Allow version-controlled branch protection policies

## Solution Approach

Implement **Branch Protection as Code** with automatic drift detection but **manual** enforcement (setting branch rules requires privileged access).

## Deliverables

### 1. Migrate Configuration Format: JSON → YAML

**Current:** `config/branch-protection.json`  
**New:** `.github/branch-protection.yml`

**Migration Task:**
```bash
# Convert existing JSON to YAML
yq eval -P config/branch-protection.json > .github/branch-protection.yml
```

**Rationale:** Team principle - "humans don't read json!"

**Example YAML:**
```yaml
# .github/branch-protection.yml
branch_protection:
  branch: main
  required_pull_request_reviews:
    dismiss_stale_reviews: true
    require_code_owner_reviews: true
    required_approving_review_count: 1
  enforce_admins: true
  required_conversation_resolution: true
  allow_force_pushes: false
  allow_deletions: false
  
  # Advanced: File-pattern-based approvers (NEW)
  required_reviewers:
    - pattern: "terraform/**/*.tf"
      teams: ["@org/platform-team"]
    - pattern: ".github/workflows/**"
      teams: ["@org/security-team"]
```

**Note:** Specific rules standardized in PSREGOV-3704.

---

### 2. Create Portable Scripts (Enhancement)

**Current:** `scripts/validate-protection-config.sh` (single script, JSON-focused)  
**New:** Two-script pattern for clarity and reusability

#### **Script 1: `repocheck` (Enhanced Validation)**

**Purpose**: Check GitHub config against YAML, output structured diff

**Enhancements over existing script:**
- Accept both JSON and YAML input formats
- Structured output (JSON/YAML) for GHA parsing
- Exit codes: 0 (match), 1 (drift), 2 (error)
- Support for Rulesets API (if chosen in PSREGOV-3704)

**Implementation:**
```bash
#!/usr/bin/env bash
# repocheck - Compare actual vs desired branch protection config

REPO="${1:?Repository required (owner/repo)}"
CONFIG_FILE="${2:-.github/branch-protection.yml}"
OUTPUT_FORMAT="${3:-json}"  # json|yaml|text

# Fetch current config from GitHub
gh api "repos/$REPO/branches/main/protection" > /tmp/current.json

# Convert YAML config to JSON for comparison
yq eval -o=json "$CONFIG_FILE" > /tmp/desired.json

# Compare and output diff
diff_result=$(jq --slurp '.[0] as $current | .[1] as $desired | {...}' /tmp/current.json /tmp/desired.json)

if [ "$diff_result" = "{}" ]; then
  echo "✅ Configuration matches"
  exit 0
else
  echo "❌ Drift detected:"
  echo "$diff_result" | jq '.'
  exit 1
fi
```

**Storage:** `scripts/repocheck` (in this repo) + organization tooling repo

---

#### **Script 2: `repoconfig` (Write - Privileged)**

**Purpose**: Apply YAML configuration to GitHub repository

**Enhancements over manual API calls:**
- Support both JSON and YAML config files
- Dry-run mode (`--dry-run` flag)
- Comprehensive audit logging
- Rollback capability (store previous config)
- Support for Rulesets API

**Implementation:**
```bash
#!/usr/bin/env bash
# repoconfig - Apply branch protection config to GitHub

REPO="${1:?Repository required (owner/repo)}"
CONFIG_FILE="${2:-.github/branch-protection.yml}"
DRY_RUN="${3:-false}"

# Convert YAML to JSON if needed
if [[ "$CONFIG_FILE" =~ \.ya?ml$ ]]; then
  config_json=$(yq eval -o=json "$CONFIG_FILE")
else
  config_json=$(cat "$CONFIG_FILE")
fi

# Backup current config
gh api "repos/$REPO/branches/main/protection" > "/tmp/backup-$(date +%s).json"

# Apply configuration
if [ "$DRY_RUN" = "true" ]; then
  echo "🔍 DRY RUN - Would apply:"
  echo "$config_json" | jq '.'
else
  gh api "repos/$REPO/branches/main/protection" -X PUT --input - <<< "$config_json"
  echo "✅ Configuration applied"
  
  # Audit log
  echo "$(date) - Applied by $USER - Repo: $REPO" >> /var/log/branch-protection-audit.log
fi
```

**Security**: This script **MUST NOT** run automatically in GHA on PRs (maintains existing security model)

**Storage:** `scripts/repoconfig` + organization tooling repo

---

### 3. Enhanced GitHub Actions Workflow

**Current:** `manage-branch-protection.yml` (creates issues on drift)  
**New:** Add PR comment + label capabilities

**File**: `.github/workflows/check-branch-protection.yml`

**Existing Triggers (Keep):**
```yaml
on:
  push:
    branches: [main]  # Apply config after merge (with manual approval)
    paths:
      - '.github/branch-protection.yml'
      - 'config/branch-protection.json'  # Legacy support during migration
  schedule:
    - cron: '0 2 * * 1'  # Weekly drift detection
  workflow_dispatch:  # Manual trigger
```

**New Triggers (Add):**
```yaml
on:
  pull_request:  # NEW: Check on PRs (read-only validation)
    paths:
      - '.github/branch-protection.yml'
      - '.github/workflows/check-branch-protection.yml'
```

**Enhanced Jobs:**
```yaml
jobs:
  # Existing: validation (keep)
  validate-config:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate YAML syntax
        run: yq eval '.github/branch-protection.yml' > /dev/null
      - name: Validate schema
        run: ./scripts/validate-schema.sh

  # NEW: Check for drift with PR feedback
  check-drift:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request' || github.event_name == 'schedule'
    permissions:
      pull-requests: write  # For comments
      issues: write  # For labels
    steps:
      - uses: actions/checkout@v4
      
      - name: Run repocheck
        id: check
        run: |
          ./scripts/repocheck "${{ github.repository }}" > drift-report.json
          echo "drift_detected=$?" >> $GITHUB_OUTPUT
      
      - name: Post PR comment if drift
        if: github.event_name == 'pull_request' && steps.check.outputs.drift_detected == '1'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const drift = JSON.parse(fs.readFileSync('drift-report.json', 'utf8'));
            
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `## ⚠️ Branch Protection Drift Detected\n\n\`\`\`json\n${JSON.stringify(drift, null, 2)}\n\`\`\``
            });
      
      - name: Add label if drift
        if: steps.check.outputs.drift_detected == '1'
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.addLabels({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              labels: ['config-drift', 'needs-review']
            });

  # Existing: apply config (keep with all security layers)
  apply-config:
    needs: validate-config
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: branch-protection-admin  # Manual approval required
    steps:
      - uses: actions/checkout@v4
      - name: Apply configuration
        run: ./scripts/repoconfig "${{ github.repository }}"
        env:
          GH_TOKEN: ${{ secrets.BRANCH_PROTECTION_TOKEN }}
      
      - name: Audit log
        run: |
          echo "Timestamp: $(date)"
          echo "Actor: ${{ github.actor }}"
          echo "Commit: ${{ github.sha }}"
```

**Security Note:** Maintains all 7 existing security layers from llm-security implementation.

---

### 4. Pre-commit Hook (NEW)

**Purpose**: Local validation before commit (catch issues early)

**Add to `.pre-commit-config.yaml`:**
```yaml
repos:
  - repo: local
    hooks:
      - id: validate-branch-protection-yaml
        name: Validate branch protection YAML
        entry: bash -c 'yq eval .github/branch-protection.yml > /dev/null'
        language: system
        files: ^\.github/branch-protection\.ya?ml$
        pass_filenames: false
      
      - id: check-branch-protection-schema
        name: Check branch protection schema
        entry: scripts/validate-schema.sh
        language: script
        files: ^\.github/branch-protection\.ya?ml$
        pass_filenames: false
      
      - id: run-repocheck-local
        name: Run repocheck (optional, slow)
        entry: scripts/repocheck
        language: script
        files: ^\.github/branch-protection\.ya?ml$
        pass_filenames: false
        stages: [manual]  # Only run if explicitly invoked
```

**Installation Instructions:**
```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Test
pre-commit run --all-files
```

---

### 6. Migration Guide Documentation (NEW)

**File**: `docs/MIGRATION.md` (in tooling repo)

**Purpose**: Guide for migrating existing repos from JSON to YAML

**Content Outline**:
1. Backup current configuration via GitHub API
2. Convert JSON to YAML (`yq eval -P config.json > config.yml`)
3. Update workflow file paths
4. Update CODEOWNERS file references
5. Test validation with new YAML format
6. Remove deprecated JSON file
7. Update repo README with new paths

---

### 7. Security Architecture (Maintain All 7 Layers)

**Reference**: See [branch-protection-security.md](branch-protection-security.md) for comprehensive documentation.

**Critical Principle:** All security layers from llm-security implementation MUST be preserved:

✅ **Layer 1: CODEOWNERS Protection**

**Purpose**: Store reusable scripts for adoption across FOG repos

**Proposed Structure:**
```
govuk-one-login/repo-governance-tools/
├── scripts/
│   ├── repocheck           # Read-only validation
│   ├── repoconfig          # Write operations (privileged)
│   └── validate-schema.sh  # YAML schema validation
├── templates/
│   ├── branch-protection.yml.example
│   ├── workflows/
│   │   └── check-branch-protection.yml
│   └── pre-commit-config.yaml
├── docs/
│   ├── SETUP.md            # Multi-repo adoption guide
│   └── MIGRATION.md        # JSON → YAML migration
└── README.md
```

**Adoption Flow for Other Repos:**
```bash
# 1. Install scripts
curl -o scripts/repocheck https://raw.githubusercontent.com/govuk-one-login/repo-governance-tools/main/scripts/repocheck
curl -o scripts/repoconfig https://raw.githubusercontent.com/govuk-one-login/repo-governance-tools/main/scripts/repoconfig
chmod +x scripts/repocheck scripts/repoconfig

# 2. Copy template config
curl -o .github/branch-protection.yml https://raw.githubusercontent.com/govuk-one-login/repo-governance-tools/main/templates/branch-protection.yml.example

# 3. Copy workflow
curl -o .github/workflows/check-branch-protection.yml https://raw.githubusercontent.com/govuk-one-login/repo-governance-tools/main/templates/workflows/check-branch-protection.yml

# 4. Update CODEOWNERS
echo "/.github/branch-protection.yml @your-security-team" >> .github/CODEOWNERS
```

---

### 6. Migration Guide (NEW Documentation)

```
/.github/branch-protection.yml @org/security-team
/.github/workflows/check-branch-protection.yml @org/security-team
/scripts/repocheck @org/security-team
/scripts/repoconfig @org/security-team
```

✅ **Layer 2: Branch Protection on Main** - Require code owner reviews, enforce for admins

✅ **Layer 3: Workflow Triggers** - Apply workflow runs ONLY on push to main (never on `pull_request`)

✅ **Layer 4: GitHub Environment Protection** - Manual approval required before applying changes

✅ **Layer 5: Validation Before Application** - Syntax, schema, security checks pass before application

✅ **Layer 6: Audit Logging** - Who, what, when logged for all configuration changes

✅ **Layer 7: Drift Detection** - Weekly cron detects manual changes outside workflow

**New Enhancement:** Add PR comments + labels (Layer 7 improvement)

**Security Documentation:** All security considerations documented in [branch-protection-security-faq.md](branch-protection-security-faq.md)

---

## Acceptance Criteria

### Phase 1: Core Migration (llm-security repo)
- [ ] Convert `config/branch-protection.json` → `.github/branch-protection.yml`
- [ ] Create `scripts/repocheck` (enhanced with YAML support)
- [ ] Create `scripts/repoconfig` (enhanced with YAML support)
- [ ] Update workflow to support both JSON (legacy) and YAML
- [ ] Add PR comment functionality to workflow
- [ ] Add PR labeling for config drift
- [ ] Add pre-commit hooks configuration
- [ ] Update branch-protection-security.md documentation
- [ ] Test end-to-end: PR → validation → merge → manual approval → apply

### Phase 2: Reusable Tooling
- [ ] Create organization tooling repository (`repo-governance-tools`)
- [ ] Port scripts to tooling repo with multi-repo support
- [ ] Create template files for easy adoption
- [ ] Write SETUP.md guide for other repos
- [ ] Write MIGRATION.md for JSON→YAML transitions
- [ ] Test adoption in 1-2 pilot repos (e.g., ct-aws-sample-pipeline)

### Phase 3: Advanced Features (Optional)
- [ ] Implement file-pattern-based required reviewers
- [ ] Add JSON Schema validation for YAML files
- [ ] Support for Repository Rulesets API (if chosen in PSREGOV-3704)
- [ ] Multi-branch protection support (not just main)
- [ ] Dashboard/reporting for compliance across repos

---

## Technical Decisions Required

### 1. Branch Protection API vs Rulesets API

**Status:** Pending decision in PSREGOV-3704

**Current:** Uses Branch Protection Rules API  
**Option:** Migrate to Rulesets API (newer, more flexible)

**Impact:** Scripts must support chosen API

**References:**
- Branch Protection: https://docs.github.com/en/rest/branches/branch-protection
- Rulesets: https://docs.github.com/en/rest/repos/rules

**Recommendation:** Wait for PSREGOV-3704 decision, design scripts to support both (abstraction layer)

### 2. Organization Tooling Repository Location

**Options:**
1. New repo: `govuk-one-login/repo-governance-tools` (recommended)
2. Existing template: `govuk-one-login/ct-aws-sample-pipeline`
3. Each repo maintains own copy (not recommended - no centralization)

**Recommendation:** Option 1 - dedicated tooling repo for governance

### 3. Config File Location

**Options:**
- `.github/branch-protection.yml` (recommended - follows GitHub conventions)
- `config/branch-protection.yml` (current in llm-security)
- `.github/branch-rules.yml` (alternative name)

**Recommendation:** `.github/branch-protection.yml` for consistency with GitHub patterns

---

## Dependencies

- **PSREGOV-3704**: Defines standardized branch rules
  - Required before finalizing YAML schema
  - Required before adding schema validation
- **Tooling repo creation**: Need org admin approval
- **GitHub token permissions**: Branch protection admin token setup
- **Pre-commit tooling**: Team adoption of pre-commit framework

---

## Out of Scope (Future Tickets)

- Auto-remediation of drift (always requires manual approval)
- Multi-repository orchestration/bulk updates
- Custom GitHub App for branch protection management
- Terraform/IaC integration for GitHub settings
- Support for organization-level rulesets
- Branch protection for non-main branches (separate ticket if needed)

---

## Testing Strategy

### Unit Testing
- Scripts tested with mock GitHub API responses
- YAML validation tested with valid/invalid configs
- Schema validation tested with edge cases

### Integration Testing
- Test in llm-security repo first (existing implementation)
- Dry-run mode testing for `repoconfig` script
- Test PR workflow: comment posting, labeling
- Test environment protection: manual approval flow

### Pilot Repos
- Select 2-3 diverse FOG repos for pilot adoption
- Document issues encountered
- Refine tooling based on feedback

---

## Timeline Estimate

**Phase 1 (Core Migration):** 3-5 days
- Day 1: JSON→YAML conversion, script enhancement
- Day 2: Workflow updates, PR comment/label features
- Day 3: Pre-commit hooks, testing
- Day 4-5: Documentation updates, end-to-end validation

**Phase 2 (Reusable Tooling):** 2-3 days
- Day 1: Tooling repo setup, script porting
- Day 2: Templates, adoption guides
- Day 3: Pilot repo testing

**Total:** 5-8 days (assuming PSREGOV-3704 rules already defined)

---

## Security Notes

**Critical Reminders:**

⚠️ **Never add `pull_request` trigger to apply workflow** - Privilege escalation risk documented in [branch-protection-security-faq.md](branch-protection-security-faq.md)

⚠️ **Always require manual approval** - Environment protection is non-negotiable

⚠️ **Protect the protectors** - Config files and scripts MUST be in CODEOWNERS

⚠️ **Audit everything** - Log who applies changes, when, and what changed

**Attack Prevention:** See comprehensive attack scenario analysis in [branch-protection-security-faq.md](branch-protection-security-faq.md) - all 7 layers prevent privilege escalation

---

## References

### Existing Implementation
- **Implementation Guide**: [branch-protection-security.md](branch-protection-security.md) (575 lines)
- **Security FAQ**: [branch-protection-security-faq.md](branch-protection-security-faq.md)
- **Working Repo**: tester311249/llm-security (this repo)

### GitHub Documentation
- Branch Protection API: https://docs.github.com/en/rest/branches/branch-protection
- Rulesets API: https://docs.github.com/en/rest/repos/rules
- CODEOWNERS: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
- GitHub Environments: https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment

### FOG Resources
- Template repo: https://github.com/govuk-one-login/ct-aws-sample-pipeline
- Working with repos: [working-with-git-repos.md](working-with-git-repos.md)
- Standardized rules: PSREGOV-3704 (pending)

---

## Success Metrics

- **Adoption**: 80% of FOG repos using branch protection as code within 6 months
- **Drift detection**: Zero undetected config changes
- **Security**: Zero privilege escalation incidents
- **Developer experience**: Config changes take <15 minutes (PR creation to application)
- **Compliance**: 100% audit trail for all branch protection modifications

---

**Owner:** Platform/Security Team  
**Stakeholders:** All FOG repo maintainers  
**Status:** Ready for Implementation (pending PSREGOV-3704) 