export default {
  async fetch(request, env, ctx) {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      // 1. Grab payload from Safaricom
      const requestBody = await request.text();
      console.log("1. Received payload from Daraja:", requestBody);
      
      // 2. Your exact IDs
      const appwriteProjectID = "fra-69a53fb00009c20573d6"; 
      const appwriteFunctionID = "69a7f6ca00157f5ebd2d";
      
      // 3. The actual Appwrite REST API Endpoint
      const appwriteEndpoint = `https://cloud.appwrite.io/v1/functions/${appwriteFunctionID}/executions`;
      console.log("2. Forwarding to:", appwriteEndpoint);

      // 4. Send to Appwrite
      const appwriteResponse = await fetch(appwriteEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Appwrite-Project": appwriteProjectID,
        },
        body: JSON.stringify({
          body: requestBody,
          method: "POST",
          path: "/",
          async: false
        })
      });

      const responseText = await appwriteResponse.text();
      console.log(`3. Appwrite Response (${appwriteResponse.status}):`, responseText);

      // 5. Tell Safaricom we received it
      return new Response(JSON.stringify({ "ResultCode": 0, "ResultDesc": "Success" }), { 
        status: 200,
        headers: { "Content-Type": "application/json" }
      });

    } catch (error) {
      console.error("Worker Error:", error);
      return new Response("Error caught, but acknowledged", { status: 200 });
    }
  }
};