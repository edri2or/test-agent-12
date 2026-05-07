/**
 * Invariant tests for the template provisioning pipeline.
 * Validates spec uniqueness, naming conventions, and parse-spec.js output contracts.
 * Complements spec-schema-validation.test.ts (schema shape) with semantic rules.
 */
import { execSync } from "node:child_process";
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import yaml from "js-yaml";

const REPO_ROOT = join(__dirname, "..", "..", "..");
const SPECS_DIR = join(REPO_ROOT, "specs");
const PARSE_SPEC = join(REPO_ROOT, "scripts", "parse-spec.js");

interface SystemSpec {
  apiVersion: string;
  kind: string;
  metadata: { name: string; description: string };
  spec: {
    gcp: { projectId: string; region: string };
    github: { repo: string; fromTemplate: string };
    railway?: { services: { name: string; kind: string }[] };
    cloudflare?: { zone: string; worker: { name: string; route: string } };
    secrets?: { required: string[] };
    intent?: { source: string };
  };
}

function loadSpecs(): { file: string; doc: SystemSpec }[] {
  return readdirSync(SPECS_DIR)
    .filter((f) => f.endsWith(".yaml") || f.endsWith(".yml"))
    .map((file) => ({
      file,
      doc: yaml.load(readFileSync(join(SPECS_DIR, file), "utf8")) as SystemSpec,
    }));
}

describe("template provisioning invariants", () => {
  const specs = loadSpecs();

  // ── Uniqueness ──────────────────────────────────────────────────────────────

  test("each spec has a unique metadata.name", () => {
    const names = specs.map((s) => s.doc.metadata.name);
    const dupes = names.filter((n, i) => names.indexOf(n) !== i);
    expect(dupes).toEqual([]);
  });

  test("each spec targets a unique GCP projectId", () => {
    const ids = specs.map((s) => s.doc.spec.gcp.projectId);
    const dupes = ids.filter((id, i) => ids.indexOf(id) !== i);
    expect(dupes).toEqual([]);
  });

  test("each spec targets a unique GitHub repo", () => {
    const repos = specs.map((s) => s.doc.spec.github.repo);
    const dupes = repos.filter((r, i) => repos.indexOf(r) !== i);
    expect(dupes).toEqual([]);
  });

  // ── Naming conventions ──────────────────────────────────────────────────────

  describe("naming conventions", () => {
    const KEBAB = /^[a-z0-9]+(-[a-z0-9]+)*$/;

    for (const { file, doc } of specs) {
      test(`${file}: metadata.name is kebab-case`, () => {
        expect(doc.metadata.name).toMatch(KEBAB);
      });

      test(`${file}: gcp.projectId starts with 'or-'`, () => {
        expect(doc.spec.gcp.projectId).toMatch(/^or-/);
      });

      test(`${file}: github.repo owner is 'edri2or'`, () => {
        const [owner] = doc.spec.github.repo.split("/");
        expect(owner).toBe("edri2or");
      });

      if (doc.spec.railway) {
        for (const svc of doc.spec.railway.services) {
          test(`${file}: railway service '${svc.name}' kind is typescript|docker`, () => {
            expect(["typescript", "docker"]).toContain(svc.kind);
          });
        }
      }
    }
  });

  // ── fromTemplate invariant ──────────────────────────────────────────────────

  test("all specs reference the canonical template repo", () => {
    const TEMPLATE = "edri2or/autonomous-agent-template-builder";
    for (const { doc } of specs) {
      expect(doc.spec.github.fromTemplate).toBe(TEMPLATE);
    }
  });

  // ── parse-spec.js output contract ──────────────────────────────────────────

  describe("parse-spec.js output contract", () => {
    const REQUIRED_OUTPUTS = [
      "spec_name",
      "gcp_project_id",
      "gcp_region",
      "github_repo",
      "github_from_template",
      "github_owner",
      "repo_name",
      "has_railway",
      "has_cloudflare",
    ];

    for (const { file, doc } of specs) {
      test(`${file}: parse-spec.js emits all required GITHUB_OUTPUT keys`, () => {
        const outFile = join(tmpdir(), `parse-spec-out-${file}-${Date.now()}.txt`);
        const sumFile = join(tmpdir(), `parse-spec-sum-${file}-${Date.now()}.txt`);
        writeFileSync(outFile, "");
        writeFileSync(sumFile, "");

        const env = {
          ...process.env,
          SPEC_PATH: join(SPECS_DIR, file),
          GITHUB_OUTPUT: outFile,
          GITHUB_STEP_SUMMARY: sumFile,
        };

        execSync(`node "${PARSE_SPEC}"`, { env, stdio: "pipe" });

        const output = readFileSync(outFile, "utf8");
        for (const key of REQUIRED_OUTPUTS) {
          expect(output).toContain(`${key}=`);
        }

        // has_railway / has_cloudflare must be boolean strings
        const hasRailway = output.match(/has_railway=(\S+)/)?.[1];
        const hasCF = output.match(/has_cloudflare=(\S+)/)?.[1];
        expect(["true", "false"]).toContain(hasRailway);
        expect(["true", "false"]).toContain(hasCF);

        // spec_name must match metadata.name
        const specName = output.match(/spec_name=(\S+)/)?.[1];
        expect(specName).toBe(doc.metadata.name);

        // gcp_project_id must match spec.gcp.projectId
        const gcpId = output.match(/gcp_project_id=(\S+)/)?.[1];
        expect(gcpId).toBe(doc.spec.gcp.projectId);
      });
    }
  });

  // ── Region whitelist ────────────────────────────────────────────────────────

  test("all specs use an allowed GCP region", () => {
    const ALLOWED = ["us-central1", "us-east1", "europe-west1"];
    for (const { doc } of specs) {
      expect(ALLOWED).toContain(doc.spec.gcp.region);
    }
  });

  // ── Required secrets declared ───────────────────────────────────────────────

  test("all specs declare at least one required secret", () => {
    for (const { doc } of specs) {
      const secrets = doc.spec.secrets?.required ?? [];
      expect(secrets.length).toBeGreaterThan(0);
    }
  });

  // ── Postgres / n8n consistency ──────────────────────────────────────────────
  // apply-railway-spec.yml auto-provisions Postgres whenever n8n is in the spec.
  // A spec that manually declares "Postgres" would conflict with auto-inject
  // (duplicate service name → Railway rejects the create call).

  test("specs with n8n must not manually declare a Postgres service (auto-injected)", () => {
    for (const { doc } of specs) {
      const services = doc.spec.railway?.services ?? [];
      const hasN8n = services.some((s) => s.name === "n8n");
      const hasManualPostgres = services.some((s) => s.name === "Postgres");
      if (hasN8n) {
        expect(hasManualPostgres).toBe(false);
      }
    }
  });
});
