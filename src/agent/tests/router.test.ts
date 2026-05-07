import {
  discoverSkills,
  routeIntent,
  jaccardSimilarity,
  validateWebhookSignature,
  RateLimiter,
  OpenRouterBudgetGate,
  GATE_REASONS,
  FetchLike,
  Skill,
  createServer,
} from "../index";
import * as http from "http";
import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";

function generateSignature(body: string, key: string): string {
  return "sha256=" + crypto.createHmac("sha256", key).update(body).digest("hex");
}

function mockFetchCredits(totalCredits: number, totalUsage: number): jest.Mock {
  return jest.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => ({ data: { total_credits: totalCredits, total_usage: totalUsage } }),
  });
}

function mockFetchReject(): jest.Mock {
  return jest.fn().mockRejectedValue(new Error("network down"));
}

// ── Jaccard Similarity ──────────────────────────────────────────────────────

describe("jaccardSimilarity", () => {
  test("identical sets return 1.0", () => {
    expect(jaccardSimilarity(["a", "b", "c"], ["a", "b", "c"])).toBe(1);
  });

  test("disjoint sets return 0.0", () => {
    expect(jaccardSimilarity(["a", "b"], ["c", "d"])).toBe(0);
  });

  test("partial overlap returns correct ratio", () => {
    // intersection: {b} = 1, union: {a, b, c} = 3 → 1/3
    expect(jaccardSimilarity(["a", "b"], ["b", "c"])).toBeCloseTo(1 / 3);
  });

  test("both empty returns 1.0", () => {
    expect(jaccardSimilarity([], [])).toBe(1);
  });

  test("one empty returns 0.0", () => {
    expect(jaccardSimilarity(["a"], [])).toBe(0);
  });

  test("case-insensitive comparison", () => {
    expect(jaccardSimilarity(["Deploy"], ["deploy"])).toBe(1);
  });
});

// ── Skill Discovery ─────────────────────────────────────────────────────────

describe("discoverSkills", () => {
  test("loads at least one skill from SKILL.md", () => {
    const skills = discoverSkills();
    expect(skills.length).toBeGreaterThan(0);
  });

  test("every skill has required fields", () => {
    const skills = discoverSkills();
    for (const skill of skills) {
      expect(typeof skill.name).toBe("string");
      expect(skill.name.length).toBeGreaterThan(0);
      expect(typeof skill.description).toBe("string");
      expect(Array.isArray(skill.intent_keywords)).toBe(true);
      expect(skill.intent_keywords.length).toBeGreaterThan(0);
      expect(typeof skill.requires_approval).toBe("boolean");
    }
  });

  test("destroy-resource skill requires approval", () => {
    const skills = discoverSkills();
    const destroySkill = skills.find((s) => s.name === "destroy-resource");
    expect(destroySkill).toBeDefined();
    expect(destroySkill?.requires_approval).toBe(true);
  });

  test("health-check skill does not require approval", () => {
    const skills = discoverSkills();
    const healthSkill = skills.find((s) => s.name === "health-check");
    expect(healthSkill).toBeDefined();
    expect(healthSkill?.requires_approval).toBe(false);
  });

  test("openrouter-infer skill is budget_gated", () => {
    const skills = discoverSkills();
    const inferSkill = skills.find((s) => s.name === "openrouter-infer");
    expect(inferSkill).toBeDefined();
    expect(inferSkill?.budget_gated).toBe(true);
  });
});

// ── Intent Routing ──────────────────────────────────────────────────────────

describe("routeIntent", () => {
  const mockSkills: Skill[] = [
    {
      name: "health-check",
      description: "Check system health",
      intent_keywords: ["health", "status", "ping", "check", "alive"],
      requires_approval: false,
    },
    {
      name: "linear-issue",
      description: "Create a Linear issue",
      intent_keywords: ["linear", "issue", "task", "ticket", "create", "bug"],
      requires_approval: false,
    },
    {
      name: "destroy-resource",
      description: "Destroy a cloud resource",
      intent_keywords: ["destroy", "delete", "remove", "drop", "terminate"],
      requires_approval: true,
    },
  ];

  test("routes health intent to health-check skill", () => {
    const result = routeIntent("check system health status", mockSkills);
    expect(result.matched).toBe(true);
    expect(result.skill?.name).toBe("health-check");
  });

  test("routes issue intent to linear-issue skill", () => {
    const result = routeIntent("create a new bug ticket in linear", mockSkills);
    expect(result.matched).toBe(true);
    expect(result.skill?.name).toBe("linear-issue");
  });

  test("routes destructive intent to destroy-resource skill", () => {
    const result = routeIntent("delete this resource now", mockSkills);
    expect(result.matched).toBe(true);
    expect(result.skill?.name).toBe("destroy-resource");
    expect(result.skill?.requires_approval).toBe(true);
  });

  test("returns matched=false for unrecognized intent", () => {
    const result = routeIntent("xyzzy frobnicate quux", mockSkills);
    expect(result.matched).toBe(false);
    expect(result.skill).toBeNull();
  });

  test("returns matched=false for empty skills array", () => {
    const result = routeIntent("check health", []);
    expect(result.matched).toBe(false);
    expect(result.skill).toBeNull();
  });

  test("score is between 0 and 1", () => {
    const result = routeIntent("check system health", mockSkills);
    expect(result.score).toBeGreaterThanOrEqual(0);
    expect(result.score).toBeLessThanOrEqual(1);
  });

  test("returns the intent string in result", () => {
    const intent = "ping the health endpoint";
    const result = routeIntent(intent, mockSkills);
    expect(result.intent).toBe(intent);
  });
});

// ── Webhook Signature Validation ────────────────────────────────────────────

describe("validateWebhookSignature", () => {
  const secret = "test-webhook-secret-32-chars-long";
  const payload = JSON.stringify({ intent: "check health" });

  test("returns true for valid signature", () => {
    const sig = generateSignature(payload, secret);
    expect(validateWebhookSignature(payload, sig, secret)).toBe(true);
  });

  test("returns false when signature header is undefined (fail-closed, R-02)", () => {
    expect(validateWebhookSignature(payload, undefined, secret)).toBe(false);
  });

  test("returns false for wrong secret", () => {
    const sig = generateSignature(payload, "wrong-secret");
    expect(validateWebhookSignature(payload, sig, secret)).toBe(false);
  });

  test("returns false for tampered payload", () => {
    const sig = generateSignature(payload, secret);
    expect(
      validateWebhookSignature('{"intent":"delete everything"}', sig, secret)
    ).toBe(false);
  });

  test("returns false for malformed signature format", () => {
    expect(validateWebhookSignature(payload, "invalid-format", secret)).toBe(
      false
    );
  });

  test("returns false for empty signature string", () => {
    expect(validateWebhookSignature(payload, "", secret)).toBe(false);
  });
});

// ── Integration: full routing pipeline ─────────────────────────────────────

describe("Full routing pipeline (SKILL.md integration)", () => {
  test("deploy intent routes correctly", () => {
    const skills = discoverSkills();
    const result = routeIntent("deploy to railway", skills);
    expect(result.matched).toBe(true);
    expect(result.skill?.name).toBe("deploy-railway");
  });

  test("telegram send intent routes correctly", () => {
    const skills = discoverSkills();
    const result = routeIntent("send a telegram notification", skills);
    expect(result.matched).toBe(true);
    expect(result.skill?.name).toBe("telegram-route");
  });

  test("openrouter infer intent routes correctly", () => {
    const skills = discoverSkills();
    const result = routeIntent("generate a summary using the llm model", skills);
    expect(result.matched).toBe(true);
    expect(result.skill?.name).toBe("openrouter-infer");
  });

  test("destroy intent requires approval", () => {
    const skills = discoverSkills();
    const result = routeIntent("delete the production database", skills);
    expect(result.matched).toBe(true);
    expect(result.skill?.requires_approval).toBe(true);
  });
});

// ── Rate Limiter (sliding window) ───────────────────────────────────────────

describe("RateLimiter", () => {
  test("allows requests under the limit", () => {
    const rl = new RateLimiter({ windowMs: 60_000, max: 3 });
    expect(rl.check("k").allowed).toBe(true);
    expect(rl.check("k").allowed).toBe(true);
    expect(rl.check("k").allowed).toBe(true);
  });

  test("blocks the request that crosses the limit", () => {
    const rl = new RateLimiter({ windowMs: 60_000, max: 2 });
    rl.check("k");
    rl.check("k");
    const decision = rl.check("k");
    expect(decision.allowed).toBe(false);
    expect(decision.retryAfterMs).toBeGreaterThanOrEqual(0);
  });

  test("prunes timestamps outside the window (sliding)", () => {
    const rl = new RateLimiter({ windowMs: 60_000, max: 2 });
    rl.check("k", 1_000);
    rl.check("k", 2_000);
    expect(rl.check("k", 3_000).allowed).toBe(false);
    // After the window slides past the first entries
    expect(rl.check("k", 70_000).allowed).toBe(true);
  });

  test("keys are independent", () => {
    const rl = new RateLimiter({ windowMs: 60_000, max: 1 });
    expect(rl.check("alice").allowed).toBe(true);
    expect(rl.check("alice").allowed).toBe(false);
    expect(rl.check("bob").allowed).toBe(true);
  });

  test("retryAfterMs is non-negative when blocked", () => {
    const rl = new RateLimiter({ windowMs: 60_000, max: 1 });
    rl.check("k", 1_000);
    const decision = rl.check("k", 2_000);
    expect(decision.allowed).toBe(false);
    expect(decision.retryAfterMs).toBeGreaterThanOrEqual(0);
    expect(decision.retryAfterMs).toBeLessThanOrEqual(60_000);
  });
});

// ── OpenRouter Budget Gate ──────────────────────────────────────────────────

describe("OpenRouterBudgetGate", () => {
  function makeGate(fetchFn: jest.Mock, opts?: { threshold?: number; failOpen?: boolean }) {
    return new OpenRouterBudgetGate({
      managementKey: "k",
      threshold: opts?.threshold ?? 1,
      failOpen: opts?.failOpen ?? false,
      fetchFn: fetchFn as unknown as FetchLike,
    });
  }

  test("parses total_credits − total_usage as remaining", async () => {
    const result = await makeGate(mockFetchCredits(20, 7)).getCreditsBalance();
    expect(result.remaining).toBe(13);
    expect(result.cached).toBe(false);
  });

  test("caches the balance within TTL (single fetch across two probes)", async () => {
    const fetchFn = mockFetchCredits(20, 5);
    const gate = makeGate(fetchFn);
    await gate.getCreditsBalance(1000);
    const second = await gate.getCreditsBalance(2000);
    expect(second.cached).toBe(true);
    expect(fetchFn).toHaveBeenCalledTimes(1);
  });

  test("re-fetches after TTL expires", async () => {
    const fetchFn = mockFetchCredits(20, 5);
    const gate = makeGate(fetchFn);
    await gate.getCreditsBalance(1000);
    await gate.getCreditsBalance(1000 + OpenRouterBudgetGate.CACHE_TTL_MS + 1);
    expect(fetchFn).toHaveBeenCalledTimes(2);
  });

  test("shouldGate=true when remaining < threshold", async () => {
    const decision = await makeGate(mockFetchCredits(10, 9.5)).shouldGate();
    expect(decision.gated).toBe(true);
    expect(decision.reason).toBe(GATE_REASONS.BUDGET_THRESHOLD);
  });

  test("shouldGate=false when remaining ≥ threshold", async () => {
    const decision = await makeGate(mockFetchCredits(10, 1)).shouldGate();
    expect(decision.gated).toBe(false);
    expect(decision.remaining).toBe(9);
  });

  test("fail-closed by default when /credits is unreachable", async () => {
    const decision = await makeGate(mockFetchReject()).shouldGate();
    expect(decision.gated).toBe(true);
    expect(decision.reason).toBe(GATE_REASONS.PROBE_FAIL_CLOSED);
  });

  test("fail-open when OPENROUTER_BUDGET_FAIL_OPEN=true", async () => {
    const decision = await makeGate(mockFetchReject(), { failOpen: true }).shouldGate();
    expect(decision.gated).toBe(false);
    expect(decision.reason).toBe(GATE_REASONS.PROBE_FAIL_OPEN);
  });
});

// ── Webhook handler integration: rate-limit + budget gate ───────────────────

describe("Webhook handler — guardrails", () => {
  const SECRET = "guardrail-test-secret-32-chars-long";

  function postSigned(
    port: number,
    body: string,
    sig: string
  ): Promise<{ status: number; body: string }> {
    return new Promise((resolve, reject) => {
      const req = http.request(
        {
          hostname: "127.0.0.1",
          port,
          path: "/webhook",
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Content-Length": Buffer.byteLength(body),
            "x-signature-256": sig,
          },
        },
        (res) => {
          const chunks: Buffer[] = [];
          res.on("data", (c) => chunks.push(c));
          res.on("end", () =>
            resolve({ status: res.statusCode ?? 0, body: Buffer.concat(chunks).toString("utf8") })
          );
        }
      );
      req.on("error", reject);
      req.write(body);
      req.end();
    });
  }

  function startServer(opts: {
    rateLimiter?: RateLimiter;
    budgetGate?: OpenRouterBudgetGate;
  }): Promise<{ server: http.Server; port: number }> {
    const server = createServer({ webhookSecret: SECRET, ...opts });
    return new Promise((resolve) => {
      server.listen(0, "127.0.0.1", () => {
        const addr = server.address();
        const port = typeof addr === "object" && addr ? addr.port : 0;
        resolve({ server, port });
      });
    });
  }

  function stopServer(server: http.Server): Promise<void> {
    return new Promise((resolve) => server.close(() => resolve()));
  }

  function makeBudgetGate(fetchFn: jest.Mock, opts?: { threshold?: number; failOpen?: boolean }) {
    return new OpenRouterBudgetGate({
      managementKey: "k",
      threshold: opts?.threshold ?? 1,
      failOpen: opts?.failOpen ?? false,
      fetchFn: fetchFn as unknown as FetchLike,
    });
  }

  test("21st request within 60s returns 429", async () => {
    const rl = new RateLimiter({ windowMs: 60_000, max: 20 });
    const budget = makeBudgetGate(mockFetchCredits(100, 0), { threshold: 0, failOpen: true });
    const { server, port } = await startServer({ rateLimiter: rl, budgetGate: budget });
    try {
      const body = JSON.stringify({ intent: "ping health", timestamp: "t" });
      const sig = generateSignature(body, SECRET);
      for (let i = 0; i < 20; i++) {
        const r = await postSigned(port, body, sig);
        expect(r.status).toBe(200);
      }
      const blocked = await postSigned(port, body, sig);
      expect(blocked.status).toBe(429);
      expect(blocked.body).toContain("Rate limit exceeded");
    } finally {
      await stopServer(server);
    }
  });

  test("budget-gated skill returns pending_approval when remaining < threshold", async () => {
    const rl = new RateLimiter({ windowMs: 60_000, max: 100 });
    const budget = makeBudgetGate(mockFetchCredits(10, 9), { threshold: 5 });
    const { server, port } = await startServer({ rateLimiter: rl, budgetGate: budget });
    try {
      const body = JSON.stringify({ intent: "summarize using llm", timestamp: "t" });
      const r = await postSigned(port, body, generateSignature(body, SECRET));
      expect(r.status).toBe(200);
      const parsed = JSON.parse(r.body);
      expect(parsed.skill).toBe("openrouter-infer");
      expect(parsed.status).toBe("pending_approval");
      expect(parsed.reason).toBe(GATE_REASONS.BUDGET_THRESHOLD);
    } finally {
      await stopServer(server);
    }
  });

  test("budget-gated skill returns pending_approval with probe_failed_fail_closed when /credits probe rejects", async () => {
    const rl = new RateLimiter({ windowMs: 60_000, max: 100 });
    const budget = makeBudgetGate(mockFetchReject());
    const { server, port } = await startServer({ rateLimiter: rl, budgetGate: budget });
    try {
      const body = JSON.stringify({ intent: "summarize using llm", timestamp: "t" });
      const r = await postSigned(port, body, generateSignature(body, SECRET));
      expect(r.status).toBe(200);
      const parsed = JSON.parse(r.body);
      expect(parsed.skill).toBe("openrouter-infer");
      expect(parsed.status).toBe("pending_approval");
      expect(parsed.reason).toBe(GATE_REASONS.PROBE_FAIL_CLOSED);
    } finally {
      await stopServer(server);
    }
  });

  test("budget-gated skill routes autonomously when balance ≥ threshold", async () => {
    const rl = new RateLimiter({ windowMs: 60_000, max: 100 });
    const budget = makeBudgetGate(mockFetchCredits(100, 0));
    const { server, port } = await startServer({ rateLimiter: rl, budgetGate: budget });
    try {
      const body = JSON.stringify({ intent: "summarize using llm", timestamp: "t" });
      const r = await postSigned(port, body, generateSignature(body, SECRET));
      expect(r.status).toBe(200);
      const parsed = JSON.parse(r.body);
      expect(parsed.skill).toBe("openrouter-infer");
      expect(parsed.status).toBeUndefined();
      expect(parsed.matched).toBe(true);
    } finally {
      await stopServer(server);
    }
  });

  test("non-budget-gated skill is unaffected by /credits probe", async () => {
    const rl = new RateLimiter({ windowMs: 60_000, max: 100 });
    const fetchFn = jest.fn();
    const budget = makeBudgetGate(fetchFn);
    const { server, port } = await startServer({ rateLimiter: rl, budgetGate: budget });
    try {
      const body = JSON.stringify({ intent: "ping health status", timestamp: "t" });
      const r = await postSigned(port, body, generateSignature(body, SECRET));
      expect(r.status).toBe(200);
      const parsed = JSON.parse(r.body);
      expect(parsed.skill).toBe("health-check");
      expect(fetchFn).not.toHaveBeenCalled();
    } finally {
      await stopServer(server);
    }
  });
});

// ── n8n workflow files ──────────────────────────────────────────────────────

describe("n8n workflow files", () => {
  const WORKFLOW_DIR = path.join(__dirname, "..", "..", "n8n", "workflows");

  // Counterpart to the prefix-agreement test below: evaluates the *body* of an n8n
  // Code node in a sandbox so R-09 trust-boundary branches (chat.id whitelist,
  // malformed callback_data, length ceiling) are asserted directly, not just by
  // cross-workflow string match.
  function evalNodeJsCode(
    workflowFile: string,
    nodeId: string,
    ctx: { input: unknown; env?: Record<string, string> },
  ): unknown {
    const wf = JSON.parse(fs.readFileSync(path.join(WORKFLOW_DIR, workflowFile), "utf8"));
    const node = (wf.nodes as { id: string; parameters?: { jsCode?: string } }[]).find(
      (n) => n.id === nodeId,
    );
    if (!node?.parameters?.jsCode) {
      throw new Error(`node ${nodeId} not found or has no jsCode in ${workflowFile}`);
    }
    const $input = { first: () => ctx.input };
    const $env: Record<string, string> = ctx.env ?? {};
    const fn = new Function("$input", "$env", "Buffer", "require", node.parameters.jsCode);
    return fn($input, $env, Buffer, require);
  }

  function makeCallbackUpdate(data: string, chatId: number) {
    return {
      json: {
        callback_query: {
          id: "cb-1",
          data,
          message: { chat: { id: chatId }, message_id: 9 },
        },
      },
    };
  }

  test("openrouter-infer.json is valid JSON", () => {
    const file = path.join(WORKFLOW_DIR, "openrouter-infer.json");
    const content = fs.readFileSync(file, "utf8");
    const parsed = JSON.parse(content);
    expect(parsed).toBeDefined();
  });

  test("openrouter-infer.json mirrors canonical workflow shape (ADR-0003)", () => {
    const file = path.join(WORKFLOW_DIR, "openrouter-infer.json");
    const wf = JSON.parse(fs.readFileSync(file, "utf8"));
    expect(Array.isArray(wf.nodes)).toBe(true);
    expect(wf.nodes.length).toBeGreaterThan(0);
    expect(typeof wf.connections).toBe("object");
    expect(wf.settings?.callerPolicy).toBe("workflowsFromSameOwner");
  });

  test("openrouter-infer.json signs Skills Router calls per ADR-0003", () => {
    const raw = fs.readFileSync(path.join(WORKFLOW_DIR, "openrouter-infer.json"), "utf8");
    expect(raw).toContain("x-signature-256");
    expect(raw).toContain("SKILLS_ROUTER_SECRET");
  });

  test("create-adr.json is valid JSON", () => {
    const file = path.join(WORKFLOW_DIR, "create-adr.json");
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    expect(parsed).toBeDefined();
    expect(Array.isArray(parsed.nodes)).toBe(true);
  });

  test("create-adr.json signs Skills Router calls per ADR-0003", () => {
    const raw = fs.readFileSync(path.join(WORKFLOW_DIR, "create-adr.json"), "utf8");
    expect(raw).toContain("x-signature-256");
    expect(raw).toContain("SKILLS_ROUTER_SECRET");
    expect(raw).toContain("CREATE_ADR_WEBHOOK_SECRET");
  });

  test("create-adr.json no longer returns the stub response", () => {
    const raw = fs.readFileSync(path.join(WORKFLOW_DIR, "create-adr.json"), "utf8");
    expect(raw).not.toContain('"status": "stub"');
    expect(raw).not.toContain("workflow not yet implemented");
  });

  test("github-pr.json is valid JSON", () => {
    const file = path.join(WORKFLOW_DIR, "github-pr.json");
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    expect(parsed).toBeDefined();
    expect(Array.isArray(parsed.nodes)).toBe(true);
  });

  test("github-pr.json signs Skills Router calls per ADR-0003", () => {
    const raw = fs.readFileSync(path.join(WORKFLOW_DIR, "github-pr.json"), "utf8");
    expect(raw).toContain("x-signature-256");
    expect(raw).toContain("SKILLS_ROUTER_SECRET");
    expect(raw).toContain("GITHUB_PR_WEBHOOK_SECRET");
  });

  test("github-pr.json no longer returns the stub response", () => {
    const raw = fs.readFileSync(path.join(WORKFLOW_DIR, "github-pr.json"), "utf8");
    expect(raw).not.toContain('"status": "stub"');
    expect(raw).not.toContain("workflow not yet implemented");
  });

  test("deploy-railway.json is valid JSON", () => {
    const file = path.join(WORKFLOW_DIR, "deploy-railway.json");
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    expect(parsed).toBeDefined();
    expect(Array.isArray(parsed.nodes)).toBe(true);
  });

  test("deploy-railway.json signs Skills Router calls per ADR-0003", () => {
    const raw = fs.readFileSync(path.join(WORKFLOW_DIR, "deploy-railway.json"), "utf8");
    expect(raw).toContain("x-signature-256");
    expect(raw).toContain("SKILLS_ROUTER_SECRET");
    expect(raw).toContain("DEPLOY_RAILWAY_WEBHOOK_SECRET");
  });

  test("deploy-railway.json no longer returns the stub response", () => {
    const raw = fs.readFileSync(path.join(WORKFLOW_DIR, "deploy-railway.json"), "utf8");
    expect(raw).not.toContain('"status": "stub"');
    expect(raw).not.toContain("workflow not yet implemented");
  });

  test("destroy-resource.json is valid JSON", () => {
    const file = path.join(WORKFLOW_DIR, "destroy-resource.json");
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    expect(parsed).toBeDefined();
    expect(Array.isArray(parsed.nodes)).toBe(true);
  });

  test("destroy-resource.json signs Skills Router calls per ADR-0003", () => {
    const raw = fs.readFileSync(path.join(WORKFLOW_DIR, "destroy-resource.json"), "utf8");
    expect(raw).toContain("x-signature-256");
    expect(raw).toContain("SKILLS_ROUTER_SECRET");
    expect(raw).toContain("DESTROY_RESOURCE_WEBHOOK_SECRET");
  });

  test("destroy-resource.json no longer returns the stub response", () => {
    const raw = fs.readFileSync(path.join(WORKFLOW_DIR, "destroy-resource.json"), "utf8");
    expect(raw).not.toContain('"status": "stub"');
    expect(raw).not.toContain("workflow not yet implemented");
  });

  test("approval-callback.json is valid JSON and uses a Telegram Trigger", () => {
    const file = path.join(WORKFLOW_DIR, "approval-callback.json");
    const wf = JSON.parse(fs.readFileSync(file, "utf8"));
    expect(Array.isArray(wf.nodes)).toBe(true);
    const triggerNodes = wf.nodes.filter(
      (n: { type?: string }) => n.type === "n8n-nodes-base.telegramTrigger",
    );
    expect(triggerNodes.length).toBeGreaterThan(0);
  });

  test("destroy-resource.json and approval-callback.json agree on callback_data prefix (ADR-0005)", () => {
    const dr = fs.readFileSync(path.join(WORKFLOW_DIR, "destroy-resource.json"), "utf8");
    const ac = fs.readFileSync(path.join(WORKFLOW_DIR, "approval-callback.json"), "utf8");
    for (const prefix of ["dr:a:rs:", "dr:d:rs:"]) {
      expect(dr).toContain(prefix);
      expect(ac).toContain(prefix);
    }
  });

  test("approval-callback.json validate-and-parse: missing TELEGRAM_CHAT_ID throws (R-09 fail-closed)", () => {
    expect(() =>
      evalNodeJsCode("approval-callback.json", "validate-and-parse", {
        input: makeCallbackUpdate("dr:a:rs:svc-abc", 123),
        env: {},
      }),
    ).toThrow(/TELEGRAM_CHAT_ID/);
  });

  test("approval-callback.json validate-and-parse: chat.id mismatch returns _action='unauthorized'", () => {
    const result = evalNodeJsCode("approval-callback.json", "validate-and-parse", {
      input: makeCallbackUpdate("dr:a:rs:svc-abc", 999),
      env: { TELEGRAM_CHAT_ID: "123" },
    }) as { json: { _action: string } }[];
    expect(result[0].json._action).toBe("unauthorized");
  });

  test("approval-callback.json validate-and-parse: malformed callback_data returns _action='unknown'", () => {
    const result = evalNodeJsCode("approval-callback.json", "validate-and-parse", {
      input: makeCallbackUpdate("garbage:not:a:command", 123),
      env: { TELEGRAM_CHAT_ID: "123" },
    }) as { json: { _action: string } }[];
    expect(result[0].json._action).toBe("unknown");
  });

  test("destroy-resource.json validate-and-extract: resource_id > 48 chars throws (callback_data 64-byte cap)", () => {
    const body = {
      resource_type: "railway-service",
      resource_id: "x".repeat(49),
      reason: "test",
    };
    const rawBody = JSON.stringify(body);
    const secret = "test-webhook-secret";
    const input = {
      headers: { "x-signature-256": generateSignature(rawBody, secret) },
      json: body,
    };
    expect(() =>
      evalNodeJsCode("destroy-resource.json", "validate-and-extract", {
        input,
        env: { DESTROY_RESOURCE_WEBHOOK_SECRET: secret },
      }),
    ).toThrow(/exceeds 48-char/);
  });

  test("every skill.n8n_webhook path is served by some workflow file", () => {
    const skills = discoverSkills().filter(
      (s) => s.n8n_webhook && s.name !== "skill-name",
    );
    const declaredPaths = new Set<string>();
    for (const file of fs.readdirSync(WORKFLOW_DIR)) {
      if (!file.endsWith(".json")) continue;
      const wf = JSON.parse(fs.readFileSync(path.join(WORKFLOW_DIR, file), "utf8"));
      for (const node of wf.nodes ?? []) {
        if (node.type === "n8n-nodes-base.webhook" && node.parameters?.path) {
          declaredPaths.add(`/webhook/${node.parameters.path}`);
        }
      }
    }
    const missing = skills
      .filter((s) => !declaredPaths.has(s.n8n_webhook!))
      .map((s) => `${s.name} → ${s.n8n_webhook}`);
    expect(missing).toEqual([]);
  });

  test("every workflow filename matches its inner webhook path (naming convention)", () => {
    const mismatches: string[] = [];
    for (const file of fs.readdirSync(WORKFLOW_DIR)) {
      if (!file.endsWith(".json")) continue;
      const expected = file.replace(/\.json$/, "");
      const wf = JSON.parse(fs.readFileSync(path.join(WORKFLOW_DIR, file), "utf8"));
      const webhookNodes = (wf.nodes ?? []).filter(
        (n: { type?: string }) => n.type === "n8n-nodes-base.webhook",
      );
      for (const node of webhookNodes) {
        const declared = node.parameters?.path;
        if (declared !== expected) {
          mismatches.push(`${file} declares path=${declared} (expected ${expected})`);
        }
      }
    }
    expect(mismatches).toEqual([]);
  });
});
