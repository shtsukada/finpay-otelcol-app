#!/usr/bin/env bash
set -euo pipefail

# Generate dev keys for finpay-client and public-keys JSON for finpay-api.
# Output:
# hack/.local/keys/<client_id>/<key_id>/{private.pem,public.pem}
# hack/.local/keys/client_public_keys.json
#
# Usage:
# ./hack/gen-keys.sh [client_id] [key_id]
#
# Example:
# ./hack/gen-keys.sh client-a k1

CLIENT_ID="${1:-client-a}"
KEY_ID="${2:-k1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/hack/.local/keys/${CLIENT_ID}/${KEY_ID}"
JSON_OUT="${ROOT_DIR}/hack/.local/keys/client_public/keys.json"

mkdir -p "${OUT_DIR}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required" >&2
  exit 1
fi

echo "==> generating Ed25519 keypair: client_id=${CLIENT_ID} key_id=${KEY_ID}"

openssl genpkey -algorithm ed25519 -out "${OUR_DIR}/private.pem" >/dev/null 2>&1
openssl pkey -in "${OUT_DIR}/private.pem" -pubout -out "${OUT_DIR}/public.pem" >/dev/null 2>&1
PUB_PEM="$(cat "${OUT_DIR}/public.pem")"

echo "==> writing public keys JSON: ${JSON_OUT}"
python3 - <<PY
import json, pathlib
client_id = ${CLIENT_ID!r}
key_id = ${KEY_ID!r}
pub_pem = pathlib.Path(${("${OUT_DIR}/public.pem")!r}).read_text()

# Simple single-key format (array). Extend when you add more clients/keys.
doc = [{
  "client_id": client_id,
  "key_id": key_id,
  "public_key_pem": pub_pem,
  "revoked_at": None,
}]

out = pathlib.Path(${JSON_OUT!r})
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
PY

echo "==> done"
echo "private: ${OUT_DIR}/private.pem"
echo "public : ${OUT_DIR}/public.pem"
echo "json   : ${JSON_OUT}"
