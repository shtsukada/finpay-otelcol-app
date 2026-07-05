.PHONY: test lint build build-api build-client buildx-api buildx-client

test:
	go test ./...

lint:
	go vet ./...

build: build-api build-client

build-api:
	go build -o bin/finpay-api ./cmd/finpay-api

build-client:
	go build -o bin/finpay-client ./cmd/finpay-client

buildx-api:
	docker buildx build --platform linux/amd64 -f Dockerfile.api -t finpay-api:dev .

buildx-client:
	docker buildx build --platform linux/amd64 -f Dockerfile.client -t finpay-client:dev .
