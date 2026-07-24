-- Spiral Stake — daily per-position collateral and borrow shares
-- Feeds the TVL history chart. Spiral-side events only, so this stays cheap.
WITH cfg AS (
  SELECT * FROM (VALUES
    ('ethereum',  0x2B12066ebD67A6A58E70b37051AbED0590E5A721),
    ('robinhood', 0x27eaF95d39cB07d544026167365689C34B4d3f9A)
  ) AS t(chain, flash_leverage)
),
days AS (SELECT d FROM UNNEST(SEQUENCE(DATE '2026-06-16', CURRENT_DATE, INTERVAL '1' DAY)) AS t(d)),
proxies AS (
  SELECT DISTINCT sc.chain, sc.onbehalf AS proxy
  FROM morpho_blue_multichain.morphoblue_evt_supplycollateral sc
  JOIN cfg c ON c.chain=sc.chain AND sc.caller=c.flash_leverage
  WHERE sc.chain IN ('ethereum','robinhood') AND sc.evt_block_date >= DATE '2026-04-01'
),
ev AS (
  SELECT sc.chain, sc.id, sc.onbehalf AS proxy, sc.evt_block_date AS d,
         CAST(sc.assets AS double) AS dc, CAST(0 AS double) AS ds
    FROM morpho_blue_multichain.morphoblue_evt_supplycollateral sc
    JOIN proxies p ON p.chain=sc.chain AND p.proxy=sc.onbehalf AND sc.evt_block_date >= DATE '2026-04-01'
  UNION ALL
  SELECT wc.chain, wc.id, wc.onbehalf, wc.evt_block_date, -CAST(wc.assets AS double), 0
    FROM morpho_blue_multichain.morphoblue_evt_withdrawcollateral wc
    JOIN proxies p ON p.chain=wc.chain AND p.proxy=wc.onbehalf AND wc.evt_block_date >= DATE '2026-04-01'
  UNION ALL
  SELECT b.chain, b.id, b.onbehalf, b.evt_block_date, 0, CAST(b.shares AS double)
    FROM morpho_blue_multichain.morphoblue_evt_borrow b
    JOIN proxies p ON p.chain=b.chain AND p.proxy=b.onbehalf AND b.evt_block_date >= DATE '2026-04-01'
  UNION ALL
  SELECT r.chain, r.id, r.onbehalf, r.evt_block_date, 0, -CAST(r.shares AS double)
    FROM morpho_blue_multichain.morphoblue_evt_repay r
    JOIN proxies p ON p.chain=r.chain AND p.proxy=r.onbehalf AND r.evt_block_date >= DATE '2026-04-01'
  UNION ALL
  SELECT l.chain, l.id, l.borrower, l.evt_block_date, -CAST(l.seizedassets AS double),
         -CAST(l.repaidshares AS double)-CAST(l.baddebtshares AS double)
    FROM morpho_blue_multichain.morphoblue_evt_liquidate l
    JOIN proxies p ON p.chain=l.chain AND p.proxy=l.borrower AND l.evt_block_date >= DATE '2026-04-01'
),
daily AS (SELECT chain, id, proxy, d, SUM(dc) AS dc, SUM(ds) AS ds FROM ev GROUP BY 1,2,3,4),
keys  AS (SELECT DISTINCT chain, id, proxy FROM ev)
SELECT k.chain, k.id, k.proxy, dy.d,
       SUM(COALESCE(x.dc,0)) OVER (PARTITION BY k.chain,k.id,k.proxy ORDER BY dy.d
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS coll_raw,
       SUM(COALESCE(x.ds,0)) OVER (PARTITION BY k.chain,k.id,k.proxy ORDER BY dy.d
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS shares
FROM keys k CROSS JOIN days dy
LEFT JOIN daily x ON x.chain=k.chain AND x.id=k.id AND x.proxy=k.proxy AND x.d=dy.d
