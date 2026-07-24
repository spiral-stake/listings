# DefiLlama TVL adapter — Spiral Stake

`projects/spiral-stake/index.js` mirrors its target path inside
[DefiLlama/DefiLlama-Adapters](https://github.com/DefiLlama/DefiLlama-Adapters), so it drops in
unchanged. **Not submitted** — hold until we decide to file the PR.

## How it computes TVL

1. `getLogs` on `FlashLeverage` for `LeveragePositionOpened` → every user that has ever opened a
   position. (Target-filtered, so the log volume is tiny and cacheable.)
2. `getUserLeveragePositions(user)` → that user's positions, each with `open`, `marketId`,
   `userProxy`. FlashLeverage is its own registry, so this stays correct through closes,
   liquidations and leverage increases.
3. `morpho.idToMarketParams(marketId)` → market params.
4. `getMorphoPosition(userProxy, marketParams)` → `{ collateral, borrowShares }`, and
   `getSharesValueInLoanToken(...)` → debt in loan-token units (the protocol's own share→assets
   conversion, so it matches what a close would actually repay).
5. `tvl` = collateral − debt · `borrowed` = debt · `doublecounted: true`.

Positions are held by per-position `UserProxy` clones, which is why step 1–2 exist: the collateral
is never under the user's own address.

## Why tvl is net of debt

The only new value Spiral brings into Morpho is the user's own margin — the leveraged portion is
flash-borrowed and immediately repaid out of the Morpho borrow. The collateral is *already* counted
in Morpho Blue's TVL (Morpho Blue is listed on DefiLlama on both our chains), so reporting the gross
looped figure would be plain double counting.

Same shape as [Contango](https://github.com/DefiLlama/DefiLlama-Adapters/blob/main/projects/contango-v2/index.js)
(`tvl` = collateral − debt, `borrowed` = debt, `doublecounted: true`) and Origami Finance.

## Testing

```sh
git clone --depth 1 https://github.com/DefiLlama/DefiLlama-Adapters.git
cd DefiLlama-Adapters && npm install
cp -r <this dir>/projects/spiral-stake projects/
node test.js projects/spiral-stake/index.js
node test.js projects/spiral-stake/index.js 2026-07-01   # timetravel check
```

Results (2026-07-23):

| | tvl | borrowed |
|---|---|---|
| ethereum | $5.68k | $33.75k |
| robinhood | $131 | $889 |
| **total** | **$5.81k** | **$34.64k** |

Cross-checked against an independent implementation (nonce-derived proxy enumeration + viem +
our own price feed, `LISTINGS-PLAN.md` §1): $5,814 net equity / $34,635 borrowed. Agreement to
within price-source noise on syrupUSDG.

Timetravel at 2026-07-01 returns $223 tvl / $2.15k borrowed with robinhood at 0 (pre-launch) —
historical backfill works.

No unknown-token or stale-price warnings. No npm dependencies added.

### ⚠️ The Robinhood leg often fails when tested locally — this is expected

`node test.js` will frequently report:

```
------ FAILED (2) ------
robinhood                 Llama RPC error! host: https://robinhoodchain.blockscout.com/api/eth-rpc
                          Request failed with status code 429
```

That is the **public Blockscout endpoint rate-limiting**, not a defect in the adapter. Measured
directly: the endpoint returns 429 on the *third* sequential request. Any adapter doing more than a
couple of calls will fail against it from a local machine.

DefiLlama's production infrastructure reads the chain without trouble — Morpho Blue currently
reports **$206.9M TVL / $197.8M borrowed on Robinhood Chain**, and the chain totals $306.6M — so
this does not affect the listing.

Two consequences worth knowing:

1. **When validating locally, judge the Ethereum leg.** Ethereum carries ~98% of Spiral's TVL
   ($5.65k of $5.74k net equity), so a green Ethereum run is a meaningful check.
2. **Mention it in the PR** so a reviewer who runs the test locally does not reject on a red
   Robinhood result. Offer a better Robinhood RPC if they want one — we have an Alchemy endpoint
   configured in `mcp/.env` (`ROBINHOOD_RPC_URL`).

## PR metadata — still needed from the founders

Everything else in the PR template is answered in `LISTINGS-PLAN.md` §2.1.

- [ ] High-resolution logo
- [ ] Official Twitter link
- [ ] Public audit report URLs (Sherlock, Cyfrin, Phage)
- [ ] CoinGecko ID / CoinMarketCap ID (leave empty if no token)
- [ ] Token address + ticker, if any

Pre-filled:

- **Name**: Spiral Stake
- **Website**: https://app.spiralstake.xyz
- **Chain**: Ethereum, Robinhood Chain
- **Category**: Leveraged Farming
- **forkedFrom**: none
- **Treasury**: `0x9ced716f16651b69D5167C82003690621e8F90b9`
- **Oracle**: per-market Morpho Blue oracles — Spiral inherits whichever oracle each Morpho market
  is configured with, rather than operating its own. Market list and per-market `oracle` addresses:
  `v2-client/src/addresses/{1,4663}.json`.
- **Github org**: (optional — only if we want commit activity tracked)
- **Referral program**: (see `REFERRAL-PLAN.md` — confirm whether it's live before answering)
