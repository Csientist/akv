package handler

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/appwrite/sdk-for-go/appwrite"
	"github.com/appwrite/sdk-for-go/models"
	"github.com/appwrite/sdk-for-go/query"
	"github.com/appwrite/sdk-for-go/tablesdb"
	"github.com/open-runtimes/types-for-go/v4/openruntimes"
)

func Main(Context openruntimes.Context) openruntimes.Response {

	// ── PROXY ADAPTER LAYER (HARDENED) ─────────────────────────
	var wrapper struct {
		Path    string            `json:"path"`
		Method  string            `json:"method"`
		Headers map[string]string `json:"headers"`
		Body    string            `json:"body"`
	}

	// 1. Call the method with parentheses to get the actual string
	rawBody := Context.Req.BodyRaw()

	// 2. Now convert the returned string to a byte array
	if err := json.Unmarshal([]byte(rawBody), &wrapper); err != nil {
		Context.Log(fmt.Sprintf("[adapter-error] failed to parse proxy payload: %v", err))
		Context.Log(fmt.Sprintf("[adapter-error] raw payload: %s", rawBody))
		return jsonErr(Context, 400, "invalid proxy payload format")
	}

	// 3. Apply the proxy wrapper data
	if wrapper.Path != "" && wrapper.Method != "" {
		Context.Req.Method = strings.ToUpper(wrapper.Method)
		Context.Req.Path = wrapper.Path

		if wrapper.Headers != nil {
			for k, v := range wrapper.Headers {
				if v != "" {
					Context.Req.Headers[strings.ToLower(k)] = v
				}
			}
		}
	}

	path := Context.Req.Path
	method := Context.Req.Method

	Context.Log(fmt.Sprintf("[core-api] %s %s", method, path))

	// Public route
	if path == "/health" && method == "GET" {
		return handleHealth(Context)
	}

	// Protected routes
	if !isAuthorized(Context) {
		return jsonErr(Context, 401, "unauthorized")
	}

	switch {
	case path == "/heartbeat/log" && method == "POST":
		return handleHeartbeatLog(Context)
	// ... rest of your routing
	default:
		return jsonErr(Context, 404, "route not found")
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH
// ─────────────────────────────────────────────────────────────────────────────

func isAuthorized(Context openruntimes.Context) bool {
	expected := os.Getenv("FUNCTION_INTERNAL_KEY")
	if expected == "" {
		Context.Log("[auth] FUNCTION_INTERNAL_KEY env var is not set in Appwrite")
		return false
	}

	// Look for the custom proxy secret injected by the Cloudflare Worker
	got := Context.Req.Headers["x-proxy-secret"]
	if got != expected {
		Context.Log("[auth] invalid or missing x-proxy-secret header")
		return false
	}

	return true
}

// ─────────────────────────────────────────────────────────────────────────────
// RESPONSE HELPERS
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// DB CLIENT
// ─────────────────────────────────────────────────────────────────────────────

func newDB() (*tablesdb.TablesDB, string, string) {
	client := appwrite.NewClient(
		appwrite.WithEndpoint(os.Getenv("APPWRITE_FUNCTION_API_ENDPOINT")),
		appwrite.WithProject(os.Getenv("APPWRITE_FUNCTION_PROJECT_ID")),
		appwrite.WithKey(os.Getenv("APPWRITE_API_KEY")),
	)
	db := tablesdb.New(client)

	return db,
		os.Getenv("APPWRITE_DB_ID"),
		os.Getenv("APPWRITE_TABLE_HEARTBEAT")
}

// ─────────────────────────────────────────────────────────────────────────────
// HEALTH CHECK (PUBLIC)
// ─────────────────────────────────────────────────────────────────────────────

func handleHealth(Context openruntimes.Context) openruntimes.Response {
	start := time.Now()

	db, dbID, tableID := newDB()

	status := "ok"
	errMsg := ""

	// Minimal DB check
	_, err := db.ListRows(dbID, tableID,
		db.WithListRowsQueries([]string{query.Limit(1)}),
	)

	if err != nil {
		status = "degraded"
		errMsg = err.Error()
	}

	latency := time.Since(start).Milliseconds()

	// Log heartbeat (non-blocking)
	_, _ = db.CreateRow(dbID, tableID, "unique()",
		map[string]interface{}{
			"status":         status,
			"latency":        latency,
			"error":          errMsg,
			"request_source": "health",
			"request_type":   "health",
			"timestamp":      time.Now().UTC().Format(time.RFC3339),
		},
	)

	return jsonOK(Context, map[string]interface{}{
		"status":  status,
		"latency": latency,
		"time":    time.Now().UTC(),
	})
}

// ─────────────────────────────────────────────────────────────────────────────
// HEARTBEAT LOG (PROTECTED)
// ─────────────────────────────────────────────────────────────────────────────

type heartbeatLogRequest struct {
	Status  string `json:"status"`
	Source  string `json:"source"`
	Type    string `json:"type"`
	Error   string `json:"error"`
	Latency int64  `json:"latency"`
}

func handleHeartbeatLog(Context openruntimes.Context) openruntimes.Response {
	var req heartbeatLogRequest
	_ = json.Unmarshal([]byte(resolveBody(Context)), &req)
	db, dbID, tableID := newDB()

	if req.Status == "" {
		req.Status = "ok"
	}
	if req.Source == "" {
		req.Source = "worker"
	}
	if req.Type == "" {
		req.Type = "synthetic"
	}

	_, err := db.CreateRow(dbID, tableID, "unique()",
		map[string]interface{}{
			"status":         req.Status,
			"latency":        req.Latency,
			"error":          req.Error,
			"request_source": req.Source,
			"request_type":   req.Type,
			"timestamp":      time.Now().UTC().Format(time.RFC3339),
		},
	)

	if err != nil {
		return jsonErr(Context, 500, "failed to log heartbeat")
	}

	return jsonOK(Context, map[string]interface{}{"logged": true})
}

// ─────────────────────────────────────────────────────────────────────────────
// HEARTBEAT CLEANUP
// ─────────────────────────────────────────────────────────────────────────────

func handleHeartbeatCleanup(Context openruntimes.Context) openruntimes.Response {
	db, dbID, tableID := newDB()

	resp, err := db.ListRows(dbID, tableID,
		db.WithListRowsQueries([]string{
			query.OrderDesc("$createdAt"),
			query.Limit(200),
		}),
	)

	if err != nil {
		return jsonErr(Context, 500, "failed to fetch logs")
	}

	var logs models.RowList
	_ = resp.Decode(&logs)

	if len(logs.Rows) <= 100 {
		return jsonOK(Context, map[string]interface{}{
			"message": "no cleanup needed",
			"count":   len(logs.Rows),
		})
	}

	deleted := 0
	for i := 100; i < len(logs.Rows); i++ {
		_, err := db.DeleteRow(dbID, tableID, logs.Rows[i].Id)
		if err == nil {
			deleted++
		}
	}

	return jsonOK(Context, map[string]interface{}{
		"deleted": deleted,
		"kept":    100,
	})
}

// ─────────────────────────────────────────────────────────────────────────────
// HEARTBEAT LIST (FOR DASHBOARD)
// ─────────────────────────────────────────────────────────────────────────────

func handleHeartbeatList(Context openruntimes.Context) openruntimes.Response {
	db, dbID, tableID := newDB()

	resp, err := db.ListRows(dbID, tableID,
		db.WithListRowsQueries([]string{
			query.OrderDesc("$createdAt"),
			query.Limit(50),
		}),
	)

	if err != nil {
		return jsonErr(Context, 500, "failed to fetch logs")
	}

	var logs models.RowList
	_ = resp.Decode(&logs)

	return jsonOK(Context, map[string]interface{}{
		"rows": logs.Rows,
	})
}

// resolveBody returns the effective request body, preferring the
// proxy-wrapper body when the request was forwarded via the adapter.
func resolveBody(Context openruntimes.Context) string {
	var wrapper struct {
		Body string `json:"body"`
	}
	if err := json.Unmarshal([]byte(Context.Req.BodyRaw()), &wrapper); err == nil && wrapper.Body != "" {
		return wrapper.Body
	}
	return Context.Req.BodyRaw()
}
