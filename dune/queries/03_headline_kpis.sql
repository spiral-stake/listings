-- Spiral Stake — headline KPIs
SELECT
  SUM(net_equity_usd)                                  AS "Net TVL (user equity)",
  SUM(collateral_usd)                                  AS "Looped collateral",
  SUM(debt_usd)                                        AS "Borrowed",
  COUNT(*)                                             AS "Open positions",
  COUNT(DISTINCT user_wallet)                          AS "Wallets with open positions",
  SUM(collateral_usd) / NULLIF(SUM(net_equity_usd),0)  AS "Avg leverage (x)",
  100 * SUM(debt_usd) / NULLIF(SUM(collateral_usd),0)  AS "Avg LTV %"
FROM dune.jodguy5641.result_spiral_positions
