-- Spiral Stake — Morpho oracle prices (collateral -> loan token), read from the price() staticcall
-- Morpho makes on every health check. This is the mark that governs liquidation and the same value
-- the Spiral app uses. Prices every collateral including Pendle PTs, which have no DEX/CoinGecko price.
WITH spiral_oracles AS (
  SELECT DISTINCT cm.chain,
         from_hex(substr(json_extract_scalar(cm.marketparams,'$.oracle'),3)) AS oracle
  FROM morpho_blue_multichain.morphoblue_evt_createmarket cm
  JOIN (
    SELECT DISTINCT sc.chain, sc.id
    FROM morpho_blue_multichain.morphoblue_evt_supplycollateral sc
    WHERE (sc.chain='ethereum'  AND sc.caller = 0x2B12066ebD67A6A58E70b37051AbED0590E5A721)
       OR (sc.chain='robinhood' AND sc.caller = 0x27eaF95d39cB07d544026167365689C34B4d3f9A)
  ) m ON m.chain=cm.chain AND m.id=cm.id
)
SELECT chain, oracle, MAX_BY(px_raw, block_time) AS px_raw, MAX(block_time) AS px_time
FROM (
  SELECT 'ethereum' AS chain, t."to" AS oracle, bytearray_to_uint256(t.output) AS px_raw, t.block_time
    FROM ethereum.traces t
   WHERE t.input = 0xa035b1fe AND t.success AND t.output IS NOT NULL
     AND t.block_time > now() - INTERVAL '30' day
     AND t."to" IN (SELECT oracle FROM spiral_oracles WHERE chain='ethereum')
  UNION ALL
  SELECT 'robinhood', t."to", bytearray_to_uint256(t.output), t.block_time
    FROM robinhood.traces t
   WHERE t.input = 0xa035b1fe AND t.success AND t.output IS NOT NULL
     AND t.block_time > now() - INTERVAL '30' day
     AND t."to" IN (SELECT oracle FROM spiral_oracles WHERE chain='robinhood')
) GROUP BY 1,2
