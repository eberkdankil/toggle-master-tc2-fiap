#!/bin/bash

# Execute este script a partir da sua maquina com kubectl configurado para o EKS.
# Ele sobe um pod temporario, inicializa os 3 bancos e remove o pod ao final.

echo "Subindo pod temporario..."
kubectl run pg-client \
  --image=postgres:15-alpine \
  --restart=Never \
  --namespace=toggle-master \
  -- sleep 300

echo "Aguardando pod ficar pronto..."
kubectl wait --for=condition=Ready pod/pg-client \
  --namespace=toggle-master \
  --timeout=60s

echo ""
echo "=== Inicializando auth-service (banco: postgres) ==="
kubectl exec -n toggle-master pg-client -- sh -c "
PGPASSWORD=auth_pass psql \
  -h togglemaster-auth.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com \
  -U auth_user \
  -d postgres \
  -c \"CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    key_hash VARCHAR(64) NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  );\"
"
echo "OK: api_keys criada."

echo ""
echo "=== Inicializando flag-service (banco: flags_db) ==="
kubectl exec -n toggle-master pg-client -- sh -c "
PGPASSWORD=flags_pass psql \
  -h togglemaster-flags.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com \
  -U flags_user \
  -d flags_db \
  -c \"
CREATE TABLE IF NOT EXISTS flags (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    is_enabled BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS \\\$\\\$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
\\\$\\\$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS set_timestamp ON flags;
CREATE TRIGGER set_timestamp
BEFORE UPDATE ON flags
FOR EACH ROW
EXECUTE PROCEDURE trigger_set_timestamp();
\"
"
echo "OK: flags criada."

echo ""
echo "=== Inicializando targeting-service (banco: targeting_db) ==="
kubectl exec -n toggle-master pg-client -- sh -c "
PGPASSWORD=targeting_pass psql \
  -h togglemaster-targeting.xxxxxxxxxxxx.us-east-1.rds.amazonaws.com \
  -U targeting_user \
  -d targeting_db \
  -c \"
CREATE TABLE IF NOT EXISTS targeting_rules (
    id SERIAL PRIMARY KEY,
    flag_name VARCHAR(100) UNIQUE NOT NULL,
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    rules JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS \\\$\\\$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
\\\$\\\$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS set_timestamp ON targeting_rules;
CREATE TRIGGER set_timestamp
BEFORE UPDATE ON targeting_rules
FOR EACH ROW
EXECUTE PROCEDURE trigger_set_timestamp();
\"
"
echo "OK: targeting_rules criada."

echo ""
echo "Removendo pod temporario..."
kubectl delete pod pg-client --namespace=toggle-master

echo ""
echo "Bancos inicializados com sucesso."
