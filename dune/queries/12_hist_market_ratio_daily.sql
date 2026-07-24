-- Spiral Stake — daily market borrow ratio (totalBorrowAssets / totalBorrowShares)
--
-- Feeds the TVL history chart. A position's debt is its borrow SHARES times this market-wide ratio
-- as it stood on that day, so historical debt reflects interest actually accrued by then rather
-- than today's ratio applied backwards.
-- Market totals are all-user and must be summed from market inception. No Spiral market existed
-- before 2025-12-14, so that floor prunes the scan without changing the result.
WITH mkts AS (
  SELECT DISTINCT sc.chain, sc.id
  FROM morpho_blue_multichain.morphoblue_evt_supplycollateral sc
  WHERE sc.chain IN ('ethereum','robinhood') AND sc.evt_block_date >= DATE '2026-04-01'
    AND ((sc.chain='ethereum'  AND sc.caller=0x2B12066ebD67A6A58E70b37051AbED0590E5A721)
      OR (sc.chain='robinhood' AND sc.caller=0x27eaF95d39cB07d544026167365689C34B4d3f9A))
),
days AS (SELECT d FROM UNNEST(SEQUENCE(DATE '2026-06-16', CURRENT_DATE, INTERVAL '1' DAY)) AS t(d)),
ev AS (
  SELECT b.chain, b.id, b.evt_block_date AS d, CAST(b.assets AS double) AS da, CAST(b.shares AS double) AS ds
    FROM morpho_blue_multichain.morphoblue_evt_borrow b JOIN mkts m ON m.chain=b.chain AND m.id=b.id
   WHERE b.evt_block_date >= DATE '2025-12-01'
  UNION ALL
  SELECT r.chain, r.id, r.evt_block_date, -CAST(r.assets AS double), -CAST(r.shares AS double)
    FROM morpho_blue_multichain.morphoblue_evt_repay r JOIN mkts m ON m.chain=r.chain AND m.id=r.id
   WHERE r.evt_block_date >= DATE '2025-12-01'
  UNION ALL
  SELECT l.chain, l.id, l.evt_block_date,
         -CAST(l.repaidassets AS double)-CAST(l.baddebtassets AS double),
         -CAST(l.repaidshares AS double)-CAST(l.baddebtshares AS double)
    FROM morpho_blue_multichain.morphoblue_evt_liquidate l JOIN mkts m ON m.chain=l.chain AND m.id=l.id
   WHERE l.evt_block_date >= DATE '2025-12-01'
  UNION ALL
  SELECT a.chain, a.id, a.evt_block_date, CAST(a.interest AS double), CAST(0 AS double)
    FROM morpho_blue_multichain.morphoblue_evt_accrueinterest a JOIN mkts m ON m.chain=a.chain AND m.id=a.id
   WHERE a.evt_block_date >= DATE '2025-12-01'
),
seed AS (SELECT chain, id, SUM(da) AS da0, SUM(ds) AS ds0 FROM ev WHERE d < DATE '2026-06-16' GROUP BY 1,2),
inw  AS (SELECT chain, id, d, SUM(da) AS da, SUM(ds) AS ds FROM ev WHERE d >= DATE '2026-06-16' GROUP BY 1,2,3)
SELECT m.chain, m.id, dy.d,
       COALESCE(s.da0,0) + SUM(COALESCE(i.da,0)) OVER (PARTITION BY m.chain,m.id ORDER BY dy.d
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS tba,
       COALESCE(s.ds0,0) + SUM(COALESCE(i.ds,0)) OVER (PARTITION BY m.chain,m.id ORDER BY dy.d
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS tbs
FROM mkts m CROSS JOIN days dy
LEFT JOIN seed s ON s.chain=m.chain AND s.id=m.id
LEFT JOIN inw i  ON i.chain=m.chain AND i.id=m.id AND i.d=dy.d
