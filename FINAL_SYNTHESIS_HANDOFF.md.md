# Autonomous Software Orchestration Platform Implementation Package

## Source Documents

- `synthesis.md`
- `evidence-index.md`
- `integration-validation.md`
- `human-actions.md`
- `implementation-plan.md`
- `template-repo-requirements.md`
- `claude-code-operating-contract.md`
- `risk-register.md`
- `final-claude-code-prompt.md`

---

# synthesis.md

## Executive Implementation Summary

The ensuing synthesis package establishes the definitive architectural blueprint for an autonomous, agent-driven software orchestration platform, specifically tailored for implementation by Claude Code. The comprehensive analysis resolves the inherent tension between the desire for zero-touch algorithmic autonomy and the rigid cryptographic perimeters enforced by modern cloud platforms. The foundational conclusion dictates that while steady-state operations, continuous integration (CI), and infrastructure mutation can be fully automated using Workload Identity Federation (WIF) and the Model Context Protocol (MCP), the initial establishment of identity, billing authorization, and cryptographic trust anchors mandates a strict, human-in-the-loop (HITL) bootstrap sequence.

This architecture integrates the Policy-as-Code (PaC) documentation enforcement mechanisms proven in the project-life-133 and ripo-skills-main repositories with the external service orchestration models derived from claude-admin. The resulting synthesis dictates a hub-and-spoke topology where GitHub operates as the immutable source of truth, triggering deployments to Railway and Cloudflare, while n8n manages external workflow orchestration and OpenRouter handles isolated inference routing. The package provides the precise operational boundaries, secrets inventory, and step-by-step implementation parameters required for a build agent to scaffold the repository without demanding human re-interpretation of the underlying research.

## Final Target Architecture

The system architecture operates as a strictly sandboxed environment governed by the principle of least privilege, with explicit boundaries between the build-time scaffold and the runtime execution engine.

The identity and security core relies on Google Cloud Platform (GCP) Workload Identity Federation (WIF). WIF acts as the primary trust broker, exchanging short-lived GitHub Actions tokens for GCP access, thereby eliminating the need for static, long-lived service account keys. GCP Secret Manager serves as the centralized vault for all third-party API keys, ensuring that the repository remains entirely devoid of hardcoded credentials.

The primary deployment target is Railway, which acts as the runtime environment for containerized services. Railway is selected due to its native OpenID Connect (OIDC) support, which allows secure, secretless deployments directly from GitHub Actions using the .well-known/openid-configuration endpoints. For edge routing, DNS management, and serverless edge functions, the architecture employs Cloudflare. However, because native OIDC is not natively supported for continuous integration deployments to Cloudflare Workers without complex workarounds, the deployment pipeline relies on the official wrangler-action utilizing standard API tokens injected securely from GCP.Workflow orchestration is managed by n8n. Deployed as a containerized instance within Railway, n8n serves as the integration engine, executing external REST calls and connecting discrete APIs. n8n is configured to pull its configurations and workflows dynamically via the n8n CLI and connects directly to GCP Secret Manager to securely mount external secrets at runtime. Crucially, n8n exposes its workflows as structured tools to the LLM agent via the official n8n-nodes-langchain.mcptrigger node, seamlessly integrating standard REST architectures into the agentic ecosystem.

The LLM gateway is managed by OpenRouter, which routes all model inference requests. To strictly control billing and rate limits, the system utilizes the OpenRouter Management API to programmatically generate, rotate, and revoke keys for isolated microservices and discrete agent sessions. Task and state management are centralized in Linear. Linear acts as the project management backend, syncing bidirectionally with GitHub pull requests to ensure task state matches code state. Linear's official remote MCP server (mcp.linear.app) is integrated into the agent's toolset, allowing the AI to query issues and update statuses natively. Finally, Telegram provides the human-in-the-loop (HITL) communication layer, serving as the interface for operational alerts, manual overrides, and approval prompts.

## Main Build-Time Components

The build-time architecture is instantiated via a GitHub Template Repository that establishes the foundational scaffold. This repository contains the directory structures (.claude/, docs/adr/, policy/, src/agent/) and the mandatory workflow files required for continuous integration.

The primary governance mechanism is Open Policy Agent (OPA) combined with Conftest. This system evaluates Rego policies during the CI cycle to enforce strict documentation synchronization. Specifically, the pipeline evaluates diffs to ensure that any modification to the source code is accompanied by corresponding updates to the CLAUDE.md context file and the JOURNEY.md session tracker. Furthermore, any changes to infrastructure dependencies trigger a policy failure unless accompanied by a properly formatted Markdown Architectural Decision Record (MADR).

Infrastructure-as-Code (IaC) is governed by Terraform. The Terraform configurations define the state for the GCP WIF pools, GCP Secret Manager instances, GitHub repository properties, and Cloudflare DNS records. During the build phase, the Claude Code CLI operates as the local build agent. It utilizes the railway skills plugin to execute local linting, configuration generation, and deployment staging without requiring complex external dependencies.

## Main Runtime Components

At runtime, the core processing logic is handled by a TypeScript Skills Router. Proven in previous implementations to require zero runtime npm dependencies, this router executes deterministic "skills" by utilizing Jaccard semantic similarity matching to map inbound user intents to discrete YAML definitions (SKILL.md).

When complex external API interactions are required, the TS Router defers to the n8n orchestrator. The containerized n8n instance retrieves its execution credentials directly from the external secret store and processes the webhook payloads asynchronously. The entire runtime environment is constrained by Model Context Protocol (MCP) servers. Both local and remote servers present structured, validated tools to the runtime LLM, enforcing input validation and providing a standardized error-handling schema. All actions taken by the runtime system are recorded by the Telemetry and Audit Logger, which maintains an append-only log in JOURNEY.md and generates external structured logging for non-repudiation.

## Component Boundaries, Data Flow, and Control Flow

The control flow operates sequentially: a Human Operator initiates a task, which translates to a GitHub Pull Request. This triggers GitHub Actions, which first run the OPA Policy Check. Upon success, the system executes a Terraform Plan/Apply sequence, followed by a Railway Deployment, which ultimately results in the activation of an n8n workflow.

The data flow ensures consistency across the ecosystem. An issue or intent registered in Linear is synced automatically to GitHub. The local Claude Code agent reads the intent, proposes a code change, and initiates local tests. Once the code is pushed and merged, the deployment pipeline updates the edge cache on Cloudflare, and the Telegram bot notifies the human operator of the successful lifecycle completion.

Trust boundaries are strictly enforced. All inbound webhook signatures must be cryptographically validated to prevent spoofing. The fail-open webhook vulnerability observed in the legacy claude-admin repository is explicitly rejected; the architecture demands a strict fail-closed, deny-by-default permission model.

Secrets boundaries dictate that production secrets must never exist in plaintext within the repository or in local .env files. Secrets are injected manually by a human into the GCP Secret Manager and retrieved strictly at runtime by the Railway environment or the n8n instance using tightly bound IAM roles.

Human-Gated Boundaries are non-negotiable. Operations including billing initialization, OAuth consent flows, Root API Token generation, and the initial creation of the WIF provider form an impenetrable perimeter that algorithms cannot cross without compromising systemic security.

## Methodological Validation

The architecture distinguishes clearly between proven, standardized, and synthesized components.
The components tagged as PROVEN_IN_REPO include the OPA/Conftest documentation enforcement cycle, the zero-dependency TypeScript Skills Router, the injection of systemic context via CLAUDE.md, and the governance of architectural decisions via ADRs.
Components tagged as OFFICIAL_STANDARD derive directly from vendor documentation. These include the implementation of WIF for GitHub Actions , the utilization of Linear's official MCP functionality , OpenRouter's programmatic key management , GitHub App permission models , and the strict security mandates defined by the MCP specification.
The SYNTHESIZED components represent the architectural novelties required for implementation. Chief among these is the connection between n8n's MCP trigger nodes and the TS Skills Router, a design choice that allows the zero-dependency TypeScript code to defer complex API integrations to a dedicated orchestration engine while maintaining strict execution state control.
The architecture dictates that the Cloudflare deployment authentication must be TESTED before production. While OIDC is highly requested for Cloudflare authentication , standard CI deployments currently utilize API tokens via the wrangler-action. The exact configuration of a WIF-to-Cloudflare fallback requires empirical validation in the deployment environment.

## Exact Acceptance Criteria

The repository is initialized from a standardized template without human intervention beyond the initial cloning command.

Pushing code to the src/ directory without a corresponding update to JOURNEY.md and CLAUDE.md results in a deterministic CI pipeline failure driven by OPA/Rego policies.

GitHub Actions successfully authenticate to the GCP environment using OIDC/WIF, entirely avoiding the presence of static service account keys in GitHub Secrets.

The system deploys an n8n instance to Railway successfully, and the n8n instance autonomously retrieves its operating credentials from GCP Secret Manager via external secret mounting.

Linear issues automatically reflect GitHub PR statuses via native webhooks, transitioning seamlessly from "In Progress" to "Done".The MCP server architecture enforces human oversight, requiring explicit human confirmation via the interface before executing any destructive file system operations or infrastructure mutations.


---

# evidence-index.md

## Source Inventory Table

Source IDSource TypeSource NameRelevant ComponentsKey ClaimsConfidenceRepo Reportproject-life-133/134Docs, CI, Skills, GCPPaC enforces documentation via OPA/Rego; TS zero-dependency Skills Router; GCP WIF integration.

HighStandards ReportInternet StandardsArchitecture, IAMFull autonomy requires human bootstrapping; OIDC prevents static token leaks.

HighRepo Reportripo-skills-mainSkills, DocsSKILL.md format, CI tests, Templatizer distribution for agent skills.

HighRepo Reportclaude-adminMCP, Cloudflare, n8nMCP Admin server provisions infra; fail-open webhook vulnerability exists.

MediumOfficial DocRailway DocsWIF, GitHub ActionsNative OIDC/WIF support via .well-known endpoints for secure CI execution.

HighOfficial DocCloudflare DocsCloudflare, CIOIDC supported for IdP; wrangler-action uses API tokens for deploy.

HighOfficial DocLinear DocsLinear, Webhooks, MCPGraphQL API, bi-directional GitHub PR sync, Official MCP Server at mcp.linear.app.

HighOfficial DocOpenRouter DocsLLM, Secrets1M free requests; Management API allows programmatic key generation and rotation.

HighOfficial Docn8n Docsn8n, Secrets, MCPExternal secrets support (GCP/AWS); CLI workflow import syntax; official MCP trigger node.

HighOfficial DocGitHub DocsGitHub AppApps require granular permissions (Contents, Workflows); Repos require write access to set secrets.

HighOfficial DocMCP SpecMCP, SecurityServers must validate input; Human-in-the-loop required for trust and safety operations.

HighOfficial DocTelegram DocsTelegram@BotFather /newbot interaction is the only official mechanism to instantiate a bot.

HighOfficial DocGCP DocsWIFWorkload Identity Federation replaces static service account keys for multicloud access.

HighOfficial DocRailway CLIClaude Code Skillsrailway skills plugin natively supports Claude Code agent integrations and deployments.

High

## Evidence Map by Component

GitHub App: Mapping derived from regarding permission scopes and token mechanisms.

WIF: Architectural necessity backed by detailing the elimination of static service account credentials.

Railway: Operational parameters validated via outlining OIDC and CLI skill structures.

Cloudflare: Deployment pathways verified against highlighting the reliance on API tokens over native CI OIDC.n8n: Orchestration capabilities sourced from concerning MCP triggers and external secret mounts.

Telegram: Bot generation limits established by explicitly mandating manual BotFather flows.

OpenRouter: Inference management confirmed by detailing programmatic key creation.

Linear: State tracking and agentic integration supported by featuring the remote MCP server.

MCP: Security architectures mandated by defining the necessity of human oversight for destructive actions.

Skills / Skill-sync: Execution paradigms proven in utilizing Jaccard similarity and TS routing.

CI: Policy enforcement proven in detailing OPA/Conftest Rego structures.

Docs: Context synchronization proven in outlining CLAUDE.md, JOURNEY.md, and MADR formatting.

Testing: Validation mechanisms inferred from detailing Jest test coverage and IaC dry-runs.

Rollback: Recovery methodologies synthesized from detailing CLI reversions and fire-and-forget risks.

Every cited claim maps directly to the enumerated sources to ensure absolute traceability and verifiable validation prior to automated implementation.


---

# integration-validation.md

## Component Validation Matrix

### GitHub App

Must use fine-grained repository permissions (Contents, Workflows, Secrets) and requires human OAuth installation to bootstrap autonomy.

OFFICIAL_STANDARD, HUMAN_REQUIREDNo direct repo evidence found in attached reports regarding the creation step.

Permission scopes required for code and secret manipulation natively support fine-grained scoping.

N/AN/AApp registration, OAuth consent, and installation on target repositories.

HighClaude Code cannot self-register the App. The agent must pause execution and provide the human operator with a direct setup link and an explicit permission checklist, validating the installation via API before proceeding.

### WIF

 via GCP Workload Identity Federation must replace static service accounts for GitHub Actions CI/CD pipelines.

PROVEN_IN_REPO, OFFICIAL_STANDARD, HUMAN_REQUIRED: Used to authenticate GH Actions.: Eliminates maintenance and security burden of keys.

OIDC token exchange mechanism and IAM policy binding successfully mitigate static token leakage.

N/AN/AInitial creation of the WIF pool, provider, and billing setup in GCP.HighClaude Code will template the Terraform configuration for the WIF infrastructure, but the actual execution of the state application requires the human operator to authenticate to GCP via CLI first.

### Railway

 as primary runtime; natively supports OIDC, and integrates securely with Claude Code via railway skills.

OFFICIAL_STANDARD, HUMAN_REQUIRED: Provisioned via shell scripts.: OIDC endpoint and CLI integration.

OIDC endpoints and native CLI agent skills provide a seamless interface for automated operations.

N/AN/AAccount creation, billing association, and initial project bootstrapping.

HighClaude Code can autonomously manage services, trigger redeployments, and view logs post-bootstrap using the use-railway plugin, significantly reducing manual DevOps overhead.

### Cloudflare

 use API Tokens for CI/CD deployments (wrangler-action) as native OIDC for Workers lacks seamless CI support without workarounds.

OFFICIAL_STANDARD, SYNTHESIS_INFERENCE, HUMAN_REQUIRED: Managed via Terraform.: Wrangler action relies on secrets; OIDC is highly requested but complex to implement natively.

Terraform configuration successfully manages DNS and caching rules using standard API inputs.

That an API token remains the safest official path until OIDC is fully stabilized for Workers CI.N/AGeneration of the Super Admin API token via the dashboard.

MediumClaude Code must instruct the human operator to generate the API token and inject it immediately into GCP Secret Manager to ensure it is never exposed in repository plaintext.

### n8n

 as backend orchestrator, retrieving secrets via GCP Secret Manager and exposing workflows to the agent via official MCP triggers.

PROVEN_IN_REPO, OFFICIAL_STANDARD: Used in service templates.: External secrets and LangChain MCP trigger nodes.

CLI import of JSON workflows and external secret mounts function deterministically.

That n8n's execution speed and routing latency are sufficient for synchronous MCP calls from an LLM.Execution latency of n8n via MCP under high concurrent load.

Initial encryption key setup and root user creation upon instance initialization.

HighClaude Code can generate workflow JSON files locally and use the n8n CLI to push them directly to the deployed n8n instance, bypassing manual UI construction.

### Telegram

 as the human-in-the-loop notification layer; bot creation is strictly gated by @BotFather and cannot be automated.

OFFICIAL_STANDARD, DO_NOT_AUTOMATE, HUMAN_REQUIREDNo direct repo evidence found in attached reports.: BotFather manual creation process is strictly enforced by Telegram.

The absolute impossibility of programmatic bot creation without utilizing an unauthorized userbot mechanism.

N/AN/AInteracting with BotFather, configuring /setcommands, and copying the HTTP API token securely.

HighClaude Code must not attempt to automate Telegram creation. It must pause and provide exact text prompts for the user to copy and paste into the BotFather interface.

### OpenRouter

 LLM access using programmatic Management API keys to isolate service billing and enforce rate limits.

OFFICIAL_STANDARD, HUMAN_REQUIREDNo direct repo evidence found in attached reports.: Management keys allow programmatic POST /api/v1/keys for dynamic provisioning.

Programmatic key generation via SDK/API enables strict budget control per service.

The necessity of a dedicated workspace specifically provisioned for the agent's operations.

N/AAccount creation, credit card setup, and creation of the first root Management Key.

HighClaude Code will utilize the Management Key to autonomously provision scoped, low-limit keys for deployed sub-services, immediately revoking them if anomalous behavior is detected.

### Linear

 for project state tracking, syncing bidirectionally with GitHub PRs, and acting as an MCP server.

OFFICIAL_STANDARDNo direct repo evidence found in attached reports.: Bi-directional GitHub sync and remote MCP server.

GraphQL API interactions and standard MCP tool schemas function natively for issue tracking.

N/AN/AWorkspace creation, GitHub integration linking, and personal API token generation.

HighClaude Code can query Linear via the MCP server to discover its next task, transition issue states automatically upon PR creation, and log operational summaries.

### MCP

 structured, validated tool boundaries. Must enforce human-in-the-loop oversight for destructive actions.

PROVEN_IN_REPO, OFFICIAL_STANDARD: MCP admin server provisions infrastructure.: Validation, access controls, and human prompts.

Schema validation and error handling separation explicitly mitigate prompt injection risks.

N/AN/AExplicit approval of tool invocations impacting billing, infrastructure mutation, or data deletion.

HighClaude Code must register the MCP servers locally, respect the isError flags rigorously, and implement sanitization requirements before passing data to the language model.

### Skills / Skill-sync

-dependency TypeScript router maps intents to SKILL.md YAML definitions using Jaccard similarity.

PROVEN_IN_REPO: TS router, Templatizer.: railway skills plugin.

The execution pattern of CI-enforced documentation and TS routing operates reliably without bloat.

N/AN/ANone.

HighClaude Code can autonomously write new routing skills, update the SKILL.md registry, and push them to the repository for immediate CI validation.

### CI

 Rego policies strictly block merges if CLAUDE.md, JOURNEY.md, or ADRs are out of sync.

PROVEN_IN_REPO: GitHub Actions blockers using Rego.: CI linting is fully automatable.

Blockers based on diff analysis against policy files prevent documentation drift effectively.

N/AN/ANone.

HighClaude Code must construct robust Rego policies and configure the .github/workflows to enforce rigid documentation drift protection prior to any code integration.

### Docs

 state is maintained in CLAUDE.md and a rotatable JOURNEY.md log, utilizing the MADR format for architectural decisions.

PROVEN_IN_REPO: Context sync, ADR validation.

No official/source evidence found in attached reports or targeted verification.

The structural requirement of these files to maintain longitudinal agent context across sessions.

N/AN/ANone.

HighClaude Code must append a chronological entry to JOURNEY.md for every operational session and update CLAUDE.md whenever the system architecture or dependencies change.

### Testing

 end-to-end automation in legacy repos, necessitating robust unit tests and mocked IaC plans.

PROVEN_IN_REPO, SYNTHESIS_INFERENCE: Missing tests noted. : Jest tests present.: IaC validation via dry-run plans.

Jest unit test execution provides a baseline for local validation prior to commit.

Comprehensive E2E integration testing methodologies tailored specifically for autonomous, non-deterministic systems.

Mocking asynchronous MCP server responses reliably within a stateless CI environment.

None.

MediumClaude Code must synthesize a sophisticated test harness that mocks external API calls, ensuring skills are mathematically validated before triggering a deployment pipeline.

### Rollback

 failures require automated config reversion and state cleanup, but destructive cleanup must remain strictly human-gated.

SYNTHESIS_INFERENCE, HUMAN_REQUIRED: Fire-and-forget model noted as a severe weak governance vector.: Vercel/Railway skills support rollback.

Reversion of deployment states via CLI operates deterministically to restore previous known-good states.

N/ATerraform state file recovery and reconciliation in extreme edge cases involving orphaned resources.

Manual review of destructive cleanup operations (e.g., dropping a production database or terminating a core network).

HighClaude Code is explicitly forbidden from deleting cloud databases autonomously and must halt to request human intervention for any operation resulting in unrecoverable state destruction.


---

# human-actions.md

## Human Action Summary

Autonomous software systems, regardless of sophistication, cannot self-originate secure identity, authorize fiat billing mechanisms, or establish root cryptographic trust without fundamentally violating the security perimeters of modern cloud platforms. The following implementation steps explicitly require a Human-In-The-Loop (HITL). Claude Code is programmed to halt execution, print comprehensive instructions for the human operator, and await manual confirmation of completion before proceeding with the automation pipeline.

## Platform-by-Platform Checklist

### 1. GitHub App & Repository Integration

Action: Create a GitHub App, assign fine-grained permissions, and install it on the target repository.

Why human is required: OAuth consent flows and organization-level installations require explicit cryptographic authorization from an administrative user to prevent rogue agent installations.

Claude Code can prepare instructions: Yes (Provides an exact, copy-paste permission checklist: Contents, Workflows, Secrets).

Claude Code can validate afterward: Yes (By executing a test API call to verify the assigned permission scopes).

Required secrets/tokens: GitHub App ID, Installation ID, and the generated Private Key.

Security notes: Private keys must be injected directly into the GCP Secret Manager. Committing them to the repository, even temporarily, compromises the entire trust chain.

Blocking status: BLOCKED until completed. Automation cannot proceed without GitHub identity.

### 2. GCP Workload Identity Federation (WIF)

Action: Create the overarching GCP Project, enable billing capabilities, and execute the initial WIF Workload Identity Pool and Provider configuration.

Why human is required: Cloud providers mandate human verification and billing attachments to prevent automated Sybil attacks and fraudulent compute resource consumption.

Claude Code can prepare instructions: Yes (Generates the specific gcloud CLI commands required for execution).

Claude Code can validate afterward: Yes (By executing a dry-run authentication payload via GitHub Actions).

Required secrets/tokens: None (The OIDC architecture explicitly eliminates the need for static tokens).

Security notes: The IAM role must be bound strictly to the specific GitHub repository and the refs/heads/main branch to prevent lateral privilege escalation.

Blocking status: BLOCKED until completed. CI/CD pipelines cannot deploy infrastructure without WIF.

### 3. Railway Deployment Platform

Action: Register a user account, link the GitHub identity, approve Stripe billing workflows, and generate the initial Project configuration.

Why human is required: OAuth consent for GitHub linkage and the requirement for credit-card processing mechanisms.

Claude Code can prepare instructions: Yes (Provides UI navigation instructions).

Claude Code can validate afterward: Yes (Via the railway status CLI command).

Required secrets/tokens: Railway API Token (if an OIDC fallback is required), or OIDC provider confirmation.

Security notes: Scope the OIDC trust specifically to the designated deployment environment, preventing cross-project contamination.

Blocking status: BLOCKED until completed. The runtime environment relies on this foundation.

### 4. Cloudflare Edge Services

Action: Create a Cloudflare account, configure the root domain name, interact with the DNS registrar, and manually generate a Super Admin API Token.

Why human is required: While OIDC is requested by the community, the official wrangler-action heavily relies on standard API tokens. Purchasing and pointing DNS nameservers requires manual registrar UI interaction.

Claude Code can prepare instructions: Yes (Provides the exact permission scopes for the token generation).

Claude Code can validate afterward: Yes (Via the wrangler whoami CLI command).

Required secrets/tokens: CLAUDEFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID.
- **Security notes:** The generated token must be stored in the GCP Secret Manager immediately to prevent exfiltration via CI logs.

Blocking status: BLOCKED until completed. Edge routing and DNS are dependent on this authorization.

### 5. n8n Orchestration Engine

Action: Initialize the first administrative user account and set the master database encryption key.

Why human is required: n8n enforces manual setup of the root owner account upon initial boot to prevent unauthorized takeover of the instance via automated scraping.

Claude Code can prepare instructions: Yes.

Claude Code can validate afterward: Yes (By making an authenticated REST API call to the instance).

Required secrets/tokens: N8N_ENCRYPTION_KEY, Admin Username/Password.

Security notes: The encryption key must be securely generated via a cryptographically secure pseudo-random number generator (CSPRNG) and stored in the GCP Secret Manager prior to the first boot.

Blocking status: BLOCKED until completed. Workflow execution requires a secure database.

### 6. Telegram Communication Layer

Action: Message @BotFather on the Telegram client, issue the /newbot command, define the bot's nomenclature, and extract the resulting HTTP API Token.

Why human is required: Telegram strictly enforces human interaction with BotFather to mitigate spam botnets. There is no official REST API endpoint to programmatically originate a bot from scratch.

Claude Code can prepare instructions: Yes (Provides the exact strings for the user to paste).

Claude Code can validate afterward: Yes (By hitting the GET /getMe endpoint with the newly minted token).

Required secrets/tokens: Telegram Bot Token.

Security notes: Do not expose the token in repository logs; route it directly to the secrets manager.

Blocking status: BLOCKED until completed. Alerting and HITL interfaces depend on this transport.

### 7. OpenRouter Inference Gateway

Action: Create an OpenRouter account, load fiat billing credits, and generate the master Management API Key.

Why human is required: Financial transactions, compliance checks, and Sybil-protection measures.

Claude Code can prepare instructions: Yes.

Claude Code can validate afterward: Yes (By hitting the GET /api/v1/keys endpoint).

Required secrets/tokens: OpenRouter Management API Key.

Security notes: This key possesses root privileges allowing it to spawn new keys; its scope within the Secret Manager must be tightly constrained.

Blocking status: BLOCKED until completed. The agent cannot perform cognitive tasks without inference access.

### 8. Linear Project Management

Action: Create a workspace, authorize the official GitHub integration app, and generate a Personal API Key.

Why human is required: OAuth flows and complex UI-based workspace bootstrapping protocols.

Claude Code can prepare instructions: Yes.

Claude Code can validate afterward: Yes (By executing a GraphQL query to list active teams).

Required secrets/tokens: Linear API Key, Linear Webhook Secret.

Security notes: Ensure webhook secrets are utilized to cryptographically validate incoming Linear requests, preventing spoofing.

Blocking status: Optional/Deferred (Can be completed asynchronously after core infrastructure is deployed).

### 9. MCP Server Trust Initialization

Action: Explicitly approve the connection and subsequent tool execution of remote MCP servers (e.g., the Linear MCP).

Why human is required: The core MCP specification explicitly mandates human-in-the-loop oversight to prevent arbitrary data exfiltration or destructive actions by autonomous LLMs.

Claude Code can prepare instructions: Yes.

Claude Code can validate afterward: Yes (By pinging the server and observing the response payload).

Required secrets/tokens: None.

Security notes: Operators must never configure auto-approval for tools possessing delete, drop, or mutate capabilities.

Blocking status: BLOCKED during runtime operations requiring novel tool usage.


---

# implementation-plan.md

## Implementation Phases and Dependencies

The implementation sequence is structured to prevent race conditions and ensure that cryptographic trust anchors are fully established before automated infrastructure mutations occur. The execution flow mandates strict validation gates at the conclusion of each phase.

PhaseGoalInputsTasks Claude Code may performHuman prerequisitesValidationRollbackAcceptance criteria1. Manual BootstrapEstablish trust anchors, billing, and identity perimeters.

Human-actions.md checklist.

Print detailed instructional prompts; validate manually provided tokens via API calls.

Complete accounts, WIF, GitHub App, and API token creation via web UIs.

Scripted curl and SDK API calls to verify token validity and permission scopes.

N/A (Manual deletion of accounts or revocation of tokens if necessary).

All cryptographic secrets are securely stored in GCP Secret Manager, confirmed by API validation.

2. Scaffolding & IaCGenerate repository structure, context files, and Terraform state definitions.template-repo-requirements.mdCreate folders, generate CLAUDE.md, draft gcp.tf and cloudflare.tf.

Phase 1 completion and local CLI authorization.

Local terraform plan execution utilizing mocked variables.git reset --hard to revert local scaffolding errors.

Repository layout matches the specification precisely; Terraform plan completes without syntax or dependency errors.

3. CI/CD & PoliciesEnforce Policy-as-Code to prevent documentation drift.

Rego snippets and PaC templates.

Write .github/workflows/, author .rego policies for ADR and JOURNEY.md validation.

Phase 2 completion.

Triggering a test PR lacking documentation to ensure Rego blocks the unauthorized change.

Revert the PR and amend the Rego logic.

A pull request missing a required JOURNEY.md update is deterministically blocked by the CI pipeline.

4. Service DeploymentDeploy n8n orchestrator and TS Skills Router to the Railway runtime.railway skills CLI plugin.

Write railway.toml, craft Dockerfile, execute deployment via CLI tools.

Railway successfully linked to the GitHub repository.

Executing railway status and querying endpoint health checks.railway down or total dashboard project deletion.

The n8n dashboard is accessible via HTTP; the TS Router successfully replies to a mock local intent.

5. AI & IntegrationsConnect Linear, Telegram, and OpenRouter via MCP schemas.

API tokens retrieved from Phase 1.

Configure n8n webhook listeners, attach the Linear MCP server, write the TS Telegram routing skill.

Phase 4 completion.

Send a test Telegram message and verify subsequent Linear issue creation via webhook sync.

Revert integration configurations in the n8n UI or repository.

The runtime agent successfully parses a Telegram message, routes it to the TS skill, and creates a valid Linear issue.

## Component Build, Configuration, and Injection Sequencing

File/folder structure generation order: .claude/ (Context) -> docs/ (ADRs) -> policy/ (Rego) -> terraform/ (IaC) -> src/agent/ (Logic) -> .github/workflows/ (Automation).

Configuration generation order: Terraform state backend initialization -> WIF pool configs -> Secret IAM bindings -> Railway TOML definition -> n8n environment variables.

Secret injection order: Manually inputted by a human operator into GCP -> Terraform reads data via data blocks -> Railway/n8n pulls the credentials dynamically at runtime.

Validation order: Local TS compilation -> Jest unit tests -> Local Terraform format/plan -> CI/CD dry-run -> Deployment smoke tests.


---

# template-repo-requirements.md

## Required Repository Layout

The physical structure of the repository dictates the logical separation of concerns. The agent must construct the exact tree below to ensure compatibility with the continuous integration pipelines and policy evaluation engines.

```
.
├── .claude/
│ ├── settings.json
│ └── plugins/
├── .github/
│ └── workflows/
│ ├── documentation-enforcement.yml
│ ├── terraform-plan.yml
│ └── deploy.yml
├── docs/
│ ├── adr/
│ │ ├── 0001-initial-architecture.md
│ │ └── template.md
│ ├── runbooks/
│ ├── CLAUDE.md
│ └── JOURNEY.md
├── policy/
│ ├── adr.rego
│ └── context_sync.rego
├── src/
│ └── agent/
│ ├── index.ts
│ ├── skills/
│ │ └── SKILL.md
│ └── tests/
├── terraform/
│ ├── gcp.tf
│ ├── cloudflare.tf
│ └── variables.tf
├── .gitignore
├── package.json
└── README.md
```

## Required Configurations and Artifacts

Config files: The package.json must be engineered to possess zero runtime dependencies, utilizing only native Node modules. Development dependencies are restricted to @types/node, typescript, and jest. The railway.toml file governs the production deployment parameters.

Environment Variable Templates: The .env.example file must meticulously map out required keys such as GCP_PROJECT_ID, TELEGRAM_BOT_TOKEN, and OPENROUTER_API_KEY. The values for these keys must remain explicitly blank to prevent accidental leakage during commits.

CI Workflows: GitHub Actions files must be configured with OIDC permissions (permissions: id-token: write, contents: read) to facilitate secure authentication to the GCP WIF endpoints.

Docs: The CLAUDE.md file serves as the system's epistemic boundary, explicitly containing project constraints and architectural context. JOURNEY.md must be instantiated as a strict, append-only chronological log of all agent sessions.

Test Scaffolds: Jest tests must be pre-mapped to the core TypeScript Router functions, specifically asserting the behavior of discoverSkills() and routeIntent().

Secret Hygiene: The .gitignore file must be comprehensively configured to strictly exclude .env, *.pem, *.key, and any local .terraform state folders from version control.

Local Dev Commands: The package scripts must define npm run dev to execute the TS router locally for rapid iteration, and npm run test for executing the Jest suite.

Deployment Commands: The package scripts must wrap railway up to standardize local deployment triggers.

## 

## Repository Readiness Checklist

- [ ] Directory structure instantiated in precise alignment with the specification.
- [ ] OPA/Conftest binaries or corresponding GitHub Actions correctly referenced in .github/workflows.
- [ ] CLAUDE.md initialized with project boundaries and hard constraints.
- [ ] .gitignore securely configured to prevent multi-vector secret leakage.
- [ ] Boilerplate SKILL.md YAML template created in the src/agent/skills/ directory.


---

# claude-code-operating-contract.md

## A. Build-Agent Autonomy Contract

This contract defines the strict operating parameters for the Claude Code CLI while acting as the local development and scaffolding agent on the operator's machine.

What Claude Code may edit: Source code contained within src/, Infrastructure-as-Code files in terraform/, policy evaluation rules in policy/, automation workflows in .github/workflows/, and documentation artifacts in docs/.
- **What Claude Code may create:** Novel agent skills (SKILL.md), new Architectural Decision Records (ADRs), comprehensive unit tests, and configuration templates based on parsed intents.

What Claude Code may delete: Deprecated code strictly confined within the src/ boundary and outdated or failing unit tests that no longer reflect the architecture.

What Claude Code may run locally: Non-destructive execution commands including npm run build, npm run test, terraform plan, railway status, and standard AST linting tools.

What Claude Code may deploy: Non-destructive iterative updates to the Railway runtime environment via the railway up command, strictly contingent upon the successful completion of the local test suite.

What Claude Code must not do: It must not execute terraform apply locally under any circumstances. It must not attempt to alter repository branch protection rules directly via the GitHub API. It must not download, compile, or execute arbitrary binaries sourced from unverified external domains.

What Claude Code must ask a human to do: Provision initial fiat billing relationships, install and authorize GitHub Apps, configure root WIF pools, interact with the Telegram @BotFather UI, and generate any root-level API tokens.

How Claude Code should handle missing secrets: The agent must halt the execution thread immediately, notify the user specifying exactly which secret is absent, and provide the precise gcloud secrets create shell command for the human operator to execute locally.

How Claude Code should handle failed validation: Upon encountering a CI failure or local test regression, the agent will ingest the complete error log, propose a mathematical or logical patch, document the failed attempt transparently in JOURNEY.md, and automatically re-run the local validation sequence.

How Claude Code should handle conflicting evidence: The agent must defer to the official standard. If official documentation contradicts the provided repository templates, the official documentation dictates the implementation. If the conflict remains unresolvable, the agent must append the issue to risk-register.md and halt for human arbitration.

## B. Runtime-System Autonomy Contract

This contract defines the systemic boundaries and operational limits of the deployed application cluster (the n8n orchestrator and the TypeScript Router).

What the deployed system may do autonomously: Route inbound user intents originating via Telegram, read repository states, automatically open pull requests, comment status updates on Linear issues, and query the OpenRouter API for generative inference.

What the deployed system must not do: Delete GitHub repositories, drop cloud databases, alter IAM permission policies, or execute requests that exceed predefined OpenRouter budget thresholds.

What requires human approval: Destructive operations, provisioning net-new cloud environments with associated billing costs, or merging generated code directly to the main branch.

Allowed external calls: Network egress is strictly limited to the Linear GraphQL endpoint, the Telegram HTTP API, the OpenRouter API, and authenticated GitHub API endpoints.

Allowed repo actions: Branch creation from the main trunk, committing generated code, opening pull requests, and executing read operations on repository files.

Allowed Linear actions: Reading issue metadata, appending comments, and transitioning issue states across the Kanban workflow.

Allowed Telegram actions: Transmitting text replies and parsing inbound text commands initiated by known operators.

Allowed OpenRouter actions: Transmitting inference prompts and dynamically selecting fallback models based on real-time latency metrics.

Rate limits and budget limits: Operational expenditure is rigidly capped at $10/day via the OpenRouter Management API limits. Furthermore, n8n webhook workflows are rate-limited to 20 requests per minute to prevent infinite loop exhaustion.

Audit logging requirements: All registered intents and subsequent actions must append an immutable entry to the external structured logging platform and the git-based JOURNEY.md file to ensure comprehensive non-repudiation.

Kill switch requirements: The architecture ensures that the immediate revocation of the Telegram Bot token or the deletion of the WIF provider immediately and safely paralyzes the runtime agent, severing its ability to interact with the external world or deploy code.

Error containment rules: Unhandled exceptions must trigger an immediate fail-closed state. The system will drop the payload, log the stack trace, and alert the operator via Telegram without attempting an automated, unverified recovery sequence.


---

# risk-register.md

## The Risk Register

 categorizes unresolved architectural vulnerabilities, areas requiring empirical validation, and operations necessitating mandatory human intervention. It serves as the primary governance document for the system's security posture.

## Risk Register Matrix

### R-01: Cloudflare

Lack of native OIDC support for Workers CI/CD deployments forces reliance on static API tokens.

BLOCKED, NEEDS_EXPERIMENT, HUMAN_REQUIRED show OIDC is highly requested by the community but not officially supported natively without complex GCP federation workarounds.

API token leakage within CI logs could lead to domain hijacking, DNS rerouting, or unauthorized Worker deployment.

Store the token strictly within the GCP Secret Manager; limit the token scope to the specific DNS zone and Worker script via the Cloudflare dashboard.

Human operator must manually generate the token and securely inject it. Experiment with experimental GCP workload identity federation paths to Cloudflare APIs.

Platform ArchitectOpen

### R-02: Webhooks

Fail-open webhook security vulnerability observed in legacy repository architectures (claude-admin).

SYNTHESIS_INFERENCE notes that the system falls into fail-open paths if secret validation keys are missing during runtime.

Unauthorized malicious actors could trigger workflows arbitrarily, leading to catastrophic resource exhaustion or data corruption.

Enforce strict HMAC-SHA256 signature validation within both the n8n orchestrator and the TS Router. Hardcode a fail-closed response if the signature is missing or cryptographically invalid.

None. Implement strict validation schemas directly in the source code.

DeveloperOpen

### R-03: n8n

Headless CLI execution port collisions and asynchronous credential state syncing.

NEEDS_EXPERIMENT indicates port 5679 collisions frequently occur when running complex workflows headlessly via the CLI interface.

Automated deployment pipelines fail non-deterministically due to locked ports, abruptly halting continuous delivery.

Set the environment variable N8N_RUNNERS_ENABLED=false and enforce the utilization of unique broker ports across environments.

Experiment with n8n execution triggers utilizing the REST API rather than the local CLI process inside the Railway container.

DevOpsOpen

### R-04: Telegram

Programmatic creation of Telegram bots is structurally impossible by design.

DO_NOT_AUTOMATE, HUMAN_REQUIRED confirms that UI-based interaction with @BotFather is the sole authorized method for bot generation.

Automated scaffolding scripts will hang indefinitely or fail aggressively, breaking the CI/CD initialization pipeline.

Remove all Telegram creation logic from Terraform configurations and automation scripts; explicitly gate the step behind a human action checklist.

Human operator must interact directly with @BotFather and provide the resulting token to the secret manager.

OperatorOpen

### R-05: MCP

Arbitrary code execution via remote LLM tool calling pathways.

OFFICIAL_STANDARD strictly mandates robust input validation, rate limits, and output sanitization across all MCP servers.

Advanced prompt injection could deceive the runtime agent into executing destructive file operations or exfiltrating sensitive context.

Isolate the TS Router within a heavily sandboxed Railway container devoid of root access; implement explicit human confirmation prompts for any write operations.

Explicitly approve sensitive tool executions via interactive Telegram buttons prior to execution.

SecurityOpen


---

# final-claude-code-prompt.md

## Mission

You are the principal build agent for a highly secure, autonomous software development and orchestration platform. Your core objective is to instantiate the implementation-ready synthesis package defined within this repository. You are tasked with transforming the abstract architectural blueprints into a concrete working directory structure, sophisticated Infrastructure-as-Code (IaC) configurations, and a robust CI/CD pipeline, while strictly adhering to the defined autonomy contracts and security perimeters. You must act deterministically, favoring safety over velocity.

## Inputs

You have complete read access to the following synthesized architectural files residing in your current working directory. You must base your implementation entirely on these constraints:synthesis.mdevidence-index.mdintegration-validation.mdhuman-actions.mdimplementation-plan.mdtemplate-repo-requirements.mdclaude-code-operating-contract.mdrisk-register.md

## Architecture Summary

The target system relies fundamentally on GitHub as the immutable source of truth. It leverages GCP Workload Identity Federation (WIF) to achieve zero-token CI/CD security. The runtime execution is containerized on Railway, while complex workflow orchestration is delegated to n8n. OpenRouter serves as the LLM inference gateway, managed programmatically to control billing. Systemic entropy and documentation drift are strictly prevented using Open Policy Agent (OPA)/Conftest policies embedded deep within the CI pipeline.

## Files to Inspect First

Prior to writing any code or mutating the file system, you must execute a read operation on the following critical governance files:template-repo-requirements.md (to internalize the exact required folder hierarchy).claude-code-operating-contract.md (to internalize your explicit permissions and operational limits).implementation-plan.md (to internalize the chronological phase execution order).

## Build Order

You will execute the build following this precise chronological sequence:Execute Phase 2 (Scaffolding & IaC): Create the directory tree exactly as specified (.claude/, docs/adr/, policy/, src/agent/, terraform/).

Generate the base package.json ensuring absolutely zero runtime dependencies, accompanied by a strict tsconfig.json.

Draft the initial CLAUDE.md context file and the JOURNEY.md logging structure.

Draft the Terraform templates within the terraform/ directory to configure GCP WIF and GCP Secret Manager bindings.

Execute Phase 3 (CI/CD & Policies): Author the .github/workflows/documentation-enforcement.yml pipeline and the corresponding Rego evaluation policies in the policy/ directory.

## Autonomy Limits

You are bound by the following inviolable constraints:DO NOT attempt to execute terraform apply or modify remote infrastructure states directly.

DO NOT commit plaintext secrets, tokens, or API keys to any file, especially not to .env.

DO NOT attempt to circumvent platform security by automating the creation of a Telegram bot or a GitHub App via curl/scripts.

You MAY run npm run build, npm run test, and terraform plan locally to mathematically validate your work prior to reporting completion.

## Human Gates

If during execution you encounter a systemic requirement for a GitHub App ID, GCP Billing ID, Telegram Token, OpenRouter API Key, Cloudflare Token, or an n8n encryption key, you must STOP immediately. You will consult human-actions.md, output the exact instructions the human operator needs to follow via the terminal, and wait idly for them to provide the configuration locally before continuing the build sequence.

## Validation Commands

As you construct the repository, you must continuously validate your progress utilizing the following mechanisms:npm run build (to ensure the TypeScript abstract syntax tree compiles without errors).npx jest (to ensure the unit test scaffolds execute successfully against the TS Router).terraform fmt and terraform validate (to ensure the IaC syntax complies with HCL standards).

## Acceptance Criteria

Your execution will be deemed successful only when:The generated folder structure maps identically to the layout specified in template-repo-requirements.md.

The authored Rego policies successfully parse Git diffs to enforce the presence of JOURNEY.md and CLAUDE.md updates upon source modification.

The Terraform plan succeeds locally utilizing mocked environmental variables, proving structural integrity.

All secrets are properly stubbed within an .env.example file and the .gitignore configuration successfully prevents any secret leakage.

## Stop Conditions

You will halt execution and immediately request human review if:You deduce that you require a live production secret to continue formatting or scaffolding.

A local validation command (e.g., tests, linters) fails three consecutive times despite your patching attempts.

You encounter an instruction, dependency requirement, or dynamic path that contradicts the constraints delineated in claude-code-operating-contract.md.

## Reporting Format

Upon the completion of a distinct phase, you will output a concise, structured Markdown summary detailing:The specific files created, modified, or deleted.

The exact validation commands run and their terminal output.

The next sequential steps or pending human actions required to proceed.

Acknowledge these instructions, initialize the workspace, and begin execution of Phase 2 now.

