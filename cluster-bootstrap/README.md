# cluster-bootstrap/

Manifests aplicados de forma **imperativa** (via `kubectl`, pelo workflow
`bootstrap-cluster.yml`), não sincronizados pelo ArgoCD — diferente de
`gitops/`, que é continuamente reconciliado.

Por quê separar: o `db-migrate-job.yaml` é uma tarefa "rode uma vez", não um
estado desejado permanente. Deixar isso dentro de `gitops/` faria o ArgoCD
tentar gerenciar o ciclo de vida de um Job que já terminou, o que não faz
sentido pro modelo de sync contínuo.

## db-migrate-job.yaml

Roda os 3 `<service>/db/init.sql` (CREATE TABLE etc.) contra as instâncias
RDS reais. Necessário porque RDS não tem o mecanismo
`docker-entrypoint-initdb.d` que o Postgres em Docker tem — os bancos sobem
vazios, alguém precisa aplicar o schema.

Só funciona rodando **de dentro da VPC** (por isso é um Job no cluster, não
um `psql` direto do runner do GitHub Actions — RDS está em subnet privada e
o Security Group só libera acesso de dentro da VPC).
