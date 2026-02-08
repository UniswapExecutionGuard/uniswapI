#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "$ROOT_DIR/.env"
set +a

POLICY_REGISTRY="${POLICY_REGISTRY:-${1:-}}"
TRADER="${TRADER:-${2:-}}"

: "${SEPOLIA_RPC_URL:?SEPOLIA_RPC_URL is required in .env}"
: "${POLICY_REGISTRY:?POLICY_REGISTRY is required (env or arg1)}"
: "${TRADER:?TRADER is required (env or arg2)}"

cast call "$POLICY_REGISTRY" \
  "getPolicy(address)(uint256,uint256,bool)" \
  "$TRADER" \
  --rpc-url "$SEPOLIA_RPC_URL"
