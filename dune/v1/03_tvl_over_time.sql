-- Spiral v1 — TVL over time (daily, cost basis). Outstanding looped collateral, borrowed and net,
-- from the valued Morpho flows. Collateral out-flows (withdraw/liquidation) are valued at each
-- market's cost basis (avg supply price), because a pure close does not call the oracle. Shows v1
-- scaling up (Oct-Dec 2025) and winding down to ~0 as PT collateral matured (Jan-Feb 2026).
WITH cb AS (
  SELECT market_id,
         SUM(usd) FILTER (WHERE kind='collateral' AND raw > 0)
           / NULLIF(SUM(raw) FILTER (WHERE kind='collateral' AND raw > 0), 0) AS px
  FROM dune.jodguy5641.result_v1_flows GROUP BY 1
),
daily AS (
  SELECT f.day,
         SUM(CASE WHEN f.kind='collateral' THEN f.raw * cb.px ELSE 0 END) AS coll_delta,
         SUM(CASE WHEN f.kind='debt'       THEN f.usd          ELSE 0 END) AS debt_delta
  FROM dune.jodguy5641.result_v1_flows f JOIN cb ON cb.market_id = f.market_id
  GROUP BY 1
),
days AS (SELECT d FROM UNNEST(SEQUENCE(DATE '2025-10-01', CURRENT_DATE, INTERVAL '1' DAY)) AS t(d))
SELECT dy.d AS day,
  SUM(COALESCE(dd.coll_delta,0)) OVER (ORDER BY dy.d)                                       AS looped_usd,
  SUM(COALESCE(dd.debt_delta,0)) OVER (ORDER BY dy.d)                                       AS borrowed_usd,
  SUM(COALESCE(dd.coll_delta,0)) OVER (ORDER BY dy.d)
    - SUM(COALESCE(dd.debt_delta,0)) OVER (ORDER BY dy.d)                                   AS net_tvl_usd
FROM days dy LEFT JOIN daily dd ON dd.day = dy.d
ORDER BY dy.d
