# SCP Integration Guide for LLM Security Platform

## Overview

This guide explains how the System Capability Protocol (SCP) enhances the LLM Security platform by providing machine-readable system architecture documentation.

## What SCP Brings to LLM Security

### 1. **Architecture Discovery**

The `scp.yaml` manifest enables:
- Automatic service discovery across the organization
- Dependency mapping for security analysis
- Understanding which services depend on our security platform
- Identifying blast radius of security service failures

### 2. **LLM-Assisted Security Analysis**

LLMs can read SCP manifests to:
```python
# Example: LLM analyzing security architecture
prompt = f"""
Based on these SCP manifests:
{scp_manifests}

Questions:
1. What services are at risk if the prompt injection detector fails?
2. Which Tier 1 services lack prompt injection protection?
3. What's the impact of a 200ms latency spike in detection?
"""
```

### 3. **Automated Security Validation**

```python
# Check if all LLM services have prompt injection protection
def validate_llm_security_coverage(scp_graph):
    llm_services = find_services_by_tag(scp_graph, "llm")
    unprotected = []
    
    for service in llm_services:
        if not depends_on(service, "urn:scp:llm-security:prompt-injection-detector"):
            unprotected.append(service)
    
    return unprotected
```

### 4. **Runtime vs Declaration Validation**

Compare SCP manifests against OpenTelemetry traces:

```python
# Detect if services are calling LLM APIs without security checks
async def detect_security_bypass(otel_traces, scp_manifests):
    """
    Find services making LLM calls that don't route through
    our prompt injection detector
    """
    declared_deps = parse_dependencies(scp_manifests)
    actual_calls = parse_service_mesh_traces(otel_traces)
    
    bypasses = []
    for call in actual_calls:
        if call.destination.contains("llm-provider"):
            if not call.passes_through("prompt-injection-detector"):
                bypasses.append({
                    'source': call.source,
                    'destination': call.destination,
                    'risk': 'CRITICAL',
                    'reason': 'Unprotected LLM access'
                })
    
    return bypasses
```

### 5. **Smart Alerting with Context**

When an alert fires, SCP provides:
- **Ownership**: Who to page (from ownership.contacts)
- **Blast radius**: What services depend on this (from depends)
- **Criticality**: How critical is the failure (from criticality)
- **Escalation path**: Who to escalate to (from ownership.escalation)

```python
# Enrich PagerDuty alert with SCP context
def enrich_alert(alert, scp_manifest):
    return {
        **alert,
        'owner_team': scp_manifest.ownership.team,
        'pagerduty_service': scp_manifest.ownership.contacts.pagerduty,
        'dependent_services': get_dependents(scp_manifest.system.urn),
        'blast_radius': calculate_impact(scp_manifest.system.urn),
        'runbook': scp_manifest.documentation.runbook
    }
```

## Using SCP with Our Detection Platform

### Architecture Validation

```bash
# Install SCP CLI
uv tool install scp-cli

# Scan all services in the organization
scp-cli scan /path/to/repos --export mermaid > architecture.md

# Validate our manifest
check-jsonschema --schemafile \
  https://raw.githubusercontent.com/krackenservices/scp-definition/main/spec/scp.schema.json \
  scp.yaml
```

### Security Policy Enforcement

Create policies that read SCP manifests:

```python
# Policy: All Tier 1 services must have prompt injection protection
class Tier1SecurityPolicy:
    def validate(self, scp_graph):
        violations = []
        
        for service in scp_graph.all_services():
            if service.classification.tier == 1:
                if service.depends_on_llm():
                    if not service.depends_on("prompt-injection-detector"):
                        violations.append({
                            'service': service.system.urn,
                            'team': service.ownership.team,
                            'violation': 'Tier 1 service uses LLM without security',
                            'severity': 'CRITICAL'
                        })
        
        return violations
```

### Integration with CI/CD

Add to your pipeline:

```yaml
# .github/workflows/security-validation.yml
name: Security Policy Validation

on: [pull_request]

jobs:
  validate-scp:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Validate SCP Manifest
        run: |
          check-jsonschema --schemafile \
            https://raw.githubusercontent.com/krackenservices/scp-definition/main/spec/scp.schema.json \
            scp.yaml
      
      - name: Check Security Dependencies
        run: |
          # Ensure all services declare dependency on prompt injection detector
          python scripts/validate_security_deps.py
      
      - name: Generate Dependency Graph
        run: |
          scp-cli scan . --export mermaid > docs/architecture.md
          git add docs/architecture.md
```

## Querying SCP Data

### Find All Services That Depend on Us

```python
def find_dependents(scp_graph, our_urn):
    """Find all services that depend on our security platform"""
    dependents = []
    
    for service in scp_graph.all_services():
        for dep in service.depends:
            if dep.system == our_urn:
                dependents.append({
                    'service': service.system.name,
                    'urn': service.system.urn,
                    'team': service.ownership.team,
                    'criticality': dep.criticality,
                    'failure_mode': dep.failure_mode
                })
    
    return dependents
```

### Calculate Blast Radius

```python
def calculate_blast_radius(scp_graph, service_urn):
    """Calculate impact of service failure"""
    def get_transitive_dependents(urn, visited=None):
        if visited is None:
            visited = set()
        if urn in visited:
            return set()
        visited.add(urn)
        
        dependents = scp_graph.get_dependents(urn)
        all_impacted = set(dependents)
        
        for dep in dependents:
            all_impacted.update(
                get_transitive_dependents(dep, visited)
            )
        
        return all_impacted
    
    impacted = get_transitive_dependents(service_urn)
    
    # Categorize by criticality
    return {
        'total_services': len(impacted),
        'critical': [s for s in impacted if s.criticality == 'critical'],
        'degraded': [s for s in impacted if s.criticality == 'degraded'],
        'optional': [s for s in impacted if s.criticality == 'optional'],
        'teams_affected': set(s.ownership.team for s in impacted)
    }
```

## Use Cases for Interview Discussion

### 1. **Automated Threat Modeling**

"Using SCP manifests, an LLM can automatically generate threat models by understanding:
- Data flows between services
- Authentication/authorization boundaries
- Tier classifications
- Attack surface area"

### 2. **Security Policy as Code**

"We encode security policies that validate SCP manifests:
- Tier 1 services must use our prompt injection detector
- All LLM calls must be authenticated
- Services handling PII must declare data_classification"

### 3. **Incident Response Acceleration**

"When an alert fires, we automatically:
- Page the right team (from SCP ownership)
- Show blast radius (from SCP dependency graph)
- Link to runbook (from SCP documentation)
- Identify affected customers (from SCP dependent services)"

### 4. **Change Impact Analysis**

"Before deploying changes to our security platform, we:
- Query SCP graph for all dependents
- Identify services with criticality='critical'
- Send pre-deploy notifications to affected teams
- Schedule deployments during their low-traffic windows"

### 5. **Compliance Auditing**

"Generate compliance reports from SCP:
- Which services handle PII?
- Which services are SOC2 compliant?
- Which Tier 1 services lack security controls?
- What's our security coverage percentage?"

## Comparison: SCP vs Service Mesh

| Aspect | Service Mesh (Istio) | SCP |
|--------|---------------------|-----|
| **Runtime** | ✅ Actual traffic | ❌ Declaration only |
| **Intent** | ❌ What happens | ✅ What should happen |
| **Human-readable** | ❌ Complex configs | ✅ Clear manifests |
| **LLM-friendly** | ❌ Too low-level | ✅ High-level semantics |
| **Ownership** | ❌ Not built-in | ✅ Team ownership |
| **SLAs** | ❌ Not declared | ✅ Explicit SLAs |
| **Change impact** | ❌ Hard to predict | ✅ Easy to analyze |

**Best practice**: Use both!
- SCP describes what **should** be
- Service mesh enforces and observes what **is**
- Diff them to detect drift

## Next Steps

1. **Add SCP to all your services**
   ```bash
   # Template for new services
   cp llm-security/scp.yaml my-service/scp.yaml
   # Customize for your service
   ```

2. **Build a service catalog**
   ```bash
   scp-cli scan /path/to/all/repos --export json > catalog.json
   ```

3. **Create security policies**
   ```python
   # Write policies that validate SCP manifests
   python scripts/validate_security_policies.py
   ```

4. **Integrate with observability**
   ```python
   # Compare SCP declarations with OpenTelemetry traces
   python scripts/validate_runtime_vs_declaration.py
   ```

5. **Train LLMs on your architecture**
   ```python
   # Use SCP manifests as context for LLM reasoning
   llm_context = load_all_scp_manifests()
   response = llm.ask("What's the impact of this change?", context=llm_context)
   ```

## Benefits for Your Interview

When discussing this in your interview, emphasize:

1. **Proactive Security**: "SCP lets us enforce security policies before code is deployed"
2. **LLM Integration**: "We feed SCP manifests to LLMs for automated threat modeling"
3. **Observability**: "We compare SCP declarations with runtime traces to detect drift"
4. **Incident Response**: "SCP gives us instant context during incidents - who owns it, what depends on it"
5. **Compliance**: "We generate compliance reports directly from SCP manifests"

This positions you as someone who thinks about:
- Modern architecture patterns
- AI-assisted security
- Automation and tooling
- Enterprise-scale operations

Perfect fit for a GenAI Security role! 🎯
