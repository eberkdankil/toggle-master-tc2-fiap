# GitOps — manifests do ToggleMaster

Pasta que o ArgoCD vai sincronizar com o cluster EKS (`terraform/environments/aws`
no repo `togglemaster-infra`). Arquivos numerados = ordem de aplicação.

## O que tem aqui

| Arquivo | O quê |
|---|---|
| `00-namespace.yaml` | Namespace `toggle-master` |
| `01-secret.yaml.example` | Modelo do Secret — **o real (`01-secret.yaml`) não é commitado** |
| `02-configmap.yaml` | Config não-sensível — tem placeholders `__ASSIM__` pra endpoints que mudam a cada `terraform apply` |
| `03` a `07` | Deployment + Service de cada um dos 5 microsserviços, imagem vindo do ECR |
| `08-hpa.yaml` | Autoscaling do evaluation-service e analytics-service |
| `09-ingress-nginx-app.yaml` | Application do ArgoCD que instala o ingress-nginx (Helm) |
| `10-ingress.yaml` | Ingress com prefixo por serviço (`/auth`, `/flags`, `/targeting`, `/evaluation`, `/analytics`) |
| `11-metrics-server-app.yaml` | Application do ArgoCD que instala o metrics-server (Helm) — necessário pro `08-hpa.yaml` funcionar |

## Antes do primeiro deploy (depois de toda recriação da infra)

Rode o workflow **`bootstrap-cluster`** (Actions → bootstrap-cluster → Run
workflow) no repo. Ele faz tudo isso automaticamente:

1. Descobre os endpoints atuais do RDS/Redis/SQS na AWS (mudam a cada
   `terraform apply`, já que a infra é destruída/recriada com frequência).
2. Reescreve os placeholders `__REDIS_ENDPOINT__`/`__SQS_QUEUE_URL__` em
   `02-configmap.yaml` e comita — o ArgoCD sincroniza normalmente a partir daí.
3. Aplica o `Secret` real direto no cluster via `kubectl` (nunca vai pro Git —
   valores vêm de GitHub Secrets, ver `.github/workflows/README.md`).
4. Roda a migração de schema nos 3 RDS (`cluster-bootstrap/db-migrate-job.yaml`)
   — RDS não tem o mecanismo `docker-entrypoint-initdb.d` do Postgres em
   Docker, então ninguém cria as tabelas sozinho; esse Job faz isso.

`01-secret.yaml.example` continua aqui só como documentação do formato — não
precisa mais criar `01-secret.yaml` manualmente, o bootstrap cobre isso.

`ingress-nginx` e `metrics-server` também são sincronizados automaticamente
pelo ArgoCD (`09-ingress-nginx-app.yaml`, `11-metrics-server-app.yaml`) — não
precisa de nenhum `kubectl apply` manual pra eles.

## Por que não tem AWS_ACCESS_KEY_ID/SECRET nos Deployments

Os nodes do EKS já usam a **LabRole** como instance profile (ver
`terraform/modules/eks`). O `aws-sdk-go` (evaluation-service) e o `boto3`
(analytics-service) resolvem credenciais automaticamente via metadata do EC2
(IMDS) sem precisar de nada explícito — e como o AWS Academy não permite criar
roles de IRSA próprias, essa é a forma correta de fazer isso aqui, não uma
gambiarra.

## Tag de imagem

Todos os Deployments apontam pra `:latest` por enquanto. Quando o pipeline de
CI for montado, o passo de CD vai reescrever a linha `image:` de cada arquivo
com a tag do commit hash (`v1.0.0-a1b2c3d`, conforme pedido no desafio) antes
de dar commit/push nesta pasta — é esse commit que o ArgoCD detecta e sincroniza.
