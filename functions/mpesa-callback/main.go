package handler

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/appwrite/sdk-for-go/appwrite"
	"github.com/appwrite/sdk-for-go/models"
	"github.com/appwrite/sdk-for-go/query"
	"github.com/appwrite/sdk-for-go/tablesdb"
	"github.com/open-runtimes/types-for-go/v4/openruntimes"
)

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

type FinancialRow struct {
	*models.Row
	CheckoutRequestID string `json:"checkout_request_id"`
	PaymentStatus     string `json:"payment_status"`
	MpesaReceipt      string `json:"mpesa_receipt"`
}

type FinancialRowList struct {
	*models.RowList
	Rows []FinancialRow `json:"rows"`
}

func Main(Context openruntimes.Context) openruntimes.Response {
	Context.Log("========== DARAJA CALLBACK INITIATED ==========")

	rawBody := Context.Req.BodyRaw()
	Context.Log("RAW PAYLOAD: " + rawBody)

	var payload DarajaCallback
	if err := json.Unmarshal([]byte(rawBody), &payload); err != nil {
		Context.Error("FATAL: Failed to parse Safaricom JSON. Error: " + err.Error())
		return ack(Context)
	}

	stk := payload.Body.StkCallback
	Context.Log(fmt.Sprintf("Parsed STK Callback. CheckoutID: %s, ResultCode: %d",
		stk.CheckoutRequestID, stk.ResultCode))

	// Build client once — passed into helpers to avoid re-init
	client := appwrite.NewClient(
		appwrite.WithEndpoint(os.Getenv("APPWRITE_FUNCTION_API_ENDPOINT")),
		appwrite.WithProject(os.Getenv("APPWRITE_FUNCTION_PROJECT_ID")),
		appwrite.WithKey(os.Getenv("APPWRITE_API_KEY")),
	)
	db := tablesdb.New(client)
	dbID := os.Getenv("APPWRITE_DB_ID")
	tableID := os.Getenv("APPWRITE_TABLE_FINANCIALS")

	if dbID == "" || tableID == "" {
		Context.Error("FATAL: Missing APPWRITE_DB_ID or APPWRITE_TABLE_FINANCIALS env vars.")
	}

	if stk.ResultCode != 0 {
		Context.Log(fmt.Sprintf(
			"⚠️ Payment not completed. CheckoutID: %s | Code: %d | Desc: %s",
			stk.CheckoutRequestID, stk.ResultCode, stk.ResultDesc,
		))
		if err := markFailed(Context, db, dbID, tableID, stk.CheckoutRequestID, stk.ResultDesc); err != nil {
			Context.Error("❌ Failed to mark transaction as failed: " + err.Error())
		} else {
			Context.Log("✅ Transaction marked as failed.")
		}
		return ack(Context)
	}

	mpesaReceipt := extractMetaString(stk.CallbackMetadata.Item, "MpesaReceiptNumber")
	amount := extractMetaFloat(stk.CallbackMetadata.Item, "Amount")
	phone := extractMetaString(stk.CallbackMetadata.Item, "PhoneNumber")

	Context.Log(fmt.Sprintf(
		"💰 Payment success. Receipt: %s | Amount: %.0f | Phone: %s",
		mpesaReceipt, amount, phone,
	))

	Context.Log(fmt.Sprintf("Querying table %s for CheckoutRequestID: %s", tableID, stk.CheckoutRequestID))

	listResp, err := db.ListRows(dbID, tableID,
		db.WithListRowsQueries([]string{
			query.Equal("checkout_request_id", stk.CheckoutRequestID),
		}),
	)
	if err != nil {
		Context.Error("❌ ListRows failed: " + err.Error())
		return ack(Context)
	}

	var financials FinancialRowList
	if err := listResp.Decode(&financials); err != nil {
		Context.Error("❌ Failed to decode rows: " + err.Error())
		return ack(Context)
	}

	Context.Log(fmt.Sprintf("Found %d matching row(s).", len(financials.Rows)))

	if len(financials.Rows) == 0 {
		Context.Error("❌ No transaction found for CheckoutRequestID: " + stk.CheckoutRequestID)
		return ack(Context)
	}

	rowID := financials.Rows[0].Id
	Context.Log("Updating row ID: " + rowID)

	// payment_status → "paid"   matches PaymentStatus.paid in Flutter
	// mpesa_receipt             Safaricom confirmation code
	// amount_paid               amount confirmed by Safaricom
	_, err = db.UpdateRow(dbID, tableID, rowID,
		db.WithUpdateRowData(map[string]interface{}{
			"payment_status": "paid",
			"mpesa_receipt":  mpesaReceipt,
			"amount_paid":    amount,
			"notes":          stk.ResultDesc,
		}),
	)
	if err != nil {
		Context.Error("❌ UpdateRow failed for " + rowID + ": " + err.Error())
	} else {
		Context.Log("✅ Transaction marked paid: " + rowID + " receipt: " + mpesaReceipt)
	}

	Context.Log("========== DARAJA CALLBACK FINISHED ==========")
	return ack(Context)
}

func ack(Context openruntimes.Context) openruntimes.Response {
	return Context.Res.Text("Success", Context.Res.WithStatusCode(200))
}

func markFailed(
	Context openruntimes.Context,
	db *tablesdb.TablesDB,
	dbID, tableID, checkoutID, reason string,
) error {
	listResp, err := db.ListRows(dbID, tableID,
		db.WithListRowsQueries([]string{
			query.Equal("checkout_request_id", checkoutID),
		}),
	)
	if err != nil {
		return fmt.Errorf("ListRows failed: %w", err)
	}

	var financials FinancialRowList
	if err := listResp.Decode(&financials); err != nil {
		return fmt.Errorf("failed to decode rows: %w", err)
	}

	if len(financials.Rows) == 0 {
		return fmt.Errorf("no row found for checkout_request_id: %s", checkoutID)
	}

	_, err = db.UpdateRow(dbID, tableID, financials.Rows[0].Id,
		db.WithUpdateRowData(map[string]interface{}{
			"payment_status": "failed",
			"note":           reason,
		}),
	)
	return err
}

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
