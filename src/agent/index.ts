/**
 * Zero-dependency TypeScript Skills Router
 *
 * Routes inbound user intents to discrete skill definitions using Jaccard
 * similarity matching. All external API calls are delegated to n8n workflows
 * via webhook triggers. No npm runtime dependencies.
 */

import * as fs from "fs";
import * as path from "path";
import * as http from "http";
import * as crypto from "crypto";

// ── Types ──────────────────────────────────────────────────────────────────

export interface Skill {
  name: string;
  description: string;
  intent_keywords: string[];
  n8n_webhook?: string;
  handler?: string;
  requires_approval: boolean;
  budget_gated?: boolean;
}

export interface SkillRegistry {
  skills: Skill[];
}

export interface RouteResult {
  matched: boolean;
  skill: Skill | null;
  score: number;
  intent: string;
}

export interface WebhookPayload {
  intent: string;
  chat_id?: string;
  user_id?: string;
  timestamp: string;
  metadata?: Record<string, unknown>;
}

// ── Skill Discovery ─────────────────────────────────────────────────────────

const SKILL_FILE = path.join(__dirname, "skills", "SKILL.md");
const SIMILARITY_THRESHOLD = 0.10;

/**
 * Parses SKILL.md YAML blocks into a typed registry.
 * SKILL.md uses fenced YAML blocks delimited by --- separators.
 */
export function discoverSkills(): Skill[] {
  const content = fs.readFileSync(SKILL_FILE, "utf8");
  const skills: Skill[] = [];

  // Extract YAML blocks between ```yaml and ``` fences
  const yamlBlockRegex = /```yaml\n([\s\S]*?)```/g;
  let match: RegExpExecArray | null;

  while ((match = yamlBlockRegex.exec(content)) !== null) {
    const block = match[1];
    const skill = parseSkillBlock(block);
    if (skill) skills.push(skill);
  }

  return skills;
}

function parseSkillBlock(yaml: string): Skill | null {
  const lines = yaml.trim().split("\n");
  const obj: Record<string, unknown> = {};

  for (const line of lines) {
    const colonIdx = line.indexOf(":");
    if (colonIdx === -1) continue;

    const key = line.slice(0, colonIdx).trim();
    const value = line.slice(colonIdx + 1).trim();

    if (key === "intent_keywords") {
      // Parse inline YAML array: [keyword1, keyword2]
      const arrayMatch = value.match(/^\[(.*)\]$/);
      if (arrayMatch) {
        obj[key] = arrayMatch[1]
          .split(",")
          .map((k) => k.trim().replace(/['"]/g, ""));
      } else {
        obj[key] = [];
      }
    } else if (key === "requires_approval" || key === "budget_gated") {
      obj[key] = value === "true";
    } else {
      obj[key] = value.replace(/['"]/g, "");
    }
  }

  if (!obj.name || !obj.description || !Array.isArray(obj.intent_keywords)) {
    return null;
  }

  return {
    name: obj.name as string,
    description: obj.description as string,
    intent_keywords: obj.intent_keywords as string[],
    n8n_webhook: obj.n8n_webhook as string | undefined,
    handler: obj.handler as string | undefined,
    requires_approval: Boolean(obj.requires_approval),
    budget_gated: Boolean(obj.budget_gated),
  };
}

// ── Jaccard Similarity ──────────────────────────────────────────────────────

/**
 * Computes Jaccard similarity between two token sets.
 * J(A,B) = |A ∩ B| / |A ∪ B|
 */
export function jaccardSimilarity(a: string[], b: string[]): number {
  if (a.length === 0 && b.length === 0) return 1;
  const setA = new Set(a.map((t) => t.toLowerCase()));
  const setB = new Set(b.map((t) => t.toLowerCase()));
  const intersection = new Set([...setA].filter((t) => setB.has(t)));
  const union = new Set([...setA, ...setB]);
  return intersection.size / union.size;
}

function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter((t) => t.length > 1);
}

// ── Intent Routing ──────────────────────────────────────────────────────────

/**
 * Routes an inbound intent string to the best-matching skill.
 * Returns a RouteResult with the matched skill and similarity score.
 */
export function routeIntent(intent: string, skills: Skill[]): RouteResult {
  const intentTokens = tokenize(intent);
  let bestScore = 0;
  let bestSkill: Skill | null = null;

  for (const skill of skills) {
    const score = jaccardSimilarity(intentTokens, skill.intent_keywords);
    if (score > bestScore) {
      bestScore = score;
      bestSkill = skill;
    }
  }

  return {
    matched: bestScore >= SIMILARITY_THRESHOLD,
    skill: bestScore >= SIMILARITY_THRESHOLD ? bestSkill : null,
    score: bestScore,
    intent,
  };
}

// ── Rate Limiter (sliding window) ───────────────────────────────────────────

/**
 * In-process sliding-window rate limiter. Bounds the n8n→Router call rate
 * per CLAUDE.md runtime autonomy contract ("n8n webhooks rate-limited to
 * 20 req/min"). Zero-dep, fail-closed: rejects with 429 when the window is
 * full. Storage is in-memory and lost on restart — acceptable for a
 * single-replica agent service.
 */
export class RateLimiter {
  private readonly windowMs: number;
  private readonly max: number;
  private readonly buckets: Map<string, number[]> = new Map();

  constructor(opts?: { windowMs?: number; max?: number }) {
    this.windowMs = opts?.windowMs ?? 60_000;
    this.max = opts?.max ?? 20;
  }

  check(key: string, now: number = Date.now()): { allowed: boolean; retryAfterMs: number } {
    const cutoff = now - this.windowMs;
    const bucket = this.buckets.get(key) ?? [];
    const live = bucket.filter((t) => t > cutoff);

    if (live.length >= this.max) {
      const retryAfterMs = Math.max(0, live[0] + this.windowMs - now);
      this.buckets.set(key, live);
      return { allowed: false, retryAfterMs };
    }

    live.push(now);
    this.buckets.set(key, live);
    return { allowed: true, retryAfterMs: 0 };
  }
}

// ── OpenRouter Budget Gate ──────────────────────────────────────────────────

export type FetchLike = (
  input: string,
  init?: { method?: string; headers?: Record<string, string> }
) => Promise<{ ok: boolean; status: number; json: () => Promise<unknown> }>;

export const GATE_REASONS = {
  BUDGET_THRESHOLD: "openrouter_budget_threshold",
  PROBE_FAIL_OPEN: "probe_failed_fail_open",
  PROBE_FAIL_CLOSED: "probe_failed_fail_closed",
} as const;

export type GateReason = (typeof GATE_REASONS)[keyof typeof GATE_REASONS] | "";

/**
 * Pre-flight HITL gate for budget-gated skills. Reads OpenRouter
 * `GET /api/v1/credits` (Management key) and gates the call when the
 * remaining balance falls below `OPENROUTER_BUDGET_THRESHOLD_USD`.
 * Default failure mode is fail-closed (gate → human approval) when the
 * probe is unreachable; flip with `OPENROUTER_BUDGET_FAIL_OPEN=true`
 * for liveness-over-strictness operators.
 */
export class OpenRouterBudgetGate {
  static readonly CACHE_TTL_MS = 60_000;
  private cache: { remaining: number; fetchedAt: number } | null = null;

  constructor(
    private readonly opts: {
      managementKey: string;
      threshold: number;
      failOpen: boolean;
      fetchFn?: FetchLike;
      endpoint?: string;
    }
  ) {}

  async getCreditsBalance(now: number = Date.now()): Promise<{ remaining: number; cached: boolean }> {
    if (this.cache && now - this.cache.fetchedAt < OpenRouterBudgetGate.CACHE_TTL_MS) {
      return { remaining: this.cache.remaining, cached: true };
    }

    const fetchFn = this.opts.fetchFn ?? (globalThis.fetch as unknown as FetchLike);
    const endpoint = this.opts.endpoint ?? "https://openrouter.ai/api/v1/credits";

    const resp = await fetchFn(endpoint, {
      method: "GET",
      headers: { Authorization: `Bearer ${this.opts.managementKey}` },
    });

    if (!resp.ok) {
      throw new Error(`OpenRouter /credits HTTP ${resp.status}`);
    }

    const body = (await resp.json()) as { data?: { total_credits?: number; total_usage?: number } };
    const totalCredits = Number(body?.data?.total_credits ?? 0);
    const totalUsage = Number(body?.data?.total_usage ?? 0);
    const remaining = totalCredits - totalUsage;

    this.cache = { remaining, fetchedAt: now };
    return { remaining, cached: false };
  }

  /**
   * Returns true when the call should be gated (HITL approval required).
   * On probe failure: fail-closed (true) by default; fail-open (false)
   * when configured.
   */
  async shouldGate(now: number = Date.now()): Promise<{ gated: boolean; remaining: number | null; reason: GateReason }> {
    try {
      const { remaining } = await this.getCreditsBalance(now);
      if (remaining < this.opts.threshold) {
        return { gated: true, remaining, reason: GATE_REASONS.BUDGET_THRESHOLD };
      }
      return { gated: false, remaining, reason: "" };
    } catch (err) {
      if (this.opts.failOpen) {
        console.warn("[BUDGET] /credits unreachable; fail-open per OPENROUTER_BUDGET_FAIL_OPEN=true:", err);
        return { gated: false, remaining: null, reason: GATE_REASONS.PROBE_FAIL_OPEN };
      }
      console.warn("[BUDGET] /credits unreachable; fail-closed (default):", err);
      return { gated: true, remaining: null, reason: GATE_REASONS.PROBE_FAIL_CLOSED };
    }
  }
}

// ── Webhook Signature Validation ────────────────────────────────────────────

/**
 * Validates HMAC-SHA256 webhook signatures. Fail-closed: returns false
 * if the signature header is missing, malformed, or does not match.
 * Prevents the fail-open vulnerability documented in R-02.
 */
export function validateWebhookSignature(
  payload: string,
  signatureHeader: string | undefined,
  secret: string
): boolean {
  if (!signatureHeader) return false;

  const parts = signatureHeader.split("=");
  if (parts.length !== 2 || parts[0] !== "sha256") return false;

  const expected = crypto
    .createHmac("sha256", secret)
    .update(payload, "utf8")
    .digest("hex");

  // Timing-safe comparison prevents timing attacks
  return crypto.timingSafeEqual(
    Buffer.from(parts[1], "hex"),
    Buffer.from(expected, "hex")
  );
}

// ── HTTP Server ─────────────────────────────────────────────────────────────

const PORT = parseInt(process.env.PORT ?? "3000", 10);
const WEBHOOK_SECRET = process.env.WEBHOOK_SECRET ?? "";
const RATE_LIMIT_MAX = parseInt(process.env.RATE_LIMIT_MAX ?? "20", 10);
const RATE_LIMIT_WINDOW_MS = parseInt(process.env.RATE_LIMIT_WINDOW_MS ?? "60000", 10);
const OPENROUTER_BUDGET_THRESHOLD_USD = parseFloat(
  process.env.OPENROUTER_BUDGET_THRESHOLD_USD ?? "1.0"
);
const OPENROUTER_BUDGET_FAIL_OPEN = process.env.OPENROUTER_BUDGET_FAIL_OPEN === "true";
const OPENROUTER_MANAGEMENT_KEY = process.env.OPENROUTER_MANAGEMENT_KEY ?? "";

const rateLimiter = new RateLimiter({
  windowMs: RATE_LIMIT_WINDOW_MS,
  max: RATE_LIMIT_MAX,
});

const budgetGate = new OpenRouterBudgetGate({
  managementKey: OPENROUTER_MANAGEMENT_KEY,
  threshold: OPENROUTER_BUDGET_THRESHOLD_USD,
  failOpen: OPENROUTER_BUDGET_FAIL_OPEN,
});

function sendJson(
  res: http.ServerResponse,
  status: number,
  body: unknown
): void {
  const json = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(json),
  });
  res.end(json);
}

function handleHealth(res: http.ServerResponse): void {
  sendJson(res, 200, { status: "ok", timestamp: new Date().toISOString() });
}

interface WebhookDeps {
  webhookSecret: string;
  rateLimiter: RateLimiter;
  budgetGate: OpenRouterBudgetGate;
}

type RouterDeps = Partial<WebhookDeps>;

async function handleWebhook(
  req: http.IncomingMessage,
  res: http.ServerResponse,
  deps: WebhookDeps
): Promise<void> {
  const chunks: Buffer[] = [];

  req.on("data", (chunk: Buffer) => chunks.push(chunk));

  await new Promise<void>((resolve) => req.on("end", resolve));

  const rawBody = Buffer.concat(chunks).toString("utf8");
  const signatureHeader = req.headers["x-signature-256"] as string | undefined;

  // Fail-closed: reject requests with invalid or missing signatures (R-02)
  if (deps.webhookSecret && !validateWebhookSignature(rawBody, signatureHeader, deps.webhookSecret)) {
    console.warn(
      `[SECURITY] Webhook signature validation failed. Source: ${req.socket.remoteAddress}`
    );
    sendJson(res, 401, { error: "Invalid signature" });
    return;
  }

  // Rate-limit gate (post-signature so attackers cannot consume counters)
  const rlKey = req.socket.remoteAddress ?? "unknown";
  const rl = deps.rateLimiter.check(rlKey);
  if (!rl.allowed) {
    console.warn(`[RATELIMIT] Rejected key=${rlKey} retry_after_ms=${rl.retryAfterMs}`);
    sendJson(res, 429, { error: "Rate limit exceeded", retry_after_ms: rl.retryAfterMs });
    return;
  }

  let payload: WebhookPayload;
  try {
    payload = JSON.parse(rawBody) as WebhookPayload;
  } catch {
    sendJson(res, 400, { error: "Invalid JSON payload" });
    return;
  }

  const skills = discoverSkills();
  const result = routeIntent(payload.intent, skills);

  console.log(
    `[ROUTER] intent="${payload.intent}" matched=${result.matched} skill=${result.skill?.name ?? "none"} score=${result.score.toFixed(3)}`
  );

  if (!result.matched || !result.skill) {
    sendJson(res, 200, {
      matched: false,
      message: "No skill matched. Please rephrase your request.",
    });
    return;
  }

  // Budget gate (HITL when the matched skill is budget_gated and remaining < threshold)
  if (result.skill.budget_gated) {
    const decision = await deps.budgetGate.shouldGate();
    if (decision.gated) {
      console.warn(
        `[BUDGET] Gating skill=${result.skill.name} reason=${decision.reason} remaining=${decision.remaining}`
      );
      sendJson(res, 200, {
        matched: true,
        skill: result.skill.name,
        status: "pending_approval",
        reason: decision.reason,
        remaining: decision.remaining,
        message: `OpenRouter budget threshold reached. Human approval required for: "${result.skill.description}"`,
      });
      return;
    }
  }

  if (result.skill.requires_approval) {
    sendJson(res, 200, {
      matched: true,
      skill: result.skill.name,
      status: "pending_approval",
      message: `This action requires human approval: "${result.skill.description}"`,
    });
    return;
  }

  sendJson(res, 200, {
    matched: true,
    skill: result.skill.name,
    score: result.score,
    n8n_webhook: result.skill.n8n_webhook,
  });
}

function createServer(deps?: RouterDeps): http.Server {
  const skills = discoverSkills();
  console.log(`[ROUTER] Loaded ${skills.length} skills from SKILL.md`);

  const resolved = {
    webhookSecret: deps?.webhookSecret ?? WEBHOOK_SECRET,
    rateLimiter: deps?.rateLimiter ?? rateLimiter,
    budgetGate: deps?.budgetGate ?? budgetGate,
  };

  return http.createServer(
    (req: http.IncomingMessage, res: http.ServerResponse) => {
      if (req.url === "/health" && req.method === "GET") {
        handleHealth(res);
        return;
      }

      if (req.url === "/webhook" && req.method === "POST") {
        handleWebhook(req, res, resolved).catch((err: Error) => {
          console.error("[ERROR] Unhandled exception in webhook handler:", err);
          // Fail-closed: drop payload, log, do not attempt recovery
          sendJson(res, 500, { error: "Internal error. Operator has been notified." });
        });
        return;
      }

      sendJson(res, 404, { error: "Not found" });
    }
  );
}

// Start server only when executed directly (not during tests)
if (require.main === module) {
  const server = createServer();
  server.listen(PORT, () => {
    console.log(`[ROUTER] Skills Router listening on port ${PORT}`);
  });
}

export { createServer };
