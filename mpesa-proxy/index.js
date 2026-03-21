export default {
  async fetch(request, env, ctx) {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      const requestBody = await request.text();
      console.log("[proxy] received payload from Daraja:", requestBody);

      const appwriteProjectID = env.AKAVANGO_API_PROJECT_ID
      // akavango-api function ID — update this after deploying the new function
      const appwriteFunctionID = env.AKAVANGO_API_FUNCTION_ID;
      const appwriteEndpoint = `https://fra.cloud.appwrite.io/v1/functions/${appwriteFunctionID}/executions`;

      console.log("[proxy] forwarding to:", appwriteEndpoint);

      const appwriteResponse = await fetch(appwriteEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Appwrite-Project": appwriteProjectID,
          // No API key here — /mpesa/callback is a public route in the function
        },
        body: JSON.stringify({
          body: requestBody,
          method: "POST",
          path: new URL(request.url).pathname.replace(/^\/akavango/, "") || "/mpesa/callback",
          async: true               // fire-and-forget; we ack Safaricom immediately
        })
      });

      console.log(`[proxy] Appwrite status: ${appwriteResponse.status}`);

    } catch (error) {
      // Log but never let Safaricom see a 5xx — they will retry aggressively
      console.error("[proxy] error:", error);
    }

    // Always ack Safaricom
    return new Response(JSON.stringify({ "ResultCode": 0, "ResultDesc": "Success" }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  }
};