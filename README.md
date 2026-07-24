# Spiral Stake — listings & analytics

Public-data deliverables for getting Spiral Stake tracked by third-party platforms. Everything here
is derived from chain data; nothing depends on a private Spiral API.

## Contents

- **[dune/](dune/)** — the public [protocol dashboard](https://dune.com/jodguy5641/spiral-stake-protocol-dashboard)
  (TVL, positions, users, revenue, liquidations, risk, TVL-over-time). All query SQL, the data-model
  writeup, and the daily refresh cron live here.
- **[defillama/](defillama/)** — the DefiLlama TVL adapter (`projects/spiral-stake/index.js`),
  validated against DefiLlama's own test harness. Not yet submitted.

## The refresh cron (already wired up)

`.github/workflows/refresh-dune-dashboard.yml` runs `dune/refresh-dashboard.mjs` daily to keep the
Dune dashboard current. **It needs one repository secret: `DUNE_API_KEY`** (Settings → Secrets and
variables → Actions). Once that's set it runs on its own; trigger it manually anytime from the
Actions tab. Details in [dune/README.md](dune/README.md).

## Chains

Ethereum mainnet (1) and Robinhood Chain (4663).
