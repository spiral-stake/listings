# DefiLlama listing — ready-to-file PR

Everything below is final. The TVL adapter is `projects/spiral-stake/index.js` (in this folder); the
logo is `spiral-stake.svg` (bundled here, sourced from app.spiralstake.xyz/logo.svg). Filing needs a
GitHub account with a fork of DefiLlama-Adapters — steps at the bottom.

---

## Protocol metadata (for the listing entry)

| Field | Value |
|---|---|
| **Name** | Spiral Stake |
| **Website** | https://spiralstake.xyz  (dapp: https://app.spiralstake.xyz) |
| **Logo** | `spiral-stake.svg` (vector) — hosted at https://app.spiralstake.xyz/logo.svg |
| **Twitter / X** | https://x.com/0xspiralstake |
| **Category** | Leveraged Farming |
| **Chains** | Ethereum, Robinhood Chain |
| **Token** | none (no CoinGecko / CMC id) |
| **forkedFrom** | none |
| **Treasury** | `0x9ced716f16651b69D5167C82003690621e8F90b9` |
| **Oracle** | per-market Morpho Blue oracles (Spiral inherits each Morpho market's configured oracle; it runs none of its own) |
| **Adapter start** | 2026-06-16 |
| **Audits** | Phage (2026-01-20), Cyfrin (2026-03-12), Sherlock (2026-04-27) — links below |

**Audit report URLs**
- Phage: https://github.com/spiral-stake/v2-core/blob/main/audits/2026-01-20-phage-spiral-stake-v2.pdf
- Cyfrin: https://github.com/spiral-stake/v2-core/blob/main/audits/2026-03-12-cyfrin-spiral-stake-v2.pdf
- Sherlock: https://github.com/spiral-stake/v2-core/blob/main/audits/2026-04-27-sherlock-spiral-stake-v2.pdf

> ⚠️ Pre-flight: confirm `spiral-stake/v2-core` is a **public** repo so the audit PDF links resolve
> for reviewers. If it's private, either make it public or host the three PDFs on docs.spiralstake.xyz
> and swap the links.

---

## Suggested PR title

`Add Spiral Stake`

## Suggested PR body (paste into the PR)

> **Spiral Stake** — one-transaction leveraged positions ("looping") on Morpho Blue. Flash-borrow the
> loan token, swap to collateral, supply, borrow against it, repay the flash loan. Each position is
> held by its own `UserProxy` clone.
>
> **TVL methodology.** `tvl` = collateral − debt across all open Spiral positions (i.e. only the
> user's own margin), `borrowed` = debt, and the module is flagged **`doublecounted: true`**. The
> leveraged collateral is flash-borrowed and already counted inside Morpho Blue's TVL (Morpho Blue is
> listed on DefiLlama on both chains), so reporting the gross looped figure would double-count. Same
> shape as the Contango and Origami adapters. Discovery is via the `LeveragePositionOpened` event
> (target-filtered) + `getUserLeveragePositions`, so it stays correct through closes, liquidations and
> leverage increases.
>
> **Chains:** Ethereum + Robinhood Chain.
>
> **Note for reviewers running `test.js` locally:** the Robinhood leg may 429 against the public
> Blockscout RPC (`robinhoodchain.blockscout.com`) — that endpoint rate-limits on the 3rd sequential
> call. It is not an adapter defect; DefiLlama's production infra reads the chain fine (Morpho Blue
> reports ~$207M there). Judge the Ethereum leg locally (it carries ~98% of TVL). Happy to provide an
> Alchemy Robinhood RPC if useful.
>
> Metadata (name, website, logo, twitter, category, audits, treasury, no token) in the PR
> description / attached.

---

## Filing steps

```sh
# 1. Fork https://github.com/DefiLlama/DefiLlama-Adapters on GitHub, then:
git clone https://github.com/<your-user>/DefiLlama-Adapters.git
cd DefiLlama-Adapters && npm install

# 2. Drop in the adapter
mkdir -p projects/spiral-stake
cp <listings>/defillama/projects/spiral-stake/index.js projects/spiral-stake/index.js

# 3. Sanity-check (Ethereum leg is the meaningful one locally; see reviewer note)
node test.js projects/spiral-stake/index.js

# 4. Branch, commit, push, open PR to DefiLlama/DefiLlama-Adapters:main
git checkout -b spiral-stake
git add projects/spiral-stake/index.js
git commit -m "Add Spiral Stake"
git push origin spiral-stake
# open the PR with the title + body above
```

The logo + full metadata go in the PR description (DefiLlama wires them into their protocol config).
There is no token, so leave CoinGecko / CMC / token-address fields empty.
