// Cloudflare Worker — Safaricom M-PESA callback proxy
// Forwards Daraja STK callbacks to the akavango-api Appwrite Function
// at the /mpesa/callback route. Always acks Safaricom with 200 regardless
// of what Appwrite returns, so Safaricom never retries on our backend errors.

export default {
  async fetch(request, env, ctx) {
    const path = new URL(request.url).pathname.replace(/^\/akavango/, "") || "/";
    const method = request.method;

    // GET requests — forward directly to Appwrite (health check + future GET routes)
    if (method === "GET") {
      const appwriteFunctionID = env.AKAVANGO_API_FUNCTION_ID;
      const appwriteProjectID = env.AKAVANGO_API_PROJECT_ID;
      const appwriteEndpoint = `https://fra.cloud.appwrite.io/v1/functions/${appwriteFunctionID}/executions`;

      try {
        const appwriteResponse = await fetch(appwriteEndpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Appwrite-Project": appwriteProjectID,
          },
          body: JSON.stringify({
            body: "",
            method: "GET",
            path: path,
            async: false
          })
        });

        const result = await appwriteResponse.json();
        // Appwrite wraps the function response in an execution object
        const responseBody = result?.responseBody ?? result;
        return new Response(
          typeof responseBody === "string" ? responseBody : JSON.stringify(responseBody),
          { status: result?.responseStatusCode ?? 200, headers: { "Content-Type": "application/json" } }
        );
      } catch (error) {
        console.error("[proxy] GET error:", error);
        return new Response(JSON.stringify({ error: "proxy error" }), { status: 502 });
      }
    }

    // Only POST beyond this point
    if (method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      const requestBody = await request.text();
      console.log("[proxy] received payload:", requestBody);

      const appwriteFunctionID = env.AKAVANGO_API_FUNCTION_ID;
      const appwriteProjectID = env.AKAVANGO_API_PROJECT_ID;
      const appwriteEndpoint = `https://fra.cloud.appwrite.io/v1/functions/${appwriteFunctionID}/executions`;

      console.log("[proxy] forwarding to:", appwriteEndpoint, "path:", path);

      const appwriteResponse = await fetch(appwriteEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Appwrite-Project": appwriteProjectID,
          // No API key — /mpesa/callback is a public route in the function
        },
        body: JSON.stringify({
          body: requestBody,
          method: "POST",
          path: path,
          async: true  // fire-and-forget; we ack Safaricom immediately
        })
      });

      console.log(`[proxy] Appwrite status: ${appwriteResponse.status}`);

    } catch (error) {
      console.error("[proxy] error:", error);
    }

    // Always ack Safaricom with 200
    return new Response(JSON.stringify({ "ResultCode": 0, "ResultDesc": "Success" }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
  }
};