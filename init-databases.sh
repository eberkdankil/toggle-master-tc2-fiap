#!/bin/bash

# Substitua pelos endpoints gerados pelo RDS após a criação
AUTH_HOST="<endpoint-rds-auth>"
FLAGS_HOST="<endpoint-rds-flags>"
TARGETING_HOST="<endpoint-rds-targeting>"

PORT="5432"

echo "=== Inicializando banco auth-service ==="
PGPASSWORD="auth_pass" psql -h $AUTH_HOST -p $PORT -U auth_user -d auth_db <<EOF
CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    key_hash VARCHAR(64) NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
EOF
echo "OK: auth_db pronto."

echo ""
echo "=== Inicializando banco flag-service ==="
PGPASSWORD="flags_pass" psql -h $FLAGS_HOST -p $PORT -U flags_user -d flags_db <<EOF
CREATE TABLE IF NOT EXISTS flags (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    is_enabled BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS \$\$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
\$\$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_timestamp ON flags;

CREATE TRIGGER set_timestamp
BEFORE UPDATE ON flags
FOR EACH ROW
EXECUTE PROCEDURE trigger_set_timestamp();
EOF
echo "OK: flags_db pronto."

echo ""
echo "=== Inicializando banco targeting-service ==="
PGPASSWORD="targeting_pass" psql -h $TARGETING_HOST -p $PORT -U targeting_user -d targeting_db <<EOF
CREATE TABLE IF NOT EXISTS targeting_rules (
    id SERIAL PRIMARY KEY,
    flag_name VARCHAR(100) UNIQUE NOT NULL,
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    rules JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS \$\$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
\$\$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_timestamp ON targeting_rules;

CREATE TRIGGER set_timestamp
BEFORE UPDATE ON targeting_rules
FOR EACH ROW
EXECUTE PROCEDURE trigger_set_timestamp();
EOF
echo "OK: targeting_db pronto."

echo ""
echo "Todos os bancos inicializados."
