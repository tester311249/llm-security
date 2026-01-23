# Branch Protection as Code - Security Documentation

**Repository:** tester311249/llm-security  
**Last Updated:** 23 January 2026  
**Status:** ✅ Implemented with Security Controls

---

## 🔒 Overview

This repository implements **Branch Protection as Code** - storing branch protection rules in version control while maintaining strict security controls to prevent privilege escalation attacks.

### Key Security Principle

**CRITICAL:** Branch protection configuration files have admin-level privileges. We implement multiple security layers to prevent malicious modification.

---

## 📁 File Structure

```
llm-security/
├── config/
│   └── branch-protection.json          # Branch protection rules (PROTECTED)
├── scripts/
│   └── validate-protection-config.sh   # Validation script (PROTECTED)
├── .github/
│   ├── CODEOWNERS                      # Protects security-critical files
│   └── workflows/
│       ├── manage-branch-protection.yml # Applies rules (PROTECTED)
│       └── validate-codeowners.yml      # Validates CODEOWNERS
└── docs/
    └── branch-protection-security.md   # This file
```

---

## 🛡️ Security Architecture

### The Privilege Escalation Risk

**Attack Scenario:**
```yaml
# ❌ INSECURE - DO NOT DO THIS
name: Apply Branch Protection
on:
  pull_request:  # Runs on untrusted PR code!

jobs:
  apply:
    steps:
      - uses: actions/checkout@v3  # Checks out attacker's PR
      - run: |
          # Attacker can modify this script
          gh api repos/$REPO/branches/main/protection -X PUT --input config/branch-protection.json
        env:
          GH_TOKEN: ${{ secrets.ADMIN_TOKEN }}  # Has admin permissions!
```

**Attack Flow:**
1. Attacker forks repository
2. Modifies `config/branch-protection.json` to disable all protections
3. Modifies workflow to exfiltrate secrets or inject code
4. Opens PR → Workflow runs with admin token
5. Branch protection disabled, malicious code merged

### Our Security Layers

#### Layer 1: CODEOWNERS Protection

```
# .github/CODEOWNERS
/config/branch-protection.json @tester311249
/.github/workflows/manage-branch-protection.yml @tester311249
/.github/CODEOWNERS @tester311249
```

**Effect:** All changes to security files require admin approval via code review.

#### Layer 2: Branch Protection on Main

```json
{
  "enforce_admins": true,
  "require_code_owner_reviews": true,
  "required_approving_review_count": 1
}
```

**Effect:** Even repo admins must go through PR process. Direct pushes blocked.

#### Layer 3: Workflow Triggers

```yaml
on:
  push:
    branches: [main]  # Only after merge to main
  # NO pull_request trigger!
```

**Effect:** Workflow never runs on untrusted PR code.

#### Layer 4: GitHub Environment Protection

```yaml
environment:
  name: branch-protection-admin
```

**Configuration Required:**
```bash
# Setup environment with protection rules
gh api repos/tester311249/llm-security/environments/branch-protection-admin \
  -X PUT \
  -f prevent_self_review=true \
  -f reviewers[][id]=<ADMIN_USER_ID>
```

**Effect:** Manual approval required from designated admin before applying changes.

#### Layer 5: Validation Before Application

```yaml
jobs:
  validate:
    # Checks JSON syntax, required fields, security best practices
  
  apply:
    needs: validate  # Only runs if validation passes
```

**Effect:** Malformed or insecure configurations rejected before application.

#### Layer 6: Audit Logging

```yaml
- name: Audit log
  run: |
    echo "Timestamp: $(date)"
    echo "Actor: ${{ github.actor }}"
    echo "Commit: ${{ github.sha }}"
```

**Effect:** All changes logged for audit trail and incident response.

#### Layer 7: Drift Detection

```yaml
on:
  schedule:
    - cron: '0 2 * * 1'  # Weekly check
```

**Effect:** Detects manual changes made outside the workflow and alerts.

---

## 🔧 Configuration

### Branch Protection Rules

File: `config/branch-protection.json`

```json
{
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1
  },
  "enforce_admins": true,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
```

**Fields Explained:**

- `require_code_owner_reviews`: Enforces CODEOWNERS file
- `enforce_admins`: Admins cannot bypass protection
- `required_conversation_resolution`: All review comments must be resolved
- `allow_force_pushes`: false - Prevents history rewriting
- `allow_deletions`: false - Prevents branch deletion

---

## 🚀 Usage

### Initial Setup (One-Time)

#### Step 1: Create GitHub Environment

```bash
# Get your user ID
USER_ID=$(gh api user --jq '.id')

# Create protected environment
gh api repos/tester311249/llm-security/environments/branch-protection-admin \
  -X PUT \
  -f prevent_self_review=true \
  -f wait_timer=0 \
  -f reviewers[][type]=User \
  -f reviewers[][id]=$USER_ID
```

#### Step 2: Verify Current Setup

```bash
# View current branch protection
gh api repos/tester311249/llm-security/branches/main/protection

# Run manual validation
./scripts/validate-protection-config.sh config/branch-protection.json
```

### Making Changes

#### Step 1: Create Feature Branch

```bash
git checkout -b update-branch-protection
```

#### Step 2: Modify Configuration

```bash
# Edit the configuration file
vim config/branch-protection.json

# Validate locally
./scripts/validate-protection-config.sh config/branch-protection.json
```

#### Step 3: Commit and Push

```bash
git add config/branch-protection.json
git commit -m "Update branch protection: increase required reviews to 2"
git push origin update-branch-protection
```

#### Step 4: Create Pull Request

```bash
gh pr create \
  --title "Update branch protection rules" \
  --body "Increasing required review count from 1 to 2 for enhanced security"
```

#### Step 5: Review and Approve

- PR requires approval from `@tester311249` (CODEOWNERS)
- Validation workflow runs automatically
- Review the changes carefully
- Approve and merge

#### Step 6: Approve Deployment

After merge, workflow runs on `main` branch:

1. GitHub will pause at environment protection
2. Admin receives notification for manual approval
3. Review the deployment request
4. Approve to apply the changes

```bash
# Monitor workflow
gh run watch

# Or approve via web UI
# https://github.com/tester311249/llm-security/actions
```

### Manual Application

```bash
# Apply current configuration immediately (requires approval)
gh workflow run manage-branch-protection.yml

# Just validate without applying
gh workflow run manage-branch-protection.yml -f action=validate

# Show current protection settings
gh workflow run manage-branch-protection.yml -f action=show-current
```

---

## 🧪 Testing & Validation

### Automated Validation

Runs automatically on every PR that touches `config/branch-protection.json`:

```bash
# Local validation
./scripts/validate-protection-config.sh config/branch-protection.json
```

**Checks:**
- ✅ JSON syntax validity
- ✅ Required fields present
- ✅ Correct data types
- ✅ Security best practices
- ⚠️ Warns on insecure settings

### Drift Detection

Runs weekly via scheduled workflow:

```bash
# Manually trigger drift check
gh workflow run manage-branch-protection.yml

# View drift detection issues
gh issue list --label drift-detection
```

**When Drift Detected:**
1. Creates GitHub issue automatically
2. Shows difference between actual vs desired
3. Provides link to apply correct configuration

---

## 🔍 Monitoring & Auditing

### View Applied Configuration

```bash
# Current branch protection
gh api repos/tester311249/llm-security/branches/main/protection | jq '.'

# Compare with config file
diff \
  <(gh api repos/tester311249/llm-security/branches/main/protection | jq 'del(.url, .required_pull_request_reviews.url)') \
  <(jq '.' config/branch-protection.json)
```

### Audit Trail

```bash
# View workflow runs
gh run list --workflow=manage-branch-protection.yml --limit 10

# View specific run details
gh run view <RUN_ID> --log

# View who triggered each run
gh run list --workflow=manage-branch-protection.yml --json databaseId,headBranch,event,conclusion,startedAt,actor --jq '.[] | "\(.startedAt) - \(.actor.login) - \(.event) - \(.conclusion)"'
```

### Security Alerts

Monitor for:
- Unexpected workflow runs
- Failed validation checks
- Drift detection issues
- Manual bypasses (should be impossible with `enforce_admins: true`)

---

## ⚠️ Security Best Practices

### DO ✅

- **Always** require code owner reviews
- **Always** enable `enforce_admins: true`
- **Always** test changes in a test repository first
- **Always** review changes carefully before approving
- Use minimal required review count (balance security vs velocity)
- Enable drift detection to catch manual changes
- Maintain audit logs of all changes
- Document reasons for configuration changes

### DON'T ❌

- **Never** add `pull_request` trigger to apply workflow
- **Never** disable CODEOWNERS protection
- **Never** allow workflows to run without manual approval
- **Never** store admin tokens in plain text
- **Never** bypass the PR process (even admins)
- **Never** disable `enforce_admins`
- **Never** allow force pushes or branch deletion on protected branches
- **Never** merge PRs without validation passing

---

## 🔐 Incident Response

### Unauthorized Configuration Change

**If branch protection is disabled or weakened:**

```bash
# 1. Immediately restore protection
gh api repos/tester311249/llm-security/branches/main/protection \
  -X PUT \
  --input config/branch-protection.json

# 2. Check recent commits for malicious changes
git log --all --oneline -20

# 3. Check workflow runs for unauthorized executions
gh run list --limit 20

# 4. Review PR history
gh pr list --state all --limit 20

# 5. Check who has admin access
gh api repos/tester311249/llm-security/collaborators?permission=admin
```

### Token Compromise

**If `GITHUB_TOKEN` or admin token compromised:**

```bash
# 1. Revoke the compromised token immediately
gh auth token  # View current token
# Revoke via: https://github.com/settings/tokens

# 2. Rotate repository secrets
gh secret set GITHUB_TOKEN

# 3. Review recent activity
gh api repos/tester311249/llm-security/events

# 4. Check for unauthorized changes
git log --all --author="*" --since="1 week ago"
```

---

## 📊 Compliance & Reporting

### Generate Compliance Report

```bash
# Current status
cat << 'EOF' > check-compliance.sh
#!/bin/bash
echo "Branch Protection Compliance Report"
echo "==================================="
echo ""
echo "Repository: tester311249/llm-security"
echo "Generated: $(date)"
echo ""

# Check code owner reviews
REQUIRE_CODEOWNERS=$(gh api repos/tester311249/llm-security/branches/main/protection \
  --jq '.required_pull_request_reviews.require_code_owner_reviews' 2>/dev/null || echo "false")

# Check admin enforcement
ENFORCE_ADMINS=$(gh api repos/tester311249/llm-security/branches/main/protection \
  --jq '.enforce_admins.enabled' 2>/dev/null || echo "false")

# Check force push
ALLOW_FORCE=$(gh api repos/tester311249/llm-security/branches/main/protection \
  --jq '.allow_force_pushes.enabled' 2>/dev/null || echo "true")

echo "✅ Code Owner Reviews: $REQUIRE_CODEOWNERS"
echo "✅ Admin Enforcement: $ENFORCE_ADMINS"
echo "✅ Force Push Blocked: $([ "$ALLOW_FORCE" = "false" ] && echo "true" || echo "false")"
echo ""

# Compliance status
if [ "$REQUIRE_CODEOWNERS" = "true" ] && [ "$ENFORCE_ADMINS" = "true" ] && [ "$ALLOW_FORCE" = "false" ]; then
  echo "Status: ✅ COMPLIANT"
  exit 0
else
  echo "Status: ❌ NON-COMPLIANT"
  exit 1
fi
EOF

chmod +x check-compliance.sh
./check-compliance.sh
```

---

## 🆘 Troubleshooting

### Workflow Not Running

**Problem:** Workflow doesn't trigger after merge

**Solution:**
```bash
# Check workflow is enabled
gh workflow list

# Enable if disabled
gh workflow enable manage-branch-protection.yml

# Manually trigger
gh workflow run manage-branch-protection.yml
```

### Environment Protection Approval Blocked

**Problem:** Cannot approve deployment

**Solution:**
```bash
# Check environment exists
gh api repos/tester311249/llm-security/environments

# Check reviewers configured
gh api repos/tester311249/llm-security/environments/branch-protection-admin

# Re-configure if needed
gh api repos/tester311249/llm-security/environments/branch-protection-admin \
  -X PUT -f reviewers[][id]=<YOUR_USER_ID>
```

### Validation Failing

**Problem:** Configuration validation fails

**Solution:**
```bash
# Run validation locally
./scripts/validate-protection-config.sh config/branch-protection.json

# Check JSON syntax
jq empty config/branch-protection.json

# View validation errors
./scripts/validate-protection-config.sh config/branch-protection.json 2>&1 | less
```

---

## 📚 References

- [GitHub Branch Protection API](https://docs.github.com/en/rest/branches/branch-protection)
- [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [CODEOWNERS Documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
- [GitHub Actions Security](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)

---

## 📝 Change Log

| Date | Change | Author | Reason |
|------|--------|--------|--------|
| 2026-01-23 | Initial implementation | @tester311249 | Infrastructure as Code for branch protection |

---

## ✅ Security Checklist

Before going live, verify:

- [ ] CODEOWNERS file protects security-critical files
- [ ] Branch protection requires code owner reviews
- [ ] `enforce_admins: true` configured
- [ ] GitHub Environment created with manual approval
- [ ] Workflow only triggers on `main` branch (not PRs)
- [ ] Validation runs before application
- [ ] Audit logging enabled
- [ ] Drift detection scheduled
- [ ] Admin approval process documented
- [ ] Incident response plan documented
- [ ] Team trained on security implications

---

**Owner:** @tester311249  
**Last Review:** 23 January 2026  
**Next Review:** 23 February 2026
