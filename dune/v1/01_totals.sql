-- Spiral v1 — all-time totals (headline counters). v1 is wound down; these are lifetime cumulative.
SELECT
  SUM(usd) FILTER (WHERE kind='collateral' AND raw > 0)
    - SUM(usd) FILTER (WHERE kind='debt' AND raw > 0)                 AS all_time_deposited_usd,
  SUM(usd) FILTER (WHERE kind='collateral' AND raw > 0)               AS all_time_looped_usd,
  SUM(usd) FILTER (WHERE kind='debt' AND raw > 0)                     AS all_time_borrowed_usd,
  SUM(usd) FILTER (WHERE kind='collateral' AND raw > 0)
    / NULLIF(SUM(usd) FILTER (WHERE kind='collateral' AND raw > 0)
             - SUM(usd) FILTER (WHERE kind='debt' AND raw > 0), 0)     AS avg_leverage_x
FROM dune.jodguy5641.result_v1_flows
