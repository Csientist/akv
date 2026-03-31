# Akavango Proxy Worker

This Cloudflare Worker acts as a unified API gateway for Appwrite Functions.

## 🔧 Features

- Path-based routing:
  - `/api/*` → Core API
  - `/akavango/*` → Integration API
  - `/sim/*` → Simulation trigger
- Secure secret injection (no hardcoded configs)
- Appwrite Function execution wrapper
- Synthetic activity simulation

---

## 📦 Requirements

- Cloudflare account
- Wrangler CLI installed
- Appwrite project with:
  - Core API function
  - Integration function

---

## 🔐 Setup Secrets

Run the following:

```bash
npx wrangler secret put APPWRITE_ENDPOINT
npx wrangler secret put APPWRITE_PROJECT_ID
npx wrangler secret put APPWRITE_API_KEY
npx wrangler secret put CORE_FUNCTION_ID
npx wrangler secret put INTEGRATION_FUNCTION_ID
npx wrangler secret put PUBLIC_BASE_URL


| Key                     | Description                                                               |
| ----------------------- | ------------------------------------------------------------------------- |
| APPWRITE_ENDPOINT       | e.g. [https://fra.cloud.appwrite.io/v1]                                   |
| APPWRITE_PROJECT_ID     | Your Appwrite project ID                                                  |
| APPWRITE_API_KEY        | Scoped API key                                                            |
| CORE_FUNCTION_ID        | Core API function ID                                                      |
| INTEGRATION_FUNCTION_ID | Integration function ID                                                   |
| PUBLIC_BASE_URL         | Your domain (e.g. [https://33373984.xyz])                                 |
