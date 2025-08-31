-- 03_sp_generate_alerts.sql
USE maatritva;

-- 1) Idempotence guard: 1 alert per user+type per day
-- (MySQL 8.0.29+ supports IF NOT EXISTS on ADD COLUMN / CREATE INDEX)
ALTER TABLE alerts
  ADD COLUMN IF NOT EXISTS alert_day DATE
    GENERATED ALWAYS AS (DATE(created_at)) STORED;

CREATE UNIQUE INDEX IF NOT EXISTS ux_alert_unique_day
  ON alerts (user_id, alert_type, alert_day);

-- 2) Helper view: current (or most recent) caregiver per user
DROP VIEW IF EXISTS vw_current_caregiver;
CREATE VIEW vw_current_caregiver AS
SELECT user_id, caregiver_id
FROM (
  SELECT
    user_id, caregiver_id,
    ROW_NUMBER() OVER (
      PARTITION BY user_id
      ORDER BY COALESCE(valid_to, '9999-12-31') DESC, valid_from DESC
    ) AS rn
  FROM user_caregiver_hist
) t
WHERE rn = 1;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_generate_alerts $$
CREATE PROCEDURE sp_generate_alerts()
BEGIN
  DECLARE now_ts DATETIME DEFAULT NOW();
  DECLARE today  DATE     DEFAULT CURRENT_DATE();

  /* ---------- Rule A: High PHQ (>=15 in last 14d; latest per user) ---------- */
  WITH recent_phq AS (
    SELECT user_id, phq_id, scored_at, total_score,
           ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY scored_at DESC) AS rn
    FROM phq_scores
    WHERE scored_at >= now_ts - INTERVAL 14 DAY
  )
  INSERT INTO alerts (user_id, alert_type, created_at, caregiver_id, details)
  SELECT rp.user_id, 'high_phq', now_ts, vc.caregiver_id,
         JSON_OBJECT('score', rp.total_score, 'scored_at', rp.scored_at, 'rule','high_phq_14d')
  FROM recent_phq rp
  LEFT JOIN vw_current_caregiver vc ON vc.user_id = rp.user_id
  WHERE rp.rn = 1 AND rp.total_score >= 15
  ON DUPLICATE KEY UPDATE user_id = alerts.user_id;  -- no-op, keeps idempotent

  /* ---------- Rule B: Inactivity (no journal in last 7d) ---------- */
  WITH last_j AS (
    SELECT user_id, MAX(ts) AS last_journal_at
    FROM journals
    GROUP BY user_id
  )
  INSERT INTO alerts (user_id, alert_type, created_at, caregiver_id, details)
  SELECT u.user_id, 'inactivity_7d', now_ts, vc.caregiver_id,
         JSON_OBJECT('last_journal_at', lj.last_journal_at, 'rule','inactivity_7d')
  FROM users u
  LEFT JOIN last_j lj ON lj.user_id = u.user_id
  LEFT JOIN vw_current_caregiver vc ON vc.user_id = u.user_id
  WHERE (lj.last_journal_at IS NULL OR lj.last_journal_at < now_ts - INTERVAL 7 DAY)
  ON DUPLICATE KEY UPDATE user_id = alerts.user_id;

  /* ---------- Rule C: 3-day negative streak (ending recently) ---------- */
  WITH day_sentiment AS (
    SELECT user_id, DATE(ts) AS ts_date,
           MIN(CASE sentiment WHEN 'negative' THEN 1 WHEN 'neutral' THEN 2 ELSE 3 END) AS mood_rank
    FROM journals
    GROUP BY user_id, DATE(ts)
  ),
  neg_days AS (SELECT user_id, ts_date FROM day_sentiment WHERE mood_rank = 1),
  runs AS (
    SELECT user_id, ts_date,
           DATEDIFF(ts_date,'2000-01-01')
           - ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY ts_date) AS grp
    FROM neg_days
  ),
  streaks AS (
    SELECT user_id, MIN(ts_date) AS start_date, MAX(ts_date) AS end_date, COUNT(*) AS streak_len
    FROM runs
    GROUP BY user_id, grp
    HAVING COUNT(*) >= 3
  )
  INSERT INTO alerts (user_id, alert_type, created_at, caregiver_id, details)
  SELECT s.user_id, 'neg_streak_3d', now_ts, vc.caregiver_id,
         JSON_OBJECT('start_date', s.start_date, 'end_date', s.end_date, 'len', s.streak_len, 'rule','neg_streak_3d_recent')
  FROM streaks s
  JOIN vw_current_caregiver vc ON vc.user_id = s.user_id
  WHERE s.end_date >= (today - INTERVAL 2 DAY)  -- don’t re-alert old streaks
  ON DUPLICATE KEY UPDATE user_id = alerts.user_id;

  /* ---------- TRIAGE: one queue item per today’s alert ---------- */
  INSERT INTO triage_queue (alert_id, assigned_to, priority, due_at, state)
  SELECT a.alert_id,
         a.caregiver_id,
         CASE a.alert_type
           WHEN 'high_phq'      THEN 'high'
           WHEN 'neg_streak_3d' THEN 'high'
           ELSE 'medium'
         END AS priority,
         CASE a.alert_type
           WHEN 'high_phq'      THEN now_ts + INTERVAL 24 HOUR
           WHEN 'neg_streak_3d' THEN now_ts + INTERVAL 24 HOUR
           ELSE now_ts + INTERVAL 48 HOUR
         END AS due_at,
         'new' AS state
  FROM alerts a
  LEFT JOIN triage_queue tq ON tq.alert_id = a.alert_id
  WHERE a.alert_day = today
    AND tq.alert_id IS NULL;
END $$

DELIMITER ;
