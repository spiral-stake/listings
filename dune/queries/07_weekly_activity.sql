-- Spiral Stake — weekly activity (opens, closes, manage actions, active wallets)
WITH ev AS (
  SELECT 'ethereum' AS chain, block_time, topic0, bytearray_substring(topic1,13,20) AS usr
    FROM ethereum.logs
   WHERE contract_address = 0x2B12066ebD67A6A58E70b37051AbED0590E5A721
     AND block_time > TIMESTAMP '2026-06-16'
  UNION ALL
  SELECT 'robinhood', block_time, topic0, bytearray_substring(topic1,13,20)
    FROM robinhood.logs
   WHERE contract_address = 0x27eaF95d39cB07d544026167365689C34B4d3f9A
)
SELECT date_trunc('week', block_time) AS week,
  COUNT(*) FILTER (WHERE topic0 = 0x2bd4e9a4bf015b6341dba92eff585a36597141e8c53ba5f7c37cef507899c39d) AS opened,
  COUNT(*) FILTER (WHERE topic0 = 0xcd2b4e62cfe22ecc5a38c25a2dce9e2dd3a29a3e10fa499505b5bfb6aec9b123) AS closed,
  COUNT(*) FILTER (WHERE topic0 IN (
      0xf517db8078797f466e934d2ca4fe2c5072a34139ef8f196dca3951d33c6c789b,
      0xc7ce0a35f17b490de2a317e7fecb2cae86b1abffb03800b2f492823521382698,
      0xacedbbea27e4adae17a27d3054028064954fb77c9983e2cb9e698b0de18d73ac,
      0xdaed309a628faec6cab72194019e2a1a34e890ca9bf9be99788992dd54692819)) AS manage_actions,
  COUNT(DISTINCT usr) FILTER (WHERE topic0 = 0x2bd4e9a4bf015b6341dba92eff585a36597141e8c53ba5f7c37cef507899c39d) AS wallets_opening
FROM ev
GROUP BY 1 ORDER BY 1
