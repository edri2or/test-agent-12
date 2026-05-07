# Security Policy

## Supported Versions

This is a template repository. Security fixes apply to the current template HEAD.

## Secrets Handling — Absolute Rules

1. **Never commit secrets.** `.env`, `*.pem`, `*.key`, `*.json` credential files are git-ignored.
2. **Never log secrets.** CI workflows must not `echo` or `cat` secret values.
3. **Never use static service account keys.** Use GCP Workload Identity Federation (WIF/OIDC) exclusively.
4. **All secrets live in GCP Secret Manager.** Human operators inject them manually. The agent reads them at runtime via IAM-scoped bindings.
5. **Cloudflare API token** must be stored in GCP Secret Manager immediately upon generation — never in GitHub Secrets or repository files (R-01).
6. **Webhook signatures must be validated** with HMAC-SHA256. Fail-closed if the signature is missing or invalid (R-02).
7. **MCP tools with `delete`, `drop`, or `mutate` capabilities** must never be auto-approved (R-05).

## WIF Security Constraints

The GCP IAM role bound to the WIF provider must be scoped to:
- Exact repository: `repo:YOUR_ORG/YOUR_REPO`
- Exact branch: `refs/heads/main`

This prevents lateral privilege escalation from forked repositories or feature branches.

## Telegram Bot Token

The Telegram Bot token is a kill switch. Revoking it via @BotFather immediately severs the runtime agent's HITL interface. Store in GCP Secret Manager only.

## OpenRouter Budget Cap

The OpenRouter Management API key is a root-privilege credential. Its IAM scope in Secret Manager must be tightly constrained. Sub-service keys are provisioned programmatically with a $10/day budget cap and are revoked on anomalous behavior detection.

## Reporting a Vulnerability

To report a security vulnerability, open a GitHub Security Advisory (private) on this repository. Do not open a public issue.

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested mitigation (optional)

We aim to respond within 72 hours and patch within 14 days for critical issues.
