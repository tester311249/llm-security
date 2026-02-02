# Branch Protection as Code - Implementation Guide

## Overview

This repository implements **branch protection as code** using YAML configuration files and automated validation workflows. This approach provides version-controlled, auditable, and drift-detectable branch protection settings.

## ✅ What's Implemented (Issue #10)

### Core Components

1. **YAML Configuration** - [.github/branch-protection.yml](.github/branch-protection.yml)
   - Human-readable YAML format (not JSON!)
   - Defines desired branch protection state
   - Version-controlled alongside code

2. **Read-Only Validation Script** - [scripts/repocheck](scripts/repocheck)
   - Compares actual vs desired configuration
   - Requires only read permissions
   - Supports multiple output formats (text, JSON, YAML)
   - Portable across repositories

3. **Schema Validation** - [scripts/validate-schema.sh](scripts/validate-schema.sh)
   - Validates YAML syntax and structure
   - Checks required fields and data types
   - Security best practices warnings

4. **Automated Workflow** - [.github/workflows/check-branch-protection.yml](.github/workflows/check-branch-protection.yml)
   - PR validation with feedback
   - Weekly drift detection
   - Manual apply with approval gates

5. **Pre-commit Hooks** - [.pre-commit-config.yaml](.pre-commit-config.yaml)
   - Local validation before commit
   - Syntax and schema checks
   - Optional drift detection

## 🚀 Quick Start

### Prerequisites

```bash
# Required tools
brew install gh jq yq  # macOS
# OR
sudo apt install gh jq  # Linux
pip install yq

# Optional for pre-commit hooks
pip install pre-commit
```

### Local Validation

```bash
# Validate configuration schema
./scripts/validate-schema.sh .github/branch-protection.yml

# Check for drift (requires GitHub authentication)
gh auth login
./scripts/repocheck tester311249/llm-security

# Check with JSON output (for parsing)
./scripts/repocheck tester311249/llm-security .github/branch-protection.yml json

# Check with YAML output
./scripts/repocheck tester311249/llm-security .github/branch-protection.yml yaml
```

### Enable Pre-commit Hooks

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Run hooks manually
pre-commit run --all-files

# Run drift check manually (optional hook)
pre-commit run check-branch-protection-drift --hook-stage manual
```

## 📋 Configuration Format

### YAML Structure

```yaml
# .github/branch-protection.yml
branch_protection:
  branch: main
  
  required_pull_request_reviews:
    dismiss_stale_reviews: true
    require_code_owner_reviews: true
    required_approving_review_count: 2
  
  enforce_admins: true
  required_conversation_resolution: true
  allow_force_pushes: false
  allow_deletions: false
  required_linear_history: true
```

See [.github/branch-protection.yml](.github/branch-protection.yml) for complete example.

### Legacy JSON Support

The system still supports the legacy JSON format at `config/branch-protection.json` for backward compatibility.

## 🔄 Workflows

### Pull Request Validation

When you create a PR modifying branch protection:

1. ✅ Configuration schema is validated
2. 🔍 Drift detection runs (comparing proposed vs actual)
3. 💬 PR comment posted with drift details
4. 🏷️ Labels added: `config-drift`, `needs-review`

**Read-only permissions** - No changes are applied.

### Weekly Drift Detection

Every Monday at 2 AM UTC:

1. 🔍 Current configuration fetched from GitHub
2. 📊 Compared against YAML configuration
3. 📝 GitHub issue created if drift detected
4. 📦 Drift report uploaded as artifact

### Manual Apply

To apply configuration changes:

1. Create PR with changes
2. Get PR approved by security team (CODEOWNERS)
3. Merge to main
4. Workflow triggers automatically
5. **Manual approval required** via GitHub Environment
6. Configuration applied to GitHub
7. Audit log generated

## 🔒 Security Controls

### 7-Layer Security Architecture

1. **CODEOWNERS** - Only approved teams can modify config
2. **Branch Protection** - Requires PR reviews
3. **Workflow Triggers** - Apply only runs on main (never PRs)
4. **Environment Protection** - Manual approval gate
5. **Validation** - Schema and syntax checks before apply
6. **Audit Logging** - All changes logged with actor/timestamp
7. **Drift Detection** - Weekly monitoring for unauthorized changes

### Permissions

- **Validation jobs**: `contents: read` only
- **PR feedback**: `contents: read`, `pull-requests: write`
- **Apply job**: Requires `BRANCH_PROTECTION_TOKEN` secret
- **Drift detection**: `contents: read`, `issues: write`

## 📊 Script Exit Codes

### repocheck

- `0` - Configuration matches (no drift)
- `1` - Configuration drift detected
- `2` - Error (missing tools, API failure, etc.)

### validate-schema.sh

- `0` - Schema validation passed
- `1` - Schema validation failed
- `2` - Error (file not found, invalid syntax, etc.)

## 🔧 Troubleshooting

### "yq is required"

```bash
# macOS
brew install yq

# Linux
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
```

### "GitHub CLI (gh) required"

```bash
# macOS
brew install gh

# Linux
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh

# Authenticate
gh auth login
```

### Drift Detected but Expected

If you intentionally changed branch protection via UI:

1. Update `.github/branch-protection.yml` to match
2. Create PR with the update
3. Merge after approval
4. Close the drift detection issue

### Apply Job Not Running

Check:
1. Are you on the `main` branch?
2. Did the PR get merged (not closed)?
3. Does `BRANCH_PROTECTION_TOKEN` secret exist?
4. Is `branch-protection-admin` environment configured?

## 🌐 Multi-Repository Adoption

To adopt this in another repository:

```bash
# 1. Copy scripts
curl -o scripts/repocheck https://raw.githubusercontent.com/tester311249/llm-security/main/scripts/repocheck
curl -o scripts/validate-schema.sh https://raw.githubusercontent.com/tester311249/llm-security/main/scripts/validate-schema.sh
chmod +x scripts/repocheck scripts/validate-schema.sh

# 2. Copy config template
curl -o .github/branch-protection.yml https://raw.githubusercontent.com/tester311249/llm-security/main/.github/branch-protection.yml

# 3. Copy workflow
curl -o .github/workflows/check-branch-protection.yml https://raw.githubusercontent.com/tester311249/llm-security/main/.github/workflows/check-branch-protection.yml

# 4. Copy pre-commit config
curl -o .pre-commit-config.yaml https://raw.githubusercontent.com/tester311249/llm-security/main/.pre-commit-config.yaml

# 5. Update CODEOWNERS
echo "/.github/branch-protection.yml @your-org/security-team" >> .github/CODEOWNERS

# 6. Customize configuration
vim .github/branch-protection.yml

# 7. Test locally
./scripts/validate-schema.sh .github/branch-protection.yml
./scripts/repocheck owner/your-repo
```

## 📚 Related Documentation

- [jira-ticket2.md](docs/jira-ticket2.md) - Original requirements
- [comparative-analysis-poc-vs-fog-proposal.md](docs/comparative-analysis-poc-vs-fog-proposal.md) - Gap analysis
- [GitHub Branch Protection API](https://docs.github.com/en/rest/branches/branch-protection)
- [GitHub Rulesets API](https://docs.github.com/en/rest/repos/rules)

## ✅ Acceptance Criteria Status

All requirements from Issue #10 have been implemented:

- [x] YAML configuration format
- [x] Read-only `repocheck` script
- [x] Schema validation script
- [x] GitHub Actions with PR triggers
- [x] PR feedback with comments and labels
- [x] Weekly drift detection
- [x] CODEOWNERS protection
- [x] Pre-commit hooks
- [x] Documentation and adoption guide

## 🎯 Success Metrics

Track these metrics to measure adoption:

- ✅ Number of repositories using branch protection as code
- 📉 Number of drift detection issues created
- ⚡ Time to detect unauthorized changes (target: < 7 days)
- 🛡️ Percentage of repositories with enforced admin rules
- 👥 Number of unauthorized branch protection changes prevented

## 🤝 Contributing

Changes to branch protection configuration require:

1. PR with changes to `.github/branch-protection.yml`
2. Schema validation pass
3. Approval from `@tester311249` (CODEOWNERS)
4. Merge to main
5. Manual approval in GitHub Environment

---

**Questions?** See [docs/jira-ticket2.md](docs/jira-ticket2.md) or create an issue.
