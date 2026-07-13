# AWS Setup — ToggleMaster EKS

Pré-requisito: cluster EKS e node group já criados com LabRole.

---

## 1. Configurar o kubectl para o EKS

```bash
aws eks update-kubeconfig --region us-east-1 --name <nome-do-cluster>
kubectl get nodes
```

Os nós devem aparecer com status `Ready`.

---

## 2. RDS PostgreSQL — auth-service

**Console AWS → RDS → Create database**

| Campo | Valor |
|---|---|
| Engine | PostgreSQL |
| Version | 15.x |
| Template | Free tier |
| DB instance identifier | `togglemaster-auth` |
| Master username | `auth_user` |
| Master password | `auth_pass` |
| Instance type | `db.t3.micro` |
| Storage | 20 GB (gp2) |
| VPC | mesma VPC do EKS |
| Public access | No |
| Security group | criar novo: `rds-auth-sg` |

Após criar, anote o **Endpoint** gerado (ex: `togglemaster-auth.xxxx.us-east-1.rds.amazonaws.com`).

---

## 3. RDS PostgreSQL — flag-service

**Console AWS → RDS → Create database**

| Campo | Valor |
|---|---|
| Engine | PostgreSQL |
| Version | 15.x |
| Template | Free tier |
| DB instance identifier | `togglemaster-flags` |
| Master username | `flags_user` |
| Master password | `flags_pass` |
| Instance type | `db.t3.micro` |
| Storage | 20 GB (gp2) |
| VPC | mesma VPC do EKS |
| Public access | No |
| Security group | criar novo: `rds-flags-sg` |

Anote o **Endpoint**.

---

## 4. RDS PostgreSQL — targeting-service

**Console AWS → RDS → Create database**

| Campo | Valor |
|---|---|
| Engine | PostgreSQL |
| Version | 15.x |
| Template | Free tier |
| DB instance identifier | `togglemaster-targeting` |
| Master username | `targeting_user` |
| Master password | `targeting_pass` |
| Instance type | `db.t3.micro` |
| Storage | 20 GB (gp2) |
| VPC | mesma VPC do EKS |
| Public access | No |
| Security group | criar novo: `rds-targeting-sg` |

Anote o **Endpoint**.

---

## 5. ElastiCache Redis — evaluation-service

**Console AWS → ElastiCache → Create cluster → Redis OSS**

| Campo | Valor |
|---|---|
| Cluster name | `togglemaster-redis` |
| Location | AWS Cloud |
| Cluster mode | Disabled |
| Node type | `cache.t3.micro` |
| Number of replicas | 0 |
| VPC | mesma VPC do EKS |
| Security group | criar novo: `elasticache-sg` |

Anote o **Primary endpoint** (ex: `togglemaster-redis.xxxx.cfg.use1.cache.amazonaws.com:6379`).

---

## 6. Liberar Security Groups

Os pods do EKS precisam alcançar o RDS e o ElastiCache. Para cada security group criado acima:

**Console AWS → EC2 → Security Groups → selecionar o sg → Inbound rules → Edit**

| Security Group | Tipo | Porta | Origem |
|---|---|---|---|
| `rds-auth-sg` | PostgreSQL | 5432 | security group dos nodes EKS |
| `rds-flags-sg` | PostgreSQL | 5432 | security group dos nodes EKS |
| `rds-targeting-sg` | PostgreSQL | 5432 | security group dos nodes EKS |
| `elasticache-sg` | Custom TCP | 6379 | security group dos nodes EKS |

> O security group dos nodes EKS está em **EKS → Clusters → seu cluster → Networking → Additional security groups**.

---

## 7. Criar as tabelas nos bancos RDS

Após os bancos ficarem `Available`, conecte em cada um e rode o SQL de inicialização.
Use um pod temporário dentro do cluster para alcançar os endpoints privados:

```bash
kubectl run pg-client --image=postgres:15-alpine -it --rm --restart=Never -- bash
```

Dentro do pod:

```bash
# auth-service
psql -h <endpoint-auth> -U auth_user -d postgres -c "CREATE DATABASE auth_db;"
psql -h <endpoint-auth> -U auth_user -d auth_db -f /init.sql
```

Ou copie o SQL direto como string:

```bash
psql "postgresql://auth_user:auth_pass@<endpoint-auth>:5432/auth_db" \
  -c "CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    key_hash VARCHAR(64) NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  );"
```

Repita para `flags_db` e `targeting_db` com os respectivos SQLs.

---

## 8. Atualizar os Secrets e ConfigMap com os endpoints reais

Edite `k8s/01-secrets.yaml` e substitua as URLs de banco pelos endpoints do RDS.
Os valores devem estar em base64. Para gerar:

```bash
echo -n "postgres://auth_user:auth_pass@<endpoint-auth>:5432/auth_db?sslmode=require" | base64 -w 0
```

Substitua `auth-db-url`, `flags-db-url` e `targeting-db-url` pelos novos valores.

Edite `k8s/02-configmap.yaml` e atualize `redis-url`:

```yaml
redis-url: redis://<endpoint-redis>:6379
```

---

## 9. Atualizar os Deployments para usar imagens do ECR

Em cada arquivo de deployment (`04` ao `08`), substitua:

```yaml
image: auth-service:latest
imagePullPolicy: Never
```

Por:

```yaml
image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/toggle-master/auth-service:latest
imagePullPolicy: IfNotPresent
```

Faça o mesmo para os outros 4 serviços ajustando o nome da imagem.

Remova também as variáveis `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` dos deployments
`evaluation-service` e `analytics-service` — as credenciais virão automaticamente
via LabRole do node group (IMDS).

---

## 10. Instalar o Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Verificar:

```bash
kubectl get deployment metrics-server -n kube-system
```

---

## 11. Instalar o NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml
```

Aguardar o Load Balancer ser provisionado (pode levar 2-3 minutos):

```bash
kubectl get svc -n ingress-nginx
```

Anote o **EXTERNAL-IP** do serviço `ingress-nginx-controller` — esse é o endereço público do cluster.

---

## 12. Aplicar os manifests

```bash
kubectl apply -f k8s/
```

Verificar os pods:

```bash
kubectl get pods -n toggle-master -w
```

Aguarde todos ficarem `Running` e `1/1 Ready`.

---

## 13. Pós-deploy — Criar a Service API Key

```bash
curl -X POST http://<EXTERNAL-IP>/admin/keys \
  -H "Authorization: Bearer local-master-key" \
  -H "Content-Type: application/json" \
  -d '{"name": "service-key"}'
```

Copie o valor do campo `key` da resposta, converta para base64 e atualize
`service-api-key` em `k8s/01-secrets.yaml`. Depois:

```bash
kubectl apply -f k8s/01-secrets.yaml
kubectl rollout restart deployment/evaluation-service -n toggle-master
```

---

## Resumo dos endpoints para anotar

| Recurso | Onde encontrar no console |
|---|---|
| Endpoint RDS auth | RDS → Databases → togglemaster-auth → Connectivity |
| Endpoint RDS flags | RDS → Databases → togglemaster-flags → Connectivity |
| Endpoint RDS targeting | RDS → Databases → togglemaster-targeting → Connectivity |
| Endpoint ElastiCache | ElastiCache → Clusters → togglemaster-redis → Details |
| External IP do Ingress | `kubectl get svc -n ingress-nginx` |
