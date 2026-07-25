# Spiral Stake — DeBank integration spec

Everything DeBank's team needs to build the adapter. All chain-derived; no Spiral API required
(though we can provide one — see the end). Reference implementation:
[../../mcp/src/execution/positions.ts](../../mcp/src/execution/positions.ts).

---

## 1. Why a bespoke adapter is needed

Each Spiral position is held by its **own `UserProxy` clone**; the Morpho collateral and debt sit
under that proxy, not under the user's wallet. So a generic Morpho Blue reader attributes the
position to an anonymous proxy contract, and the user's EOA shows nothing. The adapter must resolve
**EOA → UserProxy(es) → Morpho position** and attribute it back to the EOA via `proxy_detail`.

## 2. Contracts (both chains, all source-verified)

| | Ethereum (`eth`) | Robinhood Chain (`hood`, 4663) |
|---|---|---|
| FlashLeverage | `0x2B12066ebD67A6A58E70b37051AbED0590E5A721` | `0x27eaF95d39cB07d544026167365689C34B4d3f9A` |
| FlashLeverageRouter | `0x3D131d654e0C413E1cB2ab1071aad78A9470ef9d` | `0x5F7550Bfdd7690E1CFe90c8DbB726964f4d34877` |
| Morpho Blue | `0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb` | `0x9D53d5E3bd5E8d4Cbfa6DB1ca238AEA02E651010` |

ABIs: `FlashLeverage.sol`, `IMorpho.sol` in the Spiral repo (`v2-client/src/abi/`).

## 3. Read path (per user EOA, per chain)

```
positions = FlashLeverage.getUserLeveragePositions(user)
  → array of { open, marketId, userProxy, amountDepositedInLoanToken, amountReturnedInLoanToken }
  → position id = array index

for each position where open == true and userProxy != 0x0:
    market = Morpho.idToMarketParams(marketId)      // loanToken, collateralToken, oracle, irm, lltv
    p      = FlashLeverage.getMorphoPosition(userProxy, market)   // { collateral, borrowShares }
    debt   = FlashLeverage.getSharesValueInLoanToken(market, p.borrowShares)   // loan-token units

    collateral_amount = p.collateral        / 10^collateralDecimals
    debt_amount       = debt                / 10^loanDecimals
    // Collateral USD via the market's Morpho oracle (this is the mark that governs liquidation and
    // the value Spiral's own UI uses; it prices Pendle PT collateral, which has no DEX/CG price):
    oracle_price      = IOracle(market.oracle).price()           // 1e36-scaled, collateral→loan
    collateral_in_loan = collateral_amount * oracle_price / 10^(36 + loanDec - collDec)
    collateral_usd    = collateral_in_loan * loanTokenUsdPrice
    debt_usd          = debt_amount       * loanTokenUsdPrice
    net_usd           = collateral_usd - debt_usd
    // liquidation health, same basis as Spiral's UI:
    health_rate       = (collateral_in_loan * (market.lltv / 1e18)) / debt_amount
```

`proxy → user` can also be indexed from `UserProxy.ProxyInitialized(address indexed user)` if a
reverse map is preferred; but `getUserLeveragePositions(user)` is the direct forward path.

Notes:
- Only `open` positions with a non-zero `userProxy` and non-zero collateral should render.
- A position is economically closed when its Morpho collateral is 0 (covers liquidations too).
- Loan tokens are all major stablecoins / WETH — standard DeBank pricing applies.

## 4. DeBank `portfolio_item` mapping

| DeBank field | value |
|---|---|
| `name` | `"Leverage"` |
| `detail_types` | `["leveraged_farming"]` (or `["lending"]`) |
| `detail.supply_token_list[]` | collateral token, `amount` = `collateral_amount` |
| `detail.borrow_token_list[]` | loan token, `amount` = `debt_amount` |
| `detail.health_rate` | `health_rate` |
| `stats.asset_usd_value` | `collateral_usd` |
| `stats.debt_usd_value` | `debt_usd` |
| `stats.net_usd_value` | `net_usd` |
| `proxy_detail.project_id` / proxy address | the position's `userProxy` |

## 5. Worked example (live data, 2026-07-25)

Wallet **`0xc15073a2f754caefecde4c6e58e5a3100dff9a43`** — has two open Spiral positions, one on each
chain. The adapter should attribute **both** to this EOA.

### Position A — Ethereum, sDOLA / USDC (proxy `0xc3b07395add2e28dc506bdefc6e1694abbdade9d`)
```json
{
  "name": "Leverage",
  "detail_types": ["leveraged_farming"],
  "detail": {
    "supply_token_list": [
      { "chain": "eth", "id": "0xb45ad160634c528Cc3D2926d9807104FA3157305",
        "symbol": "sDOLA", "decimals": 18, "amount": 1515.977728, "price": 1.3976 }
    ],
    "borrow_token_list": [
      { "chain": "eth", "id": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        "symbol": "USDC", "decimals": 6, "amount": 1925.166734, "price": 1.0003 }
    ],
    "health_rate": 1.007
  },
  "stats": { "asset_usd_value": 2118.79, "debt_usd_value": 1925.75, "net_usd_value": 193.04 },
  "proxy_detail": { "proxy": "0xc3b07395add2e28dc506bdefc6e1694abbdade9d" }
}
```

### Position B — Robinhood Chain, syrupUSDG / USDG (proxy `0x6e65c65fcd4110f59ca535696bdfa84d3e6db322`)
```json
{
  "name": "Leverage",
  "detail_types": ["leveraged_farming"],
  "detail": {
    "supply_token_list": [
      { "chain": "hood", "id": "0x40858070814a57FdF33a613ae84fE0a8b4a874f7",
        "symbol": "syrupUSDG", "decimals": 6, "amount": 942.824238, "price": 1.0052 }
    ],
    "borrow_token_list": [
      { "chain": "hood", "id": "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168",
        "symbol": "USDG", "decimals": 6, "amount": 857.025496, "price": 1.0014 }
    ],
    "health_rate": 1.010
  },
  "stats": { "asset_usd_value": 947.77, "debt_usd_value": 858.22, "net_usd_value": 89.55 },
  "proxy_detail": { "proxy": "0x6e65c65fcd4110f59ca535696bdfa84d3e6db322" }
}
```

## 6. Test vectors for QA (live, 2026-07-25)

| Wallet | Chain | Market | Net USD | Health |
|---|---|---|---|---|
| `0xc15073a2f754caefecde4c6e58e5a3100dff9a43` | eth | sDOLA/USDC | ~$193 | ~1.01 |
| `0xc15073a2f754caefecde4c6e58e5a3100dff9a43` | hood | syrupUSDG/USDG | ~$90 | ~1.01 |
| `0x47c9fd3afd07ec00a2264c74fa4ac889f11454cc` | hood | USDe/USDG | ~$3.3 | ~1.01 |

These are small (protocol is early); the numbers move with price/interest, so match *shape and
attribution* first, then values within a tolerance. The Dune dashboard is an independent cross-check:
https://dune.com/jodguy5641/spiral-stake-protocol-dashboard

## 7. Optional: hosted API instead of a chain spec

If DeBank prefers an API over reading chain directly, we can expose a public
`GET /v1/positions/{address}` on `api.spiralstake.xyz` returning the resolved positions (net value,
collateral, debt, health, proxy) per the shape above — the logic already exists in
[../../mcp/src/execution/positions.ts](../../mcp/src/execution/positions.ts). Chain-native is
preferred for trust-minimisation; the API is a convenience if they want it.
