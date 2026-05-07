/**
 * Cloudflare Worker — Edge Router
 *
 * Lightweight edge router that proxies requests to the Railway Skills Router.
 * Deployed via wrangler-action in .github/workflows/deploy.yml.
 * API token is never stored here — injected at deploy time from GCP Secret Manager.
 */

addEventListener("fetch", (event) => {
  event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
  const url = new URL(request.url);

  // Health check at edge
  if (url.pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok", layer: "edge" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Proxy all other requests to Railway origin
  // RAILWAY_ORIGIN is set via wrangler.toml [vars] — not a secret
  const origin = RAILWAY_ORIGIN ?? "https://your-railway-app.railway.app";
  const upstreamUrl = `${origin}${url.pathname}${url.search}`;

  const upstreamRequest = new Request(upstreamUrl, {
    method: request.method,
    headers: request.headers,
    body: request.method !== "GET" && request.method !== "HEAD" ? request.body : undefined,
  });

  try {
    const response = await fetch(upstreamRequest);
    return new Response(response.body, {
      status: response.status,
      headers: response.headers,
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Upstream unavailable" }),
      { status: 502, headers: { "Content-Type": "application/json" } }
    );
  }
}
