-- Spiral Stake — data quality: how every position is priced and how fresh that mark is
SELECT price_source,
  COUNT(*) AS positions,
  SUM(collateral_usd) AS collateral_usd,
  MAX(oracle_age_hours) AS worst_price_age_hours
FROM dune.jodguy5641.result_spiral_positions
GROUP BY 1 ORDER BY collateral_usd DESC
