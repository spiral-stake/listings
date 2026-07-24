-- Spiral Stake — daily Morpho oracle marks, forward-filled
-- Feeds the TVL history chart. Oracles are only called when a market is touched, so days with no
-- observation carry the last known mark forward; days before the first observation are backfilled
-- from it so a position is never valued at zero for want of a price.
WITH mkts AS (
  SELECT DISTINCT sc.chain, sc.id
  FROM morpho_blue_multichain.morphoblue_evt_supplycollateral sc
  WHERE sc.chain IN ('ethereum','robinhood') AND sc.evt_block_date >= DATE '2026-04-01'
    AND ((sc.chain='ethereum'  AND sc.caller=0x2B12066ebD67A6A58E70b37051AbED0590E5A721)
      OR (sc.chain='robinhood' AND sc.caller=0x27eaF95d39cB07d544026167365689C34B4d3f9A))
),
days AS (SELECT d FROM UNNEST(SEQUENCE(DATE '2026-06-16', CURRENT_DATE, INTERVAL '1' DAY)) AS t(d)),
params AS (
  SELECT cm.chain, from_hex(substr(json_extract_scalar(cm.marketparams,'$.oracle'),3)) AS oracle
  FROM morpho_blue_multichain.morphoblue_evt_createmarket cm
  JOIN mkts m ON m.chain=cm.chain AND m.id=cm.id
),
obs AS (
  SELECT chain, oracle, d, MAX_BY(px, bt) AS px_raw FROM (
    SELECT 'ethereum' AS chain, t."to" AS oracle, t.block_date AS d,
           bytearray_to_uint256(t.output) AS px, t.block_time AS bt
      FROM ethereum.traces t
     WHERE t.input = 0xa035b1fe AND t.success AND t.output IS NOT NULL
       AND t.block_date >= DATE '2026-06-16'
       AND t."to" IN (SELECT oracle FROM params WHERE chain='ethereum')
    UNION ALL
    SELECT 'robinhood', t."to", t.block_date, bytearray_to_uint256(t.output), t.block_time
      FROM robinhood.traces t
     WHERE t.input = 0xa035b1fe AND t.success AND t.output IS NOT NULL
       AND t.block_date >= DATE '2026-06-16'
       AND t."to" IN (SELECT oracle FROM params WHERE chain='robinhood')
  ) GROUP BY 1,2,3
),
keys AS (SELECT DISTINCT chain, oracle FROM obs)
SELECT k.chain, k.oracle, dy.d,
       COALESCE(
         last_value(o.px_raw)  IGNORE NULLS OVER (PARTITION BY k.chain,k.oracle ORDER BY dy.d
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
         first_value(o.px_raw) IGNORE NULLS OVER (PARTITION BY k.chain,k.oracle ORDER BY dy.d
                               ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
       ) AS px_raw
FROM keys k CROSS JOIN days dy
LEFT JOIN obs o ON o.chain=k.chain AND o.oracle=k.oracle AND o.d=dy.d
