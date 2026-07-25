-- Spiral v1 — liquidations of v1 position proxies (Morpho)
WITH proxies AS (SELECT DISTINCT proxy FROM dune.jodguy5641.result_v1_flows)
SELECT
  COUNT(*)                          AS liquidations,
  COUNT(DISTINCT l.borrower)        AS positions_liquidated,
  COALESCE(SUM(CAST(l.baddebtassets AS double)) / 1e6, 0) AS bad_debt_assets_approx
FROM morpho_blue_ethereum.morphoblue_evt_liquidate l
JOIN proxies px ON px.proxy = l.borrower
