-- Freshness guard for the refresh Action (Dune query 8292626, executed by refresh-dashboard.mjs).
--
-- Reports the WORST staleness across the two matviews heavy enough to time out on the free engine —
-- result_spiral_tvl_history and result_spiral_alltime. Either one silently freezing (a refresh that
-- exceeds the 2-minute cap) is what breaks the dashboard while the "updated" timestamp still looks
-- fresh. refresh-dashboard.mjs fails the run when stale_days is high, so a frozen matview surfaces as
-- a red CI run instead of user complaints.
--
--   tvl_history freshness = today - max(day)          (the day column advances only on a real refresh)
--   alltime freshness     = today - max(computed_on)  (computed_on = now() baked in at refresh time)
WITH t AS (
  SELECT date_diff('day', max(day), CAST(now() AS date)) AS sd, CAST(max(day) AS varchar) AS thru
  FROM dune.jodguy5641.result_spiral_tvl_history
),
a AS (
  SELECT date_diff('day', max(computed_on), CAST(now() AS date)) AS sd
  FROM dune.jodguy5641.result_spiral_alltime
)
SELECT (SELECT thru FROM t)                              AS data_through,
       GREATEST((SELECT sd FROM t), (SELECT sd FROM a))  AS stale_days
