#!/usr/bin/env bash
set -euo pipefail

# Local runner for finpay-api + finpay-client.
# starts Redis (docker) if available
# generates dev keys (optional)
# runs finpay-api and optionally finpay-client
#
# Usage:
# ./hack/run-local.sh api
# ./hack/run-local.sh client
# ./hack/run-local.sh all
#
# Optional env overrides:
#  CLIENT_ID=client-a KEY_ID=k1
#  OTEL_ENDPOINT=localhost:4317   (if you run otelcol locally)

MODE="${1:-all}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CLIENT_ID="${CLIENT_ID:-client-a}"
KEY_ID="${KEY_ID:-k1}"

KEY_BASE="${ROOT_DIR}/hack/.local/keys/${CLIENT_ID}/${KEY_ID}"
PUBKEYS_JSON="${ROOT_DIR}/hack/.local/keys/client_public_keys.json"

API_ENV_EXAMPLE="${ROOT_DIR}/configs/finpay-api.env.example"
CLIENT_ENV_EXAMPLE="${ROOT_DIR}/configs/finpay-client.env.example"

REDIS_CONTAINER_NAME="finpay-redis"
REDIS_PORT="6379"

cleanup() {
  if [[ -n "${API_PID:-}" ]] && kill -0 "${API_PID}" 2>/dev/null; then
    echo "==> stopping finpay-api (pid=${API_PID})"
    kill "${API_PID}" >/dev/null 2>&1 || true
  fi

  if command -v docker >/dev/null 2>&1; then
    if docker ps -a --format '{{.Names}}' | grep -q "^${REDIS_CONTAINER_NAME}$"; then
      echo "==> stopping redis container"
      docker rm -f "${REDIS_CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup EXIT

need_file() {
  local f="$1"
  [[ -f "$f" ]] || { echo "ERROR: missing file: $f" >&2; exit 1; }
}

need_file "${API_ENV_EXAMPLE}"
need_file "${CLIENT_ENV_EXAMPLE}"

# 1) Ensure dev keys exist
if [[ ! -f "${KEY_BASE}/private.pem" || ! -f "${KEY_BASE}/public.pem" || ! -f "${PUBKEYS_JSON}" ]]; then
  echo "==> dev keys not found. generating..."
  "${ROOT_DIR}/hack/gen-keys.sh" "${CLIENT_ID}" "${KEY_ID}"
fi

# 2) Start Redis (docker) if available
if command -v docker >/dev/null 2>&1; then
  echo "==> starting redis via docker (name=${REDIS_CONTAINER_NAME})"
  docker rm -f "${REDIS_CONTAINER_NAME}" >/dev/null 2>&1 || true
  docker run -d --name "${REDIS_CONTAINER_NAME}" -p "${REDIS_PORT}:6379" redis:7.4.1 >/dev/null
else
  echo "WARN: docker not found. please start redis at localhost:6379 manually." >&2
fi

# 3) Decide OTEL behavior
OTEL_ENDPOINT="${OTEL_ENDPOINT:-}"
if [[ -z "${OTEL_ENDPOINT}" ]]; then
  if command -v nc >/dev/null 2>&1 && nc -z localhost 4317 >/dev/null 2>&1; then
    OTEL_ENDPOINT="localhost:4317"
  fi
fi

if [[ -z "${OTEL_ENDPOINT}" ]]; then
  echo "==> OTLP endpoint not detected. disabling OTel SDK for local run."
  export OTEL_SDK_DISABLED=true
else
  echo "==> using OTLP endpoint: ${OTEL_ENDPOINT}"
  export OTEL_SDK_DISABLED=false
fi

load_env() {
  local f="$1"
  set -a
  source "$f"
  set +a
}

run_api() {
  echo "==> running finpay-api"
  load_env "${API_ENV_EXAMPLE}"

  # Local overrides
  export FINPAY_REDIS_ADDR="localhost:6379"
  export FINPAY_DB_DSN="file:${ROOT_DIR}/hack/.local/finpay.db"
  export FINPAY_KEYS_FILE="${PUBKEYS_JSON}"

  if [[ "${OTEL_SDK_DISABLED}" == "false" ]]; then
    export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_ENDPOINT}"
    export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
  fi

  mkdir -p "${ROOT_DIR}/hack/.local"
  (cd "${ROOT_DIR}" && go run ./cmd/finpay-api) &
  API_PID=$!
  echo "==> finpay-api pid=${API_PID}"
}

run_client() {
  echo "==> running finpay-client"
  load_env "${CLIENT_ENV_EXAMPLE}"

  # Local overrides
  export FINPAY_TARGET="localhost:8080"
  export FINPAY_CLIENT_ID="${CLIENT_ID}"
  export FINPAY_KEY_ID="${KEY_ID}"
  export FINPAY_PRIVATE_KEY_FILE="${KEY_BASE}/private.pem"

  if [[ "${OTEL_SDK_DISABLED}" == "false" ]]; then
    export OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_ENDPOINT}"
    export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
  fi

  (cd "${ROOT_DIR}" && go run ./cmd/finpay-client)
}

case "${MODE}" in
  api)
    run_api
    echo "==> finpay-api is running. press Ctrl+C to stop."
    wait "${API_PID}"
    ;;
  client)
    # client-only assumes api already running
    run_client
    ;;
  all)
    run_api
    # wait a bit for server to start
    sleep 1
    run_client
    echo "==> done. stopping finpay-api..."
    ;;
  *)
    echo "Usage: $0 {api|client|all}" >&2
    exit 1
    ;;
esac
