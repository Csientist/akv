package handler

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/open-runtimes/types-for-go/v4/openruntimes"
)

// ── Incoming payload from Flutter ─────────────────────────────────────────────

type RequestPayload struct {
	PhoneNumber string `json:"phone_number"`
	Amount      int    `json:"amount"`
	AccountRef  string `json:"account_reference"`
}

// ── Safaricom STK response ────────────────────────────────────────────────────

type STKResponse struct {
	MerchantRequestID   string `json:"MerchantRequestID"`
	CheckoutRequestID   string `json:"CheckoutRequestID"`
	ResponseCode        string `json:"ResponseCode"`
	ResponseDescription string `json:"ResponseDescription"`
	CustomerMessage     string `json:"CustomerMessage"`
	RequestID           string `json:"requestId"`
	ErrorCode           string `json:"errorCode"`
	ErrorMessage        string `json:"errorMessage"`
}

// ── Response helper ───────────────────────────────────────────────────────────
// The openruntimes Response struct takes []byte Body and int StatusCode directly.
// There is no functional-options pattern — we build the response struct fields.

func jsonResponse(Context openruntimes.Context, status int, data map[string]interface{}) openruntimes.Response {
	body, err := json.Marshal(data)
	if err != nil {
		// Fallback — should never happen with a simple map
		body = []byte(`{"error":"internal serialisation error"}`)
	}
	res := Context.Res.Json(body)
	res.StatusCode = status
	return res
}

// ── Main ──────────────────────────────────────────────────────────────────────

func Main(Context openruntimes.Context) openruntimes.Response {

	// 1. Parse payload
	var req RequestPayload
	if err := json.Unmarshal([]byte(Context.Req.BodyRaw()), &req); err != nil {
		return jsonResponse(Context, 400, map[string]interface{}{
			"error": "Invalid payload: " + err.Error(),
		})
	}
	// 2. Validate payload
	if req.PhoneNumber == "" || req.AccountRef == "" {
		return jsonResponse(Context, 400, map[string]interface{}{
			"error": "phone_number and account_reference are required",
		})
	}
	if req.Amount < 1 {
		return jsonResponse(Context, 400, map[string]interface{}{
			"error": "amount must be at least KES 1",
		})
	}

	// 3. Sanitize phone → 254XXXXXXXXX
	phone, err := sanitizePhone(req.PhoneNumber)
	if err != nil {
		return jsonResponse(Context, 400, map[string]interface{}{
			"error": err.Error(),
		})
	}

	// 4. Load and validate env vars
	consumerKey := os.Getenv("MPESA_CONSUMER_KEY")
	consumerSecret := os.Getenv("MPESA_CONSUMER_SECRET")
	shortcode := os.Getenv("MPESA_SHORTCODE")
	passkey := os.Getenv("MPESA_PASSKEY")
	callbackURL := os.Getenv("MPESA_CALLBACK_URL")
	environment := os.Getenv("MPESA_ENVIRONMENT") // "sandbox" | "production"

	if consumerKey == "" || consumerSecret == "" || shortcode == "" || passkey == "" || callbackURL == "" {
		Context.Error("Missing required M-PESA environment variables")
		return jsonResponse(Context, 500, map[string]interface{}{
			"error": "Server misconfiguration — missing M-PESA credentials",
		})
	}

	baseURL := darajaBaseURL(environment)

	// 5. Get Daraja access token
	token, err := getAccessToken(consumerKey, consumerSecret, baseURL)
	if err != nil {
		Context.Error("Token fetch failed: " + err.Error())
		return jsonResponse(Context, 500, map[string]interface{}{
			"error": "M-PESA auth failed",
		})
	}

	// 6. Build STK Push password + timestamp
	timestamp := time.Now().Format("20060102150405")
	password := base64.StdEncoding.EncodeToString([]byte(shortcode + passkey + timestamp))

	// 7. Build STK Push payload
	stkPayload := map[string]interface{}{
		"BusinessShortCode": shortcode,
		"Password":          password,
		"Timestamp":         timestamp,
		"TransactionType":   "CustomerPayBillOnline",
		"Amount":            req.Amount,
		"PartyA":            phone,
		"PartyB":            shortcode,
		"PhoneNumber":       phone,
		"CallBackURL":       callbackURL,
		"AccountReference":  req.AccountRef,
		"TransactionDesc":   "Farm Manager Payment",
	}

	payloadBytes, err := json.Marshal(stkPayload)
	if err != nil {
		Context.Error("Failed to marshal STK payload: " + err.Error())
		return jsonResponse(Context, 500, map[string]interface{}{
			"error": "Internal error building request",
		})
	}

	// 8. Fire STK Push
	stkURL := baseURL + "/mpesa/stkpush/v1/processrequest"
	httpReq, _ := http.NewRequest("POST", stkURL, bytes.NewBuffer(payloadBytes))
	httpReq.Header.Set("Authorization", "Bearer "+token)
	httpReq.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		Context.Error("STK Push HTTP error: " + err.Error())
		return jsonResponse(Context, 502, map[string]interface{}{
			"error": "Failed to reach M-PESA — try again",
		})
	}
	defer func(Body io.ReadCloser) {
		err := Body.Close()
		if err != nil {

		}
	}(resp.Body)

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		Context.Error("Failed to read STK response: " + err.Error())
		return jsonResponse(Context, 500, map[string]interface{}{
			"error": "Failed to read M-PESA response",
		})
	}

	// 9. Parse Safaricom response
	var stkResp STKResponse
	if err := json.Unmarshal(body, &stkResp); err != nil {
		Context.Error("Failed to parse STK response: " + err.Error())
		return jsonResponse(Context, 500, map[string]interface{}{
			"error": "Unexpected response from M-PESA",
			"raw":   string(body),
		})
	}

	// 10. Return clean response to Flutter
	if stkResp.ResponseCode == "0" {
		return jsonResponse(Context, 200, map[string]interface{}{
			"success":             true,
			"checkout_request_id": stkResp.CheckoutRequestID,
			"merchant_request_id": stkResp.MerchantRequestID,
			"customer_message":    stkResp.CustomerMessage,
		})
	}

	// Safaricom returned a business error
	errMsg := stkResp.ErrorMessage
	if errMsg == "" {
		errMsg = stkResp.ResponseDescription
	}
	Context.Error(fmt.Sprintf("Safaricom rejected STK: %s (code: %s)", errMsg, stkResp.ErrorCode))
	return jsonResponse(Context, 400, map[string]interface{}{
		"success": false,
		"error":   errMsg,
		"code":    stkResp.ErrorCode,
	})
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func sanitizePhone(raw string) (string, error) {
	cleaned := regexp.MustCompile(`[\s\-\(\)]`).ReplaceAllString(raw, "")

	switch {
	case strings.HasPrefix(cleaned, "+254"):
		cleaned = cleaned[1:]
	case strings.HasPrefix(cleaned, "0"):
		cleaned = "254" + cleaned[1:]
	case strings.HasPrefix(cleaned, "254"):
		// already correct
	default:
		return "", fmt.Errorf("unrecognised phone format: %s", raw)
	}

	if matched, _ := regexp.MatchString(`^254\d{9}$`, cleaned); !matched {
		return "", fmt.Errorf("invalid Kenyan phone number: %s", raw)
	}
	return cleaned, nil
}

func darajaBaseURL(env string) string {
	if env == "production" {
		return "https://api.safaricom.co.ke"
	}
	return "https://sandbox.safaricom.co.ke"
}

func getAccessToken(key, secret, baseURL string) (string, error) {
	url := baseURL + "/oauth/v1/generate?grant_type=client_credentials"

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return "", fmt.Errorf("failed to build token request: %w", err)
	}
	req.Header.Set("Authorization", "Basic "+
		base64.StdEncoding.EncodeToString([]byte(key+":"+secret)))

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("token request failed: %w", err)
	}
	defer func(Body io.ReadCloser) {
		err := Body.Close()
		if err != nil {

		}
	}(resp.Body)

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("failed to decode token response: %w", err)
	}

	token, ok := result["access_token"].(string)
	if !ok || token == "" {
		errMsg, _ := result["errorMessage"].(string)
		return "", fmt.Errorf("no access token returned: %s", errMsg)
	}
	return token, nil
}
