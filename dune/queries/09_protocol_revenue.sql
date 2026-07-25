-- Spiral Stake — protocol revenue (10 bps swap fee)
--
-- The protocol's only fee is the 10 bps swap fee charged by the KyberSwap / Pendle aggregator and
-- remitted to the treasury. It is a plain ERC-20 transfer with no Spiral event behind it, and the
-- on-chain yield/deposit fee switches are 0% (permanently).
--
-- Scoping: count transfers INTO the treasury that are REMITTED BY the Spiral contracts
-- (FlashLeverage / FlashLeverageRouter) on each chain. This is the robust definition:
--   * It captures BOTH fee-charging swaps in an open — the leverage swap (loan -> collateral) and
--     the swapAndLeverage pre-swap (input -> collateral) — because the Spiral contract remits the
--     fee in both cases, regardless of which aggregator executed the swap or what the tx `to` was.
--   * Scoping by the transaction's `to` (an earlier version) undercounted, because the pre-swap
--     rides in a transaction called on the aggregator, not on a Spiral contract.
--   * The treasury is a general SAFE, so we do NOT sum all of its inflows — only what its own
--     contracts sent as swap fees.
-- A small tail of fees remitted directly by an aggregator is intentionally excluded to keep the
-- definition provably Spiral-only.
WITH fees AS (
  SELECT 'ethereum' AS chain, t.evt_block_time AS bt, t.contract_address AS tok, CAST(t.value AS double) AS v
    FROM erc20_ethereum.evt_Transfer t
   WHERE t.to = 0x9ced716f16651b69D5167C82003690621e8F90b9                 -- treasury / fee receiver
     AND t."from" IN (0x2B12066ebD67A6A58E70b37051AbED0590E5A721,          -- FlashLeverage
                      0x3D131d654e0C413E1cB2ab1071aad78A9470ef9d)          -- FlashLeverageRouter
     AND t.evt_block_date >= DATE '2026-06-01'
  UNION ALL
  SELECT 'robinhood', t.evt_block_time, t.contract_address, CAST(t.value AS double)
    FROM erc20_robinhood.evt_Transfer t
   WHERE t.to = 0x9ced716f16651b69D5167C82003690621e8F90b9
     AND t."from" IN (0x27eaF95d39cB07d544026167365689C34B4d3f9A,          -- FlashLeverage
                      0x5F7550Bfdd7690E1CFe90c8DbB726964f4d34877)          -- FlashLeverageRouter
     AND t.evt_block_date >= DATE '2026-06-01'
)
SELECT date_trunc('week', f.bt) AS week,
       COUNT(*) AS fee_transfers,
       SUM(f.v / power(10, p.decimals) * p.price) AS fee_usd,
       SUM(SUM(f.v / power(10, p.decimals) * p.price)) OVER (ORDER BY date_trunc('week', f.bt)) AS cumulative_fee_usd
FROM fees f
LEFT JOIN prices.hour p
  ON p.blockchain = f.chain AND p.contract_address = f.tok
 AND p.timestamp = date_trunc('hour', f.bt)
GROUP BY 1
-- newest first so the "total revenue" counter reads row 1 and gets the full running cumulative
ORDER BY 1 DESC
