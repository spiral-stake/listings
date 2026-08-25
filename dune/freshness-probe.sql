-- Freshness guard for the refresh Action (Dune query 8292626, executed by refresh-dashboard.mjs).
--
-- Reports how many days stale the daily data pipeline is, measured at the last link
-- (result_spiral_tvl_history, which depends on all three daily stages). refresh-dashboard.mjs fails
-- the run when stale_days is too high, so a silently-frozen matview surfaces as a red CI run instead
-- of user complaints.
--
-- (The all-time counters + result_spiral_alltime matview were retired 2026-08-25 — the all-time
-- "deposited" figure is a small difference of two large gross sums and went negative/misleading, and
-- dropping it also cut the credit burn. So this guard now watches tvl_history only.)
SELECT
  CAST(max(day) AS varchar)                        AS data_through,
  date_diff('day', max(day), CAST(now() AS date))  AS stale_days
FROM dune.jodguy5641.result_spiral_tvl_history
