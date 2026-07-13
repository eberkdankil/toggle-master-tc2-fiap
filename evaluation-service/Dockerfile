FROM golang:1.21-alpine AS builder
RUN apk add --no-cache git
WORKDIR /app
COPY go.mod go.sum ./
COPY . .
RUN go mod tidy && go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -o /evaluation-service .

FROM alpine:3.18
RUN apk add --no-cache ca-certificates
WORKDIR /
COPY --from=builder /evaluation-service /evaluation-service
EXPOSE 8004
ENTRYPOINT ["/evaluation-service"]
