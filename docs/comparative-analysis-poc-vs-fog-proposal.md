# Comparative Analysis: llm-security POC vs FOG Proposal

**Date:** 29 January 2026  
**Purpose:** Compare the working POC implementation in `tester311249/llm-security` with the proposed FOG project implementation detailed in `jira-ticket1.md`

---

## Executive Summary

The **llm-security repository** contains a **working proof-of-concept (POC)** implementation of branch protection as code with comprehensive security controls. The **FOG proposal** (jira-ticket1.md) outlines requirements for a production-ready, multi-repository solution. This analysis identifies gaps, overlaps, and recommendations for leveraging the POC to accelerate FOG implementation.

---

## 1. Configuration Format

| Aspect | POC (llm-security) | FOG Proposal | Gap Analysis |
|--------|-------------------|--------------|--------------|
| **Format** | JSON | YAML | ⚠️ Format mismatch |
| **Location** | `config/branch-protection.json` | `.github/branch-protection.yml` | ⚠️ Location differs |
| **Rationale** | Standard JSON format | "Humans don't read JSON!" | ✅ YAML better for team |
| **Content** | Complete branch rules | Flexible schema, file-pattern approvers | 🔄 POC simpler, FOG more advanced |

**Verdict:** POC uses JSON in `config/`; FOG requires YAML in `.github/`. **Migration needed.**

**Migration Path:**
```bash
# Convert POC JSON to FOG YAML format
yq eval -P config/branch-protection.json > .github/branch-protection.yml
```

---

## 2. Validation Scripts

| Aspect | POC (llm-security) | FOG Proposal | Gap Analysis |
|--------|-------------------|--------------|--------------|
| **Script Count** | 1 script | 2 scripts | ⚠️ POC has single validation script |
| **Script 1 Name** | `validate-protection-config.sh` | `repocheck` | 🔄 Rename needed |
| **Script 1 Purpose** | Validate JSON syntax & security | Read-only drift detection with structured output | 🔄 POC validates, FOG checks live config |
| **Script 2** | ❌ Not present | `repoconfig` (write/apply) | ❌ Missing in POC |
| **Output Format** | Text/exit codes | JSON/YAML structured output | ⚠️ POC less machine-readable |
| **Multi-repo Support** | ❌ No | ✅ Yes (accepts repo param) | ❌ POC single-repo only |

**Verdict:** POC has validation logic but lacks:
- Separate read/write script pattern
- Structured output for GHA parsing
- Multi-repository support
- Live config comparison against desired state

**Gap:** FOG requires `repocheck` to fetch live GitHub config and compare with YAML file. POC only validates file syntax.

---

## 3. GitHub Actions Workflows

| Aspect | POC (llm-security) | FOG Proposal | Gap Analysis |
|--------|-------------------|--------------|--------------|
| **Workflow Name** | `manage-branch-protection.yml` | `check-branch-protection.yml` | 🔄 Rename recommended |
| **Triggers** | • `push` to main<br>• `schedule` (weekly)<br>• `workflow_dispatch` | Same + `pull_request` (read-only) | ⚠️ POC missing PR trigger for checks |
| **Validation Job** | ✅ Present | ✅ Required | ✅ Match |
| **Apply Job** | ✅ Present (with environment) | ✅ Required (manual approval) | ✅ Match |
| **Drift Detection** | ✅ Weekly cron → Creates GitHub issue | ✅ Weekly cron → Issue + **PR comments + labels** | ⚠️ POC lacks PR feedback |
| **PR Comments** | ❌ Not implemented | ✅ Required (post drift details) | ❌ Missing in POC |
| **PR Labels** | ❌ Not implemented | ✅ Required (`config-drift`) | ❌ Missing in POC |
| **Environment Protection** | ✅ `branch-protection-admin` | ✅ Required | ✅ Match |
| **Manual Approval** | ✅ Present | ✅ Required | ✅ Match |

**Verdict:** POC has solid foundation but needs enhancements:
- Add `pull_request` trigger for read-only validation
- Implement PR comment posting on drift detection
- Add automatic labeling for PRs with config drift

**Workflow Comparison:**

### POC Workflow Structure
```yaml
on:
  push:
    branches: [main]
  schedule:
    - cron: '0 2 * * 1'

jobs:
  validate:
    # JSON syntax validation
  
  apply:
    needs: validate
    environment: branch-protection-admin
    # Applies config via GitHub API
```

### FOG Proposal Enhancement
```yaml
on:
  push:
    branches: [main]
  pull_request:  # NEW
    paths: ['.github/branch-protection.yml']
  schedule:
    - cron: '0 2 * * 1'

jobs:
  validate:
    # YAML syntax + schema validation
  
  check-drift:  # NEW
    # Run repocheck, post PR comment if drift
    # Add 'config-drift' label
  
  apply:
    needs: validate
    environment: branch-protection-admin
    # Applies config with audit logging
```

---

## 4. Security Architecture

| Layer | POC (llm-security) | FOG Proposal | Gap Analysis |
|-------|-------------------|--------------|--------------|
| **Layer 1: CODEOWNERS** | ✅ Protects JSON, workflows, CODEOWNERS | ✅ Protects YAML, workflows, scripts | ✅ Match (update paths) |
| **Layer 2: Branch Protection** | ✅ Code owner reviews, enforce admins | ✅ Same requirements | ✅ Match |
| **Layer 3: Workflow Triggers** | ✅ Only `push` to main (never PRs) | ✅ Same + read-only PR trigger | ⚠️ POC stricter (good!) |
| **Layer 4: Environment Protection** | ✅ Manual approval required | ✅ Manual approval required | ✅ Match |
| **Layer 5: Validation** | ✅ JSON syntax, security checks | ✅ YAML syntax, schema validation | 🔄 Format change |
| **Layer 6: Audit Logging** | ✅ Timestamp, actor, commit | ✅ Same + more detail | ✅ Match |
| **Layer 7: Drift Detection** | ✅ Weekly cron, GitHub issues | ✅ Same + PR feedback | ⚠️ FOG more proactive |

**Verdict:** POC has **excellent** 7-layer security architecture. FOG proposal maintains all layers with enhancements.

**Security Comparison:**

| Security Concern | POC Solution | FOG Solution | Assessment |
|------------------|-------------|--------------|------------|
| Privilege escalation | ✅ Never runs on PRs | ✅ Same (apply job only on main) | ✅ Equivalent |
| Malicious config changes | ✅ CODEOWNERS + manual approval | ✅ Same | ✅ Equivalent |
| Secret exfiltration | ✅ Protected environment | ✅ Same | ✅ Equivalent |
| Drift goes unnoticed | ✅ Weekly check → issue | ✅ Weekly check → issue + PR feedback | ✅ FOG better UX |
| No audit trail | ✅ Comprehensive logging | ✅ Enhanced logging | ✅ Equivalent |

**Security Documentation:**

| Document | POC | FOG | Assessment |
|----------|-----|-----|------------|
| Implementation guide | ✅ 575 lines (comprehensive) | 🔄 References POC doc | ✅ POC exceptional |
| Security FAQ | ✅ Attack scenarios documented | 🔄 References POC FAQ | ✅ POC exceptional |
| Incident response | ✅ Detailed procedures | ❌ Not specified | ⚠️ POC superior |

---

## 5. Pre-commit Hooks

| Aspect | POC (llm-security) | FOG Proposal | Gap Analysis |
|--------|-------------------|--------------|--------------|
| **Pre-commit Config** | ❌ Not present | ✅ Required | ❌ Missing in POC |
| **YAML Validation** | N/A | ✅ Syntax check | ❌ Missing |
| **Schema Validation** | N/A | ✅ Schema check | ❌ Missing |
| **Local Repocheck** | N/A | ✅ Optional (manual stage) | ❌ Missing |

**Verdict:** POC lacks local validation. FOG requires pre-commit hooks for early feedback.

**Gap:** Developers working on POC must manually validate changes. FOG proposal includes `.pre-commit-config.yaml` for automatic local checks.

---

## 6. Reusability & Portability

| Aspect | POC (llm-security) | FOG Proposal | Gap Analysis |
|--------|-------------------|--------------|--------------|
| **Designed For** | Single repo (llm-security) | Multi-repo (all FOG repos) | ⚠️ POC not portable |
| **Script Parameters** | ❌ Hardcoded repo paths | ✅ Accepts repo as parameter | ❌ POC needs refactor |
| **Organization Tooling Repo** | ❌ Not present | ✅ `repo-governance-tools` | ❌ Missing |
| **Templates** | ❌ No templates | ✅ Config, workflow, pre-commit templates | ❌ Missing |
| **Adoption Guide** | ❌ No guide | ✅ SETUP.md, MIGRATION.md | ❌ Missing |
| **Pilot Repos** | N/A | ✅ Test in 2-3 repos | ❌ Not applicable yet |

**Verdict:** POC is **single-repo focused**. FOG requires **organization-wide reusable tooling**.

**Portability Gap:**

### POC (Single Repo)
```bash
# Hardcoded for llm-security
./scripts/validate-protection-config.sh config/branch-protection.json
gh api repos/tester311249/llm-security/branches/main/protection
```

### FOG (Multi-Repo)
```bash
# Accepts any repo
./scripts/repocheck owner/repo .github/branch-protection.yml
./scripts/repoconfig owner/repo .github/branch-protection.yml --dry-run
```

**Organization Tooling Structure (Missing in POC):**
```
govuk-one-login/repo-governance-tools/  # NEW
├── scripts/
│   ├── repocheck
│   ├── repoconfig
│   └── validate-schema.sh
├── templates/
│   ├── branch-protection.yml.example
│   ├── workflows/check-branch-protection.yml
│   └── pre-commit-config.yaml
└── docs/
    ├── SETUP.md
    └── MIGRATION.md
```

---

## 7. Advanced Features

| Feature | POC (llm-security) | FOG Proposal | Gap Analysis |
|---------|-------------------|--------------|--------------|
| **File-Pattern Approvers** | ❌ Not present | ✅ Optional feature | ❌ Missing in POC |
| **JSON Schema Validation** | ❌ Not present | ✅ Planned | ❌ Missing |
| **Rulesets API Support** | ❌ Branch Protection API only | ✅ Decision pending (PSREGOV-3704) | ⚠️ POC uses legacy API |
| **Multi-Branch Protection** | ❌ Main branch only | ✅ Optional future feature | ❌ Missing |
| **Compliance Dashboard** | ❌ Not present | ✅ Optional future feature | ❌ Missing |

**Verdict:** POC implements core functionality. FOG proposal includes advanced features for enterprise use.

**Advanced Feature Example (FOG):**
```yaml
# .github/branch-protection.yml
branch_protection:
  branch: main
  # ... standard rules ...
  
  # NEW: File-pattern-based required reviewers
  required_reviewers:
    - pattern: "terraform/**/*.tf"
      teams: ["@govuk-one-login/platform-team"]
    - pattern: ".github/workflows/**"
      teams: ["@govuk-one-login/security-team"]
    - pattern: "src/security/**"
      teams: ["@govuk-one-login/security-team"]
```

---

## 8. Documentation

| Document | POC (llm-security) | FOG Proposal | Gap Analysis |
|----------|-------------------|--------------|--------------|
| **Implementation Guide** | ✅ `branch-protection-security.md` (575 lines) | 🔄 References POC doc | ✅ POC exceptional |
| **Security FAQ** | ✅ `branch-protection-security-faq.md` | 🔄 References POC FAQ | ✅ POC exceptional |
| **Setup Instructions** | ✅ Detailed for single repo | ✅ Required for multi-repo | ⚠️ POC single-repo focused |
| **Migration Guide** | ❌ Not applicable (new POC) | ✅ Required (JSON→YAML) | ❌ Missing |
| **Working with Git Repos** | ✅ `working-with-git-repos.md` (FOG context) | ✅ Referenced | ✅ Available |
| **Attack Scenarios** | ✅ Comprehensive analysis | ✅ Same | ✅ POC exceptional |
| **Troubleshooting** | ✅ Detailed procedures | 🔄 Can reuse POC | ✅ POC exceptional |

**Verdict:** POC documentation is **outstanding** (575 lines of implementation detail, comprehensive security FAQ). FOG can leverage this as foundation.

---

## 9. API & Technology Choices

| Technology | POC (llm-security) | FOG Proposal | Gap Analysis |
|------------|-------------------|--------------|--------------|
| **GitHub API** | Branch Protection Rules API | Decision pending (Branch Protection vs Rulesets) | ⚠️ FOG may use newer API |
| **Config Format** | JSON | YAML | ⚠️ Migration required |
| **CLI Tool** | GitHub CLI (`gh`) | GitHub CLI (`gh`) | ✅ Match |
| **YAML Parser** | N/A (uses JSON) | `yq` | ⚠️ New dependency |
| **Pre-commit** | ❌ Not used | ✅ Required | ❌ Missing |
| **Environment** | ✅ GitHub Environments | ✅ GitHub Environments | ✅ Match |

**API Decision Point:**

### Branch Protection Rules API (POC Uses)
- **Endpoint:** `/repos/{owner}/{repo}/branches/{branch}/protection`
- **Status:** Stable, widely used
- **Limitations:** Per-branch configuration

### Repository Rulesets API (FOG May Use)
- **Endpoint:** `/repos/{owner}/{repo}/rulesets`
- **Status:** Newer, more flexible
- **Benefits:** Tag protection, bypass actors, insight dashboards
- **Decision:** Pending PSREGOV-3704

**Recommendation:** Design FOG scripts to support both APIs via abstraction layer.

---

## 10. Testing Strategy

| Aspect | POC (llm-security) | FOG Proposal | Gap Analysis |
|--------|-------------------|--------------|--------------|
| **Unit Tests** | ❌ Not present | ✅ Required (mock API) | ❌ Missing |
| **Integration Tests** | 🔄 Manual testing | ✅ Automated testing | ⚠️ POC ad-hoc |
| **Dry-Run Mode** | ❌ Not present | ✅ Required for repoconfig | ❌ Missing |
| **Pilot Repos** | N/A (single repo) | ✅ 2-3 diverse repos | N/A |
| **Rollback Testing** | ❌ Not tested | ✅ Required | ❌ Missing |

**Verdict:** POC proves concept works but lacks formal testing. FOG requires comprehensive test strategy.

---

## 11. Compliance & Governance

| Aspect | POC (llm-security) | FOG Proposal | Gap Analysis |
|--------|-------------------|--------------|--------------|
| **Audit Trail** | ✅ Complete logging | ✅ Enhanced logging | ✅ Match |
| **Compliance Reporting** | ✅ Manual check script | ✅ Automated reporting | 🔄 POC has foundation |
| **Change Log** | ✅ Documented | ✅ Required | ✅ Match |
| **Security Checklist** | ✅ Comprehensive | ✅ Required | ✅ Match |
| **Success Metrics** | ❌ Not defined | ✅ Defined (adoption, incidents) | ❌ Missing |

**Verdict:** POC has solid governance foundation. FOG adds measurable success criteria.

---

## Summary: Gap Analysis

### ✅ What POC Does Well (Leverage These)

1. **Security Architecture** - Exceptional 7-layer defense, thoroughly documented
2. **Documentation** - 575 lines of implementation detail + comprehensive FAQ
3. **Workflow Design** - Sound trigger logic, environment protection, manual approval
4. **CODEOWNERS Protection** - Proper file protection patterns
5. **Attack Scenario Analysis** - Real-world threats documented and mitigated
6. **Incident Response** - Detailed procedures for security events
7. **Troubleshooting** - Common issues and solutions documented

### ⚠️ What Needs Enhancement (Close These Gaps)

1. **Configuration Format** - Migrate JSON → YAML
2. **Script Architecture** - Split validation into `repocheck` (read) + `repoconfig` (write)
3. **Multi-Repo Support** - Make scripts accept repository parameters
4. **PR Feedback** - Add drift detection comments and labels on PRs
5. **Pre-commit Hooks** - Add local validation before push
6. **Structured Output** - Machine-readable JSON/YAML for GHA parsing

### ❌ What's Missing (Build These New)

1. **Organization Tooling Repo** - Centralized scripts and templates
2. **Reusability** - Templates, adoption guides, migration docs
3. **File-Pattern Approvers** - Advanced context-sensitive review requirements
4. **Formal Testing** - Unit tests, integration tests, dry-run mode
5. **Compliance Metrics** - Success criteria, adoption tracking
6. **Rulesets API Support** - Modern GitHub API (if chosen in PSREGOV-3704)

---

## Recommendations

### Phase 1: Enhance POC in llm-security (3-5 days)

**Objective:** Prepare POC for multi-repo use

1. **Migrate JSON → YAML**
   ```bash
   yq eval -P config/branch-protection.json > .github/branch-protection.yml
   ```

2. **Create `repocheck` Script**
   - Extend `validate-protection-config.sh`
   - Add live config fetching via GitHub API
   - Implement structured diff output (JSON/YAML)
   - Accept repo parameter: `repocheck owner/repo config.yml`

3. **Create `repoconfig` Script**
   - Extract apply logic from workflow
   - Add dry-run mode (`--dry-run` flag)
   - Add rollback capability (backup previous config)
   - Accept repo parameter: `repoconfig owner/repo config.yml`

4. **Enhance Workflow**
   - Add `pull_request` trigger (read-only validation)
   - Implement PR comment posting on drift
   - Add automatic labeling (`config-drift`)
   - Support both JSON (legacy) and YAML during transition

5. **Add Pre-commit Hooks**
   - Create `.pre-commit-config.yaml`
   - YAML syntax validation
   - Schema validation (if schema defined)

### Phase 2: Create FOG Tooling Repository (2-3 days)

**Objective:** Make POC reusable across FOG

1. **Create `govuk-one-login/repo-governance-tools`**
   - Port enhanced `repocheck` and `repoconfig` scripts
   - Create template files:
     - `branch-protection.yml.example`
     - `workflows/check-branch-protection.yml`
     - `pre-commit-config.yaml`

2. **Write Adoption Documentation**
   - `SETUP.md` - How to adopt in new repo
   - `MIGRATION.md` - How to migrate from JSON to YAML
   - `README.md` - Overview and quick start

3. **Test in Pilot Repos**
   - Select 2-3 FOG repos (diverse use cases)
   - Document adoption issues
   - Refine tooling based on feedback

### Phase 3: Advanced Features (Optional, 2-5 days)

**Objective:** Enterprise-grade capabilities

1. **File-Pattern-Based Approvers**
   - Extend YAML schema
   - Implement checking logic in `repocheck`

2. **Rulesets API Support** (if chosen in PSREGOV-3704)
   - Abstract API calls (support both Branch Protection and Rulesets)
   - Update scripts for new API

3. **Compliance Dashboard**
   - Multi-repo status view
   - Drift detection aggregation
   - Adoption metrics

---

## Decision Matrix: Reuse vs Rebuild

| Component | Recommendation | Rationale |
|-----------|---------------|-----------|
| Security Architecture | ✅ **Reuse POC as-is** | Excellent 7-layer design, thoroughly vetted |
| Documentation | ✅ **Reuse POC as-is** | Exceptional quality (575 lines), just update file paths |
| Workflow Structure | ✅ **Reuse with enhancements** | Sound foundation, add PR feedback features |
| CODEOWNERS Pattern | ✅ **Reuse as-is** | Proper protection, just update file paths |
| Validation Script | 🔄 **Enhance & Split** | Good logic, needs multi-repo support and read/write separation |
| Config Format | ⚠️ **Migrate JSON→YAML** | POC uses JSON, FOG requires YAML |
| Scripts Architecture | ⚠️ **Refactor for portability** | POC single-repo, FOG needs multi-repo |
| Pre-commit Hooks | ❌ **Build new** | Not present in POC |
| Organization Tooling | ❌ **Build new** | POC is single-repo, FOG needs central repo |
| Templates & Guides | ❌ **Build new** | POC has no reusability artifacts |

---

## Timeline Estimate

**Based on POC Foundation:**

| Phase | Duration | Effort |
|-------|----------|--------|
| **Phase 1: Enhance POC** | 3-5 days | JSON→YAML, split scripts, PR feedback |
| **Phase 2: FOG Tooling Repo** | 2-3 days | Templates, docs, pilot testing |
| **Phase 3: Advanced (Optional)** | 2-5 days | File-pattern approvers, Rulesets API |
| **Total** | **7-13 days** | With POC foundation vs 15-20 days from scratch |

**Savings:** POC reduces implementation time by ~40-50% (security architecture, documentation, workflow design already proven).

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **JSON→YAML conversion issues** | Medium | Thorough testing, support both formats during transition |
| **Script portability challenges** | Medium | Parameterize all repo-specific logic, test in pilot repos |
| **Rulesets API decision pending** | Low | Abstract API calls, support both APIs initially |
| **Adoption resistance** | Medium | Comprehensive docs, pilot success stories, training |
| **POC security model too complex** | Low | POC is proven secure; document clearly for FOG teams |

---

## Success Criteria

### POC Validation (Proven)
- ✅ Security architecture prevents privilege escalation
- ✅ Manual approval gate works effectively
- ✅ Drift detection catches unauthorized changes
- ✅ Audit trail provides full visibility

### FOG Implementation (Target)
- [ ] 80% of FOG repos adopt branch protection as code within 6 months
- [ ] Zero privilege escalation incidents
- [ ] 100% drift detection (no unnoticed config changes)
- [ ] Config changes take <15 minutes end-to-end
- [ ] 100% audit trail for all modifications

---

## Conclusion

**POC Assessment:** The `tester311249/llm-security` POC is a **high-quality implementation** with excellent security architecture and comprehensive documentation. It proves the concept works and provides a solid foundation.

**Gap Assessment:** POC is **single-repo focused** and uses JSON. FOG requires **multi-repo tooling** with YAML, enhanced drift detection (PR feedback), and reusable templates.

**Recommendation:** **Leverage POC extensively.** The security architecture, documentation, and workflow design are production-ready. Focus FOG effort on:
1. Format migration (JSON → YAML)
2. Portability (multi-repo support)
3. Reusability (tooling repo, templates, guides)
4. Enhanced UX (PR comments, pre-commit hooks)

**Estimated Savings:** Using POC as foundation saves ~8-12 days of implementation effort compared to building from scratch.

---

**References:**
- POC Implementation: [branch-protection-security.md](branch-protection-security.md)
- POC Security FAQ: [branch-protection-security-faq.md](branch-protection-security-faq.md)
- FOG Proposal: [jira-ticket1.md](jira-ticket1.md)
- FOG Context: [working-with-git-repos.md](working-with-git-repos.md)
- FOG Standards: PSREGOV-3704 (pending)

---

**Document Owner:** Platform/Security Team  
**Last Updated:** 29 January 2026  
**Status:** Analysis Complete
