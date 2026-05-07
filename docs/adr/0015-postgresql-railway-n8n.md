# ADR-0015 — PostgreSQL + Persistent Volume for n8n on Railway

**Date:** 2026-05-04  
**Status:** Accepted  
**Supersedes:** Nothing (extends ADR-0009)  
**Deciders:** Operator (edri2or), Claude Code agent

---

## Context

`apply-railway-provision.yml` (ADR-0009) provisions a Railway project with two services:
`n8n` (orchestrator) and `agent` (TypeScript Skills Router). The `n8n` service uses its
default SQLite database, which stores the database file inside the container's ephemeral
filesystem.

This creates three production-blocking problems:

1. **Data loss on redeploy.** Every Railway redeployment replaces the container image
   with a fresh one; the SQLite file is lost. Workflow definitions, credentials, execution
   history, and the owner account are wiped.

2. **No queue mode.** n8n's horizontal scaling (multiple workers pulling from a shared
   queue) requires PostgreSQL. SQLite cannot handle concurrent writes from multiple n8n
   processes and is not supported by n8n's queue engine.

3. **No safe hot backup.** SQLite's file-level locking makes live backups unreliable.
   Railway's incremental Copy-on-Write volume snapshots require a properly mounted volume
   filesystem, not an in-container file.

The operator requested alignment with `edri2or/project-life-130`, which demonstrates a
production-grade Railway deployment with PostgreSQL and a persistent volume.

---

## Decision

Extend `apply-railway-provision.yml` to provision a third service (`Postgres`) and attach
a persistent volume, and extend `bootstrap.yml` to inject the PostgreSQL connection into
the `n8n` service.

### Service

- **Image:** `ghcr.io/railwayapp-templates/postgres-ssl:17`  
  Railway's official SSL-enabled PostgreSQL 17 template image. Chosen over the bare
  `postgres:17` Docker Hub image because it auto-generates SSL certificates (valid 820 days)
  and enforces encrypted connections on both public and private endpoints — no extra
  configuration needed.

### Volume

- **Mount path:** `/var/lib/postgresql/data`
- **PGDATA:** `/var/lib/postgresql/data/pgdata`

The volume is mounted at the standard PostgreSQL data directory. `PGDATA` is set to
a **subdirectory** (`pgdata/`) because Railway initialises all volumes with a `lost+found/`
entry at the root. PostgreSQL's `initdb` refuses to initialise in a non-empty directory,
so a subdirectory avoids this conflict.

### n8n database environment variables

Injected by `bootstrap.yml` into the `n8n` service via `variableCollectionUpsert`:

```
DB_TYPE      = postgresdb
DATABASE_URL = ${{Postgres.DATABASE_URL}}
```

`${{Postgres.DATABASE_URL}}` is a Railway reference variable resolved at deploy time
from the `Postgres` service's auto-generated `DATABASE_URL`. This is the idiomatic
Railway approach — it automatically stays correct if the Postgres password rotates.

`DB_TYPE` (not `DATABASE_TYPE`) is the current n8n environment variable name per
the official n8n docs. `DATABASE_TYPE` is a deprecated alias that still works but
should not be used in new deployments.

### PostgreSQL service environment variables

Set by `apply-railway-provision.yml` via `variableUpsert`, only on first provision
(skip-gated by presence of `PGDATA`):

```
POSTGRES_DB       = railway
POSTGRES_USER     = postgres
POSTGRES_PASSWORD = <CSPRNG hex-32>
PGDATA            = /var/lib/postgresql/data/pgdata
DATABASE_URL      = postgresql://postgres:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/railway
```

The `DATABASE_URL` on the Postgres service uses Railway reference variables for
password and hostname so it remains self-consistent if Railway rotates the internal
domain.

### Railway project token

`projectTokenCreate` is called once (skip-gated by presence in GCP Secret Manager) and
the resulting token is stored as `railway-project-token` in GCP Secret Manager.

**Scope clarification:** Railway project tokens are scoped to a specific project+environment
for Railway CLI use (`railway up`, `railway run`). They **cannot** perform GraphQL mutations
such as `serviceCreate`, `variableUpsert`, or `serviceInstanceRedeploy`. All automation
workflows in this template continue to use the account-level `RAILWAY_API_TOKEN`
(`secrets.RAILWAY_API_TOKEN`) for GraphQL operations.

---

## Consequences

**Positive:**
- n8n data (workflows, credentials, execution history, owner account) persists across
  redeployments and Railway infrastructure maintenance.
- Queue mode is now architecturally supported; adding `n8n-worker` service is a
  future no-ADR change.
- Railway's volume snapshots provide incremental, zero-downtime backups.
- Cloudflare SSL + Railway private networking means the Postgres service is never
  exposed publicly.

**Negative / trade-offs:**
- Each Railway project now requires a volume slot (Railway Hobby plan: up to 2 volumes
  per project). This is not a constraint for the template-builder or its clones at
  current scale.
- First provision takes slightly longer (volume creation + Postgres initialisation before
  n8n can connect).
- Postgres password is generated once and stored in GCP Secret Manager as part of the
  Postgres service's env vars. Rotation requires a coordinated update to both the Postgres
  service variable and the `DATABASE_URL` on n8n — a future ADR can address this if
  needed.

**No change to:**
- n8n owner account management (`N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true`, bcrypt hash) —
  the env-var-managed approach (n8n ≥ 2.17.0) is retained in preference to the legacy
  `/rest/owner/setup` API call.
- `railway.toml` (TypeScript Skills Router / `agent` service) — unaffected.
- State-A/B/C classifier semantics — state-A now requires all three services (n8n, agent,
  Postgres); state-B fills in whichever are missing.

---

## References

- [n8n Supported Databases](https://docs.n8n.io/hosting/configuration/supported-databases-settings/)
- [n8n Database Environment Variables](https://docs.n8n.io/hosting/configuration/environment-variables/database/)
- [Railway Volumes](https://docs.railway.com/volumes)
- [Railway PostgreSQL](https://docs.railway.com/databases/postgresql)
- [Railway Variables Reference](https://docs.railway.com/variables/reference)
- [Railway Public API — Token Scopes](https://docs.railway.com/integrations/api)
- ADR-0009 — Railway mutation workflow
- `edri2or/project-life-130` `.github/workflows/bootstrap.yml` + `deploy-n8n.yml` (reference implementation)
