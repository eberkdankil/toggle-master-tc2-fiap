FROM golang:1.25-alpine AS builder
# golang.org/x/crypto v0.55.0 (correção da CVE-2026-56854, ver go.mod) exige
# Go >= 1.25 pra compilar. As imagens oficiais do Docker Hub fixam
# GOTOOLCHAIN=local (diferente do binário Go usado no CI, que tem
# GOTOOLCHAIN=auto e baixa um toolchain novo sozinho) — sem bumpar a imagem
# base aqui, o build falha mesmo com o go.mod correto.
RUN apk add --no-cache git
WORKDIR /app
COPY go.mod ./
COPY . .
RUN go mod tidy && go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -o /evaluation-service .

FROM alpine:3.18
RUN apk add --no-cache ca-certificates
WORKDIR /
COPY --from=builder /evaluation-service /evaluation-service
EXPOSE 8001
ENTRYPOINT ["/evaluation-service"]
