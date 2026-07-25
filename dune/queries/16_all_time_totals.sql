-- Spiral Stake — all-time cumulative flows (headline counters above the TVL chart).
-- These are LIFETIME totals (include closed positions), not the current snapshot:
--   all_time_looped   = every collateral supply to a Spiral proxy, valued at supply time
--   all_time_borrowed = every borrow by a Spiral proxy, valued at borrow time
--   all_time_deposited = looped - borrowed  (user equity contributed over the protocol's life)
-- Collateral is valued with the market Morpho oracle x loan-token USD price (same basis as the rest
-- of the dashboard), which prices PT collateral that has no DEX price on Dune. Spiral collateral
-- supplies are always remitted by FlashLeverage, so `caller` identifies them in a single scan;
-- borrows are by the position proxy, so they are matched on the proxy set from the supplies.
WITH supplies AS (
  SELECT sc.chain, sc.id, sc.onbehalf AS proxy, sc.evt_block_time AS bt, CAST(sc.assets AS double) AS assets
  FROM morpho_blue_multichain.morphoblue_evt_supplycollateral sc
  WHERE sc.chain IN ('ethereum','robinhood') AND sc.evt_block_date >= DATE '2026-04-01'
    AND ((sc.chain='ethereum'  AND sc.caller = 0x2B12066ebD67A6A58E70b37051AbED0590E5A721)
      OR (sc.chain='robinhood' AND sc.caller = 0x27eaF95d39cB07d544026167365689C34B4d3f9A))
),
proxies AS (SELECT DISTINCT chain, proxy FROM supplies),
mids AS (SELECT DISTINCT chain, id FROM supplies),
borrows AS (
  SELECT b.chain, b.id, b.evt_block_time AS bt, CAST(b.assets AS double) AS assets
  FROM morpho_blue_multichain.morphoblue_evt_borrow b
  JOIN proxies px ON px.chain=b.chain AND px.proxy=b.onbehalf
  WHERE b.chain IN ('ethereum','robinhood') AND b.evt_block_date >= DATE '2026-04-01'
),
params AS (
  SELECT cm.chain, cm.id,
         from_hex(substr(json_extract_scalar(cm.marketparams,'$.loanToken'),3)) AS loan_token,
         from_hex(substr(json_extract_scalar(cm.marketparams,'$.oracle'),3))    AS oracle
  FROM morpho_blue_multichain.morphoblue_evt_createmarket cm
  JOIN mids m ON m.chain=cm.chain AND m.id=cm.id
),
loan_px AS (
  SELECT blockchain, contract_address, timestamp, price FROM prices.hour
  WHERE timestamp >= TIMESTAMP '2026-06-01' AND contract_address IN (SELECT loan_token FROM params)
),
lt AS (SELECT blockchain, contract_address, decimals FROM tokens.erc20 WHERE contract_address IN (SELECT loan_token FROM params)),
supply_usd AS (
  SELECT SUM(s.assets * od.px_raw / power(10, 36 + lt.decimals) * lp.price) AS usd
  FROM supplies s
  JOIN params p ON p.chain=s.chain AND p.id=s.id
  JOIN lt ON lt.blockchain=s.chain AND lt.contract_address=p.loan_token
  LEFT JOIN dune.jodguy5641.result_spiral_oracle_daily od ON od.chain=s.chain AND od.oracle=p.oracle AND od.d=CAST(s.bt AS date)
  LEFT JOIN loan_px lp ON lp.blockchain=s.chain AND lp.contract_address=p.loan_token AND lp.timestamp=date_trunc('hour', s.bt)
),
borrow_usd AS (
  SELECT SUM(b.assets / power(10, lt.decimals) * lp.price) AS usd
  FROM borrows b
  JOIN params p ON p.chain=b.chain AND p.id=b.id
  JOIN lt ON lt.blockchain=b.chain AND lt.contract_address=p.loan_token
  LEFT JOIN loan_px lp ON lp.blockchain=b.chain AND lp.contract_address=p.loan_token AND lp.timestamp=date_trunc('hour', b.bt)
)
SELECT s.usd - bo.usd AS all_time_deposited_usd,
       s.usd          AS all_time_looped_usd,
       bo.usd         AS all_time_borrowed_usd
FROM supply_usd s CROSS JOIN borrow_usd bo
