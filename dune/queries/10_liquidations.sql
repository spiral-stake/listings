-- Spiral Stake — liquidations
-- Morpho Liquidate events whose borrower is a Spiral position proxy. Aggregates always return a
-- row, so the counters read 0 rather than going blank when there have been no liquidations.
WITH proxies AS (
  SELECT DISTINCT sc.chain, sc.onbehalf AS proxy
  FROM morpho_blue_multichain.morphoblue_evt_supplycollateral sc
  WHERE sc.chain IN ('ethereum','robinhood')
    AND ( (sc.chain='ethereum'  AND sc.caller = 0x2B12066ebD67A6A58E70b37051AbED0590E5A721)
       OR (sc.chain='robinhood' AND sc.caller = 0x27eaF95d39cB07d544026167365689C34B4d3f9A) )
),
liq AS (
  SELECT l.chain, l.id, l.borrower, l.evt_block_time,
         CAST(l.seizedassets  AS double) AS seized,
         CAST(l.repaidassets  AS double) AS repaid,
         CAST(l.baddebtassets AS double) AS bad_debt
  FROM morpho_blue_multichain.morphoblue_evt_liquidate l
  JOIN proxies p ON p.chain = l.chain AND p.proxy = l.borrower
  WHERE l.chain IN ('ethereum','robinhood')
),
params AS (
  SELECT cm.chain, cm.id,
         from_hex(substr(json_extract_scalar(cm.marketparams,'$.loanToken'),3))       AS loan_token,
         from_hex(substr(json_extract_scalar(cm.marketparams,'$.collateralToken'),3)) AS collateral_token
  FROM morpho_blue_multichain.morphoblue_evt_createmarket cm
  WHERE cm.chain IN ('ethereum','robinhood')
    AND cm.id IN (SELECT id FROM liq)
),
priced AS (
  SELECT l.*,
         l.seized   / power(10, ct.decimals) * cp.price AS seized_usd,
         l.repaid   / power(10, lt.decimals) * lp.price AS repaid_usd,
         l.bad_debt / power(10, lt.decimals) * lp.price AS bad_debt_usd
  FROM liq l
  LEFT JOIN params p        ON p.chain=l.chain AND p.id=l.id
  LEFT JOIN tokens.erc20 ct ON ct.blockchain=l.chain AND ct.contract_address=p.collateral_token
  LEFT JOIN tokens.erc20 lt ON lt.blockchain=l.chain AND lt.contract_address=p.loan_token
  LEFT JOIN prices.latest cp ON cp.blockchain=l.chain AND cp.contract_address=p.collateral_token
  LEFT JOIN prices.latest lp ON lp.blockchain=l.chain AND lp.contract_address=p.loan_token
)
SELECT
  COUNT(*)                                  AS "Liquidations",
  COUNT(DISTINCT borrower)                  AS "Positions liquidated",
  COALESCE(SUM(seized_usd), 0)              AS "Collateral seized (USD)",
  COALESCE(SUM(bad_debt_usd), 0)            AS "Bad debt (USD)",
  MAX(evt_block_time)                       AS "Last liquidation"
FROM priced
