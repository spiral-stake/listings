# DefiLlama listing — ready-to-file PR

TVL adapter: `projects/spiral-stake/index.js` (in this folder). Logo: `spiral-stake.svg` (bundled,
from app.spiralstake.xyz/logo.svg). Everything below maps 1:1 to DefiLlama's current PR template.

---

## ⚠️ Before you open the PR — repo notes from the template

- **Tick "Allow edits by maintainers"** on the PR page (the template explicitly requires it).
- **Do NOT commit `package-lock.json`** — this repo uses **pnpm**; `npm install` left a stray
  `package-lock.json` in the tree. Delete it (`rm package-lock.json`) and commit **only**
  `projects/spiral-stake/index.js`. **Do not edit or push `pnpm-lock.yaml`**, and add no npm deps
  (we added none).
- **Not a fetch adapter** — TVL is computed from on-chain Morpho state (`getLogs` + `multiCall`), which
  is what they now require. ✅
- Fees/volume adapters go in a **separate** repo (`DefiLlama/dimension-adapters`) — optional, later.
- To change listing info **after** merge, email **metadata@defillama.com**.
- After merge it can take up to ~24h to appear on the UI; ping their Discord if longer.

---

## Template fields — copy-paste answers

**Name (to be shown on DefiLlama):**
Spiral Stake

**Twitter Link:**
https://x.com/0xspiralstake

**List of audit links if any:**
- Phage Security (2026-01-20): https://github.com/spiral-stake/v2-core/blob/main/audits/2026-01-20-phage-spiral-stake-v2.pdf
- Cyfrin (2026-03-12): https://github.com/spiral-stake/v2-core/blob/main/audits/2026-03-12-cyfrin-spiral-stake-v2.pdf
- Sherlock (2026-04-27): https://github.com/spiral-stake/v2-core/blob/main/audits/2026-04-27-sherlock-spiral-stake-v2.pdf

**Website Link:**
https://spiralstake.xyz

**Logo (High resolution, will be shown with rounded borders):**
https://app.spiralstake.xyz/logo.svg  (vector; also attached to the PR as spiral-stake.svg)

**Current TVL:**
~$7,000 net equity across Ethereum + Robinhood Chain (computed live from chain by the adapter). Note
the gross looped collateral (~$194k lifetime) is intentionally NOT counted — see methodology.

**Treasury Addresses (if the protocol has treasury):**
0x9ced716f16651b69D5167C82003690621e8F90b9

**Chain:**
Ethereum, Robinhood Chain

**Coingecko ID:**
(none — no token)

**Coinmarketcap ID:**
(none — no token)

**Short Description (to be shown on DefiLlama):**
Spiral Stake opens one-transaction leveraged ("looping") positions on Morpho Blue markets — flash-borrow the loan asset, swap to collateral, supply, and borrow against it — with each position held in its own proxy.

**Token address and ticker if any:**
None (no token).

**Category (choose one):**
Leveraged Farming

**Oracle Provider(s):**
Per-market Morpho Blue oracles (inherited). Spiral operates no oracle of its own; each position is
valued and liquidated by the oracle configured on its Morpho Blue market — which varies by market
(Chainlink/RedStone-style feeds for liquid collateral, Pendle PT oracles for PT collateral, etc.).

**Implementation Details (how the oracle is integrated):**
Spiral does not integrate a price oracle directly. Positions live in Morpho Blue markets, and each
market's own oracle governs collateral valuation and liquidation. The TVL adapter reads raw on-chain
collateral and debt token amounts from Morpho (no price feed of its own); DefiLlama prices the tokens.

**Documentation/Proof (oracle usage):**
https://docs.spiralstake.xyz — per-market `oracle` addresses are on-chain via Morpho
`idToMarketParams`, and mirrored in v2-client/src/addresses/{1,4663}.json.

**forkedFrom:**
None.

**methodology (what is counted as TVL, how it is calculated):**
TVL = collateral − debt summed over all open Spiral positions (only the user's own margin), because
the leveraged portion is flash-borrowed and immediately repaid out of the Morpho borrow. Debt is
reported separately as `borrowed`. The collateral is already inside Morpho Blue's TVL, so the module
is flagged `doublecounted: true`. Positions are discovered via the `LeveragePositionOpened` event and
`getUserLeveragePositions`, then valued from Morpho on-chain state (`getMorphoPosition` /
`getSharesValueInLoanToken`). Same shape as Contango and Origami.

**Github org/user (Optional):**
https://github.com/spiral-stake

**Does this project have a referral program?**
[CONFIRM before submitting — see REFERRAL-PLAN.md; answer Yes/No]

---

## Filing steps (in your terminal, from this clone)

```sh
cd /Users/bhimgoudapatil/Desktop/spiral-stake/v2/defillama-adapters
rm -f package-lock.json                       # stray npm lockfile — repo uses pnpm; do not commit it
git add projects/spiral-stake/index.js        # ONLY the adapter
git commit -m "Add Spiral Stake"
git push -u origin spiral-stake
```

Then open the PR (base `DefiLlama/DefiLlama-Adapters:main`, head `spiral-stake:spiral-stake`), title
`Add Spiral Stake`, paste the template answers above, attach `spiral-stake.svg`, and **tick "Allow
edits by maintainers."**

Or, if the GitHub CLI is authenticated:
```sh
gh pr create --repo DefiLlama/DefiLlama-Adapters \
  --base main --head spiral-stake:spiral-stake \
  --title "Add Spiral Stake" --body-file ../listings/defillama/PR.md
```
