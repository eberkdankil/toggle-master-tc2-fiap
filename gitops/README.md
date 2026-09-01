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
| `08-hpa.yaml` | Autoscaling do evaluation-service e analytics-service (precisa do `metrics-server` instalado no cluster) |

## Antes do primeiro deploy

1. **Secret**: copie `01-secret.yaml.example` → `01-secret.yaml`, preencha com
   os valores reais (senhas do RDS, master key, service API key) e aplique
   manualmente uma vez — `kubectl apply -f gitops/01-secret.yaml`. Isso fica
   fora do sync do ArgoCD de propósito (não expõe credencial real no Git).

2. **ConfigMap**: rode no repo `togglemaster-infra`:
   ```bash
   terraform -chdir=terraform/environments/aws output redis_endpoint
   terraform -chdir=terraform/environments/aws output sqs_queue_url
   ```
   e substitua `__REDIS_ENDPOINT__` e `__SQS_QUEUE_URL__` em `02-configmap.yaml`
   pelos valores reais antes de commitar. Esses endpoints mudam toda vez que a
   infra é destruída/recriada — automatizar essa substituição via CI é um
   próximo passo natural, não implementado ainda.

3. **metrics-server** (pra HPA funcionar):
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

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
