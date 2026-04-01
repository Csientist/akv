# Akavango Proxy Worker

This Cloudflare Worker acts as a unified API gateway for Appwrite Functions.

## 🔧 Features

* **Domain-based routing (Production):**
    * `api.33373984.xyz` → Core API Function
    * `akavango.33373984.xyz` → Integration API Function
* **Path-based routing (Fallback/Dev):**
    * `/api/*` → Core API Function
    * `/akavango/*` → Integration API Function
* **Synthetic activity simulation:** Background execution (`/sim/*`) via `ctx.waitUntil` to prevent worker timeouts.
* Secure secret injection (no hardcoded configs).
* Appwrite Function execution wrapper.

---

## 📦 Requirements

* Cloudflare account
* Wrangler CLI installed
* Appwrite project with:
    * Core API function
    * Integration function

---

## 🔐 Setup Secrets

Run the following commands to securely inject your environment variables:

```bash
npx wrangler secret put APPWRITE_ENDPOINT
npx wrangler secret put APPWRITE_PROJECT_ID
npx wrangler secret put APPWRITE_API_KEY
npx wrangler secret put CORE_FUNCTION_ID
npx wrangler secret put INTEGRATION_FUNCTION_ID
npx wrangler secret put PUBLIC_BASE_URL
npx wrangler secret put CORE_DOMAIN
npx wrangler secret put INTEGRATION_DOMAIN
```

| Key | Description |
| :--- | :--- |
| **APPWRITE_ENDPOINT** | e.g., `https://fra.cloud.appwrite.io/v1` |
| **APPWRITE_PROJECT_ID** | Your Appwrite project ID |
| **APPWRITE_API_KEY** | Scoped API key |
| **CORE_FUNCTION_ID** | Core API function ID |
| **INTEGRATION_FUNCTION_ID** | Integration function ID |
| **PUBLIC_BASE_URL** | Your fallback/dev domain (e.g., `https://akavango-proxy.workers.dev`) |
| **CORE_DOMAIN** | Production domain for core API (e.g., `api.33373984.xyz`) |
| **INTEGRATION_DOMAIN** | Production domain for integration API (e.g., `akavango.33373984.xyz`) |

---

## 🚀 Usage

**Local Development**
Run a local server to test your path-based routing:

```bash
npx wrangler dev
```

**Deployment**
Deploy your Worker and bind it to your custom domains via Cloudflare:

```bash
npx wrangler deploy
```

> **Note:** Ensure your `custom_domains` are properly configured in your `wrangler.toml` before running the deployment command.