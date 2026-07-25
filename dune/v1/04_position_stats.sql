-- Spiral v1 — lifetime position stats (from FlashLeverage events)
WITH ev AS (
  SELECT topic0, bytearray_substring(topic1,13,20) AS usr
  FROM ethereum.logs
  WHERE contract_address = 0xcAcCfC3168402668DBDCc054947Dea0101812cca
    AND block_date >= DATE '2025-10-01'
    AND topic0 IN (0xa4f732b8c6eeb0f534d2e40c2bfb293de7684855cdae052e554ff9d53f37a825, 0xcd2b4e62cfe22ecc5a38c25a2dce9e2dd3a29a3e10fa499505b5bfb6aec9b123)
)
SELECT
  COUNT(*) FILTER (WHERE topic0 = 0xa4f732b8c6eeb0f534d2e40c2bfb293de7684855cdae052e554ff9d53f37a825)               AS positions_opened,
  COUNT(*) FILTER (WHERE topic0 = 0xcd2b4e62cfe22ecc5a38c25a2dce9e2dd3a29a3e10fa499505b5bfb6aec9b123)               AS positions_closed,
  COUNT(DISTINCT usr) FILTER (WHERE topic0 = 0xa4f732b8c6eeb0f534d2e40c2bfb293de7684855cdae052e554ff9d53f37a825)    AS unique_users
FROM ev
