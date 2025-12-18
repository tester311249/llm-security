# SCP vs MCP: A Comprehensive Comparison

## Executive Summary

**SCP (System Capability Protocol)** and **MCP (Model Context Protocol)** are complementary protocols that serve different purposes in modern AI-assisted systems. Understanding their distinctions is critical for building robust, observable, and secure GenAI platforms.

| Protocol | Primary Purpose | Consumer | Focus |
|----------|----------------|----------|-------|
| **MCP** | How to **USE** systems | AI Models | Tool invocation, real-time execution |
| **SCP** | What systems **ARE** | Humans, LLMs, Tools | Architecture, dependencies, ownership |

---

## Model Context Protocol (MCP)

### What It Is
MCP is a **communication protocol** that enables AI assistants (like Claude) to interact with external tools and data sources. It defines how tools are discovered, invoked, and how results are returned.

### Primary Purpose
- **Enable LLMs to use tools** in real-time
- **Standardize tool interfaces** across different AI models
- **Provide structured tool schemas** that LLMs can understand
- **Execute actions** on behalf of users through conversation

### Key Characteristics

```json
// MCP Tool Definition Example
{
  "name": "generate_ppt_from_markdown",
  "description": "Convert markdown to PowerPoint presentation",
  "inputSchema": {
    "type": "object",
    "properties": {
      "title": { "type": "string" },
      "markdown": { "type": "string" },
      "stylePreset": { "type": "string", "enum": ["corporate", "modern"] }
    },
    "required": ["title", "markdown"]
  }
}
```

**What MCP Tells You:**
- ✅ What parameters this tool accepts
- ✅ What types those parameters must be
- ✅ What the tool does when invoked
- ✅ How to call the tool right now

**What MCP Doesn't Tell You:**
- ❌ Who owns this tool/service
- ❌ What other services depend on it
- ❌ What happens if it fails
- ❌ What its SLA is
- ❌ Who to call when it breaks

### MCP Architecture

```
┌─────────────┐         MCP Protocol          ┌─────────────┐
│             │◄──────────────────────────────►│             │
│  AI Model   │  Tool Discovery & Invocation  │  MCP Server │
│  (Claude)   │                                │  (Tools)    │
│             │◄──────────────────────────────►│             │
└─────────────┘         JSON-RPC              └─────────────┘
```

### MCP Use Cases

1. **Conversational Tool Access**
   ```
   User: "Generate a PowerPoint about Q4 results"
   Claude: [Invokes generate_ppt_from_markdown tool via MCP]
   Result: PowerPoint file created
   ```

2. **IDE Integration**
   - VS Code extensions can expose MCP servers
   - Cline agent uses MCP to access tools

3. **Multi-Tool Orchestration**
   - Claude can chain multiple MCP tools
   - Example: Fetch data → Analyze → Generate report

### MCP Server Examples
- PowerPoint generator (your ppt server)
- Azure Terraform provisioner (your azure-tf server)
- Database query tools
- File system operations
- API integrations

---

## System Capability Protocol (SCP)

### What It Is
SCP is a **declarative manifest format** that describes what systems are, how they interconnect, who owns them, and what capabilities they provide. It's like a "nutrition label" for services.

### Primary Purpose
- **Document system architecture** in machine-readable format
- **Enable LLM reasoning** about system relationships
- **Support automated governance** and compliance
- **Facilitate change impact analysis**
- **Provide operational context** (ownership, SLAs, dependencies)

### Key Characteristics

```yaml
# SCP Manifest Example
scp: "0.1.0"

system:
  urn: "urn:scp:payment-service:api"
  name: "Payment Service"
  classification:
    tier: 1
    domain: "payments"

ownership:
  team: "payments-platform"
  contacts:
    - type: "pagerduty"
      ref: "https://pagerduty.com/services/PAYMENTS"

provides:
  - capability: "payment-processing"
    type: "rest"
    sla:
      availability: "99.99%"
      latency_p99_ms: 100

depends:
  - system: "urn:scp:user-service:api"
    criticality: "required"
    failure_mode: "fail-fast"

runtime:
  environments:
    production:
      otel_service_name: "payment-service"
```

**What SCP Tells You:**
- ✅ What this system is and its purpose
- ✅ Who owns it and how to contact them
- ✅ What capabilities it provides
- ✅ What it depends on
- ✅ What its SLA commitments are
- ✅ How it should fail
- ✅ How to observe it

**What SCP Doesn't Tell You:**
- ❌ How to invoke tools in real-time
- ❌ Exact API parameter schemas
- ❌ Current runtime state

### SCP Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    SCP Manifests                         │
│              (Declarative Architecture)                  │
└────────┬────────────────────────────┬────────────────────┘
         │                            │
         ▼                            ▼
┌────────────────────┐      ┌────────────────────┐
│   LLM Analysis     │      │  Governance Tools   │
│ (Change Impact)    │      │ (Policy Validation) │
└────────────────────┘      └────────────────────┘
         │                            │
         ▼                            ▼
┌────────────────────┐      ┌────────────────────┐
│  OpenTelemetry     │      │  Service Catalog    │
│ (Runtime vs Decl)  │      │ (Architecture Viz)  │
└────────────────────┘      └────────────────────┘
```

### SCP Use Cases

1. **LLM-Assisted Architecture Analysis**
   ```
   Question: "What's the impact if the payment service goes down?"
   LLM: [Reads SCP manifests]
   Answer: "17 services depend on it, 5 are critical tier.
           Contact payments-platform team via PagerDuty."
   ```

2. **Automated Compliance**
   ```python
   # Policy: All Tier 1 services must have 99.9% SLA
   for service in scp_graph.tier_1_services():
       if service.sla.availability < 99.9:
           violations.append(service)
   ```

3. **Change Impact Analysis**
   ```python
   # Before deploying changes to payment-service
   dependents = scp_graph.get_transitive_dependents("payment-service")
   notify_teams(dependents.owners)
   ```

4. **Runtime Validation**
   ```python
   # Compare SCP declarations with OpenTelemetry traces
   declared_deps = scp_manifest.depends
   actual_calls = otel_traces.get_service_calls()
   
   if actual_calls != declared_deps:
       alert("Configuration drift detected!")
   ```

---

## Side-by-Side Comparison

### Purpose

| Aspect | MCP | SCP |
|--------|-----|-----|
| **Question Answered** | "How do I use this?" | "What is this?" |
| **Analogy** | API documentation | System blueprint |
| **Execution Model** | Real-time invocation | Declarative intent |
| **Primary Consumer** | AI models during conversations | Humans, LLMs, governance tools |
| **Lifespan** | Request/response cycle | Entire system lifecycle |

### Scope

| Aspect | MCP | SCP |
|--------|-----|-----|
| **Defines** | Tool schemas, parameters, invocation | Architecture, ownership, dependencies |
| **Granularity** | Individual tool/function level | System/service level |
| **Cardinality** | Many tools per service | One manifest per service |
| **Focus** | What can be done | What exists and how it relates |

### Information Provided

| Information | MCP | SCP |
|-------------|-----|-----|
| **Tool Parameters** | ✅ Yes | ❌ No |
| **Return Types** | ✅ Yes | ❌ No |
| **Ownership** | ❌ No | ✅ Yes |
| **Dependencies** | ❌ No | ✅ Yes |
| **SLAs** | ❌ No | ✅ Yes |
| **Failure Modes** | ❌ No | ✅ Yes |
| **Contact Info** | ❌ No | ✅ Yes |
| **Observability** | ❌ No | ✅ Yes |

### Technical Details

| Aspect | MCP | SCP |
|--------|-----|-----|
| **Format** | JSON-RPC, JSON Schema | YAML manifest |
| **Protocol** | stdio, HTTP/SSE | File-based |
| **Validation** | JSON Schema | JSON Schema |
| **Versioning** | Per-tool versions | System-level versioning |
| **Runtime** | Active server process | Static manifest files |

---

## How They Work Together

### Complementary Nature

**MCP provides the "How"** → SCP provides the "What"

```
┌─────────────────────────────────────────────────────────┐
│                    User Request                          │
│          "Deploy an Azure Function App"                  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │   Claude (AI Model)   │
         └───────────┬───────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
        ▼                         ▼
┌───────────────┐         ┌───────────────┐
│      MCP      │         │      SCP      │
│  "How to do"  │         │ "What exists" │
└───────┬───────┘         └───────┬───────┘
        │                         │
        ▼                         ▼
┌───────────────┐         ┌───────────────┐
│ Invoke tool:  │         │ Understand:   │
│ plan_deploy   │         │ - Who owns it │
│ parameters... │         │ - What's tier │
└───────────────┘         │ - SLA impact  │
                          └───────────────┘
```

### Example: Azure Terraform Server

**MCP Server** (`azure-tf-mcp-server.js`):
```json
{
  "tools": [
    {
      "name": "plan_deployment",
      "description": "Generate Terraform plan",
      "inputSchema": {
        "type": "object",
        "properties": {
          "recipeName": { "type": "string" },
          "parameters": { "type": "object" }
        }
      }
    }
  ]
}
```

**SCP Manifest** (`azure-tf/scp.yaml`):
```yaml
scp: "0.1.0"

system:
  urn: "urn:scp:genai-mcpservers:azure-tf-server"
  name: "Azure Terraform MCP Server"
  classification:
    tier: 1  # Critical infrastructure

ownership:
  team: "platform-engineering"
  contacts:
    - type: "pagerduty"
      ref: "https://pagerduty.com/platform-eng"

provides:
  - capability: "infrastructure-provisioning"
    type: "mcp-tools"
    sla:
      availability: "99.9%"
      latency_p99_ms: 5000

depends:
  - system: "urn:scp:cloud-providers:azure"
    criticality: "critical"
    failure_mode: "fail-fast"
```

**How They Work Together:**

1. **Tool Discovery** (MCP)
   - Claude discovers `plan_deployment` tool via MCP
   - Knows what parameters it accepts

2. **Context Understanding** (SCP)
   - Claude reads SCP manifest
   - Knows this is Tier 1, critical infrastructure
   - Knows it depends on Azure (critical)
   - Knows who to notify if problems occur

3. **Informed Execution**
   - Claude invokes tool (MCP)
   - Understands consequences (SCP)
   - Can warn: "This is a Tier 1 service, proceed carefully"

---

## Real-World Scenarios

### Scenario 1: Deploying Infrastructure

**Using MCP Only:**
```
User: "Deploy a function app"
Claude: [Calls plan_deployment via MCP]
Result: ✅ Deployment planned
```

**Using MCP + SCP:**
```
User: "Deploy a function app"
Claude: [Reads SCP manifest first]
        "This will use the Azure Terraform MCP Server (Tier 1).
         This service has a 99.9% SLA and is owned by platform-engineering.
         It depends critically on Azure Cloud.
         
         If Azure is down, this will fail-fast.
         
         Ready to proceed?"
User: "Yes"
Claude: [Calls plan_deployment via MCP]
Result: ✅ Deployment planned with full context
```

### Scenario 2: Troubleshooting

**Using MCP Only:**
```
User: "Why is my deployment failing?"
Claude: "Let me check the tool output..."
Result: ❌ Limited context
```

**Using MCP + SCP:**
```
User: "Why is my deployment failing?"
Claude: [Reads SCP manifest]
        "The Azure Terraform MCP Server depends on:
         1. Azure Cloud (critical, fail-fast)
         2. Terraform CLI (critical, fail-fast)
         
         Checking OpenTelemetry traces...
         Azure API is returning 503 errors.
         
         Since the failure_mode is 'fail-fast', the service
         is correctly rejecting requests.
         
         Contact: platform-engineering team via PagerDuty
         (https://pagerduty.com/platform-eng)"
Result: ✅ Full operational context
```

### Scenario 3: Change Impact Analysis

**Using MCP Only:**
```
User: "I need to update the payment service"
Claude: "Okay, what changes?"
Result: ❌ No awareness of dependencies
```

**Using MCP + SCP:**
```
User: "I need to update the payment service"
Claude: [Reads SCP graph]
        "The payment service has 17 dependents:
         - 5 Tier 1 (critical)
         - 8 Tier 2 (standard)
         - 4 Tier 3 (low priority)
         
         Critical dependents include:
         - checkout-service (owned by commerce-team)
         - subscription-service (owned by billing-team)
         
         Recommended actions:
         1. Notify affected teams via Slack
         2. Schedule during low-traffic window
         3. Deploy to staging first
         4. Monitor dependent service health"
Result: ✅ Informed decision making
```

---

## When to Use Which

### Use MCP When:
- ✅ Building conversational AI tools
- ✅ Enabling LLMs to take actions
- ✅ Creating IDE integrations (VS Code)
- ✅ Implementing real-time tool invocation
- ✅ Standardizing tool interfaces

### Use SCP When:
- ✅ Documenting system architecture
- ✅ Enabling governance and compliance
- ✅ Facilitating change impact analysis
- ✅ Providing operational context
- ✅ Supporting LLM reasoning about systems
- ✅ Validating runtime vs declared behavior

### Use Both When:
- ✅ Building enterprise GenAI platforms
- ✅ Implementing infrastructure-as-conversation
- ✅ Creating AI-assisted DevOps tools
- ✅ Supporting multi-team service ecosystems
- ✅ Ensuring observable, governable AI systems

---

## Comparison to Other Protocols

### MCP vs OpenAPI

| Aspect | MCP | OpenAPI |
|--------|-----|---------|
| **Purpose** | AI tool invocation | HTTP API documentation |
| **Consumer** | AI models | Developers, API clients |
| **Protocol** | stdio, JSON-RPC | HTTP REST |
| **Focus** | Conversational access | Programmatic access |

**Key Difference:** MCP is designed for AI consumption, OpenAPI for human/program consumption.

### SCP vs Service Mesh (Istio)

| Aspect | SCP | Service Mesh |
|--------|-----|--------------|
| **Nature** | Declarative intent | Runtime enforcement |
| **Scope** | What should be | What is happening |
| **Implementation** | Static manifests | Dynamic proxy injection |
| **Observability** | Declared metrics | Actual traffic data |

**Key Difference:** SCP declares intent, Service Mesh enforces and observes reality. Best used together!

### SCP vs Backstage Service Catalog

| Aspect | SCP | Backstage |
|--------|-----|-----------|
| **Format** | YAML manifests | YAML + UI |
| **LLM-Readable** | ✅ Yes | ⚠️ Partially |
| **Standardization** | Schema-based | Plugin-based |
| **Dependency Modeling** | First-class | Via plugins |

**Key Difference:** SCP is more LLM-focused and standardized; Backstage is more feature-rich and UI-driven.

---

## Best Practices

### For MCP Servers

1. **Clear Tool Descriptions**
   ```json
   {
     "name": "deploy_function",
     "description": "Deploy Azure Function App with specified configuration"
   }
   ```

2. **Detailed Parameter Schemas**
   ```json
   {
     "inputSchema": {
       "type": "object",
       "properties": {
         "name": { 
           "type": "string",
           "description": "Function app name (alphanumeric, 3-24 chars)"
         }
       }
     }
   }
   ```

3. **Error Handling**
   - Return structured error messages
   - Include actionable guidance

### For SCP Manifests

1. **Complete Ownership Info**
   ```yaml
   ownership:
     team: "platform-engineering"
     contacts:
       - type: "pagerduty"
       - type: "slack"
       - type: "email"
   ```

2. **Explicit Dependencies**
   ```yaml
   depends:
     - system: "urn:scp:azure:cloud"
       criticality: "critical"
       failure_mode: "fail-fast"
       timeout_ms: 30000
   ```

3. **Observability Integration**
   ```yaml
   runtime:
     environments:
       production:
         otel_service_name: "payment-service"
   ```

### For Combined Usage

1. **Cross-Reference in Documentation**
   ```yaml
   # SCP Manifest
   provides:
     - capability: "infrastructure-provisioning"
       type: "mcp-tools"
       contract:
         type: "mcp-server"
         ref: "./azure-tf-mcp-server.js"
   ```

2. **Validate Both**
   ```bash
   # Validate MCP server tools
   mcp-validate azure-tf-mcp-server.js
   
   # Validate SCP manifest
   check-jsonschema scp.yaml
   ```

3. **Keep in Sync**
   - When adding MCP tools, update SCP manifest
   - When changing dependencies, update both

---

## Interview Talking Points

### For GenAI Security Role

**1. Security Context**
- "MCP enables conversational security tools, but SCP provides the security context - who owns what, what's critical, what's the blast radius"

**2. Governance**
- "We use SCP manifests to enforce security policies: All Tier 1 services must have prompt injection protection, PagerDuty integration, and 99.9% SLA"

**3. Observable Security**
- "SCP declares OpenTelemetry service names, we compare against actual traces to detect if security services are being bypassed"

**4. Intelligent Incident Response**
- "When a security alert fires, SCP tells us who to page, what's affected, and what the SLA impact is - all machine-readable for AI-assisted response"

**5. LLM-Assisted Threat Modeling**
- "LLMs read SCP manifests to generate threat models: 'Show me all services that can access PII but don't route through security checks'"

---

## Summary

### MCP (Model Context Protocol)
- **Purpose**: Enable AI to USE tools
- **Format**: JSON-RPC, tool schemas
- **Focus**: Real-time invocation
- **Consumer**: AI models
- **Scope**: Tool/function level

### SCP (System Capability Protocol)  
- **Purpose**: Describe what systems ARE
- **Format**: YAML manifests
- **Focus**: Architecture & dependencies
- **Consumer**: Humans, LLMs, tools
- **Scope**: System/service level

### Together
**MCP provides the interface**, **SCP provides the context**

For enterprise GenAI platforms, especially in security, you need **both**:
- MCP for conversational tool access
- SCP for governance, observability, and intelligent operations

---

## Resources

### MCP
- Specification: https://modelcontextprotocol.io
- GitHub: https://github.com/anthropics/mcp
- Examples: Your `experiment-genai-mcpservers` project

### SCP
- Website: https://systemcapabilityprotocol.com
- Specification: https://github.com/krackenservices/scp-definition
- Demo: https://github.com/krackenservices/scp-demo
- Your Implementation: `experiment-genai-mcpservers/*/scp.yaml`

---

**Document Version**: 1.0  
**Last Updated**: December 17, 2025  
**Author**: Interview Preparation Material
