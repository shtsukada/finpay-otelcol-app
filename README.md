# finpay-otelcol-app

金融を模した題材のデモアプリ(gRPC)です。

* `finpay-api`: 送金API(署名・nonce・冪等・重複排除・Redis/SQLite)
* `finpay-client`: デモ用ロードジェネレータ(retry storm対応)

両者ともOpenTelemetry計装を行い、OTLPで`otelcol-gateway`に送信します。

---

## Features(MVP)

### 署名とリプレイ耐性

* timestamp skew check: `±FINPAY_TS_SKEW` 超過→ `Unauthenticated`
* nonce: Redis `SET <nonceKey> NX EX=<FINPAY_NONCE_TTL>` 再利用 → `FailedPrecondition`
* key rotation: `(client_id, key_id)` で公開鍵参照、`revoked_at`があれば拒否

### 冪等と二重実行防止(Idempotency/Dedupe)

* Redis lock + cache + DB unique constraint (MVP SQLite,Plus)
* 同一 `idempotency_key`は**同一レスポンスを返す**(snapshot)
* `client_transfer_id` 重複も検知(AlreadyExists/OK)

### Observability

* Prometheus metrics: method/code を中心に低カーディナリティ
* OTel traces: `trace-id` を中心に可観測化
* High-cardinality Identifiers (`transfer_id` 等) は Prom ラベルにしない(span attributesへ)

## ディレクトリ構成_TODO:完成後修正のこと

finpay-otelcol-app/
├─ README.md
├─ go.mod
├─ go.sum
├─ cmd/
│  ├─ finpay-api/
│  │  └─ main.go
│  └─ finpay-client/
│     └─ main.go
├─ internal/
│  ├─ api/                         # gRPC handlers
│  ├─ auth/
│  │  ├─ signer.go                 # canonical string / verify
│  │  ├─ keys.go                   # FINPAY_KEYS_FILE load, key rotation
│  │  └─ replay.go                 # timestamp skew + nonce
│  ├─ idempotency/
│  │  ├─ lock.go                   # Redis lock
│  │  ├─ cache.go                  # response snapshot
│  │  └─ dedupe.go                 # client_transfer_id checks
│  ├─ store/
│  │  ├─ redis/
│  │  │  └─ client.go
│  │  └─ db/
│  │     ├─ sqlite.go              # MVP: SQLite
│  │     └─ migrations/            # （任意）将来用
│  ├─ telemetry/
│  │  ├─ otel.go                   # tracer/meter init
│  │  └─ metrics.go                # prom metrics（cardinality守る）
│  ├─ errors/
│  │  └─ grpc_status.go            # status mapping
│  └─ config/
│     └─ config.go                 # ENV 読み込み
├─ pkg/                            # （必要なら）外部に公開する型
├─ protodeps/                      # proto module のバージョン固定メモ等（任意）
├─ deploy/                         # app単体のmanifest（任意。基本はmonitoring chartで起動）
├─ hack/
│  ├─ genkeys/                     # dev鍵生成（MVP用）
│  └─ e2e/                         # 軽量E2E（docker/kind）
├─ Dockerfile.api
├─ Dockerfile.client
├─ Makefile                        # test/lint/buildx/smoke
└─ .github/
   └─ workflows/
      ├─ ci.yml                    # go test/lint + buildx amd64
      └─ release.yml               # tagでpush + SBOM/署名（PlusでもOK）

---

## Contracts

* Env / Service / Secret / values contracts are defined in:
  * root repo: `finpay-otelcol/DESIGN.md`

---

## Environment variables (MVP)

### finpay-api

* `FINPAY_GRPC_ADDR` (default `:8080`)
* `FINPAY_METRICS_ADDR` (default `:2112`)
* `FINPAY_REDIS_ADDR` (e.g. `redis:6379`)
* `FINPAY_DB_DSN` (e.g. `file:/var/lib/finpay/finpay.db`)
* `FINPAY_IDEMPOTENCY_LOCK_TTL` (e.g. `15s`)
* `FINPAY_IDEMPOTENCY_CACHE_TTL` (e.g. `10m`)
* `FINPAY_NONCE_TTL` (e.g. `10m`)
* `FINPAY_TS_SKEW` (e.g. `300s`)
* `FINPAY_KEYS_FILE` (e.g. `/etc/finpay/client_public_keys/json`)
* `OTEL_EXPORTER_OTLP_ENDPOINT` (e.g. `otelcol-gateway:4317`)
* `OTEL_EXPORTER_OTLP_PROTOCOL` (`grpc`)

### finpay-client

* `FINPAY_TARGET` (e.g. `finpay-api:8080`)
* `FINPAY_CLIENT_ID` , `FINPAY_KEY_ID`
* `FINPAY_PRIVATE_KEY_FILE` ( Secret mount )
* `FINPAY_DURATION` (e.g. `5m`)
* `FINPAY_CONCURRENCY` (e.g. `20`)
* `FINPAY_RETRY_STORM` (e.g. `true`)
* `OTEL_SERVICE_NAME` (e.g. `finpay-client`)
* `OTEL_EXPORTER_OTLP_ENDPOINT` (e.g. `otelcol-gateway:4317`)

## Local dev / buildx / CI

```bash
go test ./...
go run ./cmd/finpay-api
go run ./cmd/finpay-client
```

```bash
make buildx-api
make buildx-client
```

```bash
go test ./...
go vet ./...
docker buildx build --platform linux/amd64
```

## License

MIT
