-- Spiral v1 (Ethereum, wound down). One row per Morpho flow by a v1 position proxy, valued at event
-- time. Collateral = Pendle PTs, priced by the market Morpho oracle read from the flow's OWN tx
-- (the leverage/close tx calls price() in its health-check), so traces stay scoped to v1 txs.
-- kind='collateral': supply(+), withdraw(-), liquidation seize(-). kind='debt': borrow(+), repay(-),
-- liquidation repaid/baddebt(-). Spiral v1 collateral supplies are remitted by FlashLeverageCore.
WITH supplies AS (
  SELECT sc.id, sc.onbehalf AS proxy, sc.evt_tx_hash AS tx, sc.evt_block_time AS bt, CAST(sc.assets AS double) AS assets
  FROM morpho_blue_ethereum.morphoblue_evt_supplycollateral sc
  WHERE sc.caller = 0xD245f4C50a8de2542138084eAafA37572B178d64
),
proxies AS (SELECT DISTINCT proxy FROM supplies),
mids AS (SELECT DISTINCT id FROM supplies),
params AS (
  SELECT cm.id,
         from_hex(substr(json_extract_scalar(cm.marketparams,'$.loanToken'),3))       AS loan_token,
         from_hex(substr(json_extract_scalar(cm.marketparams,'$.collateralToken'),3)) AS collateral_token,
         from_hex(substr(json_extract_scalar(cm.marketparams,'$.oracle'),3))          AS oracle
  FROM morpho_blue_ethereum.morphoblue_evt_createmarket cm JOIN mids m ON m.id = cm.id
),
lt  AS (SELECT contract_address, symbol, decimals FROM tokens.erc20 WHERE blockchain='ethereum' AND contract_address IN (SELECT loan_token FROM params)),
ct  AS (SELECT contract_address, symbol, decimals FROM tokens.erc20 WHERE blockchain='ethereum' AND contract_address IN (SELECT collateral_token FROM params)),
-- raw collateral + debt flows
flows AS (
  SELECT 'collateral' AS kind, sc.id, sc.onbehalf AS proxy, sc.evt_tx_hash AS tx, sc.evt_block_time AS bt, CAST(sc.assets AS double) AS raw
    FROM morpho_blue_ethereum.morphoblue_evt_supplycollateral sc WHERE sc.caller = 0xD245f4C50a8de2542138084eAafA37572B178d64
  UNION ALL
  SELECT 'collateral', wc.id, wc.onbehalf, wc.evt_tx_hash, wc.evt_block_time, -CAST(wc.assets AS double)
    FROM morpho_blue_ethereum.morphoblue_evt_withdrawcollateral wc JOIN proxies px ON px.proxy = wc.onbehalf
  UNION ALL
  SELECT 'collateral', l.id, l.borrower, l.evt_tx_hash, l.evt_block_time, -CAST(l.seizedassets AS double)
    FROM morpho_blue_ethereum.morphoblue_evt_liquidate l JOIN proxies px ON px.proxy = l.borrower
  UNION ALL
  SELECT 'debt', b.id, b.onbehalf, b.evt_tx_hash, b.evt_block_time, CAST(b.assets AS double)
    FROM morpho_blue_ethereum.morphoblue_evt_borrow b JOIN proxies px ON px.proxy = b.onbehalf
  UNION ALL
  SELECT 'debt', r.id, r.onbehalf, r.evt_tx_hash, r.evt_block_time, -CAST(r.assets AS double)
    FROM morpho_blue_ethereum.morphoblue_evt_repay r JOIN proxies px ON px.proxy = r.onbehalf
  UNION ALL
  SELECT 'debt', l.id, l.borrower, l.evt_tx_hash, l.evt_block_time, -CAST(l.repaidassets AS double) - CAST(l.baddebtassets AS double)
    FROM morpho_blue_ethereum.morphoblue_evt_liquidate l JOIN proxies px ON px.proxy = l.borrower
),
otx AS (
  SELECT t.tx_hash, t."to" AS oracle, MAX(bytearray_to_uint256(t.output)) AS px_raw
  FROM ethereum.traces t
  WHERE t.input = 0xa035b1fe AND t.success AND t.output IS NOT NULL
    AND t.block_date BETWEEN DATE '2025-10-01' AND DATE '2026-02-01'
    AND t.tx_hash IN (SELECT DISTINCT tx FROM flows)
    AND t."to" IN (SELECT oracle FROM params)
  GROUP BY 1,2
),
loan_px AS (
  SELECT contract_address, timestamp, price FROM prices.hour
  WHERE blockchain='ethereum' AND timestamp >= TIMESTAMP '2025-10-01' AND contract_address IN (SELECT loan_token FROM params)
)
SELECT
  f.kind, f.id AS market_id, f.proxy, f.tx, f.bt AS block_time, CAST(f.bt AS date) AS day,
  ct.symbol AS collateral_symbol, lt.symbol AS loan_symbol,
  f.raw,
  CASE WHEN f.kind='collateral'
       THEN f.raw * o.px_raw / power(10, 36 + lt.decimals) * lp.price
       ELSE f.raw / power(10, lt.decimals) * lp.price END AS usd
FROM flows f
JOIN params p ON p.id = f.id
JOIN lt ON lt.contract_address = p.loan_token
JOIN ct ON ct.contract_address = p.collateral_token
LEFT JOIN otx o ON o.tx_hash = f.tx AND o.oracle = p.oracle
LEFT JOIN loan_px lp ON lp.contract_address = p.loan_token AND lp.timestamp = date_trunc('hour', f.bt)
