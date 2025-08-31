-- 03_verify.sql
USE maatritva;

-- (Optional) Ensure u-1 exists if you started fresh
INSERT INTO users (user_id, full_name, district, phone)
VALUES ('u-1','Asha Devi','Bengaluru Rural','9991112222')
ON DUPLICATE KEY UPDATE full_name=VALUES(full_name);

INSERT INTO caregivers (caregiver_id, full_name, phone, district)
VALUES ('c-1','Dr. Meera','9990001111','Bengaluru Rural')
ON DUPLICATE KEY UPDATE full_name=VALUES(full_name);

INSERT INTO user_caregiver_hist (user_id, caregiver_id, valid_from)
VALUES ('u-1','c-1', NOW())
ON DUPLICATE KEY UPDATE user_id=user_id;  -- no-op

-- Run generator twice (should not duplicate)
CALL sp_generate_alerts();
CALL sp_generate_alerts();

-- 1) Counts by type (2nd run should not increase)
SELECT alert_type, COUNT(*) AS alerts_total
FROM alerts
GROUP BY alert_type
ORDER BY alerts_total DESC;

-- 2) Triage coverage: every today alert has exactly one triage
SELECT a.alert_type,
       COUNT(*) AS alerts_today,
       SUM(tq.alert_id IS NOT NULL) AS triage_created
FROM alerts a
LEFT JOIN triage_queue tq ON tq.alert_id = a.alert_id
WHERE a.alert_day = CURRENT_DATE()
GROUP BY a.alert_type;

-- 3) Peek recent alerts
SELECT alert_id, user_id, alert_type, created_at, details
FROM alerts
WHERE alert_day = CURRENT_DATE()
ORDER BY created_at DESC
LIMIT 20;

-- 4) Workload snapshot
SELECT assigned_to AS caregiver_id,
       COUNT(*) AS open_items
FROM triage_queue
WHERE state IN ('new','in_progress')
GROUP BY assigned_to
ORDER BY open_items DESC;
