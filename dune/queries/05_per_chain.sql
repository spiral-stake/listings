-- Spiral Stake — per-chain split
SELECT chain,
  COUNT(*) AS positions,
  COUNT(DISTINCT user_wallet) AS users,
  SUM(collateral_usd) AS collateral_usd,
  SUM(debt_usd) AS debt_usd,
  SUM(net_equity_usd) AS net_equity_usd
FROM dune.jodguy5641.result_spiral_positions
GROUP BY 1 ORDER BY net_equity_usd DESC
