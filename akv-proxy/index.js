export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    try {
      if (path.startsWith("/api/")) {
        return await routeToFunction(request, env, env.CORE_FUNCTION_ID, "/api");
      }

      if (path.startsWith("/akavango/")) {
        return await routeToFunction(request, env, env.INTEGRATION_FUNCTION_ID, "/akavango");
      }

      if (path.startsWith("/sim/")) {
        await runSimulation(env);
        return new Response("Simulation triggered", { status: 200 });
      }

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

  const internalPath = url.pathname.replace(prefix, "");

  const payload = {
    path: internalPath,
    method: request.method,
    headers: Object.fromEntries(request.headers),
    body: await safeBody(request),
  };

  const endpoint = `${env.APPWRITE_ENDPOINT}/functions/${functionId}/executions`;

  const res = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Appwrite-Project": env.APPWRITE_PROJECT_ID,
      "X-Appwrite-Key": env.APPWRITE_API_KEY,
    },
    body: JSON.stringify({
      async: false,
      data: JSON.stringify(payload),
    }),
  });

  const result = await res.json();

  return unwrapExecutionResponse(result);
}

// ─────────────────────────────────────────────
// RESPONSE UNWRAP
// ─────────────────────────────────────────────

function unwrapExecutionResponse(result) {
  try {
    const body = JSON.parse(result.responseBody);

    return new Response(JSON.stringify(body), {
      status: result.responseStatusCode || 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch {
    return new Response(result.responseBody || "Invalid response", {
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

  if (roll < 0.5) {
    await fetch(`${base}/api/health`);
  } else if (roll < 0.8) {
    await fetch(`${base}/api/heartbeat/log`, { method: "POST" });
  } else {
    await fetch(`${base}/api/heartbeat/cleanup`, { method: "POST" });
  }
}

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