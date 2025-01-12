-- Create database
CREATE DATABASE open_tofu_backend;

-- Connect to the database
\c open_tofu_backend

-- Create schema
CREATE SCHEMA open_tofu_state;

-- Create user
CREATE USER open_tofu WITH PASSWORD ''; -- Use actual password

-- Grant necessary permissions
GRANT ALL ON SCHEMA open_tofu_state TO open_tofu;
GRANT ALL ON ALL TABLES IN SCHEMA open_tofu_state TO open_tofu;
ALTER DEFAULT PRIVILEGES IN SCHEMA open_tofu_state GRANT ALL ON TABLES TO open_tofu;

-- Create table to track workspaces (optional but useful)
CREATE TABLE open_tofu_state.workspaces (
    id SERIAL PRIMARY KEY,
    app_name VARCHAR(255) NOT NULL,
    environment VARCHAR(255) NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(app_name, environment)
);