// 1. Define your strict whitelists outside the fetch block for speed
const CORE_ALLOWED_PATHS = new Set([
  "/health",
  "/heartbeat/log",
  "/heartbeat/cleanup",
  "/heartbeat/list"
]);

const INTEGRATION_ALLOWED_PATHS = new Set([
  "/health",
  "/mpesa/callback",
  "/mpesa/stk-push",
  "/etims/submit",
  "/etims/query"
]);

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    const hostname = url.hostname;

    try {
      // Allow robots.txt to respond politely to Googlebot/ClaudeBot
      if (path === "/robots.txt") {
        return new Response("User-agent: *\nDisallow: /", { 
          status: 200, 
          headers: { "Content-Type": "text/plain" } 
        });
      }

      // Simulation trigger
      if (path.startsWith("/sim/")) {
        ctx.waitUntil(runSimulation(env));
        return new Response("Simulation triggered in background", { status: 202 });
      }

      // ─────────────────────────────────────────────
      // PRODUCTION DOMAIN ROUTING
      // ─────────────────────────────────────────────
      if (hostname === "api.33373984.xyz" || hostname === env.CORE_DOMAIN) {
        if (!CORE_ALLOWED_PATHS.has(path)) {
          return new Response("Forbidden: Endpoint not allowed", { status: 403 });
        }
        return await routeToFunction(request, env, env.CORE_FUNCTION_ID, "");
      }

      if (hostname === "akavango.33373984.xyz" || hostname === env.INTEGRATION_DOMAIN) {
        if (!INTEGRATION_ALLOWED_PATHS.has(path)) {
          return new Response("Forbidden: Endpoint not allowed", { status: 403 });
        }
        return await routeToFunction(request, env, env.INTEGRATION_FUNCTION_ID, "");
      }

      // ─────────────────────────────────────────────
      // FALLBACK PATH ROUTING (Local Dev / workers.dev)
      // ─────────────────────────────────────────────
      if (path.startsWith("/api/")) {
        const internalPath = path.replace("/api", "");
        if (!CORE_ALLOWED_PATHS.has(internalPath)) {
          return new Response("Forbidden: Endpoint not allowed", { status: 403 });
        }
        return await routeToFunction(request, env, env.CORE_FUNCTION_ID, "/api");
      }

      if (path.startsWith("/akavango/")) {
        const internalPath = path.replace("/akavango", "");
        if (!INTEGRATION_ALLOWED_PATHS.has(internalPath)) {
          return new Response("Forbidden: Endpoint not allowed", { status: 403 });
        }
        return await routeToFunction(request, env, env.INTEGRATION_FUNCTION_ID, "/akavango");
      }

      // Catch anything else (like random bot scans on root "/")
      return new Response("Not found", { status: 404 });

    } catch (err) {
      console.error("Proxy error:", err);
      return new Response("Internal proxy error", { status: 500 });
    }
  }
};

// ─────────────────────────────────────────────
// ROUTE TO APPWRITE FUNCTION
// ─────────────────────────────────────────────

async function routeToFunction(request, env, functionId, prefix) {
  const url = new URL(request.url);

  // If prefix is "", the whole path is sent to Appwrite. 
  // If prefix is "/api", it gets stripped out.
  const internalPath = prefix ? url.pathname.replace(prefix, "") : url.pathname;

const appwritePayload = {
    async: false,
    path: internalPath,
    method: request.method,
    headers: {
      ...Object.fromEntries(request.headers),
      "x-proxy-secret": env.FUNCTION_INTERNAL_KEY
    },
    data: await safeBody(request), // 🔴 CRITICAL: This must be 'data', not 'body'
  };

  const endpoint = `${env.APPWRITE_ENDPOINT}/functions/${functionId}/executions`;

  const res = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Appwrite-Project": env.APPWRITE_PROJECT_ID,
      "X-Appwrite-Key": env.APPWRITE_API_KEY,
    },
    body: JSON.stringify(appwritePayload), 
  });

  const result = await res.json();
  return unwrapExecutionResponse(result);
}

// ─────────────────────────────────────────────
// RESPONSE UNWRAP
// ─────────────────────────────────────────────
function unwrapExecutionResponse(result) {
  // Catch hard Appwrite API failures
  if (result.responseBody === undefined) {
    console.error("Appwrite API Call Failed!");
    return new Response(`Appwrite Gateway Error: ${result.message || "Unknown"}`, { 
      status: result.code || 502 
    });
  }

  let responseText = result.responseBody;

  // SMART DECODE: Attempt to Base64 decode, but safely fall back if it fails
  try {
    // If it clearly already looks like JSON, don't try to decode it
    if (typeof responseText === 'string' && !responseText.trim().startsWith('{') && !responseText.trim().startsWith('[')) {
      responseText = atob(responseText);
    }
  } catch (decodeError) {
    // atob() failed (meaning it wasn't Base64). 
    // We swallow the error and leave responseText exactly as Appwrite sent it.
  }

  try {
    // Parse the safely resolved string into a JSON object
    const body = JSON.parse(responseText);
    
    return new Response(JSON.stringify(body), {
      status: result.responseStatusCode || 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (parseError) {
    // Fallback: If it's valid text but NOT JSON (e.g., an HTML error page or raw string)
    console.error("JSON Parse Failed!");
    console.error("Raw responseText:", responseText);

    return new Response(responseText || "Invalid response format", {
      // Preserve Appwrite's original status code, default to 500 only if missing
      status: result.responseStatusCode || 500, 
    });
  }
}

// ─────────────────────────────────────────────
// SIMULATION
// ─────────────────────────────────────────────

async function runSimulation(env) {
  const base = env.PUBLIC_BASE_URL;

  await sleep(Math.random() * 30000);

  const roll = Math.random();

  try {
    if (roll < 0.5) {
      await fetch(`${base}/api/health`);
    } else if (roll < 0.8) {
      await fetch(`${base}/api/heartbeat/log`, { method: "POST" });
    } else {
      await fetch(`${base}/api/heartbeat/cleanup`, { method: "POST" });
    }
  } catch (err) {
    console.error("Simulation fetch error:", err);
  }
}

// ─────────────────────────────────────────────
// UTILS
// ─────────────────────────────────────────────

async function safeBody(request) {
  try {
    return await request.text();
  } catch {
    return "";
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}