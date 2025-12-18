# CI/CD Pipeline Documentation

## Overview

Comprehensive CI/CD pipeline for the Prompt Injection Detection System with automated testing, security scanning, and deployment workflows.

## Pipeline Structure

### 1. Continuous Integration (CI)

**Workflow**: `.github/workflows/ci.yml`

**Triggers**:
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop`
- Manual dispatch

**Jobs**:

#### Test Job
- **Matrix Strategy**: Tests across Python 3.9, 3.10, 3.11, 3.12
- **Operating Systems**: Ubuntu, macOS, Windows
- **Steps**:
  1. Checkout code
  2. Setup Python environment
  3. Install dependencies with pip caching
  4. Run pytest with coverage
  5. Upload coverage to Codecov

#### Lint Job
- **Code Quality Tools**:
  - Black (code formatting)
  - isort (import sorting)
  - flake8 (style guide enforcement)
  - pylint (comprehensive linting)
  - mypy (type checking)
- **Continues on error** for non-critical issues

#### Security Job
- **Security Scanners**:
  - Bandit (Python security scanner)
  - Safety (dependency vulnerability checker)
- **Outputs**: JSON security reports
- **Artifacts**: Security scan results uploaded

#### Integration Test Job
- **Tests**:
  - Run detector demo
  - Execute integration examples
  - Test API service startup
- **Timeout**: 10 seconds for API startup test

#### Performance Job
- **Benchmarks**:
  - Latency measurements (mean, median, p95, p99)
  - Throughput calculation
  - Performance assertions (< 50ms mean latency)
- **Failure**: Creates issue if performance degrades

#### Build Status Job
- **Purpose**: Aggregate all job results
- **Condition**: Runs always, even if previous jobs fail
- **Success Criteria**: All critical checks pass

**Estimated Duration**: 5-10 minutes

---

### 2. Continuous Deployment (CD)

**Workflow**: `.github/workflows/cd.yml`

**Triggers**:
- Git tags matching `v*.*.*` (e.g., v1.0.0)
- Release published
- Manual dispatch with environment selection

**Jobs**:

#### Build and Test
- Full test suite execution
- Build Python distribution packages (sdist, wheel)
- Upload artifacts for deployment

#### Docker Build
- Multi-stage Docker build
- Image metadata extraction
- Tag generation (version, SHA, latest)
- Build caching with GitHub Actions cache
- Image saved as artifact

#### Deploy Staging
- **Environment**: staging
- **Condition**: Manual workflow with staging selected
- Downloads Docker image artifact
- Executes staging deployment commands
- Placeholder for kubectl/helm commands

#### Deploy Production
- **Environment**: production
- **Condition**: Release published or manual workflow
- **Protection Rules**: Requires approval (configure in GitHub)
- Downloads Docker image artifact
- Executes production deployment
- Creates deployment notification

#### Publish PyPI
- **Environment**: pypi
- **Condition**: Release published
- Builds Python package
- Publishes to PyPI using API token
- Requires `PYPI_API_TOKEN` secret

#### Smoke Test
- **Condition**: After staging deployment
- Executes smoke tests against staging environment
- Health checks and basic API tests

**Estimated Duration**: 10-15 minutes

---

### 3. Pull Request Checks

**Workflow**: `.github/workflows/pr-checks.yml`

**Triggers**:
- Pull request opened, synchronized, reopened
- Only for non-draft PRs

**Jobs**:

#### PR Validation
- **Checks**:
  - PR title format (conventional commits)
  - PR description presence
  - Branch naming convention
- **Warnings**: Non-blocking for style issues

#### Changes Detection
- **Path Filters**:
  - Code changes (*.py, requirements.txt)
  - Documentation changes (*.md)
  - Test changes (test_*.py)
- **Outputs**: Flags for conditional job execution

#### Quick Test
- **Condition**: Code changes detected
- Parallel test execution (pytest-xdist)
- Fast feedback for developers

#### Security Check
- **Scanners**:
  - Bandit for security issues
  - TruffleHog for secrets detection
- **Scope**: Changed files only

#### Automated Code Review
- **Analysis**:
  - Complexity metrics (radon)
  - Style issues (flake8)
- **Output**: Automated comment on PR

#### Test Coverage
- Coverage report generation
- Coverage comment on PR
- HTML coverage report uploaded

#### Docs Check
- **Condition**: Documentation changes
- Markdown link checking
- Markdown linting

#### Size Check
- File size report generation
- Bundle size tracking

#### PR Summary
- Aggregates all check results
- Posts summary to GitHub Actions summary

**Estimated Duration**: 3-5 minutes

---

### 4. Scheduled Workflows

**Workflow**: `.github/workflows/scheduled.yml`

**Trigger**: Daily at 2 AM UTC (cron: `0 2 * * *`)

**Jobs**:

#### Dependency Audit
- **Tools**:
  - pip-audit for vulnerability scanning
  - Safety for dependency checks
- **Action**: Creates GitHub issue if vulnerabilities found
- Lists outdated dependencies

#### Pattern Database Check
- Reports total detection patterns
- Generates pattern effectiveness report
- Uploads report as artifact

#### Performance Regression
- **Metrics**:
  - Mean, median, p95, p99 latencies
  - Statistical analysis
- **Action**: Creates issue if performance degrades
- Tracks performance over time

#### Code Quality Report
- **Metrics**:
  - Cyclomatic complexity (radon)
  - Maintainability index
  - Raw code metrics
- Uploads quality report

**Estimated Duration**: 5-8 minutes

---

### 5. Docker Workflow

**Workflow**: `.github/workflows/docker.yml`

**Triggers**:
- Push to `main` branch
- Git tags `v*.*.*`
- Pull requests
- Manual dispatch

**Jobs**:

#### Build and Test
- **Registry**: GitHub Container Registry (ghcr.io)
- **Steps**:
  1. Setup Docker Buildx
  2. Login to GHCR
  3. Extract metadata and tags
  4. Build Docker image with caching
  5. Test container (health check, API endpoints)
  6. Vulnerability scanning (Trivy)
  7. Push image to registry
- **Tags Generated**:
  - Branch name
  - PR number
  - Semantic version
  - SHA prefix
  - Latest (for default branch)

#### Multi-Architecture Build
- **Condition**: Git tags only
- **Platforms**: linux/amd64, linux/arm64
- Uses QEMU for cross-platform builds
- Pushes multi-arch manifest

**Estimated Duration**: 10-15 minutes

---

## Configuration Files

### .flake8
```ini
max-line-length = 127
max-complexity = 10
ignore = E203, E501, W503
```

### .pylintrc
```ini
max-line-length = 127
disable = C0111, R0903, R0913, C0301
```

### .markdownlint.json
```json
{
  "default": true,
  "MD013": false,
  "MD033": false
}
```

---

## Docker Support

### Dockerfile
- **Base Image**: python:3.11-slim
- **Multi-stage Build**: Builder + Runtime
- **Security**:
  - Non-root user (UID 1000)
  - Minimal dependencies
  - Health check included
- **Port**: 8000
- **Command**: Uvicorn API server

### docker-compose.yml
- **Services**:
  - API service
  - Prometheus (monitoring profile)
  - Grafana (monitoring profile)
- **Networks**: detector-network
- **Volumes**: Persistent storage for metrics

### Build and Run
```bash
# Build image
docker build -t prompt-injection-detector:latest .

# Run container
docker run -p 8000:8000 prompt-injection-detector:latest

# Run with docker-compose
docker-compose up

# With monitoring
docker-compose --profile monitoring up
```

---

## Kubernetes Deployment

### k8s-deployment.yaml

**Resources**:
- **Deployment**: 3 replicas
- **Service**: ClusterIP on port 80
- **HPA**: Auto-scaling 3-10 pods
- **Ingress**: NGINX with rate limiting

**Configuration**:
```yaml
Resources:
  requests: 128Mi memory, 100m CPU
  limits: 512Mi memory, 500m CPU

Health Checks:
  liveness: /health every 30s
  readiness: /health every 10s

Security:
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  capabilities dropped: ALL
```

**Deploy**:
```bash
kubectl apply -f k8s-deployment.yaml
```

---

## Build Script

### build.sh

Automated build script for CI/CD:

**Steps**:
1. Linting with flake8
2. Testing with pytest
3. Security scanning with bandit
4. Docker image build
5. Integration tests

**Usage**:
```bash
./build.sh
# or with version
VERSION=v1.2.3 ./build.sh
```

---

## Required Secrets

Configure in GitHub Settings → Secrets:

### CI Secrets
- `CODECOV_TOKEN` - Codecov upload token (optional)

### CD Secrets
- `DOCKER_USERNAME` - Docker Hub username
- `DOCKER_PASSWORD` - Docker Hub password
- `PYPI_API_TOKEN` - PyPI API token for package publishing
- `GITHUB_TOKEN` - Automatically provided

### Deployment Secrets
- `KUBE_CONFIG` - Kubernetes config for deployments
- `STAGING_URL` - Staging environment URL
- `PRODUCTION_URL` - Production environment URL

---

## Branch Protection Rules

Recommended settings for `main` branch:

- ✅ Require pull request reviews (1 approver)
- ✅ Require status checks to pass:
  - test (Python 3.11, ubuntu-latest)
  - lint
  - security
  - integration-test
  - performance
- ✅ Require branches to be up to date
- ✅ Require linear history
- ✅ Include administrators
- ✅ Require signed commits (recommended)

---

## Monitoring & Alerts

### GitHub Actions Notifications
- Slack/Discord webhooks for failures
- Email notifications for critical issues
- Status badges in README

### Automated Issue Creation
- Security vulnerabilities detected
- Performance regression detected
- Dependency updates needed

---

## Performance Targets

### CI Pipeline
- Total CI time: < 10 minutes
- PR checks: < 5 minutes
- Docker build: < 15 minutes

### Application Performance
- Mean latency: < 10ms
- P99 latency: < 50ms
- Throughput: > 1000 req/s

---

## Troubleshooting

### Common Issues

**Tests Failing**
```bash
# Run locally
pytest test_detector.py -v

# With coverage
pytest test_detector.py --cov=prompt_injection_detector
```

**Docker Build Failing**
```bash
# Build locally
docker build -t test .

# Check logs
docker logs <container-id>
```

**Deployment Failing**
```bash
# Check deployment status
kubectl get deployments
kubectl describe deployment prompt-injection-detector
kubectl logs -l app=prompt-injection-detector
```

---

## Best Practices

1. **Run tests locally** before pushing
2. **Keep PRs small** and focused
3. **Use conventional commit** messages
4. **Update tests** with code changes
5. **Monitor CI metrics** regularly
6. **Review security** scan results
7. **Test Docker images** locally
8. **Use semantic versioning** for releases

---

## Next Steps

1. Configure GitHub secrets
2. Set up branch protection rules
3. Configure deployment environments
4. Setup monitoring dashboards
5. Configure alerting channels
6. Document deployment procedures
7. Plan rollback strategy
8. Setup staging environment

---

## Support

For CI/CD issues:
1. Check workflow logs in Actions tab
2. Review this documentation
3. Open an issue with workflow run link
4. Contact DevOps team

---

**Last Updated**: 2025-12-11
**Version**: 1.0.0
