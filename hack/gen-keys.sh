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

openssl genpkey -algorithm ed25519 -out "${OUT_DIR}/private.pem" >/dev/null 2>&1
openssl pkey -in "${OUT_DIR}/private.pem" -pubout -out "${OUT_DIR}/public.pem" >/dev/null 2>&1

echo "==> writing public keys JSON: ${JSON_OUT}"
python3 - "${CLIENT_ID}" "${KEY_ID}" "${OUT_DIR}/public.pem" "${JSON_OUT}" <<'PY'
import json
import pathlib
import sys
client_id = sys.argv[1]
key_id = sys.argv[2]
public_key_path = pathlib.Path(sys.argv[3])
json_out_path = pathlib.Path(sys.argv[4])
pub_pem = public_key_path.read_text()

# Simple single-key format (array). Extend when you add more clients/keys.
doc = [{
  "client_id": client_id,
  "key_id": key_id,
  "public_key_pem": pub_pem,
  "revoked_at": None,
}]

out = json_out_path
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
PY

echo "==> done"
echo "private: ${OUT_DIR}/private.pem"
echo "public : ${OUT_DIR}/public.pem"
echo "json   : ${JSON_OUT}"
