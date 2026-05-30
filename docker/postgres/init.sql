-- ============================================================
-- Auren - Initial Database Setup
-- ============================================================

-- Create schema for Keycloak (separate from app data)
CREATE SCHEMA IF NOT EXISTS keycloak;

-- Create schema for application data
CREATE SCHEMA IF NOT EXISTS auren;

-- Set default search path
ALTER DATABASE auren SET search_path TO auren, public;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
