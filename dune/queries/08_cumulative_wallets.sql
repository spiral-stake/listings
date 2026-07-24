-- Spiral Stake — cumulative unique wallets that have ever opened a position
WITH opens AS (
  SELECT 'ethereum' AS chain, block_time, bytearray_substring(topic1,13,20) AS usr
    FROM ethereum.logs
   WHERE contract_address = 0x2B12066ebD67A6A58E70b37051AbED0590E5A721
     AND topic0 = 0x2bd4e9a4bf015b6341dba92eff585a36597141e8c53ba5f7c37cef507899c39d
     AND block_time > TIMESTAMP '2026-06-16'
  UNION ALL
  SELECT 'robinhood', block_time, bytearray_substring(topic1,13,20)
    FROM robinhood.logs
   WHERE contract_address = 0x27eaF95d39cB07d544026167365689C34B4d3f9A
     AND topic0 = 0x2bd4e9a4bf015b6341dba92eff585a36597141e8c53ba5f7c37cef507899c39d
),
firsts AS (SELECT usr, MIN(block_time) AS first_open FROM opens GROUP BY 1)
SELECT date_trunc('day', first_open) AS day,
       COUNT(*) AS new_wallets,
       SUM(COUNT(*)) OVER (ORDER BY date_trunc('day', first_open)) AS cumulative_wallets
FROM firsts GROUP BY 1 ORDER BY 1
