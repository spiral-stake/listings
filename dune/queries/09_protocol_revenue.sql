-- Spiral Stake — protocol revenue.
-- The only fee the protocol earns is the 10 bps swap fee, charged by the KyberSwap/Pendle
-- aggregator on the swap input and paid to the treasury. It is a plain ERC-20 transfer with no
-- Spiral event behind it, and the treasury also receives unrelated transfers -- so this is scoped
-- strictly to transfers that occur INSIDE a Spiral transaction.
WITH ss_tx AS (
  SELECT 'ethereum' AS chain, hash FROM ethereum.transactions
   WHERE "to" IN (0x2B12066ebD67A6A58E70b37051AbED0590E5A721,
                  0x3D131d654e0C413E1cB2ab1071aad78A9470ef9d)
     AND success AND block_time > TIMESTAMP '2026-06-16'
     AND block_date >= DATE '2026-06-16'
  UNION ALL
  SELECT 'robinhood', hash FROM robinhood.transactions
   WHERE "to" IN (0x27eaF95d39cB07d544026167365689C34B4d3f9A,
                  0x5F7550Bfdd7690E1CFe90c8DbB726964f4d34877)
     AND success AND block_date >= DATE '2026-04-01'
),
fees AS (
  SELECT 'ethereum' AS chain, t.evt_block_time AS bt, t.contract_address AS tok, CAST(t.value AS double) AS v
    FROM erc20_ethereum.evt_Transfer t
    JOIN ss_tx s ON s.chain='ethereum' AND s.hash = t.evt_tx_hash
   WHERE t.to = 0x9ced716f16651b69D5167C82003690621e8F90b9
  UNION ALL
  SELECT 'robinhood', t.evt_block_time, t.contract_address, CAST(t.value AS double)
    FROM erc20_robinhood.evt_Transfer t
    JOIN ss_tx s ON s.chain='robinhood' AND s.hash = t.evt_tx_hash
   WHERE t.to = 0x9ced716f16651b69D5167C82003690621e8F90b9
     AND t.evt_block_date >= DATE '2026-04-01'
)
SELECT date_trunc('week', f.bt) AS week,
       COUNT(*) AS fee_transfers,
       SUM(f.v / power(10, p.decimals) * p.price) AS fee_usd,
       SUM(SUM(f.v / power(10, p.decimals) * p.price)) OVER (ORDER BY date_trunc('week', f.bt)) AS cumulative_fee_usd
FROM fees f
LEFT JOIN prices.hour p
  ON p.blockchain = f.chain AND p.contract_address = f.tok
 AND p.timestamp = date_trunc('hour', f.bt)
GROUP BY 1
-- newest first so a counter reading row 1 gets the running total
ORDER BY 1 DESC