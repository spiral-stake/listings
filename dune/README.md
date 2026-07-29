# Dune — Spiral Stake protocol dashboards

**v2 (live):** https://dune.com/jodguy5641/spiral-stake-protocol-dashboard
**v1 (historical):** https://dune.com/jodguy5641/spiral-stake-v1-protocol-dashboard-historical

The two dashboards cross-link. `queries/` holds the v2 SQL; `v1/` holds the v1 SQL — each `.sql` is
the exact source of a live query, so either dashboard can be rebuilt from this repo. Companion
research: [../../LISTINGS-PLAN.md](../../LISTINGS-PLAN.md) §4.

Audited for production on 2026-07-23 — see [Audit](#audit-2026-07-23) for what was checked and fixed.

> **v1 vs v2.** v1 (Ethereum, `FlashLeverage 0xcAcC…` / `FlashLeverageCore 0xD245…`) is **wound down**
> — it ran Oct 2025→early 2026 on Pendle-PT collateral and closed out as the PTs matured
> (~$3.9M all-time looped, $784k deposited, 22 users, 0 liquidations). Its dashboard is a
> **retrospective**, built to the same methodology as v2 (per-position proxies, oracle-priced PT
> collateral) but frozen: one weekly base matview (`result_v1_flows`, from `v1/00_base_flows.sql`)
> that every v1 panel reads. Because v1 is frozen and a pure close doesn't call the oracle, the v1
> TVL-over-time chart is **cost basis** (out-flows valued at entry marks), which is exact at the
> endpoints and nets cleanly to ~0 at wind-down. v1 revenue is the **10% yield fee** on profitable
> closes to the v1 treasury `0xeB90…49D5` (v1 charged no swap fee); v2's is the 10 bps swap fee.
> The daily refresh cron (`refresh-dashboard.mjs`) refreshes both dashboards.

---

## Data model

Everything is derived from chain data. No API is used as a source of truth.

```
Morpho Blue events (morpho_blue_multichain.*)   raw logs (ethereum.logs / robinhood.logs)
        │                                                │
        ├── proxies:  onBehalf of collateral supplied BY FlashLeverage
        ├── collateral: supply − withdraw − seized                 (exact; collateral never accrues)
        ├── shares:     borrow − repay − repaidShares − badDebtShares
        └── market totals: totalBorrowAssets / totalBorrowShares   (incl. AccrueInterest)
                     │
        oracle price() staticcalls from *.traces
                     │
              02_oracle_prices.sql ──► matview  result_spiral_oracle_prices   (every 6h)
                     │
              01_position_state.sql ─► matview  result_spiral_positions       (every 12h)
                     │
        panels 03–06, 11 read the matview (≈0.01 credits each)
```

**Position identification.** Each Spiral position is held by its own `UserProxy` clone, so positions
are never found by user address. They are the `onBehalf` of collateral supplied by the
`FlashLeverage` contract. `proxy → user` comes from `UserProxy.ProxyInitialized` logs.

A position counts as open when it still holds collateral or debt on Morpho. The dashboard
deliberately does **not** read the contract's `open` flag — economic state is the stronger signal,
and it stays correct through partial withdrawals and liquidations.

**Debt.** Morpho debt accrues, so a position's borrow *shares* are converted to assets with that
market's own `totalBorrowAssets / totalBorrowShares`, both rebuilt from events including
`AccrueInterest`. This matches what closing the position would actually have to repay.

**Liquidations.** `Liquidate` carries `seizedAssets`, `repaidShares` and `badDebtShares`, and Morpho
emits **no** accompanying `WithdrawCollateral` or `Repay` for the borrower — verified against 500
real Morpho liquidations. Subtracting from the `Liquidate` event alone is therefore correct and will
not double-count when Spiral sees its first liquidation.

**Collateral valuation — the important design decision.** Collateral is valued with each market's
**Morpho oracle**, read from the `price()` staticcall Morpho makes on every health check:

```
collateral_usd = collateral_units
               × oracle_price_raw / 10^(36 + loanDecimals − collateralDecimals)
               × loan_token_usd
```

This is the same rule the app uses ([mcp/src/core/compose.ts](../../mcp/src/core/compose.ts) —
`collateralTokenValueInLoanToken × loanTokenValueInUsd`), and it is the correct mark for a leverage
protocol because it is the one that governs liquidation.

It also solves a problem nothing else does. Dune has **no price at all** for Pendle PT tokens —
not in `prices.latest`, not in `prices_dex`, not in `dex.trades` (Pendle's AMM is not indexed) — and
its `sDOLA` price was six weeks stale. Since 40+ of the 95 configured mainnet markets are PT markets,
a CoinGecko/DEX-based dashboard would have had a growing hole in it. The oracle prices every
collateral with zero per-token special-casing. Only loan tokens need an external feed, and those are
all major stablecoins with full coverage.

Verified against the app's own values at build time:

| oracle | dashboard | app |
|---|---|---|
| PT-USDat | 0.99377 | 0.9934 |
| PT-sUSDe | 0.99747 | 0.99746 |
| sDOLA | 1.39700 | 1.3967 |

**Staleness.** An oracle that has not been called recently is a stale mark. Past **48 hours** the
query switches to a live market price where one exists; a collateral with no market price (PTs)
keeps the oracle mark and is labelled `morpho_oracle (STALE)` rather than silently dropped. The
**Pricing data quality** panel exposes the source and age of every mark, so the dashboard is
self-auditing rather than quietly wrong.

**Revenue.** The only protocol fee is the 10 bps swap fee charged by the KyberSwap/Pendle aggregator
and paid to the treasury (`0x9ced716f16651b69D5167C82003690621e8F90b9`). The on-chain `s_yieldFee`
and `s_depositFee` switches are 0% and stay that way. That address is also a general treasury, so we
count only the transfers its own contracts remit: **ERC-20 transfers into the treasury whose sender
is FlashLeverage or FlashLeverageRouter.** This captures both fee-charging swaps in an open — the
leverage swap *and* the `swapAndLeverage` pre-swap — regardless of which aggregator executed them.
Scoping by the transaction's `to` (an earlier version) undercounted, because the pre-swap rides in a
transaction called on the aggregator, not on a Spiral contract. ⚠️ [../../REFERRAL-DUNE-SPEC.md](../../REFERRAL-DUNE-SPEC.md)
§4 still uses the old `tx.to` scoping and has the **same undercount bug** — fix it there before the
referral dashboard is built.

---

## Architecture — two layers, and why

Dune has two independent refresh concepts, and the dashboard needs both:

1. **Compute layer — materialized views (Dune-native cron).** The heavy on-chain work is done by 6
   base matviews on their own schedules. A matview refresh recomputes the view's *table*.
2. **Display layer — query executions (external cron).** A dashboard tile renders its query's
   `latest_execution_id`. **A matview refresh does NOT advance that pointer** — only executing the
   query does (interactive Run, a paid-engine scheduler, or the API). So the display is refreshed by
   an external GitHub Action, `refresh-dashboard.mjs`, that re-executes the dashboard queries daily.
   Because every dashboard query reads a matview (not raw chain tables), each execution is cheap.

> This layering was a fix, not the original design. The first version materialized *every* panel and
> assumed the matview cron kept the dashboard live — it does not. Those panel matviews refreshed
> tables nothing read (≈950 credits/month wasted, `result_spiral_revenue` alone ≈700) while the
> displayed numbers sat frozen. The panel matviews were deleted; the display cron is the real fix.

### Base matviews (compute — kept)

| Query | Matview | Refresh | Feeds |
|---|---|---|---|
| `01_position_state.sql` ([8081300](https://dune.com/queries/8081300)) | `result_spiral_positions` | 12h | snapshot panels 03–06, 11 |
| `02_oracle_prices.sql` ([8081347](https://dune.com/queries/8081347)) | `result_spiral_oracle_prices` | 6h | position state |
| `12_hist_market_ratio_daily.sql` ([8089806](https://dune.com/queries/8089806)) | `result_spiral_mkt_ratio_daily` | daily | TVL history |
| `13_hist_position_daily.sql` ([8089807](https://dune.com/queries/8089807)) | `result_spiral_pos_daily` | daily | TVL history |
| `14_hist_oracle_daily.sql` ([8089808](https://dune.com/queries/8089808)) | `result_spiral_oracle_daily` | daily | TVL history |
| `15_tvl_over_time.sql` ([8089848](https://dune.com/queries/8089848)) | `result_spiral_tvl_history` | daily | TVL history chart |

### Dashboard queries (display — executed daily by the cron)

| Query | Reads |
|---|---|
| `03_headline_kpis.sql` ([8081304](https://dune.com/queries/8081304)) | `result_spiral_positions` |
| `04_per_market.sql` ([8081588](https://dune.com/queries/8081588)) | `result_spiral_positions` |
| `05_per_chain.sql` ([8081589](https://dune.com/queries/8081589)) | `result_spiral_positions` |
| `06_pricing_quality.sql` ([8081591](https://dune.com/queries/8081591)) | `result_spiral_positions` |
| `11_position_risk.sql` ([8089503](https://dune.com/queries/8089503)) | `result_spiral_positions` |
| `10_tvl_over_time` chart ([8089848](https://dune.com/queries/8089848)) | `result_spiral_tvl_history` |
| `07_weekly_activity.sql` ([8081592](https://dune.com/queries/8081592)) | raw logs (cheap) |
| `08_cumulative_wallets.sql` ([8081593](https://dune.com/queries/8081593)) | raw logs (cheap) |
| `09_protocol_revenue.sql` ([8081595](https://dune.com/queries/8081595)) | ERC-20 transfers, sender-scoped (~2 cr) |
| `10_liquidations.sql` ([8082178](https://dune.com/queries/8082178)) | Morpho liquidate (~3 cr) |
| `16_all_time_totals.sql` ([8101568](https://dune.com/queries/8101568)) | lifetime deposited / looped / borrowed — supply+borrow events, oracle-priced (~7 cr). **Compute only** — materialized daily as `result_spiral_alltime`; the dashboard tiles read a thin display query ([8144540](https://dune.com/queries/8144540)) so they refresh cheaply. |

> **Why the split (2026-07-29 fix).** The all-time-totals tiles were showing stale ("4d ago") while
> the rest of the dashboard was current. Cause: with no external cron running (the GitHub Action was
> not yet set up), the only thing refreshing the display was Dune's free *popular-dashboard*
> auto-refresh, which runs on the community cluster with a 2-minute cap. Every other tile reads a
> matview and completes instantly, but the all-time-totals query scanned raw multichain Morpho
> events (~7 cr) and timed out there, so those three counters got stuck at their last manual run.
> Fix: materialize the heavy query (`result_spiral_alltime`, daily) and point the counters at a thin
> `SELECT * FROM result_spiral_alltime`. **General rule: every dashboard tile must read a matview or
> be otherwise cheap — never scan raw event tables directly — so free auto-refresh can complete it.**

`refresh-dashboard.mjs` runs these sequentially with 429-backoff (free tier caps at 3 concurrent
executions and ~15 execute-requests/min). A full pass ≈ 12 credits.

**TVL over time** is built in three daily stages (12–14) because the full derivation does not fit in
one 2-minute execution: per-position daily collateral + shares, per-market daily borrow ratio, and
daily oracle marks (forward-filled). The final query (15) joins them, valuing each day's debt with
*that day's* market ratio and each day's collateral with *that day's* oracle mark — history is
rebuilt, not today's numbers projected backward. The last point reconciles with the live snapshot to
within 0.15%.

---

## Cost

Free tier (`community_fluid_engine_v2`), **2,500 credits/month**.

| Layer | credits/day |
|---|---|
| Compute: position state matview (14.7 × 2/day) | 29.4 |
| Compute: oracle prices matview (2.2 × 4/day) | 8.8 |
| Compute: 4 history-stage matviews (daily) | ~14.0 |
| Display: cron pass, once daily (~5 cr/pass) | ~5.0 |
| **total** | **≈57/day → ≈1,700/month** |

Fits inside the 2,500 ceiling with ~550 credits/month of headroom. Two deliberate choices keep it
there: the history stages refresh once daily (TVL history is a daily series, so finer is pointless),
and the display cron runs once daily.

**Tuning knobs** if you want a fresher-looking dashboard:
- Run the display cron more often (edit the workflow `cron`). Each extra pass ≈ 5 credits, so 2×/day
  adds ~150/month — comfortably fits.
- The display cost is dominated by the liquidations (~3) query, which scans raw
  tables. If you want frequent refreshes cheaply, materialize those two and point their panels at the
  matview — then a full pass drops to ~1 credit.

> Two production issues the audit found and fixed here. **(1)** An early config refreshed matviews
> **hourly** — ~12,000 credits/month, would have exhausted the quota in ~6 days and frozen the
> dashboard. **(2)** Nine per-panel matviews refreshed tables that nothing read (~950 credits/month
> wasted) while the *displayed* numbers never updated, because a matview refresh does not advance a
> query's `latest_execution_id`. Both are resolved by the two-layer design above.

Free-tier constraints worth knowing: **2-minute** query timeout (why the heavy derivations are
materialized rather than nested), **max 3 concurrent executions** and **~15 execute-requests/min**
(why the cron is sequential with backoff), and **no private queries or dashboards** — everything
here is public.

---

## Keeping the dashboard fresh (required — it is not automatic)

Dune does not auto-refresh dashboards on the free tier. The Action is already included in this repo
at `.github/workflows/refresh-dune-dashboard.yml` (it runs `dune/refresh-dashboard.mjs`). To activate
it, once:

1. Add a repository secret **`DUNE_API_KEY`** (Settings → Secrets and variables → Actions → New
   repository secret).
2. Done — it runs daily at 01:00 UTC, and can be triggered manually from the Actions tab
   (**Run workflow**).

Run it locally anytime with `DUNE_API_KEY=… node dune/refresh-dashboard.mjs` from the repo root.

The script does two things per run: (1) executes the dashboard queries — refreshes the tile **data**;
(2) re-saves the dashboard unchanged — resets the **"updated at"** label, which tracks the last
dashboard *edit*, not query executions, so step 1 alone would leave it stale. Step 2 goes through
Dune's MCP endpoint because there is no plain-REST dashboard-write on this plan. Without the cron the
matview crons still keep the data *tables* current, but neither the rendered tiles nor the timestamp
advance on their own.

---

## Audit (2026-07-23)

Checked against chain truth, not against its own code.

**Verified correct**
- No NULL collateral, debt, symbol or user on any position — nothing silently dropped from a `SUM`.
- Liquidation accounting does not double-count (500 Morpho liquidations sampled).
- No position is above its liquidation LTV; no negative equity.
- Totals reconcile with two independent implementations (below).

**Fixed**
| Issue | Fix |
|---|---|
| **Revenue undercounted** ($110 vs the true ~$142) — scoping by tx `to` missed the `swapAndLeverage` pre-swap fee, which rides in a transaction called on the aggregator | re-scoped to transfers into the treasury *remitted by* FlashLeverage / Router (captures both swaps, any aggregator) |
| Hourly matview refresh would exhaust the quota in ~6 days and freeze the dashboard | daily/6h/12h matview schedules |
| **The dashboard display never auto-updated** — matview refreshes don't advance a query's `latest_execution_id`, so tiles showed frozen data regardless of the crons | external GitHub Action re-executes the dashboard queries daily (`refresh-dashboard.mjs`) |
| 9 per-panel matviews refreshed tables nothing read (~950 credits/month wasted) | deleted; only the 6 compute matviews remain |
| A stale oracle mark (USP, 11 days old, 92% of TVL) was used with no fallback | 48h staleness threshold → live market price, with the source surfaced |
| Per-market panel grouped by token-pair name, silently merging distinct markets that share a pair | grouped by Morpho market id |
| Revenue chart plotted weekly and cumulative on one axis (columns cannot use a right axis) | weekly stays a column; total became a counter |
| Fee query scanned unpruned partitions | date filters, 9.9 → 5.6 credits |
| No visibility of how close positions run to liquidation | added the **Position risk** panel |

**Known and accepted**
- **One position is 92% of protocol TVL** ($37.0k of $40.4k). Every headline number is effectively
  that position. Not a dashboard defect, but essential context for anyone reading it.
- Several positions run **0.6–1.0% from liquidation**. By design — max LTV is `liqLtv − 0.25%` —
  and now visible in the Position risk panel.
- **Display refresh is once daily** and depends on the external cron being set up (see above). The
  matview data tables are always current; only what the dashboard *renders* waits for the cron.
- **The dashboard is public.** Private dashboards require a paid plan.
- Owned by team `jodguy5641` (`team_id 51215`). Moving to a differently-named team means recreating
  the queries and matviews and updating the `dune.<team>.result_*` references.
- Credit budget runs at ~1,930/month against a 2,500 ceiling (see Cost) — ~550 headroom.

---

## Verification

The core query was validated against two fully independent implementations. Every collateral amount
matched exactly; totals agree to ~0.1%, the difference being price-source noise.

| | Dune | Independent on-chain probe | DefiLlama adapter |
|---|---|---|---|
| Gross collateral | $40,395 | $40,449 | — |
| Borrowed | $34,650 | $34,635 | $34,640 |
| Net equity | $5,744 | $5,814 | $5,810 |

---

## Rebuilding from scratch

1. Create `02_oracle_prices.sql` → materialize `result_spiral_oracle_prices`, cron `0 */6 * * *`.
2. Create `01_position_state.sql`, pointing its `oracle_px` CTE at that matview → materialize
   `result_spiral_positions`, cron `0 */12 * * *`.
3. Create `12`–`14` (history stages) → materialize each, cron `0 0 * * *`.
4. Create `15_tvl_over_time.sql` reading the three history matviews → materialize
   `result_spiral_tvl_history`, cron `0 0 * * *`.
5. Create the display queries `03`–`11` (they read the matviews; do **not** materialize these — the
   external cron executes them instead).
6. Build visualizations and the dashboard from `03`–`11` + `15`.
7. Set up the display cron (see *Keeping the dashboard fresh*).

Matview cron must be the plain `0 */N * * *` / `0 0 * * *` form; Dune rejects comma lists, non-zero
minutes, and intervals over 24h. If the team handle changes, update the `dune.<team>.result_*`
references in `01`, `03`–`06`, `11`, and `15`, and the query IDs in `refresh-dashboard.mjs`.

---

## Open items

- [ ] Set up the display-refresh Action (see *Keeping the dashboard fresh*) — **required** for the
      dashboard to stay current. Needs the `DUNE_API_KEY` secret in the CI repo.
- [ ] Decide whether the dashboard should stay public (free tier) or move to a paid plan. A paid plan
      also unlocks Dune-native dashboard scheduling, which removes the need for the external cron.
- [ ] Optional: if you want sub-daily display refresh cheaply, materialize the revenue + liquidations
      panels and point them at the matview (see Cost → Tuning knobs).
