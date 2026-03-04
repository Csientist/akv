package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/appwrite/sdk-for-go/appwrite"
	"github.com/appwrite/sdk-for-go/models"
	"github.com/appwrite/sdk-for-go/query"
	"github.com/open-runtimes/types-for-go/v4/openruntimes"
)

// ── Safaricom callback payload ────────────────────────────────────────────────

type DarajaCallback struct {
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

// Decoded financial document — matches your financials Appwrite collection
type FinancialDoc struct {
	*models.Document
	CheckoutRequestID string `json:"checkout_request_id"`
	Status            string `json:"status"`
	MpesaReceipt      string `json:"mpesa_receipt"`
}

type FinancialList struct {
	*models.DocumentList
	Documents []FinancialDoc `json:"documents"`
}

// ── Main ──────────────────────────────────────────────────────────────────────

func Main(Context openruntimes.Context) openruntimes.Response {
	// Safaricom requires a fast 200 OK or it will retry the callback.
	// We always return 200 — errors are logged, never exposed to Safaricom.

	// 1. Parse Safaricom payload
	var payload DarajaCallback
	if err := json.Unmarshal([]byte(Context.Req.BodyRaw()), &payload); err != nil {
		Context.Error("Failed to parse Safaricom JSON: " + err.Error())
		return ack(Context) // still 200 — malformed retries won't help
	}

	stk := payload.Body.StkCallback

	// 2. Non-zero ResultCode = user cancelled, insufficient funds, timeout, etc.
	if stk.ResultCode != 0 {
		Context.Log(fmt.Sprintf(
			"Payment not completed. CheckoutID: %s | Code: %d | Desc: %s",
			stk.CheckoutRequestID, stk.ResultCode, stk.ResultDesc,
		))
		// Optionally mark the transaction as FAILED in Appwrite here
		_ = markFailed(Context, stk.CheckoutRequestID, stk.ResultDesc)
		return ack(Context)
	}

	// 3. Extract M-PESA receipt number from the metadata array
	mpesaReceipt := extractMetaString(stk.CallbackMetadata.Item, "MpesaReceiptNumber")
	amount := extractMetaFloat(stk.CallbackMetadata.Item, "Amount")
	phone := extractMetaString(stk.CallbackMetadata.Item, "PhoneNumber")

	Context.Log(fmt.Sprintf(
		"Payment success. Receipt: %s | Amount: %.0f | Phone: %s",
		mpesaReceipt, amount, phone,
	))

	// 4. Connect to Appwrite with the injected API key
	// APPWRITE_FUNCTION_API_ENDPOINT and APPWRITE_FUNCTION_PROJECT_ID are
	// injected automatically by the Appwrite Functions runtime.
	client := appwrite.NewClient(
		appwrite.WithEndpoint(os.Getenv("APPWRITE_FUNCTION_API_ENDPOINT")),
		appwrite.WithProject(os.Getenv("APPWRITE_FUNCTION_PROJECT_ID")),
		appwrite.WithKey(os.Getenv("APPWRITE_API_KEY")),
	)
	databases := appwrite.NewDatabases(client)

	dbID := os.Getenv("APPWRITE_DB_ID")
	colID := os.Getenv("APPWRITE_COL_FINANCIALS")

	// 5. Find the matching transaction by checkout_request_id
	// query.Equal returns a properly formatted Appwrite query string
	listResp, err := databases.ListDocuments(dbID, colID,
		databases.WithListDocumentsQueries([]string{
			query.Equal("checkout_request_id", stk.CheckoutRequestID),
		}),
	)
	if err != nil {
		Context.Error("ListDocuments failed: " + err.Error())
		return ack(Context)
	}

	var financials FinancialList
	if err := listResp.Decode(&financials); err != nil {
		Context.Error("Failed to decode documents: " + err.Error())
		return ack(Context)
	}

	if len(financials.Documents) == 0 {
		Context.Error("No transaction found for CheckoutRequestID: " + stk.CheckoutRequestID)
		return ack(Context)
	}

	// 6. Update the document — mark COMPLETED with receipt
	transactionID := financials.Documents[0].Id

	_, err = databases.UpdateDocument(dbID, colID, transactionID,
		databases.WithUpdateDocumentData(map[string]interface{}{
			"mpesa_receipt": mpesaReceipt,
			"status":        "COMPLETED",
			"amount_paid":   amount,
		}),
	)
	if err != nil {
		Context.Error("UpdateDocument failed for " + transactionID + ": " + err.Error())
	} else {
		Context.Log("Transaction marked COMPLETED: " + transactionID)
	}

	return ack(Context)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// ack returns the 200 OK Safaricom expects. Always call this.
func ack(Context openruntimes.Context) openruntimes.Response {
	return Context.Res.Text("Success", Context.Res.WithStatusCode(200))
}

// markFailed updates a transaction to FAILED status without crashing if it errors.
func markFailed(Context openruntimes.Context, checkoutID, reason string) error {
	client := appwrite.NewClient(
		appwrite.WithEndpoint(os.Getenv("APPWRITE_FUNCTION_API_ENDPOINT")),
		appwrite.WithProject(os.Getenv("APPWRITE_FUNCTION_PROJECT_ID")),
		appwrite.WithKey(os.Getenv("APPWRITE_API_KEY")),
	)
	databases := appwrite.NewDatabases(client)
	dbID := os.Getenv("APPWRITE_DB_ID")
	colID := os.Getenv("APPWRITE_COL_FINANCIALS")

	listResp, err := databases.ListDocuments(dbID, colID,
		databases.WithListDocumentsQueries([]string{
			query.Equal("checkout_request_id", checkoutID),
		}),
	)
	if err != nil {
		return err
	}

	var financials FinancialList
	if err := listResp.Decode(&financials); err != nil || len(financials.Documents) == 0 {
		return fmt.Errorf("no doc found for %s", checkoutID)
	}

	_, err = databases.UpdateDocument(dbID, colID, financials.Documents[0].Id,
		databases.WithUpdateDocumentData(map[string]interface{}{
			"status":      "FAILED",
			"fail_reason": reason,
		}),
	)
	return err
}

// extractMetaString pulls a string value from the Safaricom metadata item array.
func extractMetaString(items []struct {
	Name  string      `json:"Name"`
	Value interface{} `json:"Value"`
}, name string) string {
	for _, item := range items {
		if item.Name == name {
			return fmt.Sprintf("%v", item.Value)
		}
	}
	return ""
}

// extractMetaFloat pulls a numeric value from the Safaricom metadata item array.
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
