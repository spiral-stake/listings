#!/usr/bin/env node
// Refresh the Spiral Stake Dune dashboard *display*.
//
// Why this exists: Dune dashboards are NOT updated automatically, and a materialized-view refresh
// updates the view's table but NOT the query execution a dashboard renders. A dashboard tile shows
// its query's `latest_execution_id`, which only advances when the query is actually executed
// (interactive Run, native scheduler on a paid engine, or the API). This script is that execution,
// on a schedule we control, for free.
//
// Two steps:
//   1. Execute each dashboard query -> refreshes the tile DATA. Each query reads a materialized view
//      (the heavy on-chain compute is done by Dune-native matview crons), so these are cheap.
//   2. Touch the dashboard (re-save it unchanged) -> resets the "updated at" timestamp shown on the
//      dashboard. That label tracks the last dashboard EDIT, not query executions, so step 1 alone
//      leaves it stale. There is no plain-REST dashboard endpoint, so this goes through Dune's MCP
//      endpoint (stateless, same API key). The get->put echoes the current layout, so it is safe if
//      the dashboard is later edited.
//
// Free-tier limits this respects:
//   * max 3 concurrent executions
//   * ~15 execute-requests/minute, ~40 status-requests/minute
// It runs queries one at a time with a short gap and retries on HTTP 429 with backoff, so it stays
// well under both caps. A full pass is ~2-4 min — fine for a daily Action.
//   * executions run on the free engine ("performance": "free") -> no surprise credit tier
//
// Env: DUNE_API_KEY (required).

const API = "https://api.dune.com/api/v1";
const MCP = "https://api.dune.com/mcp/v1";
const DASHBOARD_ID = 216731;
const KEY = process.env.DUNE_API_KEY;
if (!KEY) {
  console.error("DUNE_API_KEY is not set");
  process.exit(1);
}

// The queries the dashboard renders. Keep in sync with listings/dune/queries/.
const QUERY_IDS = [
  8101568, // all-time totals (deposited / looped / borrowed)
  8081304, // headline KPIs
  8081588, // per-market breakdown
  8081589, // per-chain split
  8081591, // pricing data quality
  8089503, // position risk
  8081592, // weekly activity
  8081593, // cumulative wallets
  8081595, // protocol revenue
  8082178, // liquidations
  8089848, // TVL over time
];

const GAP_MS = 3000; // between queries
const POLL_MS = 10000; // between status checks
const MAX_WAIT_MS = 240000; // per query
const MAX_429_RETRIES = 6;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const headers = { "X-Dune-Api-Key": KEY, "Content-Type": "application/json" };

// Fetch that transparently retries HTTP 429 with backoff (honouring Retry-After when present).
async function req(url, init, label) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, init);
    if (res.status !== 429) {
      if (!res.ok) throw new Error(`${label}: ${res.status} ${await res.text()}`);
      return res.json();
    }
    if (attempt >= MAX_429_RETRIES) throw new Error(`${label}: rate-limited after ${attempt} retries`);
    const retryAfter = Number(res.headers.get("retry-after"));
    const backoff = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : Math.min(2000 * 2 ** attempt, 30000);
    await sleep(backoff);
  }
}

async function execute(queryId) {
  const body = JSON.stringify({ performance: "free" });
  const json = await req(`${API}/query/${queryId}/execute`, { method: "POST", headers, body }, `execute ${queryId}`);
  return json.execution_id;
}

async function waitFor(queryId, executionId) {
  const deadline = Date.now() + MAX_WAIT_MS;
  while (Date.now() < deadline) {
    const { state } = await req(`${API}/execution/${executionId}/status`, { headers }, `status ${queryId}`);
    if (state === "QUERY_STATE_COMPLETED") return;
    if (state === "QUERY_STATE_FAILED" || state === "QUERY_STATE_CANCELLED" || state === "QUERY_STATE_EXPIRED") {
      throw new Error(`query ${queryId} ended ${state}`);
    }
    await sleep(POLL_MS);
  }
  throw new Error(`query ${queryId} timed out after ${MAX_WAIT_MS}ms`);
}

// Dashboard writes are only exposed via Dune's MCP endpoint (stateless JSON-RPC, same API key),
// not the plain REST Data API. Returns the tool result.
async function mcp(name, args) {
  const res = await fetch(MCP, {
    method: "POST",
    headers: { "X-Dune-Api-Key": KEY, "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name, arguments: args } }),
  });
  const raw = await res.text();
  let msg;
  for (const line of raw.split("\n")) if (line.startsWith("data:")) msg = JSON.parse(line.slice(5).trim());
  if (!msg) throw new Error(`mcp ${name}: no data (${res.status}) ${raw.slice(0, 160)}`);
  if (msg.error) throw new Error(`mcp ${name}: ${JSON.stringify(msg.error)}`);
  const c = msg.result?.content?.[0];
  return c?.type === "text" ? JSON.parse(c.text) : msg.result;
}

// Re-save the dashboard unchanged to reset its "updated at" timestamp. Echoes the current widget
// layout so it stays correct even if the dashboard is edited later.
async function touchDashboard() {
  const d = await mcp("getDashboard", { id: DASHBOARD_ID });
  await mcp("updateDashboard", {
    dashboardId: DASHBOARD_ID,
    visualizationWidgets: (d.visualizationWidgets ?? []).map((w) => ({ visualizationId: w.visualizationId, position: w.position })),
    textWidgets: (d.textWidgets ?? []).map((w) => ({ text: w.text, position: w.position })),
  });
}

async function main() {
  console.log(`Refreshing ${QUERY_IDS.length} Spiral dashboard queries (sequential, 429-safe)…`);
  const failures = [];
  for (const queryId of QUERY_IDS) {
    try {
      await waitFor(queryId, await execute(queryId));
      console.log(`  ✓ ${queryId}`);
    } catch (e) {
      failures.push(queryId);
      console.error(`  ✗ ${queryId}: ${e.message}`);
    }
    await sleep(GAP_MS);
  }
  if (failures.length) {
    console.error(`\n${failures.length} query(s) failed: ${failures.join(", ")}`);
    process.exit(1);
  }
  await touchDashboard();
  console.log("\nDashboard display refreshed and timestamp reset.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
