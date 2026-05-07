#!/usr/bin/env node
// Parses a SystemSpec YAML file and emits fields to GITHUB_OUTPUT + GITHUB_STEP_SUMMARY.
// Usage: SPEC_PATH=specs/foo.yaml node scripts/parse-spec.js
// Called by .github/workflows/apply-system-spec.yml (dispatch mode only).
"use strict";
const { readFileSync, appendFileSync } = require("node:fs");
const yaml = require("js-yaml");

const path = process.env.SPEC_PATH;
if (!path) { console.error("SPEC_PATH is required"); process.exit(1); }

const doc = yaml.load(readFileSync(path, "utf8"));
const { spec, metadata } = doc;
const out     = process.env.GITHUB_OUTPUT;
const summary = process.env.GITHUB_STEP_SUMMARY;

const region   = spec.gcp.region || "us-central1";
const template = spec.github.fromTemplate || "edri2or/autonomous-agent-template-builder";
const svcs     = (spec.railway    || {}).services || [];
const secrets  = (spec.secrets    || {}).required || [];
const cf       =  spec.cloudflare || {};

const [repoOwner, repoName] = spec.github.repo.split("/");
const outputs = [
  "spec_name="            + metadata.name,
  "gcp_project_id="       + spec.gcp.projectId,
  "gcp_region="           + region,
  "github_repo="          + spec.github.repo,
  "github_from_template=" + template,
  "github_owner="         + repoOwner,
  "repo_name="            + repoName,
  "has_railway="          + ("railway"    in spec ? "true" : "false"),
  "has_cloudflare="       + ("cloudflare" in spec ? "true" : "false"),
].join("\n") + "\n";
appendFileSync(out, outputs);

const summaryLines = [
  "# Apply system spec — " + metadata.name,
  "",
  "**Spec:** `" + path + "`",
  "",
  "## Parsed fields",
  "",
  "| Field | Value |",
  "|-------|-------|",
  "| `spec.gcp.projectId` | `" + spec.gcp.projectId + "` |",
  "| `spec.gcp.region` | `" + region + "` |",
  "| `spec.github.repo` | `" + spec.github.repo + "` |",
  "| `spec.github.fromTemplate` | `" + template + "` |",
  "| `spec.railway.services` | " + svcs.length + " service(s) |",
  "| `spec.cloudflare.zone` | " + (cf.zone ? "`" + cf.zone + "`" : "—") + " |",
  "| `spec.secrets.required` | " + secrets.map(function(s) { return "`" + s + "`"; }).join(", ") + " |",
].join("\n") + "\n";
appendFileSync(summary, summaryLines);
console.log(summaryLines);
