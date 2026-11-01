# Fase 4 — Observabilidade: Plano de Execução

> Documento de planejamento, não é entregável em si. Serve pra alinhar o grupo
> antes de começar a implementar. Atualizar conforme as decisões forem
> tomadas (marcadas como "DECISÃO PENDENTE" abaixo).

## 1. Onde estamos / o que já existe

Pra não reconstruir do zero o que o desafio já assume como base:

- **5 microsserviços conteinerizados** — auth-service e evaluation-service em
  Go, flag-service/targeting-service/analytics-service em Python/Flask.
- **IaC (Terraform)** — `togglemaster-infra`: VPC (2 subnets públicas sem
  NAT, 2 privadas), EKS (node group `t3.medium`, 2 nodes), 3x RDS Postgres,
  ElastiCache Redis, DynamoDB, SQS, 5x ECR, backend remoto S3.
- **CI/CD + DevSecOps** — GitHub Actions por serviço (build/test, lint,
  Trivy SCA + container scan, gosec/bandit SAST, bloqueio em CRÍTICO), tag
  por commit hash, atualização automática do GitOps.
- **GitOps (ArgoCD)** — repo `toggle-master 2`, pasta `gitops/`: Deployments/
  Services dos 5 serviços, Ingress (ingress-nginx, prefixo por serviço),
  metrics-server, tudo sincronizado automaticamente via Applications do
  ArgoCD ("app cuidando de app").
- **Bootstrap do cluster** — workflow `bootstrap-cluster.yml` recria Secret,
  ConfigMap (com endpoints dinâmicos do RDS/Redis/SQS) e roda migração de
  schema toda vez que a infra é recriada.

Isso importa porque **o padrão "app cuidando de app" via ArgoCD já está
validado** — tudo que a Fase 4 pede pra observabilidade (Prometheus, Loki,
Grafana, OTel Collector) entra exatamente nesse mesmo padrão, sem
reinventar nada.

## 2. O que o desafio exige (resumo técnico)

1. **Prometheus + Loki + Grafana** no cluster, via Helm charts no GitOps.
   Grafana precisa de ≥1 dashboard customizado: uso de recursos do cluster +
   taxa de requisições dos microsserviços + painel de logs em tempo real.
2. **OTel Collector obrigatório** como peça central: recebe métricas/logs/
   traces dos microsserviços e roteia pro Prometheus, Loki e pro APM.
   (Grafana Alloy no lugar do Collector padrão é permitido, mas opcional.)
3. **APM comercial** (Datadog OU New Relic, conta gratuita/education):
   instrumentar os 5 serviços (preferencialmente com SDKs OpenTelemetry),
   gerar Distributed Tracing real, e o painel do APM precisa mostrar o
   Service Map dos 5 serviços.
4. **Alertas + Incident Management + ChatOps + Self-Healing**:
   - Alerta inteligente (Grafana ou APM) — ex: 5xx do auth-service > 5%.
   - Abre incidente automaticamente no PagerDuty OU OpsGenie.
   - Notifica um canal (Slack/Discord/Teams) com detalhe.
   - Self-Healing **obrigatório**: automação (Runbook Automation/Lambda/
     GitHub Action via webhook) que reage ao alerta sozinha — ex:
     `kubectl rollout restart deployment/auth-service`.

**Regra de avaliação dura**: não basta configurar, tem que **demonstrar
funcionando** no vídeo — inclusive causando um problema de propósito e
mostrando o ciclo completo (alerta → incidente → chatops → self-healing →
pod se recuperando, ao vivo, no terminal).

## 3. Arquitetura recomendada (visão geral)

```
┌─────────────────────────────────────────────────────────────┐
│ Cluster EKS                                                  │
│                                                               │
│  5 microsserviços  ──OTLP (gRPC/HTTP)──▶  OTel Collector     │
│  (instrumentados                              │   │   │      │
│   com SDK OTel)                               │   │   │      │
│                                     métricas───┘   │   └─traces
│                                          │          │        │
│                                          ▼          ▼        ▼
│                                    Prometheus      Loki    APM (Datadog/
│                                   (kube-prometheus  │      New Relic, via
│                                    -stack)          │      OTLP intake)
│                                          │           │
│  Logs de TODOS os pods ──filelogreceiver─┘           │
│  (OTel Collector DaemonSet,                          │
│   lê /var/log/pods)  ─────────────────────────────────┘
│                                          │
│                                          ▼
│                                      Grafana
│                                   (dashboard custom:
│                                    recursos + taxa req + logs)
│                                          │
│                                   Alerta dispara
│                                          │
│                                          ▼
│                              Webhook (Grafana Alerting
│                               contact point) ──┬──▶ OpsGenie/PagerDuty
│                                                 │       (incidente)
│                                                 │       │
│                                                 │       ▼
│                                                 │   Slack/Discord
│                                                 │   (ChatOps)
│                                                 │
│                                                 └──▶ GitHub Actions
│                                                     (repository_dispatch)
│                                                          │
│                                                          ▼
│                                              kubectl rollout restart
│                                              (self-healing)
└─────────────────────────────────────────────────────────────┘
```

**Por que o OTel Collector cobre métricas, logs E traces**: o requisito diz
que ele é "a peça central" — em vez de instalar Promtail/Grafana Agent
separado só pra logs, uso o próprio OTel Collector (como DaemonSet, com
`filelogreceiver` lendo `/var/log/pods` de cada node) como único coletor de
logs também. Isso evita um componente redundante e reforça exatamente o
ponto que o requisito 2 pede ("o OTel se encarrega de rotear pros backends
corretos").

## 4. Decisões em aberto (precisam de confirmação do grupo)

### 4.1 APM: Datadog vs New Relic
| | Datadog | New Relic |
|---|---|---|
| Conta grátis | Trial de 14 dias (cartão geralmente pedido) | Tier "always free" (100GB ingest/mês, sem cartão) |
| Risco pro cronograma | Trial pode expirar no meio do projeto | Sem prazo de expiração |
| OTLP nativo | Sim (Datadog Agent/intake aceita OTLP) | Sim (endpoint OTLP direto) |
| Service Map | Sim (APM → Service Map) | Sim (APM → Service Maps) |

**Recomendação**: **New Relic** — tier gratuito permanente remove o risco de
o trial vencer antes da gravação do vídeo (já tivemos esse tipo de problema
de "coisa que expira no meio do caminho" com as credenciais do Academy).

### 4.2 Incident Management: PagerDuty vs OpsGenie
| | PagerDuty | OpsGenie |
|---|---|---|
| Plano grátis | Trial 14 dias | Free plan permanente (até 5 usuários) |
| Integração com Grafana/webhook | Sim | Sim |

**Recomendação**: **OpsGenie** — mesmo raciocínio do item anterior (plano
grátis sem prazo de validade, não só trial).

### 4.3 ChatOps: Slack vs Discord vs Teams
**Recomendação**: **Discord** — zero fricção de setup (criar um webhook de
canal leva 30 segundos, não precisa criar workspace corporativo nem pedir
aprovação de admin, como o Slack às vezes exige).

### 4.4 Self-Healing: GitHub Action vs Lambda vs Runbook nativo
**Recomendação**: **GitHub Action via `repository_dispatch`** — já temos
todo o know-how de rodar `aws eks update-kubeconfig` + `kubectl` a partir de
Actions (o `bootstrap-cluster.yml` já faz exatamente isso). O contact point
de webhook do Grafana Alerting pode chamar direto a API do GitHub
(`POST /repos/{owner}/{repo}/dispatches`) com um PAT no header
`Authorization` — sem precisar de Lambda nem API Gateway novos.

### 4.5 Node sizing do EKS
O cluster hoje tem 2 nodes `t3.medium` já rodando 5 apps + ingress-nginx +
ArgoCD + metrics-server. `kube-prometheus-stack` + Loki + OTel Collector
somam bastante CPU/memória. **Risco real de faltar recurso.**

**Recomendação**: antes de instalar a stack, bump do node group pra 3 nodes
(`desired_size = 3` no `terraform/modules/eks`) ou considerar `t3.large`.
Ajustar via `terraform apply` no repo de infra — decisão de custo x
segurança do demo (mais barato manter `t3.medium` x3 que arriscar o cluster
não aguentar na hora de gravar).

## 5. Plano de execução (fases)

### Fase A — Stack de observabilidade (GitOps)
1. Adicionar ao `gitops/` (mesmo padrão `Application` do ArgoCD já usado
   pro ingress-nginx/metrics-server):
   - `kube-prometheus-stack` (Prometheus + Alertmanager + Grafana + 
     exporters) — chart `prometheus-community/kube-prometheus-stack`.
   - `loki` (modo single-binary/monolítico, suficiente pro volume desse
     projeto — não precisa do modo distribuído).
   - `opentelemetry-collector` (chart `open-telemetry/opentelemetry-collector`)
     — um Deployment (recebe OTLP dos apps) + um DaemonSet (logs via
     `filelogreceiver`), com um `ConfigMap` de pipeline customizado
     (receivers: otlp, filelog; exporters: prometheusremotewrite, loki,
     otlp/newrelic).
2. Validar: métricas de cluster (CPU/memória dos nodes, via kube-state-
   metrics/cAdvisor já embutidos no kube-prometheus-stack) aparecendo no
   Grafana, e logs de qualquer pod aparecendo no Loki — **antes** de
   instrumentar os apps, pra isolar problema de infra vs problema de app.

### Fase B — Instrumentação dos 5 serviços
- **Go (auth-service, evaluation-service)**: SDK `go.opentelemetry.io/otel`
  + `otelhttp` (instrumenta automaticamente os handlers `net/http` e o
  `http.Client` do evaluation-service — captura as chamadas pro
  flag-service/targeting-service como spans filhos, dando o "caminho da
  requisição" pedido no requisito 3).
- **Python (flag/targeting/analytics-service)**: `opentelemetry-distro` +
  auto-instrumentação (`opentelemetry-instrumentation-flask`,
  `-requests`, `-psycopg2`, `-boto3` no analytics-service) — captura rotas
  Flask, chamadas HTTP de saída e queries no Postgres como spans, sem
  reescrever lógica de negócio.
- Todos exportam via OTLP pro Collector interno do cluster
  (`otel-collector.<namespace>.svc:4317`), configurado via env vars
  (`OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`) no `gitops/*-service.yaml`
  — mesmo padrão de ConfigMap que já usamos pras outras env vars.

### Fase C — APM
1. Criar conta (New Relic, conforme decisão 4.1).
2. Configurar o OTel Collector pra também exportar traces pro OTLP intake
   do New Relic (exporter adicional no pipeline de traces).
3. Validar Service Map (deve mostrar os 5 serviços conectados) e um Trace
   Distribuído completo fazendo uma chamada em `/evaluate`.

### Fase D — Dashboard do Grafana
1 dashboard customizado com 3 painéis mínimos:
- Uso de recursos do cluster (CPU/memória por node ou por pod).
- Taxa de requisições por serviço (contador OTel `http.server.requests`
  exportado pro Prometheus, usando os spans/métricas da instrumentação).
- Painel de logs em tempo real (datasource Loki, query por namespace).

### Fase E — Alertas, Incidente, ChatOps, Self-Healing
1. Regra de alerta no Grafana Alerting: taxa de 5xx do auth-service > 5%
   (usa a métrica de requisições já exportada na Fase B/D).
2. Contact point 1: integração OpsGenie (abre incidente).
3. Contact point 2: webhook Discord (notificação detalhada).
4. Contact point 3: webhook pro GitHub (`repository_dispatch`) → workflow
   novo `self-heal.yml` que roda `kubectl rollout restart deployment/<serviço>`.
5. Testar o ciclo inteiro **de propósito** (ex: escalar o Deployment do
   auth-service pra 0 réplicas, ou derrubar uma RDS, provocando 5xx reais).

### Fase F — Gravação e relatório
- Roteiro do vídeo já está basicamente definido pelo próprio enunciado
  (seção "Vídeo de Demonstração") — seguir a ordem: visão geral → métricas/
  logs/OTel → APM/tracing → incidente real com self-healing ao vivo.
- Relatório: prints de cada evidência obrigatória + justificativa técnica
  (arquitetura do OTel, por que New Relic/OpsGenie/Discord).

## 6. Riscos conhecidos (aprendidos nas fases anteriores)

- **Ambiente efêmero**: toda vez que a infra for destruída/recriada, a
  stack de observabilidade sobe de novo sozinha via ArgoCD — mas o
  Collector/Grafana podem precisar de tempo pra "aquecer" antes da
  gravação. Rodar um teste completo pelo menos 1x antes do dia da gravação
  de verdade.
- **Pods não recarregam env var sozinhos** (já vivemos isso com o Redis) —
  depois de adicionar `OTEL_EXPORTER_OTLP_ENDPOINT` nos Deployments, pode
  ser preciso `kubectl rollout restart` nos 5 serviços.
- **Trivy/gosec podem gerar novidade** nas libs de instrumentação OTel
  recém-adicionadas (dependências novas = superfície nova pro SCA) —
  esperado, tratar como já tratamos antes (corrigir versão real ou
  `.trivyignore`/`#nosec` com justificativa).
- **Capacidade do cluster** — ver decisão 4.5, validar com
  `kubectl top nodes` depois de subir a stack, antes de prosseguir.
