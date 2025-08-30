-- 02_alerts_triage.sql
USE maatritva;

-- ALERTS: one row per “reason to look”
DROP TABLE IF EXISTS alerts;
CREATE TABLE alerts (
  alert_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id      VARCHAR(36) NOT NULL,
  alert_type   ENUM('high_phq','inactivity_7d','neg_streak_3d') NOT NULL,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  caregiver_id VARCHAR(36) NULL,          -- snapshot of current assignee (optional)
  status       ENUM('open','ack','closed') NOT NULL DEFAULT 'open',
  details      JSON NULL,
  CONSTRAINT fk_alert_user FOREIGN KEY (user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;

-- TRIAGE QUEUE: operational work item derived from an alert
DROP TABLE IF EXISTS triage_queue;
CREATE TABLE triage_queue (
  queue_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
  alert_id        BIGINT NOT NULL,
  assigned_to     VARCHAR(36) NULL,  -- could be caregiver_id or ops user
  priority        ENUM('low','medium','high','critical') NOT NULL DEFAULT 'medium',
  due_at          DATETIME NULL,
  state           ENUM('new','in_progress','blocked','done') NOT NULL DEFAULT 'new',
  last_action_at  DATETIME NULL,
  parent_queue_id BIGINT NULL,
  CONSTRAINT fk_tq_alert FOREIGN KEY (alert_id) REFERENCES alerts(alert_id)
) ENGINE=InnoDB;

-- Helpful indexes (we’ll add FTS + partitions later)
CREATE INDEX ix_alerts_user_created ON alerts (user_id, created_at);
CREATE INDEX ix_alerts_type_status ON alerts (alert_type, status);
CREATE INDEX ix_journals_user_ts     ON journals (user_id, ts);          -- supports inactivity/streak scans
CREATE INDEX ix_phq_user_ts          ON phq_scores (user_id, scored_at); -- supports “latest PHQ” scan
