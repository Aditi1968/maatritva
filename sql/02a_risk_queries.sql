-- 02a_risk_queries.sql
USE maatritva;

-- (Optional) Small seed to demo results — safe if you already inserted u-1 on Day 1
-- Add a 3-day negative streak for u-1
INSERT INTO journals (user_id, ts, text, sentiment) VALUES
('u-1', NOW() - INTERVAL 2 DAY, 'poor sleep and anxiety', 'negative'),
('u-1', NOW() - INTERVAL 1 DAY, 'felt low today', 'negative'),
('u-1', NOW(), 'tired and anxious', 'negative');

-- Add a new user with no journals to show inactivity
INSERT INTO users (user_id, full_name, district, phone)
VALUES ('u-2','Lakshmi','Bengaluru Urban','9993334444')
ON DUPLICATE KEY UPDATE full_name=VALUES(full_name);

-- A) High PHQ in last 14 days (latest per user, threshold >= 15)
WITH recent_phq AS (
  SELECT
    user_id,
    phq_id,
    scored_at,
    total_score,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY scored_at DESC) AS rn
  FROM phq_scores
  WHERE scored_at >= NOW() - INTERVAL 14 DAY
)
SELECT user_id, phq_id, scored_at, total_score
FROM recent_phq
WHERE rn = 1 AND total_score >= 15;

-- B) Inactivity for 7 days (no journal in last 7 days)
SELECT u.user_id, u.full_name
FROM users u
LEFT JOIN (
  SELECT user_id, MAX(ts) AS last_journal_at
  FROM journals
  GROUP BY user_id
) j ON j.user_id = u.user_id
WHERE (j.last_journal_at IS NULL OR j.last_journal_at < NOW() - INTERVAL 7 DAY);

-- C) Negative-mood streaks (>=3 consecutive days)
-- Steps: daily mood → filter negatives → “islands & gaps” grouping → keep runs with len>=3
WITH day_sentiment AS (
  SELECT
    user_id,
    DATE(ts) AS ts_date,
    MIN(CASE sentiment
          WHEN 'negative' THEN 1
          WHEN 'neutral'  THEN 2
          WHEN 'positive' THEN 3
        END) AS mood_rank
  FROM journals
  GROUP BY user_id, DATE(ts)
),
neg_days AS (
  SELECT user_id, ts_date FROM day_sentiment WHERE mood_rank = 1
),
runs AS (
  SELECT
    user_id,
    ts_date,
    DATEDIFF(ts_date, '2000-01-01')
      - ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY ts_date) AS grp
  FROM neg_days
)
SELECT
  user_id,
  MIN(ts_date) AS start_date,
  MAX(ts_date) AS end_date,
  COUNT(*)     AS streak_len
FROM runs
GROUP BY user_id, grp
HAVING COUNT(*) >= 3
ORDER BY end_date DESC;
