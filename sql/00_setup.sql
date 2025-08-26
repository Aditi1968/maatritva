-- 00_setup.sql
DROP DATABASE IF EXISTS maatritva;
CREATE DATABASE maatritva
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE maatritva;

-- Safer defaults per session (your server may have stricter global modes)
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- Timestamp sanity (optional)
SET time_zone = '+05:30';
