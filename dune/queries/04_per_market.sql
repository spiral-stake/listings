-- Spiral Stake — per-market breakdown
-- Grouped by Morpho market id, not by token-pair name: Spiral supports several distinct markets
-- that share a collateral/loan pair but differ in liquidation LTV, and grouping by name alone
-- would silently merge them.
SELECT
  chain,
  market,
  MAX(liq_ltv_pct)                                     AS liq_ltv_pct,
  COUNT(*)                                             AS positions,
  COUNT(DISTINCT user_wallet)                          AS users,
  SUM(collateral_usd)                                  AS collateral_usd,
  SUM(debt_usd)                                        AS debt_usd,
  SUM(net_equity_usd)                                  AS net_equity_usd,
  100 * SUM(debt_usd) / NULLIF(SUM(collateral_usd),0)  AS ltv_pct,
  SUM(collateral_usd) / NULLIF(SUM(net_equity_usd),0)  AS leverage_x
FROM dune.jodguy5641.result_spiral_positions
GROUP BY chain, market, market_id
ORDER BY net_equity_usd DESC
