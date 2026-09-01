module auth-service

go 1.21

require (
	github.com/jackc/pgx/v4 v4.18.3
	github.com/joho/godotenv v1.5.1
)

require (
	github.com/jackc/chunkreader/v2 v2.0.1 // indirect
	github.com/jackc/pgconn v1.14.3 // indirect
	github.com/jackc/pgio v1.0.0 // indirect
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgproto3/v2 v2.3.3 // indirect
	github.com/jackc/pgservicefile v0.0.0-20221227161230-091c0ba34f0a // indirect
	github.com/jackc/pgtype v1.14.0 // indirect
	github.com/pkg/errors v0.9.1 // indirect
	// DEMO DevSecOps: pra reproduzir o Trivy bloqueando o pipeline (CVE-2026-56854,
	// CRÍTICA), troque a linha abaixo por "golang.org/x/crypto v0.20.0 // indirect"
	// e dê push — o job security-scan deve falhar. Depois volte pra v0.55.0 (ou
	// mais nova) pra mostrar passando de novo. Instrução completa no README.md
	// deste serviço, caso esse comentário não sobreviva a um `go mod tidy`.
	golang.org/x/crypto v0.55.0 // indirect
	golang.org/x/text v0.14.0 // indirect
)