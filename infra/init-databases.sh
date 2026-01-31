#!/bin/bash
set -e

# Script para criar múltiplos databases no PostgreSQL
# Executado automaticamente na inicialização do container

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Database para Keycloak
    CREATE DATABASE keycloak;
    GRANT ALL PRIVILEGES ON DATABASE keycloak TO postgres;
    
    -- Database para Properties Service
    CREATE DATABASE properties;
    GRANT ALL PRIVILEGES ON DATABASE properties TO postgres;
    
    -- Database para Outbox Pattern (Identity Service)
    CREATE DATABASE outbox;
    GRANT ALL PRIVILEGES ON DATABASE outbox TO postgres;
    
    -- Log de sucesso
    \echo 'Databases criados com sucesso: keycloak, properties, outbox'
EOSQL
