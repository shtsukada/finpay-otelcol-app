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
