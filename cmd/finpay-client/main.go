package main

import (
	"context"
	"log"
	"os"
	"time"

	finpayv1 "github.com/shtsukada/finpay-otelcol-proto/gen/go/finpay/v1"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
)

func env(key, def string) string {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	return v
}

func initTracer(ctx context.Context) (func(context.Context) error, error) {
	ep := env("OTEL_EXPORTER_OTLP_ENDPOINT", "otelcol-gateway:4317")
	exp, err := otlptracegrpc.New(ctx, otlptracegrpc.WithEndpoint(ep), otlptracegrpc.WithInsecure())
	if err != nil {
		return nil, err
	}
	tp := sdktrace.NewTracerProvider(sdktrace.WithBatcher(exp))
	otel.SetTracerProvider(tp)
	return tp.Shutdown, nil
}

func main() {
	target := env("FINPAY_TARGET", "finpay-api:8080")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	shutdown, err := initTracer(ctx)
	if err != nil {
		log.Fatalf("init tracer: %v", err)
	}
	defer func() { _ = shutdown(context.Background()) }()

	conn, err := grpc.NewClient(target, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("dial: %v", err)
	}
	defer conn.Close()

	finpayClient := finpayv1.NewFinpayServiceClient(conn)
	_ = finpayClient

	c := healthpb.NewHealthClient(conn)
	resp, err := c.Check(context.Background(), &healthpb.HealthCheckRequest{})
	if err != nil {
		log.Fatalf("health check: %v", err)
	}
	log.Printf("health: %s", resp.Status.String())
}
