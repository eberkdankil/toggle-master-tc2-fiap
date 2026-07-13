#!/bin/bash

LB="http://<seu-load-balancer>.elb.us-east-1.amazonaws.com"

# Preencha com sua API key (gerada pelo auth-service)
API_KEY="tm_key_SEU_TOKEN_AQUI"

# Configuracoes do teste
WORKERS=100       # requisicoes paralelas
DURATION=180      # segundos de carga (3 minutos)
FLAG_NAME="load-test-flag"

# ============================================================
echo "=== 1. Verificando saude dos servicos ==="
echo -n "auth:       "; curl -s -o /dev/null -w "%{http_code}" $LB/auth/health; echo
echo -n "flags:      "; curl -s -o /dev/null -w "%{http_code}" $LB/flags/health; echo
echo -n "targeting:  "; curl -s -o /dev/null -w "%{http_code}" $LB/targeting/health; echo
echo -n "evaluation: "; curl -s -o /dev/null -w "%{http_code}" $LB/evaluate/health; echo
echo ""

# ============================================================
echo "=== 2. Criando flag de teste ==="
curl -s -X POST $LB/flags/flags \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$FLAG_NAME\", \"description\": \"Flag para load test\", \"is_enabled\": true}"
echo ""
echo "Flag criada."
echo ""

# ============================================================
echo "=== 3. Iniciando carga no evaluation-service ==="
echo "Workers: $WORKERS | Duracao: ${DURATION}s"
echo ""
echo "Monitorar HPA em outro terminal:"
echo "  watch -n 5 kubectl get hpa -n toggle-master"
echo "  kubectl get pods -n toggle-master -w"
echo ""

COUNTER_FILE=$(mktemp)

worker() {
  local end=$((SECONDS + DURATION))
  local user_id="user-$RANDOM"
  while [ $SECONDS -lt $end ]; do
    curl -s -o /dev/null \
      "$LB/evaluate?user_id=$user_id&flag_name=$FLAG_NAME"
    echo >> $COUNTER_FILE
  done
}

START=$SECONDS

for i in $(seq 1 $WORKERS); do
  worker $i &
done

while [ $((SECONDS - START)) -lt $DURATION ]; do
  sleep 15
  REQS=$(wc -l < $COUNTER_FILE)
  ELAPSED=$((SECONDS - START))
  RPS=$((REQS / (ELAPSED + 1)))
  echo "[${ELAPSED}s] Requisicoes enviadas: $REQS | RPS medio: $RPS"
  kubectl get hpa evaluation-service-hpa -n toggle-master --no-headers 2>/dev/null
done

wait
rm -f $COUNTER_FILE
echo ""

# ============================================================
echo "=== 4. Status final ==="
kubectl get hpa -n toggle-master
echo ""
kubectl get pods -n toggle-master
