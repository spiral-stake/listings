#!/usr/bin/env node
// Refresh the Spiral Stake Dune dashboard *display*, and act as a freshness monitor.
//
// Why this exists: Dune dashboards are NOT updated automatically, and a materialized-view refresh
// updates the view's table but NOT the query execution a dashboard renders. A dashboard tile shows
// its query's `latest_execution_id`, which only advances when the query is actually executed
// (interactive Run, native scheduler on a paid engine, or the API). This script is that execution,
// on a schedule we control, for free.
//
// Three steps:
//   1. Execute each dashboard query -> refreshes the tile DATA. Each query reads a materialized view
//      (the heavy on-chain compute is done by Dune-native matview crons), so these are cheap. A
//      failed query is retried once before it counts as failed (network blips are common).
//   2. Touch the dashboard (re-save it unchanged) -> resets the "updated at" timestamp shown on the
//      dashboard. That label tracks the last dashboard EDIT, not query executions, so step 1 alone
//      leaves it stale. There is no plain-REST dashboard endpoint, so this goes through Dune's MCP
//      endpoint (stateless, same API key). The get->put echoes the current layout, so it is safe if
//      the dashboard is later edited.
//   3. Freshness guard -> execute the freshness probe query and check how many days stale the daily
//      data pipeline is. This is what makes the run's red/green MEANINGFUL:
//        * Green  = dashboards updated AND the underlying data is current.
//        * Red    = a real problem worth investigating (a matview refresh is silently failing, or
//                   credits are exhausted, or auth is broken) — NOT a single transient blip.
//      Before this guard, a frozen matview (e.g. a query that started timing out) showed a fresh
//      "updated" timestamp on stale numbers, and nobody noticed until users complained. Now it goes
//      red here first.
//
// Exit code policy (a single flaky query must NOT page anyone):
//   * exit 1 (RED) only if: the data is >= STALE_DAYS_ALERT days stale, OR a dashboard could not be
//     touched, OR at least half the queries failed even after a retry (systemic: credits/auth).
//   * exit 0 (GREEN) otherwise — a few transient query failures are logged as warnings and tolerated
//     because the dashboards were still touched and the data is confirmed fresh.
//
// Free-tier limits this respects:
//   * max 3 concurrent executions; ~15 execute-requests/minute, ~40 status-requests/minute
//     -> runs queries one at a time with a short gap, retries HTTP 429 with backoff.
//   * executions run on the free engine ("performance": "free") -> no surprise credit tier.
//
// Env: DUNE_API_KEY (required).

const API = "https://api.dune.com/api/v1";
const MCP = "https://api.dune.com/mcp/v1";
const DASHBOARD_IDS = [216731, 216873]; // v2 (live) + v1 (historical)
const KEY = process.env.DUNE_API_KEY;
if (!KEY) {
  console.error("DUNE_API_KEY is not set");
  process.exit(1);
}

// The queries both dashboards render. Keep in sync with listings/dune/queries/ (v2) and v1/ (v1).
// v1 is wound down: its data is frozen behind the weekly result_v1_flows matview, so re-executing
// its display queries just re-reads that — cheap, and keeps the v1 dashboard's timestamp current.
const QUERY_IDS = [
  // v2 (live)
  // (all-time totals 8144540 + result_spiral_alltime matview retired 2026-08-25 — see README)
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
  // v1 (historical)
  8103175, // v1 all-time totals
  8103176, // v1 per-market
  8103177, // v1 TVL over time
  8103178, // v1 position stats
  8103179, // v1 weekly activity
  8103180, // v1 revenue
  8103181, // v1 liquidations
];

const FRESHNESS_QUERY_ID = 8292626; // returns { data_through, stale_days } off result_spiral_tvl_history
const STALE_DAYS_ALERT = 2; // matviews refresh daily; >=2 days behind means a refresh is broken

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

// Execute a query and wait for it, retrying once on any failure (transient blips are common).
async function runQuery(queryId) {
  try {
    await waitFor(queryId, await execute(queryId));
  } catch (first) {
    console.error(`  … ${queryId} failed (${first.message}); retrying once`);
    await sleep(GAP_MS);
    await waitFor(queryId, await execute(queryId)); // a second failure propagates
  }
}

async function fetchRows(executionId) {
  const json = await req(`${API}/execution/${executionId}/results`, { headers }, `results ${executionId}`);
  return json.result?.rows ?? [];
}

// Execute the freshness probe and return how stale the daily data pipeline is.
async function checkFreshness() {
  const executionId = await execute(FRESHNESS_QUERY_ID);
  await waitFor(FRESHNESS_QUERY_ID, executionId);
  const row = (await fetchRows(executionId))[0] ?? {};
  return { staleDays: Number(row.stale_days ?? NaN), dataThrough: row.data_through ?? null };
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

// Re-save a dashboard unchanged to reset its "updated at" timestamp. Echoes the current widget
// layout so it stays correct even if the dashboard is edited later.
async function touchDashboard(dashboardId) {
  const d = await mcp("getDashboard", { id: dashboardId });
  await mcp("updateDashboard", {
    dashboardId,
    visualizationWidgets: (d.visualizationWidgets ?? []).map((w) => ({ visualizationId: w.visualizationId, position: w.position })),
    textWidgets: (d.textWidgets ?? []).map((w) => ({ text: w.text, position: w.position })),
  });
}

async function main() {
  console.log(`Refreshing ${QUERY_IDS.length} Spiral dashboard queries (sequential, 429-safe, retry-once)…`);
  const failures = [];
  for (const queryId of QUERY_IDS) {
    try {
      await runQuery(queryId);
      console.log(`  ✓ ${queryId}`);
    } catch (e) {
      failures.push(queryId);
      console.error(`  ✗ ${queryId}: ${e.message}`);
    }
    await sleep(GAP_MS);
  }

  // Reset dashboard timestamps best-effort — a single flaky query must not leave them looking stale.
  let touchFailed = false;
  for (const id of DASHBOARD_IDS) {
    try {
      await touchDashboard(id);
    } catch (e) {
      touchFailed = true;
      console.error(`  ✗ touch dashboard ${id}: ${e.message}`);
    }
  }

  // Freshness guard: is the underlying data actually current? (This is the real staleness alarm.)
  let staleDays = NaN;
  let dataThrough = null;
  try {
    ({ staleDays, dataThrough } = await checkFreshness());
  } catch (e) {
    console.error(`  ✗ freshness probe failed: ${e.message}`);
  }

  const systemic = failures.length >= Math.ceil(QUERY_IDS.length / 2);
  const dataStale = !Number.isFinite(staleDays) || staleDays >= STALE_DAYS_ALERT;

  console.log(
    `\nData through ${dataThrough ?? "?"} (stale_days=${Number.isFinite(staleDays) ? staleDays : "unknown"}); ` +
      `${failures.length}/${QUERY_IDS.length} queries failed after retry.`
  );

  if (systemic || touchFailed || dataStale) {
    if (systemic) console.error(`FAIL: ${failures.length}/${QUERY_IDS.length} queries failed — systemic (credits exhausted or auth broken?).`);
    if (touchFailed) console.error(`FAIL: a dashboard could not be touched.`);
    if (dataStale) console.error(`FAIL: data is ${Number.isFinite(staleDays) ? staleDays + " days" : "of UNKNOWN age"} stale (>= ${STALE_DAYS_ALERT}d) — a matview refresh is broken. Check Dune matview schedules.`);
    process.exit(1);
  }

  if (failures.length) {
    console.warn(`Note: ${failures.length} transient query failure(s) tolerated — dashboards updated and data confirmed fresh.`);
  }
  console.log("Dashboards refreshed, timestamps reset, data fresh.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
