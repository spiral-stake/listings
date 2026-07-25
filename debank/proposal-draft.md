# DeBank proposal — draft (ready to post)

Post at **https://debank.com/proposal** → create proposal. DeBank's proposal categories include
"Support new protocol", "Support new token", "Support new chain". Ours is **Support new protocol**.
Community votes prioritise it; once it passes, DeBank's team builds the adapter using
[INTEGRATION.md](./INTEGRATION.md).

> Confirm the current proposal-creation mechanics on the site before posting (whether it needs a
> minimum DeBank web3-ID/voting balance or a small fee — DeBank changes this over time). The content
> below is what to paste; the mechanics are DeBank's to enforce.

---

### Title

```
Support new protocol: Spiral Stake
```

### Category / chains

Leveraged Farming · Ethereum + Robinhood Chain

### Description (paste)

**Spiral Stake** is a non-custodial, risk-aware leverage engine for onchain yield, built on Morpho.
Users deposit a yield-bearing asset and open a leveraged position in a single transaction (flash-loan
→ swap → supply → borrow → repay), with no manual looping. Positions are isolated per user and the
protocol never takes custody. Audited by Sherlock, Cyfrin, and Phage Security.

**Why DeBank users want this:** Spiral positions are held in per-position proxy contracts, so today
they do **not** show up in a user's DeBank portfolio even though the underlying collateral/debt sits
in Morpho Blue (which DeBank already indexes). Users who leverage through Spiral currently can't see
those positions — their collateral, debt, net value, and liquidation health — anywhere in DeBank.
A Spiral adapter surfaces them correctly, attributed to the user's own wallet.

- Website: https://app.spiralstake.xyz
- Docs: https://docs.spiralstake.xyz  *(confirm final URL)*
- Twitter: *(add)*
- Audits: Sherlock, Cyfrin, Phage — *(add report links)*
- Chains: Ethereum (`eth`), Robinhood Chain (`hood`, id 4663)

**Integration is straightforward** and fully specified for your team (contracts, position-resolution,
and the exact `portfolio_item` mapping incl. `proxy_detail`): see the technical packet linked in the
comments. Positions read from one contract call per user; collateral is priced by each market's
Morpho oracle. A worked example against a live wallet with two open positions (one per chain) is
included so results can be matched exactly.

### For DeBank's engineers (link the packet)

Full spec + worked example + test vectors: `listings/debank/INTEGRATION.md` (in the Spiral repo; we
can share directly). One-line summary: **given a user EOA, call
`FlashLeverage.getUserLeveragePositions(user)` → per position read the proxy's Morpho collateral/debt
→ emit a `leveraged_farming` portfolio item with `proxy_detail` = the position's UserProxy.**

---

## Assets to attach (gather once — reused for the DefiLlama listing too)

- [ ] Logo — high-res, square, transparent PNG/SVG
- [ ] Official Twitter/X handle
- [ ] Public audit report URLs (Sherlock, Cyfrin, Phage)
- [ ] Final docs URL
- [ ] One-line + one-paragraph descriptions (above is a draft)

## Campaign notes

- A proposal is prioritised by **votes**, so line up support before/at posting: team wallets, community,
  and anyone with DeBank web3-IDs. Real Spiral users voting is the strongest signal.
- Lead the pitch with the *all-time* traction ($148k looped, $16k deposited lifetime — see the Dune
  dashboard) and the audits, not the current snapshot.
- Link the live Dune dashboard as third-party-verifiable proof of activity:
  https://dune.com/jodguy5641/spiral-stake-protocol-dashboard
