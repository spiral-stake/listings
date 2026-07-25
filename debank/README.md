# DeBank listing — roadmap

Goal: Spiral Stake positions show up inside users' DeBank portfolios (the leverage position, its
collateral, debt, net value and health), on Ethereum and Robinhood Chain.

Status: **not started.** This is the roadmap + the technical packet to hand DeBank. Companion research
in [../../LISTINGS-PLAN.md](../../LISTINGS-PLAN.md) §3.

---

## How DeBank works — the two routes

DeBank writes every protocol adapter **in-house** — there's no public adapter repo, PR, or SDK
(their docs are all about *consuming* data, not getting indexed). A protocol appears in portfolios
only when DeBank's team builds it. There are two ways to get them to build it:

1. **The proposal + vote route (primary): https://debank.com/proposal.** DeBank runs a public
   governance board where anyone posts a request — categories include *Support new protocol*,
   *Support new token*, *Support new chain*. The community votes; well-supported proposals get
   prioritised and built. Real examples: "Support new protocol: Beradrome (Vote76)", "…Chicken Miner
   (Vote279)". **This is the path the founders are taking.** Our proposal is
   *"Support new protocol: Spiral Stake"* — draft ready in [proposal-draft.md](./proposal-draft.md).
2. **The warm-contact route (accelerant):** the founders have a DeBank contact, which can shepherd
   the proposal and hand our spec straight to their engineers.

Either way, the deliverable that makes it *build-able* is the same: a precise spec + reference
implementation + test vectors, in [INTEGRATION.md](./INTEGRATION.md). What we control is making the
adapter trivial to build and impossible to get wrong; DeBank still ships it.

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

**Phase 1 — Packet (DONE, ours to build):**
- [x] Integration spec + read path + `portfolio_item` mapping — [INTEGRATION.md](./INTEGRATION.md)
- [x] Worked example against a live wallet with two positions (one per chain), exact expected JSON
- [x] Test vectors for QA
- [x] Proposal draft — [proposal-draft.md](./proposal-draft.md)
- [ ] Brand assets: logo, Twitter, audit report URLs *(founders — same set the DefiLlama PR needs)*
- [ ] *(optional)* un-gate a public `GET /v1/positions/{address}` on `mcp` for an API-based integration

**Phase 2 — Post the proposal (founders):**
1. Post *"Support new protocol: Spiral Stake"* at https://debank.com/proposal (content in the draft).
2. Confirm on-site whether creating/voting needs a DeBank web3-ID balance or fee, and satisfy it.
3. Rally votes — team, community, and especially real Spiral users; link the Dune dashboard as proof.
4. In parallel, the warm contact shepherds it and takes the spec to their engineers.

**Phase 3 — Support their build + QA:** provide test addresses + expected numbers; verify net value,
tokens, health rate, per-position split, and EOA attribution via `proxy_detail`.

**Phase 4 — Launch + verify:** confirm Spiral shows in live users' portfolios on both chains.

> Timing: current net TVL is ~$5.8k across 9 users; lead the proposal with the all-time figures
> (~$148k looped, ~$16k deposited lifetime) and the audits. Votes matter more than snapshot TVL, so
> the campaign (rallying real users to vote) is the lever — decide when you can mobilise that.

---

## Blockers & risks

1. **Approval is vote/queue-gated, no SLA.** DeBank still builds it and on their timeline. Mitigations:
   the proposal vote (rally real users) + the warm contact. Nothing we build merges it ourselves.
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
