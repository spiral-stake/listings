-- Spiral v1 — protocol revenue (10% yield fee on profitable closes), remitted to the v1 treasury by
-- the v1 contracts. v1 charged no swap fee.
WITH fees AS (
  SELECT t.evt_block_time AS bt, t.contract_address AS tok, CAST(t.value AS double) AS v
  FROM erc20_ethereum.evt_Transfer t
  WHERE t.to = 0xeB90258b1F74a846F7941514C7c02Bb03EB249D5
    AND t."from" IN (0xcAcCfC3168402668DBDCc054947Dea0101812cca, 0xD245f4C50a8de2542138084eAafA37572B178d64)
    AND t.evt_block_date >= DATE '2025-10-01'
)
SELECT date_trunc('week', f.bt) AS week,
  COUNT(*) AS fee_transfers,
  SUM(f.v / power(10, p.decimals) * p.price) AS fee_usd,
  SUM(SUM(f.v / power(10, p.decimals) * p.price)) OVER (ORDER BY date_trunc('week', f.bt)) AS cumulative_fee_usd
FROM fees f
LEFT JOIN prices.hour p ON p.blockchain='ethereum' AND p.contract_address=f.tok AND p.timestamp=date_trunc('hour', f.bt)
GROUP BY 1 ORDER BY 1 DESC
