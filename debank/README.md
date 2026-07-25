# DeBank listing — roadmap

Goal: Spiral Stake positions show up inside users' DeBank portfolios (the leverage position, its
collateral, debt, net value and health), on Ethereum and Robinhood Chain.

Status: **not started.** This is the roadmap + the technical packet to hand DeBank. Companion research
in [../../LISTINGS-PLAN.md](../../LISTINGS-PLAN.md) §3.

---

## How DeBank works — and why it's unlike DefiLlama / Dune

DeBank is fundamentally different from the other two listings, and this shapes everything:

- **There is no self-service path.** No public adapter repo, no PR, no submission form, no SDK.
  DeBank's docs (`docs.cloud.debank.com`) are entirely about *consuming* their data — the Cloud API,
  DeBank Connect (OAuth2), the portfolio endpoints. Nothing about getting *your* protocol indexed.
- **DeBank writes every protocol adapter in-house.** A protocol appears in portfolios only when
  DeBank's own team builds and ships an adapter for it. So this is a **relationship-driven ask**, not
  an engineering task we can complete unilaterally. We can make it fast and easy for them, but we
  cannot merge it ourselves.
- **We have a warm contact** (per the founders), which is the single biggest lever — it turns an
  unbounded cold queue into a real conversation.

What we control: making the integration trivial for them to build and impossible to get wrong — a
precise spec, a reference implementation, and test vectors.

---

## The technical crux — why a generic Morpho adapter won't show Spiral

DeBank **already indexes Morpho Blue on both our chains** (confirmed: `eth` and `hood`/4663). So you
might expect Spiral positions to already appear. They don't, and here's the exact reason:

Every Spiral position is held by its own **`UserProxy` clone**, and the Morpho collateral/debt sits
under that proxy — not under the user's wallet. DeBank's generic Morpho adapter attributes each
Morpho position to the address that holds it, which is an **anonymous proxy contract**. The user's
own EOA has no Morpho position, so **a Spiral user sees nothing in their DeBank portfolio today.**

A Spiral-specific adapter is the *only* way these positions surface, and it must do the
proxy→user resolution. The good news: **DeBank's portfolio schema already has a `proxy_detail` field**
on portfolio items — they explicitly model proxy-held positions, so this is a shape they support.

---

## What DeBank's adapter has to do (the spec we hand them)

This maps one-to-one onto logic we already run in
[../../mcp/src/execution/positions.ts](../../mcp/src/execution/positions.ts).

**1. Discover a user's positions** — given a user EOA, on each chain:
```
FlashLeverage.getUserLeveragePositions(user)
  → [{ open, marketId, userProxy, amountDepositedInLoanToken, amountReturnedInLoanToken }]
```
Position id = array index. (Equivalently, index `UserProxy.ProxyInitialized(address indexed user)`
events for the proxy→user map.)

**2. Value each open position** — per position:
```
getMorphoPosition(userProxy, marketParams) → { collateral, borrowShares }
getSharesValueInLoanToken(marketParams, borrowShares) → debt (loan-token units)
collateral valued via the market's Morpho oracle  (prices PT collateral too)
```

**3. Emit a DeBank portfolio item** per open position:

| DeBank field | Spiral value |
|---|---|
| `name` | `"Leverage"` |
| `detail_types` | `["leveraged_farming"]` (or `["lending"]`) |
| `detail.supply_token_list` | collateral token, `amount` = leveraged collateral |
| `detail.borrow_token_list` | loan token, `amount` = debt |
| `detail.health_rate` | `liqLtv / currentLtv` (position's distance to liquidation) |
| `stats.asset_usd_value` | collateral USD |
| `stats.debt_usd_value` | debt USD |
| `stats.net_usd_value` | net equity USD (the user's real position value) |
| `proxy_detail` | the `UserProxy` address |

Contract addresses (both chains, all **source-verified**):

| | Ethereum | Robinhood Chain (4663) |
|---|---|---|
| FlashLeverage | `0x2B12066ebD67A6A58E70b37051AbED0590E5A721` | `0x27eaF95d39cB07d544026167365689C34B4d3f9A` |
| FlashLeverageRouter | `0x3D131d654e0C413E1cB2ab1071aad78A9470ef9d` | `0x5F7550Bfdd7690E1CFe90c8DbB726964f4d34877` |
| Morpho Blue | `0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb` | `0x9D53d5E3bd5E8d4Cbfa6DB1ca238AEA02E651010` |

---

## Chain coverage (verified against DeBank's chain list)

- **Ethereum** (`eth`) — fully supported.
- **Robinhood Chain** (`hood`, network_id 4663) — supported, `start_at` 2026-04-30, but
  `is_support_history: false` → DeBank shows **current** portfolio only on Robinhood, no historical
  balance chart there. Fine for position display; just set expectations.

So chain coverage is **not** a blocker.

---

## Roadmap

**Phase 0 — Timing decision (founders).** DeBank is discretionary and you get roughly one clean shot
at the contact's attention. Current net TVL is ~$5.8k across 9 users; the all-time figures
(~$148k looped, ~$16k deposited) tell a better story. Decide whether to spend the contact now or
after more growth. Everything below can be *prepared* now regardless.

**Phase 1 — Build the integration packet** (ours to do, ~1 day):
1. This spec (done) + a **worked example**: run `mcp` position-read against a real Spiral user and
   produce the exact DeBank portfolio-item JSON we expect, so they have ground truth to match.
2. Optionally stand up a public read endpoint — un-gate a `/v1/positions/{address}` from the existing
   partner route in `mcp` — for integrators who prefer an API to a chain spec. Offer it; don't lead
   with it (chain-native specs get taken more seriously).
3. Brand assets: logo (high-res, square), name, site, category ("Leveraged Farming"), audit links.

**Phase 2 — Make the ask** (via the warm contact):
1. Send the packet; ask their preferred integration input (chain spec / API / subgraph) and their
   queue + any cost.
2. Fallback channels if needed: `hello.cloud@debank.com` (their documented address), or their BD via
   the app.

**Phase 3 — Support their build + QA:**
1. Provide test addresses (real open positions on both chains) and the expected rendered numbers.
2. Verify: net value, collateral/debt tokens, health rate, per-position split, and that the position
   is attributed to the **EOA** (not the proxy) via `proxy_detail`.

**Phase 4 — Launch + verify:** confirm Spiral appears in live users' portfolios on both chains and
the protocol/TVL entry is correct.

---

## Blockers & risks

1. **Relationship-gated, no SLA, unbounded timeline.** Nothing we build removes this; the warm
   contact is the mitigation.
2. **UserProxy attribution** — the reason a bespoke adapter is required at all. Fully specified above;
   `proxy_detail` is DeBank's native mechanism for it.
3. **TVL optics** — a ~$5.8k ask is weak; lead with the all-time/looped framing and the audits.
4. **Robinhood history** — `is_support_history: false`; current-only on that chain. Minor.
5. **Cost** — no published listing fee (likely free for a legitimate, audited protocol, but confirm
   with the contact). Note: DeBank's paid products — the Cloud **API** (units-based) and **broadcast
   "attention fee"** marketing — are unrelated to being listed; don't conflate them.

---

## Open questions for the founders

1. Who is the DeBank contact, and is it BD or engineering? (Determines whether we lead with the spec
   or the relationship ask.)
2. Do we want to offer the public `/v1/positions/{address}` endpoint, or hand a pure chain spec?
3. Logo / category / audit report URLs — same assets the DefiLlama PR needs; gather once, reuse.
4. Go now or after more TVL? (Phase 0.)
