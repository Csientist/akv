***

# Akavango Integration API

This Appwrite Function (Go) handles the core financial integrations for Akavango, specifically managing M-PESA Daraja (payments) and KRA eTIMS (tax invoicing).

It is designed to sit behind a Cloudflare Worker proxy, utilizing Appwrite's native 1.4+ HTTP routing capabilities.

## 🏗 Architecture

* **Runtime:** Go (Appwrite `open-runtimes/types-for-go/v4`)
* **Security:** Protected routes require a custom `x-proxy-secret` header injected by the Cloudflare Worker to bypass Appwrite's native header scrubbing.
* **Timezones:** Hardcoded to East Africa Time (EAT, UTC+3) to satisfy strict KRA eTIMS and Safaricom Daraja timestamp requirements.

---

## 📍 Endpoints

### Public Routes
These routes do not require authentication headers.

* `GET /health`
    * Returns the operational status of the function.
* `POST /mpesa/callback`
    * **Webhook:** Safaricom Daraja callback URL.
    * Receives transaction success/failure payloads, updates the database, and returns a strict Daraja-compliant ACK response to prevent retry loops.

### Protected Routes
These routes *must* be called via the Cloudflare proxy to ensure the `x-proxy-secret` is injected.

* `POST /mpesa/stk-push`
    * **Payload:** `phone_number`, `amount`, `account_reference`
    * Triggers an M-PESA STK push to the user's phone.
* `POST /etims/submit`
    * **Payload:** `transaction_id`, `items[]`, `customer_pin` (optional B2B), `customer_name` (optional)
    * Fetches transaction details from the database, signs the payload with the CMC Key, submits the invoice to KRA OSCU, and saves the generated KRA Receipt/Serial to the database.
* `POST /etims/query`
    * **Payload:** `transaction_id`, `invoice_seq`
    * Queries KRA for the exact status of a previously submitted invoice (useful for timeout recovery/retry loops).

---

## 🔐 Environment Variables

This function relies on environment variables injected via the Appwrite Console. You must define these in your Appwrite project under **Functions > Settings > Variables**.

### Security & Database
| Variable | Description |
| :--- | :--- |
| `FUNCTION_INTERNAL_KEY` | Must match the Cloudflare proxy secret. |
| `APPWRITE_DB_ID` | The ID of your Akavango database. |
| `APPWRITE_TABLE_FINANCIALS` | The ID of the financial/transactions collection. |

*(Note: `APPWRITE_FUNCTION_API_ENDPOINT`, `APPWRITE_FUNCTION_PROJECT_ID`, and `APPWRITE_API_KEY` are automatically provided by the Appwrite runtime).*

### M-PESA Daraja
| Variable | Description |
| :--- | :--- |
| `MPESA_ENVIRONMENT` | Set to `sandbox` or `production`. |
| `MPESA_CONSUMER_KEY` | Safaricom App Consumer Key. |
| `MPESA_CONSUMER_SECRET`| Safaricom App Consumer Secret. |
| `MPESA_SHORTCODE` | Paybill or Till Number (e.g., `174379`). |
| `MPESA_PASSKEY` | STK Push Passkey provided by Safaricom. |
| `MPESA_CALLBACK_URL` | Your public Cloudflare endpoint (e.g., `https://akavango.yourdomain.xyz/mpesa/callback`). |

### KRA eTIMS
| Variable | Description |
| :--- | :--- |
| `ETIMS_ENVIRONMENT` | Set to `sandbox` or `production`. |
| `ETIMS_PIN` | The KRA PIN associated with the business. |
| `ETIMS_BRANCH_ID` | The 2-digit branch code (usually `00`). |
| `ETIMS_CMC_KEY` | The initialization signing key provided by KRA. |
| `ETIMS_DEVICE_SERIAL` | The OSCU Device Serial Number. |

---

## 🚀 Going to Production

This codebase is natively switchable. **Do not alter the Go code to go live.** When you are ready to switch from sandbox testing to live customer transactions:
1. Navigate to the **Appwrite Console**.
2. Go to **Functions** -> Select this Integration Function -> **Settings**.
3. Under **Variables**, change `MPESA_ENVIRONMENT` to `production`.
4. Change `ETIMS_ENVIRONMENT` to `production`.
5. Replace your Sandbox Consumer Keys, Passkeys, and eTIMS CMC Keys with your Live Production credentials.
6. Click Save. The next request will instantly route to the live Safaricom and KRA APIs.