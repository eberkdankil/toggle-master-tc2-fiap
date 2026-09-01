# Workflows

Um workflow por microsserviço (`auth-service.yml`, `flag-service.yml`,
`targeting-service.yml`, `evaluation-service.yml`, `analytics-service.yml`),
cada um disparando só quando o respectivo diretório muda. Todos chamam um dos
dois workflows reutilizáveis (`_reusable-go-service.yml` ou
`_reusable-python-service.yml`) pra não repetir os mesmos ~150 jobs 5 vezes.

## Pipeline (por serviço)

1. **Build & Unit Test**
2. **Linter** (não bloqueia o pipeline por enquanto — código ainda não foi
   auditado, ver comentário no workflow reutilizável)
3. **Security Scan (SAST & SCA)** — Trivy (dependências) + gosec/bandit
   (código-fonte). **Bloqueia o pipeline em qualquer achado CRÍTICO.**
4. **Docker Build & Push** — só em push na `master` (não em PR). Trivy escaneia
   a imagem antes do push (mesma regra de bloqueio). Tag = hash curto do commit.
5. **Atualizar GitOps** — reescreve a tag da imagem no arquivo correspondente
   dentro de `gitops/` e comita direto nesse mesmo repo (é o commit que o
   ArgoCD detecta e sincroniza).

## `bootstrap-cluster.yml` — disparo manual, não por serviço

Diferente dos 5 workflows acima (que disparam em push/PR), esse só roda
quando você manda (Actions → bootstrap-cluster → Run workflow) — porque ele
não é sobre código de um serviço, é sobre preparar o cluster depois que a
infra (`togglemaster-infra`) é criada/recriada do zero. Faz 3 coisas:
descobre os endpoints atuais de RDS/Redis/SQS e atualiza `gitops/02-configmap.yaml`,
aplica o `Secret` real direto no cluster, e roda a migração de schema nos 3
RDS (ver `cluster-bootstrap/README.md`). Rode ele **toda vez que recriar a
infra**, antes de esperar os pods subirem de verdade.

## Secrets necessários (Settings → Secrets and variables → Actions)

| Secret | Valor |
|---|---|
| `AWS_ACCESS_KEY_ID` | Do AWS Academy Learner Lab → AWS Details → aba AWS CLI |
| `AWS_SECRET_ACCESS_KEY` | Idem |
| `AWS_SESSION_TOKEN` | Idem |
| `DB_AUTH_PASSWORD` | Mesma senha usada em `auth_db_password` no `terraform.tfvars` do repo `togglemaster-infra` |
| `DB_FLAGS_PASSWORD` | Idem, `flags_db_password` |
| `DB_TARGETING_PASSWORD` | Idem, `targeting_db_password` |
| `MASTER_KEY` | Chave mestra do auth-service (qualquer valor forte, à sua escolha) |
| `SERVICE_API_KEY` | Chave interna do evaluation-service — ver nota em `gitops/01-secret.yaml.example` sobre reusar a chave de dev já semeada |

⚠️ `DB_AUTH_PASSWORD`/`DB_FLAGS_PASSWORD`/`DB_TARGETING_PASSWORD` **precisam
bater exatamente** com o que está no `terraform.tfvars` do repo de infra —
são a mesma senha em dois lugares (o Terraform define a senha do RDS, o
`bootstrap-cluster` usa a mesma pra montar a connection string). Se
mudar uma, muda a outra.

⚠️ **AWS Academy**: essas credenciais são temporárias e expiram em poucas
horas. Toda vez que a sessão do Learner Lab for renovada, alguém do grupo
precisa **atualizar esses 3 secrets manualmente** antes do próximo push —
sem isso, o job `docker-build-push` falha no login do ECR. Não tem como
automatizar essa parte no modo Academy (não permite usuário IAM de longa
duração).

## Por que o registro do ECR não está hardcoded

O `docker-build-push` descobre a conta/região via
`aws-actions/amazon-ecr-login` (que usa as credenciais acima), não um account
ID fixo no YAML — isso evita o mesmo problema que o `ecr-push.sh` antigo tinha
(account ID de uma conta diferente hardcoded no script).
