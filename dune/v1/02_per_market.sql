-- Spiral v1 — per-market cumulative (deposited / looped / borrowed / positions)
SELECT collateral_symbol AS market, loan_symbol AS loan,
  COUNT(DISTINCT proxy)                                     AS positions,
  SUM(usd) FILTER (WHERE kind='collateral' AND raw > 0)     AS looped_usd,
  SUM(usd) FILTER (WHERE kind='debt' AND raw > 0)           AS borrowed_usd,
  SUM(usd) FILTER (WHERE kind='collateral' AND raw > 0)
    - SUM(usd) FILTER (WHERE kind='debt' AND raw > 0)       AS deposited_usd
FROM dune.jodguy5641.result_v1_flows
GROUP BY 1,2 ORDER BY looped_usd DESC
