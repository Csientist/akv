package handler

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

// FinancialDoc Decoded financial document — matches your financials Appwrite collection
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
	Context.Log("========== DARAJA CALLBACK INITIATED ==========")

	// 1. Parse Safaricom payload
	rawBody := Context.Req.BodyRaw()
	Context.Log("RAW PAYLOAD: " + rawBody) // Crucial for debugging malformed Daraja JSON

	var payload DarajaCallback
	if err := json.Unmarshal([]byte(rawBody), &payload); err != nil {
		Context.Error("FATAL: Failed to parse Safaricom JSON. Error: " + err.Error())
		return ack(Context)
	}

	stk := payload.Body.StkCallback
	Context.Log(fmt.Sprintf("Parsed STK Callback. CheckoutID: %s, ResultCode: %d", stk.CheckoutRequestID, stk.ResultCode))

	// 2. Non-zero ResultCode = user cancelled, insufficient funds, timeout, etc.
	if stk.ResultCode != 0 {
		Context.Log(fmt.Sprintf(
			"⚠️ Payment not completed. CheckoutID: %s | Code: %d | Desc: %s",
			stk.CheckoutRequestID, stk.ResultCode, stk.ResultDesc,
		))

		Context.Log("Attempting to mark transaction as FAILED in DB...")
		err := markFailed(Context, stk.CheckoutRequestID, stk.ResultDesc)
		if err != nil {
			Context.Error("❌ Failed to update DB with FAILED status: " + err.Error())
		} else {
			Context.Log("✅ Transaction successfully marked as FAILED in DB.")
		}
		return ack(Context)
	}

	// 3. Extract M-PESA receipt number from the metadata array
	mpesaReceipt := extractMetaString(stk.CallbackMetadata.Item, "MpesaReceiptNumber")
	amount := extractMetaFloat(stk.CallbackMetadata.Item, "Amount")
	phone := extractMetaString(stk.CallbackMetadata.Item, "PhoneNumber")

	Context.Log(fmt.Sprintf(
		"💰 Payment Success Extracted. Receipt: %s | Amount: %.0f | Phone: %s",
		mpesaReceipt, amount, phone,
	))

	// 4. Connect to Appwrite
	Context.Log("Initializing Appwrite Client...")
	client := appwrite.NewClient(
		appwrite.WithEndpoint(os.Getenv("APPWRITE_FUNCTION_API_ENDPOINT")),
		appwrite.WithProject(os.Getenv("APPWRITE_FUNCTION_PROJECT_ID")),
		appwrite.WithKey(os.Getenv("APPWRITE_API_KEY")),
	)
	databases := appwrite.NewDatabases(client)

	dbID := os.Getenv("APPWRITE_DB_ID")
	colID := os.Getenv("APPWRITE_COL_FINANCIALS")

	if dbID == "" || colID == "" {
		Context.Error("FATAL: Missing APPWRITE_DB_ID or APPWRITE_COL_FINANCIALS environment variables.")
	}

	// 5. Find the matching transaction by checkout_request_id
	Context.Log(fmt.Sprintf("Searching DB (%s) Col (%s) for CheckoutRequestID: %s", dbID, colID, stk.CheckoutRequestID))

	listResp, err := databases.ListDocuments(dbID, colID,
		databases.WithListDocumentsQueries([]string{
			query.Equal("checkout_request_id", stk.CheckoutRequestID),
		}),
	)
	if err != nil {
		Context.Error("❌ ListDocuments failed: " + err.Error())
		return ack(Context)
	}

	var financials FinancialList
	if err := listResp.Decode(&financials); err != nil {
		Context.Error("❌ Failed to decode Appwrite documents: " + err.Error())
		return ack(Context)
	}

	Context.Log(fmt.Sprintf("Found %d matching document(s).", len(financials.Documents)))

	if len(financials.Documents) == 0 {
		Context.Error("❌ No transaction found for CheckoutRequestID: " + stk.CheckoutRequestID)
		return ack(Context)
	}

	// 6. Update the document — mark COMPLETED with receipt
	transactionID := financials.Documents[0].Id
	Context.Log("Attempting to update document ID: " + transactionID)

	_, err = databases.UpdateDocument(dbID, colID, transactionID,
		databases.WithUpdateDocumentData(map[string]interface{}{
			"mpesa_receipt": mpesaReceipt,
			"status":        "COMPLETED",
			"amount_paid":   amount,
		}),
	)
	if err != nil {
		Context.Error("❌ UpdateDocument failed for " + transactionID + ": " + err.Error())
	} else {
		Context.Log("✅ Transaction successfully marked COMPLETED in Appwrite: " + transactionID)
	}

	Context.Log("========== DARAJA CALLBACK FINISHED ==========")
	return ack(Context)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func ack(Context openruntimes.Context) openruntimes.Response {
	return Context.Res.Text("Success", Context.Res.WithStatusCode(200))
}

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
		return fmt.Errorf("ListDocuments query failed: %w", err)
	}

	var financials FinancialList
	if err := listResp.Decode(&financials); err != nil {
		return fmt.Errorf("failed to decode response: %w", err)
	}

	if len(financials.Documents) == 0 {
		return fmt.Errorf("no matching document found to update")
	}

	_, err = databases.UpdateDocument(dbID, colID, financials.Documents[0].Id,
		databases.WithUpdateDocumentData(map[string]interface{}{
			"status":      "FAILED",
			"fail_reason": reason,
		}),
	)
	if err != nil {
		return fmt.Errorf("UpdateDocument failed: %w", err)
	}

	return nil
}

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
