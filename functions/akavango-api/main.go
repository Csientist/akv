package handler

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/appwrite/sdk-for-go/appwrite"
	"github.com/appwrite/sdk-for-go/models"
	"github.com/appwrite/sdk-for-go/query"
	"github.com/appwrite/sdk-for-go/tablesdb"
	"github.com/open-runtimes/types-for-go/v4/openruntimes"
)

// ── Router ────────────────────────────────────────────────────────────────────

func Main(Context openruntimes.Context) openruntimes.Response {
	path := Context.Req.Path
	method := Context.Req.Method

	Context.Log(fmt.Sprintf("[akavango-api] %s %s", method, path))

	// Public routes — no auth check (Safaricom calls these)
	if path == "/mpesa/callback" && method == "POST" {
		return handleMpesaCallback(Context)
	}

	// Health check — public
	if path == "/health" {
		return jsonOK(Context, map[string]interface{}{"status": "ok", "ts": time.Now().UTC().Format(time.RFC3339)})
	}

	// All other routes require a valid Appwrite API key
	if !isAuthorized(Context) {
		return jsonErr(Context, 401, "unauthorised")
	}

	switch {
	case path == "/mpesa/stk-push" && method == "POST":
		return handleStkPush(Context)
	case path == "/etims/submit" && method == "POST":
		return handleEtimsSubmit(Context)
	case path == "/etims/query" && method == "POST":
		return handleEtimsQuery(Context)
	default:
		return jsonErr(Context, 404, fmt.Sprintf("no route for %s %s", method, path))
	}
}

// isAuthorized checks for a matching Appwrite API key in the request headers.
// Flutter calls arrive with the key set by AppwriteClient; Safaricom callbacks
// do not — those routes bypass this check above.
func isAuthorized(Context openruntimes.Context) bool {
	expected := os.Getenv("APPWRITE_API_KEY")
	if expected == "" {
		return false
	}
	got := Context.Req.Headers["x-appwrite-key"]
	return got == expected
}

// ── Shared response helpers ───────────────────────────────────────────────────

func jsonOK(Context openruntimes.Context, data map[string]interface{}) openruntimes.Response {
	return jsonResp(Context, 200, data)
}

func jsonErr(Context openruntimes.Context, status int, msg string) openruntimes.Response {
	return jsonResp(Context, status, map[string]interface{}{"error": msg})
}

func jsonResp(Context openruntimes.Context, status int, data map[string]interface{}) openruntimes.Response {
	body, _ := json.Marshal(data)
	res := Context.Res.Json(body)
	res.StatusCode = status
	return res
}

// ── Appwrite DB client ────────────────────────────────────────────────────────

func newDB() (*tablesdb.TablesDB, string, string) {
	client := appwrite.NewClient(
		appwrite.WithEndpoint(os.Getenv("APPWRITE_FUNCTION_API_ENDPOINT")),
		appwrite.WithProject(os.Getenv("APPWRITE_FUNCTION_PROJECT_ID")),
		appwrite.WithKey(os.Getenv("APPWRITE_API_KEY")),
	)
	db := tablesdb.New(client)
	return db, os.Getenv("APPWRITE_DB_ID"), os.Getenv("APPWRITE_TABLE_FINANCIALS")
}

// ── FinancialRow (shared by M-PESA callback + eTIMS) ─────────────────────────

type FinancialRow struct {
	*models.Row
	CheckoutRequestID string  `json:"checkout_request_id"`
	PaymentStatus     string  `json:"payment_status"`
	PaymentMethod     string  `json:"payment_method"`
	MpesaReceipt      string  `json:"mpesa_receipt"`
	Amount            float64 `json:"amount"`
	TransactionID     string  `json:"transaction_id"`
	Description       string  `json:"description"`
	CreatedBy         string  `json:"created_by"`
}

type FinancialRowList struct {
	*models.RowList
	Rows []FinancialRow `json:"rows"`
}

// ═════════════════════════════════════════════════════════════════════════════
// HANDLER 1 — M-PESA STK Push
// ═════════════════════════════════════════════════════════════════════════════

type stkRequest struct {
	PhoneNumber string `json:"phone_number"`
	Amount      int    `json:"amount"`
	AccountRef  string `json:"account_reference"`
}

type stkSafaricomResp struct {
	MerchantRequestID   string `json:"MerchantRequestID"`
	CheckoutRequestID   string `json:"CheckoutRequestID"`
	ResponseCode        string `json:"ResponseCode"`
	ResponseDescription string `json:"ResponseDescription"`
	CustomerMessage     string `json:"CustomerMessage"`
	ErrorCode           string `json:"errorCode"`
	ErrorMessage        string `json:"errorMessage"`
}

func handleStkPush(Context openruntimes.Context) openruntimes.Response {
	var req stkRequest
	if err := json.Unmarshal([]byte(Context.Req.BodyRaw()), &req); err != nil {
		return jsonErr(Context, 400, "invalid payload: "+err.Error())
	}
	if req.PhoneNumber == "" || req.AccountRef == "" {
		return jsonErr(Context, 400, "phone_number and account_reference are required")
	}
	if req.Amount < 1 {
		return jsonErr(Context, 400, "amount must be at least KES 1")
	}

	phone, err := sanitizePhone(req.PhoneNumber)
	if err != nil {
		return jsonErr(Context, 400, err.Error())
	}

	consumerKey := os.Getenv("MPESA_CONSUMER_KEY")
	consumerSecret := os.Getenv("MPESA_CONSUMER_SECRET")
	shortcode := os.Getenv("MPESA_SHORTCODE")
	passkey := os.Getenv("MPESA_PASSKEY")
	callbackURL := os.Getenv("MPESA_CALLBACK_URL")
	env := os.Getenv("MPESA_ENVIRONMENT")

	if consumerKey == "" || consumerSecret == "" || shortcode == "" || passkey == "" || callbackURL == "" {
		Context.Error("missing M-PESA env vars")
		return jsonErr(Context, 500, "server misconfiguration — missing M-PESA credentials")
	}

	baseURL := darajaBaseURL(env)
	token, err := getAccessToken(consumerKey, consumerSecret, baseURL)
	if err != nil {
		Context.Error("token fetch failed: " + err.Error())
		return jsonErr(Context, 500, "M-PESA auth failed")
	}

	timestamp := time.Now().Format("20060102150405")
	password := base64.StdEncoding.EncodeToString([]byte(shortcode + passkey + timestamp))

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
		"TransactionDesc":   "Akavango Farm Payment",
	}

	payloadBytes, _ := json.Marshal(stkPayload)
	httpReq, _ := http.NewRequest("POST", baseURL+"/mpesa/stkpush/v1/processrequest", bytes.NewBuffer(payloadBytes))
	httpReq.Header.Set("Authorization", "Bearer "+token)
	httpReq.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		return jsonErr(Context, 502, "failed to reach M-PESA — try again")
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var stkResp stkSafaricomResp
	if err := json.Unmarshal(body, &stkResp); err != nil {
		return jsonErr(Context, 500, "unexpected response from M-PESA")
	}

	if stkResp.ResponseCode == "0" {
		return jsonOK(Context, map[string]interface{}{
			"success":             true,
			"checkout_request_id": stkResp.CheckoutRequestID,
			"merchant_request_id": stkResp.MerchantRequestID,
			"customer_message":    stkResp.CustomerMessage,
		})
	}

	errMsg := stkResp.ErrorMessage
	if errMsg == "" {
		errMsg = stkResp.ResponseDescription
	}
	return jsonErr(Context, 400, errMsg)
}

// ═════════════════════════════════════════════════════════════════════════════
// HANDLER 2 — M-PESA Callback (called by Safaricom, no auth)
// ═════════════════════════════════════════════════════════════════════════════

type darajaCallback struct {
	Body struct {
		StkCallback struct {
			MerchantRequestID string `json:"MerchantRequestID"`
			CheckoutRequestID string `json:"CheckoutRequestID"`
			ResultCode        int    `json:"ResultCode"`
			ResultDesc        string `json:"ResultDesc"`
			CallbackMetadata  struct {
				Item []struct {
					Name  string      `json:"Name"`
					Value interface{} `json:"Value"`
				} `json:"Item"`
			} `json:"CallbackMetadata"`
		} `json:"stkCallback"`
	} `json:"Body"`
}

func handleMpesaCallback(Context openruntimes.Context) openruntimes.Response {
	Context.Log("===== M-PESA CALLBACK =====")
	raw := Context.Req.BodyRaw()
	Context.Log("payload: " + raw)

	var payload darajaCallback
	if err := json.Unmarshal([]byte(raw), &payload); err != nil {
		Context.Error("failed to parse callback: " + err.Error())
		return ack(Context)
	}

	stk := payload.Body.StkCallback
	db, dbID, tableID := newDB()

	if stk.ResultCode != 0 {
		Context.Log(fmt.Sprintf("payment not completed — code %d: %s", stk.ResultCode, stk.ResultDesc))
		if err := markFinancialFailed(db, dbID, tableID, stk.CheckoutRequestID, stk.ResultDesc); err != nil {
			Context.Error("mark failed error: " + err.Error())
		}
		return ack(Context)
	}

	receipt := extractMetaString(stk.CallbackMetadata.Item, "MpesaReceiptNumber")
	amount := extractMetaFloat(stk.CallbackMetadata.Item, "Amount")
	phone := extractMetaString(stk.CallbackMetadata.Item, "PhoneNumber")

	Context.Log(fmt.Sprintf("payment OK — receipt: %s amount: %.0f phone: %s", receipt, amount, phone))

	listResp, err := db.ListRows(dbID, tableID,
		db.WithListRowsQueries([]string{
			query.Equal("checkout_request_id", stk.CheckoutRequestID),
		}),
	)
	if err != nil {
		Context.Error("ListRows failed: " + err.Error())
		return ack(Context)
	}

	var financials FinancialRowList
	if err := listResp.Decode(&financials); err != nil || len(financials.Rows) == 0 {
		Context.Error("no row found for checkout_request_id: " + stk.CheckoutRequestID)
		return ack(Context)
	}

	rowID := financials.Rows[0].Id
	_, err = db.UpdateRow(dbID, tableID, rowID,
		db.WithUpdateRowData(map[string]interface{}{
			"payment_status": "paid",
			"mpesa_receipt":  receipt,
			"amount_paid":    amount,
			"notes":          stk.ResultDesc,
		}),
	)
	if err != nil {
		Context.Error("UpdateRow failed for " + rowID + ": " + err.Error())
	} else {
		Context.Log("marked paid: " + rowID + " receipt: " + receipt)
	}

	return ack(Context)
}

func ack(Context openruntimes.Context) openruntimes.Response {
	return Context.Res.Text("Success", Context.Res.WithStatusCode(200))
}

// ═════════════════════════════════════════════════════════════════════════════
// HANDLER 3 — eTIMS Submit
// ═════════════════════════════════════════════════════════════════════════════
//
// Receives a transaction_id, fetches the Financial row, builds an eTIMS
// invoice payload, submits to KRA OSCU, then writes the KRA receipt + CU
// serial back to the financials row.
//
// eTIMS OSCU API reference:
//   Sandbox:    https://etims-sbx.kra.go.ke/etims-api
//   Production: https://etims.kra.go.ke/etims-api
//
// Relevant endpoints used here:
//   POST /saveInvoice    — submit a new tax invoice

type etimsSubmitRequest struct {
	TransactionID string      `json:"transaction_id"`
	Items         []etimsItem `json:"items"`        // line items from Flutter
	CustomerPIN   string      `json:"customer_pin"` // optional B2B
	CustomerName  string      `json:"customer_name"`
}

type etimsItem struct {
	Name      string  `json:"name"`
	Qty       float64 `json:"qty"`
	UnitPrice float64 `json:"unit_price"`
	// VAT rate code per KRA classification:
	// "A" = 16% standard, "B" = 0% zero-rated, "C" = exempt
	VatRateCode string `json:"vat_rate_code"`
}

func handleEtimsSubmit(Context openruntimes.Context) openruntimes.Response {
	Context.Log("===== eTIMS SUBMIT =====")

	var req etimsSubmitRequest
	if err := json.Unmarshal([]byte(Context.Req.BodyRaw()), &req); err != nil {
		return jsonErr(Context, 400, "invalid payload: "+err.Error())
	}
	if req.TransactionID == "" {
		return jsonErr(Context, 400, "transaction_id is required")
	}
	if len(req.Items) == 0 {
		return jsonErr(Context, 400, "at least one line item is required")
	}

	// Load env
	pin := os.Getenv("ETIMS_PIN")
	branchID := os.Getenv("ETIMS_BRANCH_ID")
	cmcKey := os.Getenv("ETIMS_CMC_KEY")
	deviceSerial := os.Getenv("ETIMS_DEVICE_SERIAL")
	etimsEnv := os.Getenv("ETIMS_ENVIRONMENT") // "sandbox" | "production"

	if pin == "" || branchID == "" || cmcKey == "" || deviceSerial == "" {
		Context.Error("missing eTIMS env vars")
		return jsonErr(Context, 500, "server misconfiguration — missing eTIMS credentials")
	}

	// Fetch the financial row from Appwrite so we have amount + date
	db, dbID, tableID := newDB()
	docResp, err := db.GetRow(dbID, tableID, req.TransactionID)
	if err != nil {
		Context.Error("GetRow failed: " + err.Error())
		return jsonErr(Context, 404, "transaction not found: "+req.TransactionID)
	}
	var financial FinancialRow
	if err := docResp.Decode(&financial); err != nil {
		return jsonErr(Context, 500, "failed to decode financial row")
	}

	// Build invoice totals
	var totalExVat, totalVat float64
	type invoiceLine struct {
		ItemNm    string  `json:"itemNm"`
		Qty       float64 `json:"qty"`
		UnitPrice float64 `json:"unitPrice"`
		VatRateCd string  `json:"vatRateCd"`
		TaxblAmt  float64 `json:"taxblAmt"`
		VatAmt    float64 `json:"vatAmt"`
		TotAmt    float64 `json:"totAmt"`
	}
	var lines []invoiceLine
	for _, item := range req.Items {
		rate := vatRate(item.VatRateCode)
		taxable := item.Qty * item.UnitPrice
		vat := taxable * rate
		total := taxable + vat
		totalExVat += taxable
		totalVat += vat
		lines = append(lines, invoiceLine{
			ItemNm:    item.Name,
			Qty:       item.Qty,
			UnitPrice: item.UnitPrice,
			VatRateCd: item.VatRateCode,
			TaxblAmt:  round2(taxable),
			VatAmt:    round2(vat),
			TotAmt:    round2(total),
		})
	}
	grandTotal := totalExVat + totalVat

	// Invoice sequence — in production this must be a monotonically
	// increasing integer per device; for now we use a timestamp-based
	// surrogate until a proper sequence store is in place.
	invoiceSeq := time.Now().UnixMilli()

	now := time.Now().UTC()
	invoice := map[string]interface{}{
		"tpin":         pin,
		"bhfId":        branchID,
		"orgSdcId":     deviceSerial,
		"orgInvcNo":    invoiceSeq,
		"cisInvcNo":    fmt.Sprintf("INV-%s", req.TransactionID[:8]),
		"custTpin":     req.CustomerPIN, // empty string = B2C
		"custNm":       req.CustomerName,
		"salesTyCd":    "N", // Normal sale
		"rcptTyCd":     "S", // Sales receipt
		"pmtTyCd":      pmtTypeCode(financial.PaymentMethod),
		"salesSttsCd":  "02", // Approved
		"cfmDt":        now.Format("20060102150405"),
		"salesDt":      now.Format("20060102"),
		"stockRlsDt":   now.Format("20060102150405"),
		"totItemCnt":   len(lines),
		"taxblAmtA":    round2(totalExVat), // taxable at 16%
		"taxblAmtB":    0,
		"taxblAmtC":    0,
		"taxblAmtD":    0,
		"taxRtA":       16,
		"taxAmtA":      round2(totalVat),
		"taxAmtB":      0,
		"taxAmtC":      0,
		"taxAmtD":      0,
		"totTaxblAmt":  round2(totalExVat),
		"totTaxAmt":    round2(totalVat),
		"totAmt":       round2(grandTotal),
		"prchrAcptcYn": "N",
		"remark":       financial.Description,
		"itemList":     lines,
	}

	// Sign the payload
	sig := etimsSign(cmcKey, invoice)
	invoice["signature"] = sig

	// Submit to KRA
	baseURL := etimsBaseURL(etimsEnv)
	endpoint := baseURL + "/saveInvoice"

	payloadBytes, _ := json.Marshal(invoice)
	httpReq, _ := http.NewRequest("POST", endpoint, bytes.NewBuffer(payloadBytes))
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("tpin", pin)
	httpReq.Header.Set("bhfId", branchID)

	httpClient := &http.Client{Timeout: 20 * time.Second}
	resp, err := httpClient.Do(httpReq)
	if err != nil {
		Context.Error("eTIMS HTTP error: " + err.Error())
		return jsonErr(Context, 502, "failed to reach KRA eTIMS — will retry")
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	Context.Log("eTIMS response: " + string(body))

	var etimsResp map[string]interface{}
	if err := json.Unmarshal(body, &etimsResp); err != nil {
		return jsonErr(Context, 500, "unexpected response from KRA eTIMS")
	}

	resultCd, _ := etimsResp["resultCd"].(string)
	if resultCd != "000" {
		msg, _ := etimsResp["resultMsg"].(string)
		Context.Error(fmt.Sprintf("eTIMS rejection — code: %s msg: %s", resultCd, msg))
		// Write the failure back so the app can surface it and retry
		_, _ = db.UpdateRow(dbID, tableID, financial.Id,
			db.WithUpdateRowData(map[string]interface{}{
				"is_kra_certified": false,
				"kra_reference":    fmt.Sprintf("FAILED:%s", resultCd),
			}),
		)
		return jsonErr(Context, 422, fmt.Sprintf("KRA rejected invoice: %s — %s", resultCd, msg))
	}

	// Extract the official KRA receipt details
	rcptInfo, _ := etimsResp["data"].(map[string]interface{})
	kraReceipt := ""
	kraSerial := ""
	kraSignature := ""
	if rcptInfo != nil {
		kraReceipt, _ = rcptInfo["rcptNo"].(string)
		kraSerial, _ = rcptInfo["sdcId"].(string)
		kraSignature, _ = rcptInfo["intrlData"].(string)
	}

	// Write confirmed KRA details back to Appwrite
	_, err = db.UpdateRow(dbID, tableID, financial.Id,
		db.WithUpdateRowData(map[string]interface{}{
			"is_kra_certified": true,
			"kra_reference":    kraReceipt,
			"kra_serial":       kraSerial,
			"kra_signature":    kraSignature,
		}),
	)
	if err != nil {
		Context.Error("UpdateRow (KRA fields) failed: " + err.Error())
	}

	Context.Log(fmt.Sprintf("eTIMS OK — receipt: %s serial: %s", kraReceipt, kraSerial))
	return jsonOK(Context, map[string]interface{}{
		"success":       true,
		"kra_receipt":   kraReceipt,
		"kra_serial":    kraSerial,
		"kra_signature": kraSignature,
		"invoice_seq":   invoiceSeq,
	})
}

// ═════════════════════════════════════════════════════════════════════════════
// HANDLER 4 — eTIMS Query
// ═════════════════════════════════════════════════════════════════════════════
//
// Polls KRA for the status of a previously submitted invoice.
// Useful for the retry loop — if submission timed out but KRA may have
// received it, query before resubmitting to avoid duplicates.

type etimsQueryRequest struct {
	TransactionID string `json:"transaction_id"`
	InvoiceSeq    int64  `json:"invoice_seq"`
}

func handleEtimsQuery(Context openruntimes.Context) openruntimes.Response {
	Context.Log("===== eTIMS QUERY =====")

	var req etimsQueryRequest
	if err := json.Unmarshal([]byte(Context.Req.BodyRaw()), &req); err != nil {
		return jsonErr(Context, 400, "invalid payload")
	}
	if req.TransactionID == "" {
		return jsonErr(Context, 400, "transaction_id is required")
	}

	pin := os.Getenv("ETIMS_PIN")
	branchID := os.Getenv("ETIMS_BRANCH_ID")
	etimsEnv := os.Getenv("ETIMS_ENVIRONMENT")

	endpoint := etimsBaseURL(etimsEnv) + "/selectInvoice"
	payload := map[string]interface{}{
		"tpin":   pin,
		"bhfId":  branchID,
		"invcNo": req.InvoiceSeq,
	}

	payloadBytes, _ := json.Marshal(payload)
	httpReq, _ := http.NewRequest("POST", endpoint, bytes.NewBuffer(payloadBytes))
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("tpin", pin)
	httpReq.Header.Set("bhfId", branchID)

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		return jsonErr(Context, 502, "failed to reach KRA eTIMS")
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return jsonErr(Context, 500, "unexpected response from KRA")
	}

	return jsonOK(Context, map[string]interface{}{
		"success":  true,
		"kra_data": result,
	})
}

// ═════════════════════════════════════════════════════════════════════════════
// eTIMS helpers
// ═════════════════════════════════════════════════════════════════════════════

func etimsBaseURL(env string) string {
	if env == "production" {
		return "https://etims.kra.go.ke/etims-api"
	}
	return "https://etims-sbx.kra.go.ke/etims-api"
}

// etimsSign creates an HMAC-SHA256 signature of the JSON payload using the
// CMC Key issued by KRA during device initialisation.
func etimsSign(cmcKey string, payload map[string]interface{}) string {
	data, _ := json.Marshal(payload)
	mac := hmac.New(sha256.New, []byte(cmcKey))
	mac.Write(data)
	return hex.EncodeToString(mac.Sum(nil))
}

// vatRate returns the decimal multiplier for a given KRA VAT rate code.
func vatRate(code string) float64 {
	switch strings.ToUpper(code) {
	case "A":
		return 0.16 // 16% standard
	case "B":
		return 0.0 // 0% zero-rated
	case "C":
		return 0.0 // exempt
	default:
		return 0.16
	}
}

// pmtTypeCode maps our internal PaymentMethod string to KRA's code.
func pmtTypeCode(method string) string {
	switch strings.ToLower(method) {
	case "mpesa":
		return "03" // Mobile money
	case "cash":
		return "01"
	case "bank":
		return "02"
	default:
		return "01"
	}
}

func round2(v float64) float64 {
	f, _ := strconv.ParseFloat(fmt.Sprintf("%.2f", v), 64)
	return f
}

// ═════════════════════════════════════════════════════════════════════════════
// M-PESA helpers (shared with STK push + callback)
// ═════════════════════════════════════════════════════════════════════════════

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
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", "Basic "+
		base64.StdEncoding.EncodeToString([]byte(key+":"+secret)))

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("token request failed: %w", err)
	}
	defer resp.Body.Close()

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

func markFinancialFailed(db *tablesdb.TablesDB, dbID, tableID, checkoutID, reason string) error {
	listResp, err := db.ListRows(dbID, tableID,
		db.WithListRowsQueries([]string{
			query.Equal("checkout_request_id", checkoutID),
		}),
	)
	if err != nil {
		return fmt.Errorf("ListRows failed: %w", err)
	}
	var financials FinancialRowList
	if err := listResp.Decode(&financials); err != nil || len(financials.Rows) == 0 {
		return fmt.Errorf("no row for checkout_request_id: %s", checkoutID)
	}
	_, err = db.UpdateRow(dbID, tableID, financials.Rows[0].Id,
		db.WithUpdateRowData(map[string]interface{}{
			"payment_status": "failed",
			"notes":          reason,
		}),
	)
	return err
}

// ── Callback metadata extraction ──────────────────────────────────────────────

func extractMetaString(items []struct {
	Name  string      `json:"Name"`
	Value interface{} `json:"Value"`
}, name string) string {
	for _, item := range items {
		if item.Name == name {
			if num, ok := item.Value.(float64); ok {
				return fmt.Sprintf("%.0f", num)
			}
			return fmt.Sprintf("%v", item.Value)
		}
	}
	return ""
}

func extractMetaFloat(items []struct {
	Name  string      `json:"Name"`
	Value interface{} `json:"Value"`
}, name string) float64 {
	for _, item := range items {
		if item.Name == name {
			switch v := item.Value.(type) {
			case float64:
				return v
			case json.Number:
				f, _ := v.Float64()
				return f
			}
		}
	}
	return 0
}
