-- Spiral Stake — TVL over time
--
-- Joins three daily stages, each materialized separately because the full derivation does not fit
-- in one execution:
--   result_spiral_pos_daily        per-position collateral + borrow shares, per day
--   result_spiral_mkt_ratio_daily  market totalBorrowAssets / totalBorrowShares, per day
--   result_spiral_oracle_daily     Morpho oracle mark, per day, forward-filled
--
-- Debt is the position's shares times the market ratio AS IT STOOD THAT DAY, so history reflects
-- interest actually accrued by then rather than today's ratio applied backwards. Collateral is
-- valued with the same Morpho oracle the snapshot and the app use, so the last point on this chart
-- reconciles with the headline counters.
--
-- PERF (2026-08-11): refresh was timing out at the 2-min engine cap once history grew. loan prices
-- read from prices.day (24x smaller than prices.hour) with an explicit blockchain IN (...) partition
-- filter; token decimals from a filtered tokens.erc20. ~4 cr, well under the cap.
-- CURRENT-DAY FIX (2026-08-12): prices.day has no row for "today" when the matview refreshes just
-- after midnight, which made today's point null (a gap/zero at the end of the chart). The loan price
-- is now forward-filled from prices.latest, so today shows. Loan tokens are stablecoins, so latest vs
-- the day's mean is a negligible difference, and historical days (which have a prices.day row) are
-- unchanged — COALESCE only fills the missing current day.
WITH mkts AS (SELECT DISTINCT chain, id FROM dune.jodguy5641.result_spiral_pos_daily),
params AS (
  SELECT cm.chain, cm.id,
         from_hex(substr(json_extract_scalar(cm.marketparams,'$.loanToken'),3))       AS loan_token,
         from_hex(substr(json_extract_scalar(cm.marketparams,'$.collateralToken'),3)) AS collateral_token,
         from_hex(substr(json_extract_scalar(cm.marketparams,'$.oracle'),3))          AS oracle
  FROM morpho_blue_multichain.morphoblue_evt_createmarket cm
  JOIN mkts m ON m.chain=cm.chain AND m.id=cm.id
),
relevant AS (
  SELECT chain, loan_token AS tok FROM params
  UNION SELECT chain, collateral_token FROM params
),
tok AS (
  SELECT t.blockchain, t.contract_address, t.decimals
  FROM tokens.erc20 t
  JOIN relevant r ON r.chain = t.blockchain AND r.tok = t.contract_address
),
loan_px AS (
  SELECT blockchain AS chain, contract_address AS tok, CAST(timestamp AS date) AS d, AVG(price) AS price
  FROM prices.day
  WHERE blockchain IN ('ethereum','robinhood')
    AND timestamp >= TIMESTAMP '2026-06-16'
    AND contract_address IN (SELECT loan_token FROM params)
  GROUP BY 1,2,3
),
latest_px AS (   -- forward-fill for "today", which prices.day has not populated yet at refresh time
  SELECT blockchain AS chain, contract_address AS tok, price
  FROM prices.latest
  WHERE blockchain IN ('ethereum','robinhood') AND contract_address IN (SELECT loan_token FROM params)
),
valued AS (
  SELECT ps.d, ps.chain,
         ps.coll_raw / power(10, ct.decimals)
           * (CAST(op.px_raw AS double) / power(10, 36 + lt.decimals - ct.decimals))
           * COALESCE(lp.price, llx.price)                                  AS collateral_usd,
         (CASE WHEN mr.tbs > 0 THEN ps.shares * (mr.tba / mr.tbs) ELSE 0 END)
           / power(10, lt.decimals) * COALESCE(lp.price, llx.price)         AS debt_usd
  FROM dune.jodguy5641.result_spiral_pos_daily ps
  JOIN params p  ON p.chain=ps.chain AND p.id=ps.id
  JOIN dune.jodguy5641.result_spiral_mkt_ratio_daily mr
                 ON mr.chain=ps.chain AND mr.id=ps.id AND mr.d=ps.d
  LEFT JOIN dune.jodguy5641.result_spiral_oracle_daily op
                 ON op.chain=ps.chain AND op.oracle=p.oracle AND op.d=ps.d
  LEFT JOIN tok ct ON ct.blockchain=ps.chain AND ct.contract_address=p.collateral_token
  LEFT JOIN tok lt ON lt.blockchain=ps.chain AND lt.contract_address=p.loan_token
  LEFT JOIN loan_px lp ON lp.chain=ps.chain AND lp.tok=p.loan_token AND lp.d=ps.d
  LEFT JOIN latest_px llx ON llx.chain=ps.chain AND llx.tok=p.loan_token
  WHERE ps.coll_raw > 0 OR ps.shares > 0
)
SELECT d AS day,
       SUM(collateral_usd)                  AS looped_collateral_usd,
       SUM(debt_usd)                        AS borrowed_usd,
       SUM(collateral_usd) - SUM(debt_usd)  AS net_tvl_usd
FROM valued
GROUP BY d
ORDER BY d
