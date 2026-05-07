# Internet Standards Research

## Document Metadata

- **Source file:** `Pasted text.txt`
- **Generated format:** GitHub-flavored Markdown
- **Purpose:** Structured research report for human review and agent-assisted repository workflows.

## 1. Executive Summary

The architectural orchestration of a fully autonomous software agent system via a GitHub Template Repository requires a rigorous delineation between operations that can be programmatically executed and those demanding manual human governance. The fundamental premise of this investigation is that "full autonomy" from an absolute zero-state is an architectural impossibility. Platform security perimeters, OAuth consent requirements, billing authorizations, and the necessity of human-in-the-loop (HITL) cryptographic bootstrapping prevent autonomous agents from independently establishing their own trust anchors.The analysis indicates that while steady-state operations—such as continuous integration, documentation generation, and infrastructure mutation—can be fully automated post-bootstrap, the initial establishment of identity and authorization requires a structured human handoff.

The recommended repository strategy involves structuring the GitHub Template as a heavily sandboxed, policy-as-code environment. This environment leverages GitHub Actions with OpenID Connect (OIDC) for identity federation, strictly avoiding the generation and storage of long-lived static credentials. The primary security model dictates that autonomous agents, such as Claude Code, operate under the principle of least privilege.

These agents must be confined by deterministic PreToolUse hooks and explicit Model Context Protocol (MCP) tool allowlists, ensuring that the blast radius of any rogue agent action is strictly limited.The most critical "do not automate blindly" warnings center on identity provisioning and infrastructure persistence. The automated generation of third-party API tokens, the unsupervised modification of cloud Identity and Access Management (IAM) policies, and the unreviewed execution of arbitrary shell commands by Large Language Models (LLMs) present unacceptable operational risks. Human bootstrap remains unavoidable for GitHub App installation, Google Cloud Workload Identity Federation (WIF) pool creation, and initial secret injection into Google Secret Manager.

Consequently, the template repository must act as a deterministic scaffolding mechanism, guiding human administrators through the prerequisite credential generation before relinquishing operational control to automated CI/CD pipelines and agentic sub-routines.

## 2. Component Table

| Component | Officially Supported Capabilities | Can be fully automated? | Automatable only after bootstrap? | Requires existing credential? | Requires human action? | Requires experiment? | Main risks | Official source | Confidence level |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GitHub Template Repository | Scaffolding directories, CI workflows, Issue/PR templates | Yes | No | No | No | No | Drift from upstream templates | [1] | High |
| GitHub Apps | Granular permissions, webhook delivery, bot identity | No | Yes | Yes | Yes | No | Over-permissioning, token leakage | [2] | High |
| GitHub App Manifest | Pre-filling app creation parameters via URL or HTML form | No | Yes | No | Yes | No | Manual app ownership claim required | [3] | High |
| GitHub Actions OIDC | Keyless authentication to external cloud providers (GCP/AWS) | Yes | Yes | Yes | Yes | No | Misconfigured subject claims allowing broad access | [4] | High |
| Google Secret Manager | Secure storage, versioning, and access control for secrets | No | Yes | Yes | Yes | No | Overly permissive IAM bindings | [5] | High |
| Google Workload Identity Federation | Keyless credential federation mapping external identities | No | Yes | Yes | Yes | No | Sub/Audience claim collisions, lateral movement | [6] | High |
| Terraform | Declarative infrastructure provisioning and state management | Yes | Yes | Yes | No | No | State file exposure, destructive execution | [7] | High |
| OpenTofu | Open-source alternative to Terraform for IaC provisioning | Yes | Yes | Yes | No | No | Provider compatibility parity | [8] | High |
| Railway API | Project mutation, environment variable injection, triggers | No | Yes | Yes | No | Yes | Token over-scoping | [9] | High |
| Railway CLI | Local workflow execution, environment linking | No | Yes | Yes | No | No | Storing account tokens in CI | [10] | High |
| Railway project tokens | Scoped authentication for specific project environments | No | Yes | Yes | Yes | No | Token leakage granting environment access | [9] | High |
| Cloudflare API tokens | Granular, resource-scoped access to DNS, Workers, Pages | No | Yes | Yes | Yes | No | Misconfigured zone scope | [11] | High |
| n8n self-hosting | Workflow execution, internal SQLite/Postgres management | Yes | Yes | Yes | No | No | Database encryption key loss | [12] | High |
| n8n public REST API | Programmatic execution, user management, credential creation | No | Yes | Yes | No | No | Plaintext credential injection | [13] | High |
| n8n CLI | Remote workflow/credential management via API key | No | Yes | Yes | No | No | Requires beta API compatibility testing | [14] | Medium |
| Telegram Bot API | Webhook configuration, message routing, command scoping | No | Yes | Yes | Yes | No | Token leakage, unauthorized bot control | [15] | High |
| OpenRouter | LLM provider routing, standard OpenAI-compatible API schemas | No | Yes | Yes | Yes | No | Exceeding billing limits, key leakage | [16] | High |
| Linear API | GraphQL mutations for issue tracking, webhook subscriptions | No | Yes | Yes | No | No | Bypassing human triage processes | [17] | High |
| Linear OAuth / API keys | Authorization for third-party integrations and agent actions | No | Yes | Yes | Yes | No | Over-permissioned OAuth scopes | [18] | High |
| MCP servers | Local/remote context provision, tool execution boundaries | Yes | Yes | Yes | Yes | No | Arbitrary code execution, unvetted tools | [19] | High |
| MCP security controls | Sandboxing, strict human-in-the-loop (HITL) tool consent | Yes | Yes | No | Yes | No | Prompt injection via tool return values | [20] | High |
| Claude Code on the web | Cloud environment execution, repository connection | No | Yes | Yes | Yes | No | Unrestricted network egress | [21] | High |
| Claude Code hooks | Lifecycle event triggers (PreToolUse, SessionStart) | Yes | No | No | No | No | Non-deterministic timeout failures | [22] | High |
| Claude Code skills | Injectable tools and prompt structures defined via Markdown | Yes | No | No | No | No | Context window exhaustion | [23] | High |
| Claude Code setup scripts | Cloud environment initialization, dependency installation | No | Yes | No | Yes | No | Dependency supply chain attacks | [24] | High |
| ADR | Architectural Decision Records detailing context/consequences | Yes | No | No | No | No | Stale documentation | [25] | High |
| Diátaxis | Documentation framework (Tutorials, How-To, Reference) | Yes | No | No | No | No | Misclassification of content types | [26] | High |
| CHANGELOG | Human-readable chronological list of notable changes | Yes | No | No | No | No | Obfuscation of breaking changes | [27] | High |
| SemVer | Semantic Versioning (Major.Minor.Patch) | Yes | No | No | No | No | Accidental major bumps | [28] | High |
| documentation drift prevention |  |  |  |  |  |  |  |  |  |
| CI enforcement | via markdownlint, link checking, and Vale | Yes | No | No | No | No | False positives blocking CI pipelines[1]HighCI enforcementGitHub Actions workflows gating pull request mergesYesNoNoNoNoPrivileged token exposure in runners | [29] | High |

## 3. What Can Be Fully Automated

The parameters for "full automation" within this architectural context are strictly defined as operations that can execute programmatically from within a generated repository without hidden manual assumptions, explicit account creation steps, or external OAuth consents. The execution environment relies solely on the default capabilities granted to a standard GitHub Actions runner or a local automated script executing within an initialized directory.Repository scaffolding and file structure generation represent the most robustly automatable domain. The instantiation of directory structures—such as docs/, infra/, .github/, and .claude/—alongside boilerplate files is fully supported via the GitHub Template Repository feature [1].

This process requires no external permissions, executes natively during repository creation, and provides the foundational architecture without human oversight. Following repository creation, continuous integration linting and validation can be fully automated. The execution of formatting checks, markdown linting using tools like markdownlint, link validation, and static analysis can be seamlessly orchestrated via GitHub Actions [30].

These processes rely exclusively on the default GITHUB_TOKEN provided to the runner environment, requiring only contents: read permissions to parse the repository state, thereby eliminating the need for external identity injection.Semantic versioning and changelog generation can similarly operate autonomously. Tools such as semantic-release or changesets algorithmically parse commit histories to determine appropriate version bumps and update CHANGELOG.md files [28]. This workflow is fully automatable via GitHub Actions, provided the workflow configuration requests contents: write permissions for the GITHUB_TOKEN to push the resulting tags and documentation commits back to the repository branch [31].

Failure modes in this domain typically revolve around improperly formatted commit messages that fail to trigger the semantic analysis engine, rather than credential exhaustion.Client-side configuration for autonomous agents, specifically the generation of local .claude/settings.json, .claude/hooks/, and .claude/skills/ files, is fully automatable during the scaffolding phase. Because these files govern the behavior of the Claude Code CLI and local agentic loops, they dictate execution parameters rather than authenticate external requests, meaning they do not require external API authentication to establish [22]. However, the underlying failure mode arises during execution; if a hook is generated but not granted executable permissions (chmod +x), the Claude Code agent will fail to invoke the automation script [22].Finally, Infrastructure-as-Code (IaC) syntax validation and planning can be automated without external credentials, provided the state is mocked.

OpenTofu and Terraform plan commands can be integrated into CI pipelines to perform static analysis and dry-run state comparisons. However, achieving a true plan against live infrastructure mandates post-bootstrap credential federation [7]. Without OIDC configuration, IaC automation is strictly limited to offline validation.

## 4. What Can Be Automated Only After Bootstrap

A vast majority of the system's operational capabilities require a fundamental cryptographic or identity-based trust anchor. These anchors must be manually established by a human administrator before programmatic automation can safely assume control of the deployment lifecycle.The GitHub App Manifest flow is designed to streamline integration, allowing a repository to pre-fill configuration parameters such as webhook endpoints and permission scopes via a structured URL or HTML form POST [32]. Despite this automation of configuration input, the actual registration, ownership claim, and installation onto the target repository strictly require human OAuth consent and organization administrator privileges [3].

Once the human administrator finalizes the installation, token generation and subsequent API interactions become fully automatable, but the initialization boundary cannot be bypassed.Similarly, cloud identity federation requires foundational human intervention. The creation of a Google Cloud Project, enablement of billing mechanisms, and the initial configuration of the Workload Identity Pool and Provider cannot be automated from a blank repository without an existing, highly privileged organization administrator credential [6]. Once the Workload Identity Federation (WIF) pool is explicitly bound to the repository's OIDC issuer (token.actions.githubusercontent.com), all subsequent infrastructure provisioning and application deployments can be entirely automated [33].

This human-gated bootstrap establishes the boundary between static credential vulnerability and dynamic, short-lived token security.Secret management necessitates a similar handoff. The initial entry of third-party API keys—such as those for OpenRouter or Telegram—into Google Secret Manager requires human action to prevent plaintext exposure in version control. Once these values are securely stored, the binding of IAM roles (roles/secretmanager.secretAccessor) to the WIF-impersonated service account can be automated via IaC, allowing CI pipelines to dynamically retrieve secrets at runtime [34].Third-party service provisioning universally relies on human-initiated account creation.

For Railway, the creation of an initial project and the generation of an Account or Workspace Token require human interaction with the provider's dashboard [9]. After this token is injected into GitHub Actions or local environment variables (RAILWAY_TOKEN), the deployment of backend services and database environments becomes fully automatable via the Railway API or CLI [10]. Cloudflare exhibits identical constraints; a human Super Administrator must authenticate to generate a scoped Account API token or User API token [11].

Following this bootstrap, DNS record manipulation, Worker deployments, and caching rules can be fully automated via the Terraform Cloudflare provider [7].Application-specific integrations also demand initial human setup. Deploying n8n can be automated via infrastructure pipelines, but the initial generation of the database encryption key (stored in /home/node/.n8n/config) and the creation of the primary administrator account require initial runtime configuration [12]. Following this, generating an API key enables the n8n CLI and REST API to automate the injection of workflows and external credentials [14].

The Telegram Bot API mandates that a human user interacts with the @BotFather interface via the Telegram application to register a new bot and extract the HTTP API token [35]. After the token is provisioned, webhook registration and message routing can be automated programmatically [15].Model routing and task delegation workflows require identical manual anchors. A human must authenticate to OpenRouter, configure billing credits, and generate the primary API key [36].

Once provisioned, model routing, fallback configuration, and inference requests are fully automated [37]. Linear integrations demand that an administrator configures an OAuth 2.0 application or generates a personal API key via the Linear settings dashboard [18]. Subsequent issue tracking, agent session state updates, and webhook payload handling become automatable [38].Finally, the execution environments for autonomous agents require explicit human trust establishment.

Model Context Protocol (MCP) servers must be explicitly trusted by a human user; the MCP specification mandates that applications present clear consent dialogs before connecting any new MCP server to prevent arbitrary code execution [20]. Once the server is registered in .vscode/mcp.json or claude_desktop_config.json, the execution of allowed tools can be automated by the agent [39]. Utilizing Claude Code on the web (claude.ai/code) similarly requires a human to explicitly install the Claude GitHub App and grant it access to specific repositories [21].

Only after this authorization can the cloud environment execute the repository's setup scripts and initialization hooks.

## 5. What Requires Human Action

To ensure cryptographic integrity, platform compliance, and systemic security, specific actions must remain strictly under human or administrator control. Attempting to bypass these requirements via programmatic automation introduces severe vulnerabilities, violates terms of service, and undermines the foundational trust model of the architecture.Account creation and billing enablement across cloud platforms (Google Cloud, Railway, Cloudflare, OpenRouter) require identity verification, CAPTCHA resolution, and valid payment methods. These processes are inherently designed to resist automated Sybil attacks.

Attempting to automate them via headless browsers is fragile, violates platform policies, and introduces unnecessary maintenance overhead. OAuth consent and application installation present similar boundaries. The authorization of GitHub Apps, Linear integrations, and third-party tools requires explicit human consent to ensure users comprehensively understand the permission scopes being granted to external entities [3].The generation of high-privilege tokens represents a critical security boundary.

The creation of root-level API tokens, such as Cloudflare Super Administrator tokens or Railway Account tokens, must be performed manually. Automating this process risks exposing highly privileged credentials in volatile memory, CI build logs, or unencrypted state files [40]. Similarly, Google Cloud IAM administrative grants, specifically assigning the roles/iam.workloadIdentityPoolAdmin or roles/resourcemanager.projectIamAdmin roles, must be executed by a human.

Broad IAM automation risks catastrophic privilege escalation if the automation principal is compromised, allowing an attacker to rewrite the organization's entire authorization framework [5].Interaction with cryptographic provisioning systems often requires manual operation. Communication with Telegram's @BotFather acts as a Sybil resistance mechanism and cannot be bypassed via standard REST APIs [35]. Furthermore, the entry of production secret values must remain a human responsibility.

The actual string values of third-party API keys must be manually inputted into Google Secret Manager or GitHub Actions Secrets. They must never be hardcoded into configuration files, committed to version control, or generated via automated scripts that lack secure memory enclaves.The Model Context Protocol (MCP) specification strictly enforces human oversight for dangerous tools. Tools representing arbitrary code execution, file system manipulation, or broad data access must require human approval before execution [20].

An autonomous agent must not be granted the autonomy to blindly execute scripts or modify critical infrastructure without a Human-In-The-Loop (HITL) confirmation. This principle extends to Infrastructure-as-Code deployments. Terraform or OpenTofu apply commands that result in the destruction of stateful resources, such as databases or storage buckets, must be gated by human review in the pull request process to prevent catastrophic data loss caused by algorithmic hallucination or logic errors [41].

Finally, high-level governance decisions, such as repository transfer, ownership reassignment, or visibility toggling, must remain manual administrative actions to preserve organizational security perimeters.

## 6. What Is Dangerous To Automate

While certain operations are technically possible to automate via APIs or CLIs, doing so introduces critical security vulnerabilities, violates the principle of least privilege, and expands the systemic blast radius beyond acceptable risk thresholds.The automation of broad IAM grants presents an existential threat to cloud environments. Programmatically assigning Owner or Editor roles across entire Google Cloud projects ensures that any compromise of the automation pipeline results in total environment takeover. The safe alternative is to implement granular least privilege via strict Workload Identity Federation attribute mapping, ensuring that temporary credentials are only valid for specific repositories, branches, and required actions [33].

Similarly, the generation and storage of long-lived static credentials, such as exporting GCP Service Account JSON keys into GitHub Secrets, is highly dangerous. These keys can be leaked in logs, exfiltrated via compromised dependencies, or left unrotated, leading to persistent unauthorized access. The recommended guardrail is the complete elimination of static keys in favor of Workload Identity Federation, generating short-lived, OIDC-federated access tokens at runtime [42].In the context of GitHub automation, utilizing legacy Personal Access Tokens (PATs) with unrestricted scopes is inherently risky.

A compromised PAT grants an attacker access to the user's entire GitHub footprint, including personal and organizational repositories. Automation must instead rely on short-lived, fine-grained GitHub App installation access tokens scoped strictly to the required repository and specific API endpoints [43].Automating the injection of secrets directly into repository files or environment logs is a prevalent but dangerous practice. Generating .env files containing live secrets during CI processes often results in credentials being accidentally committed to Git history or exposed in GitHub Actions build logs.

The safe alternative is to inject secrets dynamically at runtime, fetching them from Secret Manager directly into the execution environment's memory space, bypassing the filesystem entirely [34].The architecture of autonomous agents introduces new vectors for exploitation. Automatic installation of untrusted MCP servers poses a severe risk. Allowing an agent to download and connect to arbitrary MCP servers via DNS rebinding or malicious manifests opens the environment to arbitrary code execution and rapid data exfiltration [19].

To mitigate this, administrators must maintain a strict allowlist of approved MCP servers in configuration files and enforce explicit human consent for any new connections [44]. Similarly, the automatic execution of Claude Code hooks that leverage shell access (type: "command") without strict validation is highly dangerous. An attacker could leverage prompt injection to manipulate the LLM into generating destructive shell commands [22].

Safe deployment requires sandboxing hook execution, utilizing strict input validation, and preferring predefined, immutable scripts over dynamic command generation.Application-specific risks also demand strict guardrails. Automating the backup of n8n credentials without securing the underlying AES-256 encryption key renders the backups useless if the key is lost, or risks credential exposure if exported via the --decrypted flag into insecure storage [45]. The safe alternative involves securely backing up the /home/node/.n8n/config key out-of-band and exporting only encrypted credentials.

For Linear integrations, automating write or administrative actions without scoping risks the mass deletion or corruption of issue tracking data. Automation must adhere to the Agent Interaction Guidelines (AIG), establishing clear delegation flows, utilizing the AgentSession state to limit the blast radius, and restricting agent mutations to explicitly assigned issues [46].Finally, documentation generation that overwrites human-authored decisions undermines the governance structure of the repository. Allowing an LLM to arbitrarily rewrite Architectural Decision Records (ADRs) destroys the historical context of system design.

CI workflows must enforce that ADRs are append-only and that any modifications to security-sensitive files require explicit human code review before merging.

## 7. Recommendations for Claude Code on the Web

Claude Code on the web (claude.ai/code) provides a robust, sandboxed cloud environment designed for executing agentic tasks against GitHub repositories without the overhead of local environment configuration [21].The official capabilities of the cloud environment are tailored for specific developer workflows. It is officially supported for reviewing pull requests, exploring complex codebases, and automating routine feature development tasks [24]. The GitHub repository connection model relies on the Claude GitHub App; authentication occurs when the user explicitly installs the application and scopes its access to specific target repositories [24].

Alternatively, users operating locally can utilize the /web-setup command to seamlessly sync their local gh CLI OAuth tokens to the cloud instance, mirroring their local permissions [21].The runtime assumptions of Claude Code on the web dictate that the environment operates on an Anthropic-managed Virtual Machine. Upon session initiation, the platform clones the target repository, applies pre-configured network access controls to restrict or allow internet egress, and executes any defined setup scripts to prepare the workspace [21]. The human review boundaries remain firmly established: Claude pushes its generated code changes to dedicated branches prefixed with claude/.

The human operator acts as the final reviewer of the resulting pull request, maintaining ultimate architectural authority and preventing unvetted code from merging into production [21].Within a template repository, Claude Code on the web can safely execute boilerplate scaffolding, documentation generation, and initial test coverage analysis. However, clear delegation boundaries must be maintained. Claude Code on the web should not be utilized to execute destructive infrastructure deployments (e.g., terraform apply) or manage production secrets.

These highly privileged tasks must be delegated to GitHub Actions, where OIDC/WIF can securely and deterministically map identities to cloud providers, ensuring that infrastructure mutation occurs within a rigorously audited pipeline [4].A critical architectural distinction exists between setup scripts and SessionStart hooks. Setup scripts are attached to the cloud environment UI and run exactly once during VM initialization to install system-level dependencies (e.g., npm install) when no cached environment is available [24]. In contrast, SessionStart hooks are defined within the repository's .claude/settings.json file and execute at the beginning of every session, both locally and in the cloud [24].

Therefore, the template repository strategy should rely heavily on SessionStart hooks for cross-platform compatibility, ensuring that environment variables and local constraints are properly initialized regardless of where the agent executes.

## 8. Recommendations for GitHub Template Repository

A professional template repository designed to instantiate autonomous agent systems must establish immediate, deterministic guardrails, prioritizing policy-as-code over open-ended LLM execution. The directory structure must clearly delineate documentation, automation, infrastructure, and agent configuration.The root README.md serves as the primary entry point, functioning not merely as an overview but as a strict operational manual outlining the human bootstrap requirements that must be satisfied before automation pipelines can successfully execute.The docs/ directory must be structured according to the Diátaxis framework, separating content by its cognitive purpose to ensure clarity for both human operators and LLM context windows [26]. This includes docs/tutorials/ for learning-oriented, step-by-step guides; docs/how-to/ for goal-oriented procedures addressing specific operational tasks; docs/reference/ for information-oriented technical specifications such as API schemas; and docs/explanation/ for understanding-oriented architectural theory [26].

Critically, the docs/adr/ subdirectory houses Architectural Decision Records (ADRs). These must be formatted as immutable, append-only logs tracking design choices, context, considered alternatives, and consequences, providing agents with historical constraints [25].Automation and governance are driven by the .github/ directory. The .github/workflows/ path contains CI/CD pipelines responsible for linting, testing, and Terraform execution via OIDC identity federation.

The .github/ISSUE_TEMPLATE/ and PULL_REQUEST_TEMPLATE.md files enforce structured, predictable input for both human contributors and agentic submissions, ensuring that required metadata is always present.Agent behavior is governed by the .claude/ directory, which acts as the core configuration nexus for Claude Code [47]. The .claude/settings.json file defines project-level configurations, model preferences, and hook registrations, ensuring consistent behavior across the engineering team [48]. The .claude/skills/ directory contains Markdown-based skill definitions (SKILL.md) utilizing explicit YAML frontmatter to control tool access, invocation logic, and context provisioning [23].

The .claude/hooks/ directory houses executable bash scripts triggered by lifecycle events, providing deterministic intervention points to block or modify agent actions [22].Operational scripts are segregated into scripts/bootstrap/ and scripts/verify/. Bootstrap scripts must be highly idempotent bash files that guide the human administrator through the manual setup of WIF, GitHub Apps, and Secret Manager, outputting clear instructions where human intervention is mandatory. Verification scripts validate that these prerequisites are successfully met before permitting CI execution.Infrastructure definitions reside in infra/terraform/ or infra/opentofu/.

These declarative state configurations for GCP, Railway, and Cloudflare are designed to be safe by default through the use of plan outputs that require manual human approval for the subsequent apply phase.Finally, repository hygiene is enforced via CHANGELOG.md and VERSION files maintained using the "Keep a Changelog" standard [27], alongside SECURITY.md and CONTRIBUTING.md files defining responsible disclosure and agent-interaction guidelines. The CODEOWNERS file is mandatory, enforcing strict human review on highly sensitive directories such as infra/ and .github/ to prevent autonomous agents from bypassing infrastructure constraints.

## 9. Recommendations for WIF and Secrets

The absolute elimination of static service account keys is the paramount security objective for infrastructure automation within an autonomous agent architecture. Traditional reliance on long-lived JSON keys introduces unacceptable risks of credential leakage, privilege escalation, and unauditable access [5].The recommended identity model utilizes GitHub Actions OIDC tokens federated with Google Workload Identity Federation (WIF) [4]. This architecture establishes a transient, cryptographically verifiable trust relationship between the GitHub repository and the cloud provider, issuing short-lived access tokens strictly bounded by the execution lifecycle of the CI/CD pipeline [42].When implementing WIF, architects must choose between Direct WIF and Service Account Impersonation.

While Direct WIF allows the GitHub Actions identity to be evaluated directly for resource access, Service Account Impersonation is overwhelmingly preferred. Impersonation establishes a robust trust delegation relationship, allowing granular IAM policies to be attached to a specific, dedicated GCP Service Account rather than attempting to manage complex, overlapping attribute conditions directly on individual cloud resources [49].To prevent lateral movement and unauthorized access, strict claim restrictions must be enforced within the WIF Provider configuration. The provider must map incoming OIDC claims to Google attributes and enforce attribute conditions that strictly match the assertion.repository_owner, assertion.repository, and assertion.ref (branch) [33].

This ensures that even if another repository within the same organization triggers an action, it cannot assume the identity assigned to the production infrastructure.Third-party credentials required by the autonomous agent—such as OpenRouter API keys, Railway tokens, or Telegram Bot tokens—must be stored exclusively in Google Secret Manager. These secrets cannot be generated automatically, as their values originate from external human-bound provisioning steps. The impersonated GCP Service Account is granted the roles/secretmanager.secretAccessor IAM role strictly scoped to the specific secrets required for the deployment, adhering to the principle of least privilege [34].This architecture significantly simplifies Terraform and OpenTofu execution.

The Google Terraform provider natively supports WIF; by configuring the GOOGLE_APPLICATION_CREDENTIALS environment variable to point to a dynamically generated credential configuration file within the GitHub Actions runner, Terraform can securely authenticate and provision infrastructure without ever requiring a static key [50]. CI pipelines must validate the integrity of this setup by running unprivileged identity verification steps before executing infrastructure mutations.

## 10. Recommendations for Railway

Railway provides a highly dynamic platform-as-a-service environment ideal for deploying backend services, databases, and webhook receivers required by the autonomous agent system.The Railway CLI provides extensive capabilities for local and CI-driven automation, officially supporting environment variable linking, local execution proxying, and deployment triggering [10]. For automation pipelines, the CLI relies on the RAILWAY_TOKEN environment variable to authenticate requests without requiring interactive login flows.A critical security distinction exists between Railway Account Tokens and Project Tokens. Account Tokens (or Workspace Tokens) grant broad access across all resources and projects authorized to the user, representing a significant security risk if exposed in CI environments [9].

Conversely, Project Tokens are strictly scoped to a specific environment within a single project, rendering them incapable of accessing cross-workspace data or account-level settings. Project Tokens are the mandatory authentication mechanism for CI/CD pipelines and agentic automation [9].The automation boundaries for Railway are clearly defined. A human administrator must manually create the initial Railway account, establish the workspace, and generate the initial Project Token via the web dashboard [9].

Once this token is securely injected into Google Secret Manager, the remainder of the deployment lifecycle becomes fully automatable. Terraform, utilizing the community-supported Railway provider [51], or GitHub Actions utilizing the Railway CLI, can autonomously orchestrate database provisioning, service deployment, and environment variable configuration without further human intervention.

## 11. Recommendations for Cloudflare

Cloudflare serves as the edge network, DNS provider, and potential serverless execution environment for the autonomous system. Robust token management is required to prevent zone hijacking and unauthorized traffic routing.Cloudflare API tokens are bifurcated into User API tokens and Account API tokens. Account API tokens are tied directly to the Cloudflare account entity and require highly privileged Super Administrator permissions to generate [11].

User API tokens are tied to an individual user identity and inherit their specific permission scope. For infrastructure automation, Account API tokens are preferred as they decouple automation from individual human lifecycles, provided they are rigorously scoped.The principle of least privilege mandates that tokens must be explicitly scoped to specific permissions and restricted to required Zones. Cloudflare provides predefined templates (e.g., "Edit Zone DNS", "Edit Cloudflare Workers") which grant specific capabilities such as DNS Write or Workers Scripts Write [52].

Tokens must never be granted broad (All read permissions) or global account access unless strictly necessary for top-level auditing [52].Human bootstrap is required; a human administrator must manually generate the initial API token via the Cloudflare Dashboard, carefully defining the access policy and zone restrictions [53]. After this token is securely vaulted, the Cloudflare Terraform provider can autonomously orchestrate the creation of DNS records, Page rules, WAF configurations, and serverless deployments without requiring interactive human oversight during the execution phase [7].

## 12. Recommendations for n8n

n8n serves as the primary workflow automation and orchestration layer, connecting the autonomous agent's decision logic with external APIs and data sources.Self-hosting n8n via Docker or Kubernetes is strongly recommended for autonomous agent systems, as it provides absolute control over data residency, execution environments, and internal network routing [54].Credential handling within n8n presents a significant operational risk that must be carefully managed. n8n encrypts all credential data at rest within its database (SQLite or PostgreSQL) using an AES-256 encryption key. This key is generated automatically during the first launch and stored in the filesystem at /home/node/.n8n/config [12]. If this configuration file is lost, or if a database backup is restored onto a new instance without the original key, all credentials fail to decrypt and become permanently inaccessible [45].

Therefore, the automated infrastructure pipeline must prioritize the secure, out-of-band backup of this encryption key, explicitly defining it via the N8N_ENCRYPTION_KEY environment variable to ensure determinism across deployments [12].Interaction with the n8n instance can be achieved via the REST API or CLI. The n8n CLI (currently in beta) communicates via the public REST API using a generated API key, making it highly suitable for CI/CD pipelines, programmatic workflow injection, and AI agent integration [14]. The built-in Server CLI, conversely, requires direct database access and bypasses standard access controls, making it inappropriate for remote automation [54].The boundary for automation requires that infrastructure deployment is handled via IaC, but the human administrator must manually backup the encryption key and generate the initial REST API key via the n8n dashboard [55].

Subsequent operations, including the importing of workflow JSON definitions and the programmatic creation of credentials, can be entirely automated via the REST API payload structures [56].

## 13. Recommendations for Telegram

Telegram provides an immediate, ubiquitous user interface for human-agent interaction, alerting, and manual override capabilities.The bot creation flow represents a hard automation boundary. The creation of a Telegram bot cannot be automated programmatically via standard APIs; a human operator must interact directly with the @BotFather interface within the Telegram application to register the bot, define its username, and obtain the HTTP API token [35].This bot token must be treated as a highly sensitive cryptographic credential. Leakage of the token allows malicious actors to intercept incoming messages, impersonate the agent, and manipulate downstream systems relying on Telegram for command execution [35].

The token must be immediately stored in Secret Manager and injected into the execution environment at runtime.For production systems, webhook setup is mandatory. Polling the Telegram API is inefficient and introduces latency. The automation pipeline should programmatically register a webhook URL—pointing to the deployed n8n instance or a dedicated backend service—using the secured API token, ensuring that the agent receives updates instantaneously [57].

## 14. Recommendations for OpenRouter

OpenRouter functions as the LLM routing and aggregation layer, providing a unified API schema across diverse model providers and enabling dynamic fallback capabilities.OpenRouter utilizes standard API keys for authentication. While a PKCE flow exists to generate user-controlled keys for frontend applications [58], standard backend autonomous agents require a manually generated service key [36]. The API is fully OpenAI-compatible, allowing standard SDKs to interact with it seamlessly.

Agents can be configured to route requests to specific models (e.g., anthropic/claude-3-opus) or allow OpenRouter to dynamically select the most cost-effective GPU available [37].Automation boundaries dictate that billing configuration, credit top-ups, and the initial key generation are strictly human-bound operations [36]. The generated API key must be securely stored in Secret Manager and exposed to the agent's execution environment via the OPENROUTER_API_KEY environment variable. To prevent financial exhaustion caused by runaway agent loops, strict billing limits must be configured manually within the OpenRouter dashboard.

## 15. Recommendations for Linear

Linear provides the structured issue tracking and task delegation framework required to manage the autonomous agent's backlog and operational status.Linear exposes a comprehensive GraphQL API for programmatic mutation and querying [17]. Authentication can be established via OAuth 2.0 for public integrations, or via Personal API keys for internal, repository-specific automation [18].When integrating agents into Linear, adherence to the Agent Interaction Guidelines (AIG) is paramount. The AIG explicitly dictates that agents must provide instant feedback, maintain transparency regarding their internal state (utilizing defined AgentSession states such as pending, active, error, or awaitingInput), and strictly respect delegation boundaries [59], [38].

The human always retains final accountability for the issue [59].Granting broad write or administrative permissions to an agent without strict scoping introduces the risk of mass deletion or corruption of issue tracking data. Automation should rely heavily on webhooks for event-driven updates and restrict the agent's mutation capabilities to specific, assigned issues, utilizing the Linear API to log reasoning steps and tool usage transparently [46].

## 16. Recommendations for MCP

The Model Context Protocol (MCP) standardizes how autonomous applications interact with external tools, data sources, and contextual environments, operating via JSON-RPC 2.0 over standard IO or HTTP transports [60].The MCP trust model enables powerful capabilities, including arbitrary code execution and broad data access. Consequently, the specification mandates strict security boundaries. Users must explicitly consent to data access, and a Human-In-The-Loop (HITL) mechanism should exist for tool invocations to prevent unauthorized operations [20].

Local MCP servers are executing binaries and must be aggressively sandboxed; they should run in isolated environments (e.g., containers or chroot jails) with heavily restricted file system and network access [61].Prompt injection represents a critical threat vector. Attackers can embed malicious instructions within tool return values, attempting to manipulate the LLM's subsequent actions [20]. Clients must validate and sanitize all tool results before passing them back into the LLM's context window [20].

Furthermore, server developers must avoid marking sensitive parameters (e.g., API keys) with the x-mcp-header extension, as this exposes them to network intermediaries [20].CI validation is essential for maintaining the security posture of the template repository. The repository must maintain a strict allowlist of approved MCP servers within its .claude/settings.json or .vscode/mcp.json configuration files [62]. CI pipelines must parse these files to validate that no unvetted servers have been introduced by human or agentic contributors, ensuring that the execution environment remains free from supply chain compromise [44].

## 17. Recommendations for Skills and Hooks

Claude Code's operational extensibility is governed through the implementation of skills and hooks, providing mechanisms to structure prompts and intervene in the execution lifecycle [22].The hook lifecycle allows scripts to execute at deterministic points, such as SessionStart, UserPromptSubmit, and critically, PreToolUse [63]. The PreToolUse hook is the primary security enforcement mechanism. A hook script returning an exit code of 2 will definitively block a tool call, overriding any LLM decisions and ensuring strict compliance with operational boundaries [22].

This mechanism must be utilized to protect sensitive files (e.g., .env, .git/, package-lock.json) from accidental or malicious modification by the agent [22].Skills provide a mechanism to inject specialized tools and prompt structures. They are defined within a SKILL.md file, which contains YAML frontmatter controlling execution parameters (e.g., allowed-tools, model overrides) and Markdown instructions detailing the operational logic [23]. To ensure consistent tooling across the engineering team, skills should be placed in the repository's .claude/skills/ directory [64].The execution of shell commands via hooks (type: "command") presents a significant risk if inputs are not sanitized, as the script receives the event's JSON input on standard input [63].

Any modification to hooks or skills fundamentally alters the agent's execution parameters and security boundaries. Therefore, the repository's CODEOWNERS policy must mandate rigorous, human-led code review for any pull request attempting to modify the .claude/hooks/ or .claude/skills/ directories.

## 18. Documentation and Enforcement Policy

Within an autonomous agent architecture, documentation is not merely supplementary text; it is a critical artifact of the system's operational state and must be governed with the same rigor as executable code to prevent hallucinations and systemic drift.The repository must adopt the Diátaxis framework, strictly categorizing documentation into four distinct quadrants: Tutorials (learning-oriented), How-To Guides (goal-oriented), Reference (information-oriented), and Explanation (understanding-oriented) [26]. This separation ensures that both human operators and LLM context retrieval systems can efficiently locate contextually appropriate information [26].Architectural Decision Records (ADRs) are mandatory for tracking design choices. ADRs must be formatted as immutable, append-only logs detailing the problem context, considered alternatives, and the consequences of the final decision [25].

If a decision changes, a new ADR must be written to supersede the original, preserving the historical rationale [25].The repository must maintain a CHANGELOG.md adhering to the "Keep a Changelog" format, categorizing changes into Added, Changed, Deprecated, Removed, Fixed, and Security [27]. Semantic Versioning (Major.Minor.Patch) must be strictly followed to communicate breaking changes clearly [28].To prevent documentation drift, Continuous Integration (CI) enforcement is paramount. GitHub Actions workflows must execute markdownlint to enforce structural style [65], utilize link checkers to prevent broken references, and apply schema validation to ensure JSON/YAML configurations remain compliant [1].

Tools like changesets or semantic-release should automate versioning based on conventional commit syntax [66]. Merges must be hard-blocked if these checks fail, ensuring that documentation accurately reflects the underlying codebase [29]. Additionally, workflows must incorporate secret scanning and dependency validation to maintain a secure baseline.

## 19. Risk Register

| Risk ID | Risk Summary | Component / Severity / Likelihood | Operational Detail |
| --- | --- | --- | --- |
| R01 | Malicious MCP server executionMCP | Critical Low System takeoverAudit logs, endpoint detectionStrict allowlisting, Docker sandboxingSecOpsLow. Evidence: [19 | ]; confidence: High |
| R02 | Prompt injection via tool returnMCP | High Medium Data exfiltrationInput validationOutput sanitization, strict JSON schemasDevMedium. Evidence: [20]; confiden | ce: High |
| R03 | GCP Service Account key leakageWIF / IAM | Critical Low Cloud env compromiseSecret scanningMandate WIF, disable key creationSecOpsLow. Evidence: [42]; confidence:  | High |
| R04 | WIF subject claim collisionWIF | High Low Unauthorized repo accessIAM policy reviewExact match on repository and refDevOpsLow. Evidence: [33]; confidence | : High |
| R05 | n8n encryption key lossn8n | High Medium Total credential lossBackup monitoringOut-of-band secure backup of configDevOpsMedium. Evidence: [45]; confi | dence: High |
| R06 | Unrestricted GitHub PAT usageGitHub | Critical Low Org-wide compromiseToken auditingUse fine-grained GitHub App tokensSecOpsLow. Evidence: [43]; confidence: H | igh |
| R07 | Broad Cloudflare API tokenCloudflare | High Low Zone hijackingToken permission reviewUse least-privilege templatesDevOpsLow. Evidence: [67]; confidence: High |  |
| R08 | Claude Code shell executionHooks | High Medium Local system compromiseProcess monitoringRestrict type: "command" hooksDevMedium. Evidence: [22]; confidence | : High |
| R09 | Telegram bot token leakageTelegram | Medium Low Bot impersonationSecret scanningStore strictly in Secret ManagerDevLow. Evidence: [35]; confidence: High |  |
| R10 | Railway token over-scopingRailway | High Low Prod env compromiseEnv var auditingUse project tokens, not account tokensDevOpsLow. Evidence: [9]; confidence:  | High |
| R11 | Documentation driftDocs | Low High System confusionCI markdownlintBlock PRs on lint failureDevLow. Evidence: [1]; confidence: High |  |
| R12 | Destructive OpenTofu applyOpenTofu | High Medium Data lossState file reviewHuman gate on apply stepDevOpsLow. Evidence: [7]; confidence: High |  |
| R13 | OpenRouter billing exhaustionOpenRouter | Medium Medium Service denialBilling alertsSet hard spending limits in dashboardAdminLow. Evidence: [68]; confidence: Hig | h |
| R14 | Linear workspace corruptionLinear | High Low Data lossAPI auditingScope OAuth permissions, AIG complianceDevLow. Evidence: [46]; confidence: High |  |
| R15 | Bypassing pre-commit hooksGit | Medium High Code quality dropCI validationEnforce checks via server-side ActionsDevOpsLow. Evidence: [29]; confidence: H | igh |
| R16 | Accidental major SemVer bumpSemVer | Medium Medium Client breakageRelease dry-runsRequire conventional commits formatDevLow. Evidence: [28]; confidence: High |  |
| R17 | Overwriting human decisionsDocs | Medium Medium Loss of architectural intentCode reviewLock ADRs as append-onlyArchLow. Evidence: [25]; confidence: High |  |
| R18 | Supply chain attack via setupScripts | High Low Env compromiseDependency scanningPin dependency versionsSecOpsLow. Evidence: [24]; confidence: High |  |
| R19 | Non-deterministic hook timeoutsHooks | Low Medium CI pipeline hangsTimeout monitoringEnforce strict timeouts on hook scriptsDevOpsLow. Evidence: [22]; confiden | ce: High |
| R20 | Exposure of x-mcp-headerMCP | High Low Credential interceptionTraffic analysisAvoid marking sensitive params as headersSecOpsLow. Evidence: [20]; conf | idence: High |

## 20. Sources

### Overview

The following verifiable sources were utilized to construct this research report, prioritizing official documentation, architectural specifications, and platform developer guides.

### Claude Code Documentation

- Claude Code hooks guide (Anthropic, https://code.claude.com/docs/en/hooks-guide, Official) [22], [22]
- Claude Code skills (Anthropic, https://code.claude.com/docs/en/skills, Official) [23], [23]
- Claude Code on the web (Anthropic, https://code.claude.com/docs/en/claude-code-on-the-web, Official) [24], [24]
- Claude Code web quickstart (Anthropic, https://code.claude.com/docs/en/web-quickstart, Official) [21], [21]
- Claude Code settings schema (Anthropic, https://code.claude.com/docs/en/settings, Official) [48], [48]
- Claude Directory structure (Anthropic, https://code.claude.com/docs/en/claude-directory, Official) [69]

### Model Context Protocol (MCP)

- MCP Specification - Security (Model Context Protocol, https://modelcontextprotocol.io/specification/2025-11-25, Official Standard) [70], [70]
- MCP Security Best Practices (Model Context Protocol, https://modelcontextprotocol.io/docs/tutorials/security/security_best_practices, Official) [19]
- MCP Tools Specification (Model Context Protocol, https://modelcontextprotocol.io/specification/draft/server/tools, Official Standard) [20], [20]
- MCP Local Server Connection (Model Context Protocol, https://modelcontextprotocol.io/docs/develop/connect-local-servers, Official) [39]

### GitHub

- Registering a GitHub App from a manifest (GitHub, https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest, Official) [3], [3]
- Registering a GitHub App using URL parameters (GitHub, https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-using-url-parameters, Official) [71]
- Configuring OIDC in

### Google Cloud

- Platform (GitHub, https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-google-cloud-platform, Official) [4]
- Enforce code quality rules in GitHub (StackOverflow, https://stackoverflow.com/questions/64793355/..., Secondary) [29]
- Google CloudWorkload Identity Federation with Deployment Pipelines (Google Cloud, https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines, Official) [72]
- Best practices for managing service account keys (Google Cloud, https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys, Official) [5]
- Best practices for using Workload Identity Federation (Google Cloud, https://docs.cloud.google.com/iam/docs/best-practices-for-using-workload-identity-federation, Official) [6]

### Railway

- Railway API Documentation (Railway, https://docs.railway.com/integrations/api, Official) [9]
- Railway CLI Tokens (Railway, https://docs.railway.com/cli, Official) [10]
- Terraform Provider for Railway (OpenTofu Search, https://search.opentofu.org/provider/terraform-community-providers/railway/latest, Secondary/Community) [51]

### Cloudflare

- Cloudflare API Tokens (Cloudflare, https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/, Official) [40]
- Cloudflare API Token Templates (Cloudflare, https://developers.cloudflare.com/fundamentals/api/reference/template/, Official) [52]
- Cloudflare Terraform Provider (Cloudflare, https://developers.cloudflare.com/terraform/, Official) [7]

### n8n

- n8n CLI (n8n, https://docs.n8n.io/api/n8n-cli/, Official) [14]n8n Server CLI Commands (n8n, https://docs.n8n.io/hosting/cli-commands/, Official) [54]
- Automated n8n Credential Backups (n8n, https://n8n.io/workflows/9154..., Official) [12]n8n REST API Authentication (n8n, https://docs.n8n.io/api/authentication/, Official) [55]

### Telegram

- Telegram Bots Features (Telegram, https://core.telegram.org/bots/features, Official) [15]
- Telegram Bots Tutorial - Obtain Token (Telegram, https://core.telegram.org/bots/tutorial, Official) [35]

### OpenRouter

- OpenRouter API Reference - Authentication (OpenRouter, https://openrouter.ai/docs/api/reference/authentication, Official) [16]
- OpenRouter Models & Routing (OpenRouter, https://openrouter.ai/docs/api/reference/overview, Official) [37]

### Linear

- Linear OAuth 2.0 authentication (Linear, https://linear.app/developers/oauth-2-0-authentication, Official) [18]
- Linear Agent Interaction Guidelines (Linear, https://linear.app/developers/aig, Official) [59]

### Documentation Standards

- Diátaxis in five minutes (Diátaxis, https://diataxis.fr/start-here/, Official Standard) [26]
- Keep a Changelog (Keep a Changelog, https://keepachangelog.com/en/1.1.0/, Official Standard) [27]
- Architecture Decision Record (Microsoft Azure, https://learn.microsoft.com/en-us/azure/well-architected/architect-role/architecture-decision-record, Official) [25]
- Semantic Release (JFrog, https://jfrog.com/learn/sdlc/semantic-release/, Secondary) [28]

### Research Integrity Notes

The findings synthesized within this document are based on official platform documentation, API references, and security specifications available as of April 2026. The capabilities of Claude Code hooks, skills, and the strict human-in-the-loop requirements of the Model Context Protocol (MCP) are verified directly against Anthropic's official schemas and drafted standards.

Ambiguities exist regarding the absolute maturity of the n8n CLI, which is explicitly marked as "beta" in official documentation; therefore, its programmatic reliability in production automation requires continued validation. Additionally, the OpenTofu provider for Railway is maintained by the community rather than HashiCorp or the OpenTofu core team, necessitating rigorous dry-run testing before relying on it for critical infrastructure mutation.

The assertion that "full autonomy" is impossible from a zero-state is an intentional, security-first architectural stance. While headless browser automation might theoretically bypass OAuth consent screens, doing so explicitly violates platform Terms of Service, introduces immense operational fragility, and defeats the cryptographic purpose of user-delegated authorization.

All recommendations herein mandate explicit, verifiable human bootstrap for identity and billing perimeters.
