-- Spiral v1 — weekly opens vs closes
WITH ev AS (
  SELECT block_time, topic0
  FROM ethereum.logs
  WHERE contract_address = 0xcAcCfC3168402668DBDCc054947Dea0101812cca
    AND block_date >= DATE '2025-10-01'
    AND topic0 IN (0xa4f732b8c6eeb0f534d2e40c2bfb293de7684855cdae052e554ff9d53f37a825, 0xcd2b4e62cfe22ecc5a38c25a2dce9e2dd3a29a3e10fa499505b5bfb6aec9b123)
)
SELECT date_trunc('week', block_time) AS week,
  COUNT(*) FILTER (WHERE topic0 = 0xa4f732b8c6eeb0f534d2e40c2bfb293de7684855cdae052e554ff9d53f37a825) AS opened,
  COUNT(*) FILTER (WHERE topic0 = 0xcd2b4e62cfe22ecc5a38c25a2dce9e2dd3a29a3e10fa499505b5bfb6aec9b123) AS closed
FROM ev GROUP BY 1 ORDER BY 1
