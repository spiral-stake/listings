-- Spiral Stake — position state (Ethereum + Robinhood Chain)
--
-- One row per open Spiral position. Everything is reconstructed from chain data only:
--   * A Spiral position lives under a per-position UserProxy clone, identified as the `onBehalf`
--     of collateral supplied BY the FlashLeverage contract.
--   * Collateral is exact: Morpho collateral does not accrue, so supply - withdraw - seized.
--   * Debt = the position's borrow shares converted with the market's own
--     totalBorrowAssets/totalBorrowShares, both rebuilt from Morpho events (incl. AccrueInterest).
--   * Collateral is valued with the MARKET'S OWN MORPHO ORACLE, read from the `price()` staticcall
--     that Morpho makes on every health check. This is the mark that governs liquidation, and it is
--     the same value the Spiral app uses (getCollateralValueInLoanToken). It prices every collateral
--     -- including Pendle PTs, which have no DEX or CoinGecko price -- with no per-token special casing.
--     Only the loan tokens need an external price, and those are all major stablecoins / WETH.
WITH cfg AS (
  SELECT * FROM (VALUES
    ('ethereum',  0x2B12066ebD67A6A58E70b37051AbED0590E5A721),
    ('robinhood', 0x27eaF95d39cB07d544026167365689C34B4d3f9A)
  ) AS t(chain, flash_leverage)
),
proxies AS (
  SELECT DISTINCT sc.chain, sc.onbehalf AS proxy
  FROM morpho_blue_multichain.morphoblue_evt_supplycollateral sc
  JOIN cfg c ON c.chain = sc.chain AND sc.caller = c.flash_leverage
  WHERE sc.chain IN ('ethereum','robinhood')
    AND sc.evt_block_date >= DATE '2026-04-01'
),
coll AS (
  SELECT chain, id, proxy, SUM(d) AS collateral_raw FROM (
    SELECT sc.chain, sc.id, sc.onbehalf AS proxy, CAST(sc.assets AS double) AS d
      FROM morpho_blue_multichain.morphoblue_evt_supplycollateral sc
      JOIN proxies p ON p.chain=sc.chain AND p.proxy=sc.onbehalf
       AND sc.evt_block_date >= DATE '2026-04-01'
       AND sc.chain IN ('ethereum','robinhood')
    UNION ALL
    SELECT wc.chain, wc.id, wc.onbehalf, -CAST(wc.assets AS double)
      FROM morpho_blue_multichain.morphoblue_evt_withdrawcollateral wc
      JOIN proxies p ON p.chain=wc.chain AND p.proxy=wc.onbehalf
       AND wc.evt_block_date >= DATE '2026-04-01'
       AND wc.chain IN ('ethereum','robinhood')
    UNION ALL
    SELECT l.chain, l.id, l.borrower, -CAST(l.seizedassets AS double)
      FROM morpho_blue_multichain.morphoblue_evt_liquidate l
      JOIN proxies p ON p.chain=l.chain AND p.proxy=l.borrower
       AND l.evt_block_date >= DATE '2026-04-01'
       AND l.chain IN ('ethereum','robinhood')
  ) GROUP BY 1,2,3
),
pos_shares AS (
  SELECT chain, id, proxy, SUM(d) AS borrow_shares FROM (
    SELECT b.chain, b.id, b.onbehalf AS proxy, CAST(b.shares AS double) AS d
      FROM morpho_blue_multichain.morphoblue_evt_borrow b
      JOIN proxies p ON p.chain=b.chain AND p.proxy=b.onbehalf
       AND b.evt_block_date >= DATE '2026-04-01'
       AND b.chain IN ('ethereum','robinhood')
    UNION ALL
    SELECT r.chain, r.id, r.onbehalf, -CAST(r.shares AS double)
      FROM morpho_blue_multichain.morphoblue_evt_repay r
      JOIN proxies p ON p.chain=r.chain AND p.proxy=r.onbehalf
       AND r.evt_block_date >= DATE '2026-04-01'
       AND r.chain IN ('ethereum','robinhood')
    UNION ALL
    SELECT l.chain, l.id, l.borrower, -CAST(l.repaidshares AS double)-CAST(l.baddebtshares AS double)
      FROM morpho_blue_multichain.morphoblue_evt_liquidate l
      JOIN proxies p ON p.chain=l.chain AND p.proxy=l.borrower
       AND l.evt_block_date >= DATE '2026-04-01'
       AND l.chain IN ('ethereum','robinhood')
  ) GROUP BY 1,2,3
),
mkts AS (SELECT DISTINCT chain, id FROM coll),
mkt_totals AS (
  SELECT chain, id, SUM(da) AS tba, SUM(ds) AS tbs FROM (
    SELECT b.chain, b.id, CAST(b.assets AS double) da, CAST(b.shares AS double) ds
      FROM morpho_blue_multichain.morphoblue_evt_borrow b JOIN mkts m ON m.chain=b.chain AND m.id=b.id
       AND b.chain IN ('ethereum','robinhood')
    UNION ALL
    SELECT r.chain, r.id, -CAST(r.assets AS double), -CAST(r.shares AS double)
      FROM morpho_blue_multichain.morphoblue_evt_repay r JOIN mkts m ON m.chain=r.chain AND m.id=r.id
       AND r.chain IN ('ethereum','robinhood')
    UNION ALL
    SELECT l.chain, l.id, -CAST(l.repaidassets AS double)-CAST(l.baddebtassets AS double),
                          -CAST(l.repaidshares AS double)-CAST(l.baddebtshares AS double)
      FROM morpho_blue_multichain.morphoblue_evt_liquidate l JOIN mkts m ON m.chain=l.chain AND m.id=l.id
       AND l.chain IN ('ethereum','robinhood')
    UNION ALL
    SELECT a.chain, a.id, CAST(a.interest AS double), CAST(0 AS double)
      FROM morpho_blue_multichain.morphoblue_evt_accrueinterest a JOIN mkts m ON m.chain=a.chain AND m.id=a.id
       AND a.chain IN ('ethereum','robinhood')
  ) GROUP BY 1,2
),
params AS (
  SELECT cm.chain, cm.id,
         from_hex(substr(json_extract_scalar(marketparams,'$.loanToken'),3))       AS loan_token,
         from_hex(substr(json_extract_scalar(marketparams,'$.collateralToken'),3)) AS collateral_token,
         from_hex(substr(json_extract_scalar(marketparams,'$.oracle'),3))          AS oracle,
         CAST(json_extract_scalar(marketparams,'$.lltv') AS double)/1e18 * 100     AS liq_ltv_pct
  FROM morpho_blue_multichain.morphoblue_evt_createmarket cm
  JOIN mkts m ON m.chain=cm.chain AND m.id=cm.id
       AND cm.chain IN ('ethereum','robinhood')
),
oracle_px AS (   -- hourly matview of Morpho oracle price() staticcalls
  SELECT chain, oracle, px_raw, px_time FROM dune.jodguy5641.result_spiral_oracle_prices
),
tok AS (SELECT blockchain, contract_address, symbol, decimals FROM tokens.erc20),
owner AS (   -- proxy -> user, from UserProxy.ProxyInitialized(address indexed user)
  SELECT chain, proxy, MAX_BY(usr, bn) AS user_wallet FROM (
    SELECT 'ethereum' AS chain, contract_address AS proxy,
           bytearray_substring(topic1,13,20) AS usr, block_number AS bn
      FROM ethereum.logs
     WHERE topic0 = 0x68b33a756922ab06deed8220bf7ff19324fdda29dab838d4b114acf93cedae3b
       AND block_time > TIMESTAMP '2026-06-16'
    UNION ALL
    SELECT 'robinhood', contract_address, bytearray_substring(topic1,13,20), block_number
      FROM robinhood.logs
     WHERE topic0 = 0x68b33a756922ab06deed8220bf7ff19324fdda29dab838d4b114acf93cedae3b
  ) GROUP BY 1,2
),
valued AS (
  SELECT
    c.chain,
    ct.symbol AS collateral_symbol,
    lt.symbol AS loan_symbol,
    o2.user_wallet,
    c.proxy,
    c.id AS market_id,
    p.liq_ltv_pct,
    c.collateral_raw / power(10, ct.decimals) AS collateral_units,
    CAST(o.px_raw AS double) / power(10, 36 + lt.decimals - ct.decimals) AS oracle_price,
    cp.price AS collateral_px_fallback,
    lp.price AS loan_price_usd,
    o.px_time AS oracle_price_at,
    (CASE WHEN mt.tbs > 0 THEN COALESCE(s.borrow_shares,0) * (mt.tba/mt.tbs) ELSE 0 END)
      / power(10, lt.decimals) AS debt_units
  FROM coll c
  LEFT JOIN pos_shares s  ON s.chain=c.chain  AND s.id=c.id AND s.proxy=c.proxy
  LEFT JOIN mkt_totals mt ON mt.chain=c.chain AND mt.id=c.id
  JOIN params p           ON p.chain=c.chain  AND p.id=c.id
  LEFT JOIN oracle_px o   ON o.chain=c.chain  AND o.oracle=p.oracle
  LEFT JOIN tok ct        ON ct.blockchain=c.chain AND ct.contract_address=p.collateral_token
  LEFT JOIN tok lt        ON lt.blockchain=c.chain AND lt.contract_address=p.loan_token
  LEFT JOIN prices.latest lp ON lp.blockchain=c.chain AND lp.contract_address=p.loan_token
  LEFT JOIN prices.latest cp ON cp.blockchain=c.chain AND cp.contract_address=p.collateral_token
  LEFT JOIN owner o2      ON o2.chain=c.chain AND o2.proxy=c.proxy
  WHERE c.collateral_raw > 0 OR COALESCE(s.borrow_shares,0) > 0
),
priced AS (
  SELECT v.*,
         collateral_units * oracle_price * loan_price_usd AS usd_oracle,
         collateral_units * collateral_px_fallback        AS usd_market,
         date_diff('hour', oracle_price_at, now())        AS oracle_age_hours
  FROM valued v
),
final AS (
  SELECT p.*,
         -- The Morpho oracle is the protocol's own mark and the one that governs liquidation, so
         -- it is preferred. But a market whose oracle has not been called recently has a stale
         -- mark, so past a 48h threshold a live market price is used instead when one exists.
         -- Pendle PTs have no market price at all, so they keep the oracle mark and are labelled
         -- STALE rather than silently dropped.
         CASE WHEN usd_oracle IS NOT NULL AND oracle_age_hours <= 48 THEN usd_oracle
              WHEN usd_market IS NOT NULL                            THEN usd_market
              ELSE usd_oracle END                                    AS collateral_usd,
         CASE WHEN usd_oracle IS NOT NULL AND oracle_age_hours <= 48 THEN 'morpho_oracle'
              WHEN usd_market IS NOT NULL                            THEN 'market_price (oracle stale)'
              WHEN usd_oracle IS NOT NULL                            THEN 'morpho_oracle (STALE)'
              ELSE 'UNPRICED' END                                    AS price_source,
         debt_units * loan_price_usd                                 AS debt_usd
  FROM priced p
)
SELECT
  chain,
  collateral_symbol,
  loan_symbol,
  collateral_symbol || ' / ' || loan_symbol AS market,
  market_id,
  user_wallet,
  proxy,
  collateral_units,
  debt_units,
  oracle_price,
  collateral_usd,
  debt_usd,
  collateral_usd - debt_usd                                    AS net_equity_usd,
  100 * debt_usd / NULLIF(collateral_usd, 0)                   AS ltv_pct,
  liq_ltv_pct,
  liq_ltv_pct - 100 * debt_usd / NULLIF(collateral_usd, 0)     AS ltv_headroom_pct,
  collateral_usd / NULLIF(collateral_usd - debt_usd, 0)        AS leverage_x,
  price_source,
  oracle_age_hours
FROM final
