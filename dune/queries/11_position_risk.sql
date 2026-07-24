-- Spiral Stake — position risk
-- Distance from liquidation for every open position. Headroom is the market's liquidation LTV
-- minus the position's current LTV, both computed from the same Morpho oracle mark that Morpho
-- itself uses to decide solvency. Negative headroom means liquidatable right now.
SELECT
  chain,
  market,
  collateral_usd,
  debt_usd,
  ltv_pct,
  liq_ltv_pct,
  ltv_headroom_pct,
  leverage_x,
  price_source,
  oracle_age_hours
FROM dune.jodguy5641.result_spiral_positions
ORDER BY ltv_headroom_pct ASC
