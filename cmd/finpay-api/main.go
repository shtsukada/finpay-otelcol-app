package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"google.golang.org/grpc"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/reflection"
)

type config struct {
	grpcAddr    string
	metricsAddr string
	otlpEP      string
	serviceName string
}

func mustEnv(key, def string) string {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	return v
}

func loadConfig() config {
	return config{
		grpcAddr:    mustEnv("FINPAY_GRPC_ADDR", ":8080"),
		metricsAddr: mustEnv("FINPAY_METRICS_ADDR", ":2112"),
		otlpEP:      mustEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "otelcol-gateway:4317"),
		serviceName: mustEnv("OTEL_SERVICE_NAME", "finpay-api"),
	}
}

func initTracer(ctx context.Context, cfg config) (func(context.Context) error, error) {
	exp, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(cfg.otlpEP),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(semconv.ServiceName(cfg.serviceName)),
	)
	if err != nil {
		return nil, err
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithResource(res),
		sdktrace.WithBatcher(exp),
	)
	otel.SetTracerProvider(tp)

	return tp.Shutdown, nil
}

func main() {
	cfg := loadConfig()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	shutdown, err := initTracer(ctx, cfg)
	if err != nil {
		log.Fatalf("init tracer: %v", err)
	}
	defer func() {
		_ = shutdown(context.Background())
	}()

	// metrics server
	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", promhttp.Handler())
		srv := &http.Server{
			Addr:              cfg.metricsAddr,
			Handler:           mux,
			ReadHeaderTimeout: 5 * time.Second,
		}
		log.Printf("metrics listening on %s", cfg.metricsAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("metrics server: %v", err)
		}
	}()

	lis, err := net.Listen("tcp", cfg.grpcAddr)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}

	grpcServer := grpc.NewServer()

	// health
	hs := health.NewServer()
	hs.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)
	healthpb.RegisterHealthServer(grpcServer, hs)

	// reflection for dev
	reflection.Register(grpcServer)

	log.Printf("grpc listening on %s", cfg.grpcAddr)
	if err := grpcServer.Serve(lis); err != nil {
		fmt.Printf("grpc serve error: %v\n", err)
	}
}
