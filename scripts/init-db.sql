-- Create outbox database if it doesn't exist
SELECT 'CREATE DATABASE outbox'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'outbox')\gexec
