# ToggleMaster — Guia de API

Plataforma de feature flags composta por 5 microsserviços. Este guia cobre todos os endpoints acessíveis pelo usuário com exemplos prontos para o Postman.

---

## Visão Geral dos Serviços

| Serviço | Porta | Descrição |
|---|---|---|
| auth-service | 8001 | Gera e valida chaves de API |
| flag-service | 8002 | CRUD de feature flags |
| targeting-service | 8003 | CRUD de regras de segmentação |
| evaluation-service | 8004 | Avalia se uma flag está ativa para um usuário |
| analytics-service | 8005 | Worker interno (sem endpoints para o usuário) |

---

## Como subir o ambiente

### Opção A — Docker Compose

```bash
docker compose up --build -d
```

Aguarde todos os containers ficarem saudáveis antes de fazer chamadas.

**Base URLs (Docker Compose):**

| Serviço | URL base |
|---|---|
| auth-service | `http://localhost:8001` |
| flag-service | `http://localhost:8002` |
| targeting-service | `http://localhost:8003` |
| evaluation-service | `http://localhost:8004` |

---

### Opção B — Kubernetes (Docker Desktop)

#### Pré-requisitos

- Docker Desktop com Kubernetes habilitado (`Settings > Kubernetes > Enable Kubernetes`)
- `kubectl` configurado para o contexto `docker-desktop`

```bash
kubectl config use-context docker-desktop
```

#### 1. Build das imagens locais

```bash
docker build -t auth-service:latest ./auth-service
docker build -t flag-service:latest ./flag-service
docker build -t targeting-service:latest ./targeting-service
docker build -t evaluation-service:latest ./evaluation-service
docker build -t analytics-service:latest ./analytics-service
```

#### 2. Instalar o NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml
```

Aguardar ficar pronto:

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

#### 3. Adicionar entradas no arquivo `hosts`

Abrir o **Bloco de Notas como administrador** e editar `C:\Windows\System32\drivers\etc\hosts`, adicionando ao final:

```
127.0.0.1  auth.togglemaster.local
127.0.0.1  flags.togglemaster.local
127.0.0.1  targeting.togglemaster.local
127.0.0.1  evaluation.togglemaster.local
```

#### 4. Aplicar os manifests

```bash
kubectl apply -f k8s/
```

Os arquivos estão numerados — o Kubernetes os aplica na ordem correta automaticamente.

#### 5. Verificar o status

```bash
kubectl get all -n toggle-master
```

Aguarde todos os pods estarem `Running` e `Ready` antes de fazer chamadas.

```bash
# Acompanhar em tempo real
kubectl get pods -n toggle-master -w
```

#### 6. Ver logs de um serviço

```bash
kubectl logs -n toggle-master deployment/auth-service
kubectl logs -n toggle-master deployment/flag-service
kubectl logs -n toggle-master deployment/evaluation-service
```

**Base URLs (Kubernetes):**

| Serviço | URL base |
|---|---|
| auth-service | `http://auth.togglemaster.local` |
| flag-service | `http://flags.togglemaster.local` |
| targeting-service | `http://targeting.togglemaster.local` |
| evaluation-service | `http://evaluation.togglemaster.local` |

#### Remover tudo do cluster

```bash
kubectl delete namespace toggle-master
```

---

## Passo a Passo — Fluxo Completo

Siga esta ordem para usar o sistema do zero. Os exemplos usam as URLs do Docker Compose — para Kubernetes, substitua as bases conforme a tabela acima.

### Passo 1 — Criar chaves de API

Todas as chamadas para o flag-service e targeting-service exigem uma chave de API.
As chaves são criadas no auth-service usando a **MASTER KEY** (`local-master-key`).

> **A chave em texto plano é retornada apenas nesta chamada. Guarde-a.**

#### 1a. Criar sua chave de usuário

**Docker Compose:**
```
POST http://localhost:8001/admin/keys
Authorization: Bearer local-master-key
Content-Type: application/json

{
  "name": "minha-chave"
}
```

**Kubernetes:**
```
POST http://auth.togglemaster.local/admin/keys
Authorization: Bearer local-master-key
Content-Type: application/json

{
  "name": "minha-chave"
}
```

**Resposta (201):**
```json
{
  "name": "minha-chave",
  "key": "tm_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "message": "Guarde esta chave com segurança! Você não poderá vê-la novamente."
}
```

#### 1b. Criar a chave de serviço (interno)

O evaluation-service precisa de uma chave própria para chamar os outros serviços.
Crie essa chave também:

```
POST http://localhost:8001/admin/keys        (Docker Compose)
POST http://auth.togglemaster.local/admin/keys  (Kubernetes)
Authorization: Bearer local-master-key
Content-Type: application/json

{
  "name": "service-key"
}
```

**Resposta (201):**
```json
{
  "name": "service-key",
  "key": "tm_yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy",
  "message": "Guarde esta chave com segurança! Você não poderá vê-la novamente."
}
```

**⚠️ Passo obrigatório:** Copie o valor do campo `key` e atualize a configuração do evaluation-service:

- **Docker Compose:** edite `docker-compose.yml`, linha `SERVICE_API_KEY`, depois rode:
  ```bash
  docker compose build --no-cache evaluation-service
  docker compose up -d evaluation-service
  ```

- **Kubernetes:** edite `k8s/01-secrets.yaml`, campo `service-api-key`, depois rode:
  ```bash
  kubectl apply -f k8s/01-secrets.yaml
  kubectl rollout restart deployment/evaluation-service -n toggle-master
  ```

> Nos passos seguintes, substitua `SUA_CHAVE` pelo valor do campo `key` da chave de usuário (passo 1a).

---

### Passo 2 — Criar uma feature flag

```
POST http://localhost:8002/flags            (Docker Compose)
POST http://flags.togglemaster.local/flags  (Kubernetes)
Authorization: Bearer SUA_CHAVE
Content-Type: application/json

{
  "name": "novo-checkout",
  "description": "Ativa o novo fluxo de checkout",
  "is_enabled": true
}
```

**Resposta (201):**
```json
{
  "id": 1,
  "name": "novo-checkout",
  "description": "Ativa o novo fluxo de checkout",
  "is_enabled": true,
  "created_at": "2026-06-09T15:00:00Z",
  "updated_at": "2026-06-09T15:00:00Z"
}
```

---

### Passo 3 — (Opcional) Criar uma regra de segmentação

Sem regra, a flag vale para 100% dos usuários. Com uma regra de `PERCENTAGE`, apenas a porcentagem definida vê a flag ativa.

```
POST http://localhost:8003/rules                   (Docker Compose)
POST http://targeting.togglemaster.local/rules      (Kubernetes)
Authorization: Bearer SUA_CHAVE
Content-Type: application/json

{
  "flag_name": "novo-checkout",
  "is_enabled": true,
  "rules": {
    "type": "PERCENTAGE",
    "value": 50
  }
}
```

**Resposta (201):**
```json
{
  "id": 1,
  "flag_name": "novo-checkout",
  "is_enabled": true,
  "rules": {
    "type": "PERCENTAGE",
    "value": 50
  },
  "created_at": "2026-06-09T15:00:00Z",
  "updated_at": "2026-06-09T15:00:00Z"
}
```

---

### Passo 4 — Avaliar a flag para um usuário

O evaluation-service decide se a flag está ativa para um usuário específico.
Não exige chave de API — é o endpoint público do sistema.

```
GET http://localhost:8004/evaluate?user_id=usuario-123&flag_name=novo-checkout            (Docker Compose)
GET http://evaluation.togglemaster.local/evaluate?user_id=usuario-123&flag_name=novo-checkout  (Kubernetes)
```

**Resposta (200):**
```json
{
  "flag_name": "novo-checkout",
  "user_id": "usuario-123",
  "result": true
}
```

> O resultado é determinístico: o mesmo `user_id` + `flag_name` sempre retorna o mesmo valor. A cada avaliação, um evento é enviado para a fila SQS e processado pelo analytics-service.

---

## Referência Completa de Endpoints

### Auth Service

| Ambiente | URL base |
|---|---|
| Docker Compose | `http://localhost:8001` |
| Kubernetes | `http://auth.togglemaster.local` |

#### Health Check
```
GET /health
```

#### Criar chave de API
```
POST /admin/keys
Authorization: Bearer local-master-key
Content-Type: application/json

{
  "name": "nome-da-chave"
}
```

#### Validar chave de API
Usado internamente pelos outros serviços. Pode ser chamado diretamente para testar se uma chave é válida.
```
GET /validate
Authorization: Bearer SUA_CHAVE
```

---

### Flag Service

| Ambiente | URL base |
|---|---|
| Docker Compose | `http://localhost:8002` |
| Kubernetes | `http://flags.togglemaster.local` |

Todos os endpoints abaixo exigem `Authorization: Bearer SUA_CHAVE`.

#### Health Check
```
GET /health
```

#### Criar flag
```
POST /flags
Authorization: Bearer SUA_CHAVE
Content-Type: application/json

{
  "name": "nome-da-flag",
  "description": "Descrição opcional",
  "is_enabled": true
}
```

#### Listar todas as flags
```
GET /flags
Authorization: Bearer SUA_CHAVE
```

#### Buscar flag por nome
```
GET /flags/nome-da-flag
Authorization: Bearer SUA_CHAVE
```

#### Atualizar flag
Pode atualizar `description`, `is_enabled` ou ambos.
```
PUT /flags/nome-da-flag
Authorization: Bearer SUA_CHAVE
Content-Type: application/json

{
  "is_enabled": false,
  "description": "Nova descrição"
}
```

#### Deletar flag
Retorna `204 No Content` em caso de sucesso.
```
DELETE /flags/nome-da-flag
Authorization: Bearer SUA_CHAVE
```

---

### Targeting Service

| Ambiente | URL base |
|---|---|
| Docker Compose | `http://localhost:8003` |
| Kubernetes | `http://targeting.togglemaster.local` |

Todos os endpoints abaixo exigem `Authorization: Bearer SUA_CHAVE`.

A cada flag pode existir no máximo **uma** regra de segmentação.
Tipo suportado atualmente: `PERCENTAGE` (valor de 0 a 100).

#### Health Check
```
GET /health
```

#### Criar regra
```
POST /rules
Authorization: Bearer SUA_CHAVE
Content-Type: application/json

{
  "flag_name": "nome-da-flag",
  "is_enabled": true,
  "rules": {
    "type": "PERCENTAGE",
    "value": 30
  }
}
```

#### Buscar regra por flag
```
GET /rules/nome-da-flag
Authorization: Bearer SUA_CHAVE
```

#### Atualizar regra
Pode atualizar `rules`, `is_enabled` ou ambos.
```
PUT /rules/nome-da-flag
Authorization: Bearer SUA_CHAVE
Content-Type: application/json

{
  "is_enabled": true,
  "rules": {
    "type": "PERCENTAGE",
    "value": 80
  }
}
```

#### Deletar regra
Retorna `204 No Content` em caso de sucesso.
```
DELETE /rules/nome-da-flag
Authorization: Bearer SUA_CHAVE
```

---

### Evaluation Service

| Ambiente | URL base |
|---|---|
| Docker Compose | `http://localhost:8004` |
| Kubernetes | `http://evaluation.togglemaster.local` |

Não exige autenticação.

#### Health Check
```
GET /health
```

#### Avaliar flag para um usuário
```
GET /evaluate?user_id=USUARIO_ID&flag_name=NOME_DA_FLAG
```

**Exemplo:**
```
GET /evaluate?user_id=usuario-abc&flag_name=novo-checkout
```

**Resposta (200):**
```json
{
  "flag_name": "novo-checkout",
  "user_id": "usuario-abc",
  "result": true
}
```

**Lógica de avaliação:**
| Cenário | Resultado |
|---|---|
| Flag não existe | `false` |
| Flag existe, `is_enabled: false` | `false` |
| Flag existe, `is_enabled: true`, sem regra | `true` para todos |
| Flag existe, `is_enabled: true`, regra de 50% | `true` para ~50% dos usuários (determinístico por user_id) |

---

### Analytics Service

| Ambiente | URL base |
|---|---|
| Docker Compose | `http://localhost:8005` |
| Kubernetes | worker interno, sem Ingress |

Serviço interno. Não possui endpoints para o usuário além do health check.
Consome automaticamente os eventos da fila SQS gerados pelo evaluation-service e os persiste no DynamoDB.

#### Health Check
```
GET /health
```

---

## Scripts Utilitários

O repositório inclui três scripts shell (`.sh`) de apoio. Nenhum deles é necessário para subir o ambiente local (Docker Compose ou Docker Desktop Kubernetes) — a inicialização dos bancos nesses casos já acontece automaticamente via `init-databases.sh` do Postgres (Docker Compose) ou ConfigMap (`k8s/02-configmap.yaml`). Eles servem para os cenários de deploy em AWS descritos em `aws-setup.md`.

Antes de rodar qualquer um, dê permissão de execução:

```bash
chmod +x init-databases.sh load-test.sh aws-k8s/init-rds.sh
```

### `init-databases.sh`

Inicializa as tabelas dos 3 bancos Postgres (`auth`, `flags`, `targeting`) conectando via `psql` **diretamente** nos endpoints do RDS, a partir da sua máquina local. Use este script quando o RDS estiver acessível pela rede (ex: `Public access: Yes`, ou você já tem uma VPN/peering para a VPC).

1. Edite as variáveis no topo do arquivo com os endpoints reais gerados pelo RDS:
   ```bash
   AUTH_HOST="<endpoint-rds-auth>"
   FLAGS_HOST="<endpoint-rds-flags>"
   TARGETING_HOST="<endpoint-rds-targeting>"
   ```
2. Rode:
   ```bash
   ./init-databases.sh
   ```

Requer o cliente `psql` instalado localmente.

### `aws-k8s/init-rds.sh`

Faz a mesma inicialização dos 3 bancos, mas para o caso mais comum: RDS com **acesso privado** (`Public access: No`), alcançável apenas de dentro da VPC/EKS. O script sobe um pod temporário (`postgres:15-alpine`) dentro do cluster, executa os `CREATE TABLE` via `kubectl exec` e remove o pod ao final.

Pré-requisitos: `kubectl` configurado apontando para o cluster EKS, e os hostnames de RDS já ajustados no próprio script (por padrão usam placeholders `xxxxxxxxxxxx` — substitua pelos endpoints reais antes de rodar).

```bash
./aws-k8s/init-rds.sh
```

### `load-test.sh`

Gera carga contra o `evaluation-service` para observar o Horizontal Pod Autoscaler (HPA) escalando os pods. Fluxo do script:

1. Checa a saúde (`/health`) dos 4 serviços expostos.
2. Cria uma flag de teste (`load-test-flag`) via `flag-service`.
3. Sobe `WORKERS` processos em paralelo (padrão: 100) fazendo requisições contínuas em `/evaluate` por `DURATION` segundos (padrão: 180s).
4. A cada 15s, imprime o total de requisições enviadas e o RPS médio, junto com o status do HPA.
5. Ao final, mostra o estado final do HPA e dos pods.

Antes de rodar, edite as duas variáveis no topo do arquivo:

```bash
LB="http://<seu-load-balancer>.elb.us-east-1.amazonaws.com"  # endereço do seu Ingress/Load Balancer
API_KEY="tm_key_SEU_TOKEN_AQUI"                                # chave de API válida (veja Passo 1)
```

```bash
./load-test.sh
```

Em outro terminal, acompanhe o autoscaling em tempo real:

```bash
watch -n 5 kubectl get hpa -n toggle-master
kubectl get pods -n toggle-master -w
```

---

## Como importar no Postman

1. Abra o Postman e clique em **Import**
2. Selecione a aba **Raw text**
3. Cole qualquer bloco de exemplo acima
4. O Postman reconhece o formato e cria a requisição automaticamente

**Dica:** Crie uma variável de ambiente no Postman chamada `BASE_URL` e `API_KEY`:
- Docker Compose: `BASE_URL = http://localhost:800X`
- Kubernetes: `BASE_URL = http://flags.togglemaster.local` (ajuste por serviço)
