package main

import (
	"context"
	"log"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// initTracer configura o OpenTelemetry e manda traces pro OTel Collector
// (Fase 4 do desafio — observabilidade).
//
// otlptracegrpc.New(ctx) sem opções já lê sozinho as env vars padrão
// OTEL_EXPORTER_OTLP_* (endpoint, TLS/insecure, etc) — de propósito, pra
// usar exatamente a mesma variável e o mesmo formato (com o prefixo
// "http://", que sinaliza "sem TLS" pro SDK) nos serviços Go e Python, sem
// cada linguagem interpretando a config de um jeito diferente.
//
// Se a env var não estiver definida (ex: rodando local sem a stack de
// observabilidade), o tracing fica desativado sem quebrar o serviço — nunca
// é um requisito pra funcionar, só um extra.
func initTracer(ctx context.Context, serviceName string) func(context.Context) error {
	noop := func(context.Context) error { return nil }

	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" {
		log.Println("OTEL_EXPORTER_OTLP_ENDPOINT não definida — tracing desativado")
		return noop
	}

	exporter, err := otlptracegrpc.New(ctx)
	if err != nil {
		log.Printf("Falha ao criar exporter OTLP: %v — tracing desativado", err)
		return noop
	}

	res, err := resource.New(ctx, resource.WithAttributes(semconv.ServiceName(serviceName)))
	if err != nil {
		res = resource.Default()
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, propagation.Baggage{},
	))

	log.Printf("OpenTelemetry tracing habilitado (service=%s)", serviceName)
	return tp.Shutdown
}
