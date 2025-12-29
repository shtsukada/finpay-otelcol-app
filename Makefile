.PHONY: test lint build buildx-api buildx-client

test:
  go test ./...

lint:
  go vet ./...

build:
  go build ./...

buildx-api:
  docker buildx build --platform linux/amd64 -f Dockerfile.api -t finpay-api:dev .

buildx-client:
  docker buildx build --platform linux/amd64 -f Dockerfile.client -t finpay-:client:dev .
