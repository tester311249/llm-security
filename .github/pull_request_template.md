## Description
<!-- Provide a clear and concise description of what this PR does -->


## Type of Change
<!-- Check all that apply -->
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Infrastructure/configuration change
- [ ] Security-related change
- [ ] Performance improvement

## Related Issues
<!-- Link any related issues using #issue-number -->
Closes #

## Changes Made
<!-- List the specific changes made in this PR -->
- 
- 
- 

---

## 🔒 Security Review Requirements

**⚠️ MANDATORY SECURITY REVIEW REQUIRED IF:**

Your PR modifies any of the following security-critical files:
- [ ] `/prompt_injection_detector.py` - Core prompt injection detection logic
- [ ] `/api_service.py` - API service and endpoint security
- [ ] `/test_detector.py` - Security test cases
- [ ] `/enterprise-prompt-injection-detection-design.md` - Security architecture design
- [ ] `/architecture.md` - System architecture documentation
- [ ] Security-related workflow files (`.github/workflows/*`)
- [ ] Authentication or authorization mechanisms
- [ ] Input validation or sanitization logic
- [ ] LLM prompt handling or filtering rules

**⚠️ INFRASTRUCTURE REVIEW REQUIRED IF:**

Your PR modifies deployment or infrastructure files:
- [ ] `/k8s-deployment.yaml` - Kubernetes deployment configuration
- [ ] `/Dockerfile` or `/docker-compose.yml` - Container configurations
- [ ] `/scp.yaml` - Service control policies
- [ ] `.github/workflows/*` - CI/CD pipeline definitions
- [ ] Any `*.yaml` or `*.yml` configuration files

**If ANY box above is checked:**
1. **@tester311249** MUST review and approve before merge
2. PR cannot be merged without required approval (enforced by branch protection)
3. Ensure all security implications are documented in PR description
4. Run full security test suite before requesting review

**Contact for security review:**
- GitHub: @tester311249
- Email: samir_pratihari@yahoo.co.in

---

## Testing Performed
<!-- Describe the tests you ran to verify your changes -->
- [ ] Unit tests pass (`python -m pytest test_detector.py`)
- [ ] Integration tests pass
- [ ] Manual testing completed
- [ ] Security scanning performed
- [ ] Prompt injection test cases validated
- [ ] No new vulnerabilities introduced

### Test Evidence
<!-- Provide screenshots, logs, or test output -->
```
# Paste test output here
```

## Security Checklist
<!-- Ensure all items are completed for security-related changes -->
- [ ] Input validation added for all new user inputs
- [ ] No hardcoded credentials or sensitive data
- [ ] Error messages don't leak sensitive information
- [ ] Rate limiting considered for new endpoints
- [ ] Logging doesn't expose PII or secrets
- [ ] Dependencies scanned for known vulnerabilities
- [ ] OWASP Top 10 considerations addressed
- [ ] Prompt injection vectors tested

## Code Quality Checklist
<!-- Ensure all items are completed before requesting review -->
- [ ] My code follows the project's style guidelines
- [ ] I have performed a self-review of my own code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings or errors
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] New and existing unit tests pass locally with my changes
- [ ] Any dependent changes have been merged and published
- [ ] I have checked CODEOWNERS and requested reviews from required reviewers

## Performance Impact
<!-- Describe any performance implications -->
- [ ] No performance impact
- [ ] Performance improved
- [ ] Performance degraded (explain why acceptable)

**Metrics:**
- Latency impact: 
- Memory impact: 
- CPU impact: 

## Deployment Notes
<!-- Any special instructions for deployment or rollback -->


## Additional Context
<!-- Add any other context, screenshots, or information about the PR here -->


---

**Branch Protection Status:**
- This repository uses CODEOWNERS to enforce mandatory reviews
- Security-critical files require @tester311249 approval
- Infrastructure changes require platform team review
- Check the Files Changed tab to see which reviewers are automatically assigned

---

## LLM Security Specific Checks
<!-- For changes to prompt injection detection -->
- [ ] Tested against OWASP LLM Top 10 attack vectors
- [ ] Validated against prompt injection test suite
- [ ] Checked for false positive/negative rates
- [ ] Documented any new attack patterns detected
- [ ] Updated detection rules documentation if applicable
