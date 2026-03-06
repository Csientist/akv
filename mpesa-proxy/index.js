export default {
  async fetch(request, env, ctx) {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      const requestBody = await request.text();
      
      const appwriteProjectID = "YOUR_APPWRITE_PROJECT_ID";
      const appwriteFunctionID = "YOUR_CALLBACK_FUNCTION_ID";
      const appwriteEndpoint = `https://cloud.appwrite.io/v1/functions/${appwriteFunctionID}/executions`;

      const appwriteResponse = await fetch(appwriteEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Appwrite-Project": appwriteProjectID,
        },
        body: JSON.stringify({
          data: requestBody 
        })
      });

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