-- 01_schema_core.sql
USE maatritva;

-- USERS
CREATE TABLE users (
  user_id     VARCHAR(36) PRIMARY KEY,
  full_name   VARCHAR(100) NOT NULL,
  dob         DATE NULL,
  district    VARCHAR(100),
  phone       VARCHAR(20) UNIQUE,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- CAREGIVERS
CREATE TABLE caregivers (
  caregiver_id VARCHAR(36) PRIMARY KEY,
  full_name    VARCHAR(100) NOT NULL,
  phone        VARCHAR(20) UNIQUE,
  district     VARCHAR(100),
  created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- SCD-2 caregiver assignment history
CREATE TABLE user_caregiver_hist (
  user_id      VARCHAR(36) NOT NULL,
  caregiver_id VARCHAR(36) NOT NULL,
  valid_from   DATETIME NOT NULL,
  valid_to     DATETIME DEFAULT NULL,
  -- Trick: only 1 open assignment per user (NULLs don't violate UNIQUE)
  open_flag    TINYINT
    GENERATED ALWAYS AS (CASE WHEN valid_to IS NULL THEN 1 ELSE NULL END) STORED,
  PRIMARY KEY (user_id, valid_from),
  CONSTRAINT fk_uch_user FOREIGN KEY (user_id) REFERENCES users(user_id),
  CONSTRAINT fk_uch_cg   FOREIGN KEY (caregiver_id) REFERENCES caregivers(caregiver_id),
  CONSTRAINT chk_uch_dates CHECK (valid_to IS NULL OR valid_to > valid_from),
  UNIQUE KEY ux_uch_one_open (user_id, open_flag)
) ENGINE=InnoDB;

-- JOURNALS (performance indexes/FTS/partitions come later)
CREATE TABLE journals (
  journal_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id    VARCHAR(36) NOT NULL,
  ts         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  text       TEXT NOT NULL,
  sentiment  ENUM('positive','neutral','negative') DEFAULT 'neutral',
  CONSTRAINT fk_j_user FOREIGN KEY (user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;

-- PHQ-9 scores with JSON answers + generated columns
CREATE TABLE phq_scores (
  phq_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id     VARCHAR(36) NOT NULL,
  scored_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  answers     JSON NOT NULL,
  total_score INT
    GENERATED ALWAYS AS (
      CAST(COALESCE(answers->>'$.q1','0') AS UNSIGNED) +
      CAST(COALESCE(answers->>'$.q2','0') AS UNSIGNED) +
      CAST(COALESCE(answers->>'$.q3','0') AS UNSIGNED) +
      CAST(COALESCE(answers->>'$.q4','0') AS UNSIGNED) +
      CAST(COALESCE(answers->>'$.q5','0') AS UNSIGNED) +
      CAST(COALESCE(answers->>'$.q6','0') AS UNSIGNED) +
      CAST(COALESCE(answers->>'$.q7','0') AS UNSIGNED) +
      CAST(COALESCE(answers->>'$.q8','0') AS UNSIGNED) +
      CAST(COALESCE(answers->>'$.q9','0') AS UNSIGNED)
    ) STORED,
  severity    VARCHAR(24)
    GENERATED ALWAYS AS (
      CASE
        WHEN total_score >= 20 THEN 'severe'
        WHEN total_score >= 15 THEN 'moderately_severe'
        WHEN total_score >= 10 THEN 'moderate'
        WHEN total_score >= 5  THEN 'mild'
        ELSE 'minimal'
      END
    ) STORED,
  CONSTRAINT fk_phq_user FOREIGN KEY (user_id) REFERENCES users(user_id),
  CONSTRAINT chk_phq_json CHECK (JSON_VALID(answers))
) ENGINE=InnoDB;
