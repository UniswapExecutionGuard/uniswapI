#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "$ROOT_DIR/.env"
set +a

ACCOUNT="${ACCOUNT:-sepolia-deployer}"
PASSWORD_FILE="${PASSWORD_FILE:-.password}"
POLICY_REGISTRY="${POLICY_REGISTRY:-${1:-}}"
TRADER="${TRADER:-${2:-}}"
MAX_SWAP_ABS="${MAX_SWAP_ABS:-${3:-1000000000000000000}}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-${4:-60}}"

: "${SEPOLIA_RPC_URL:?SEPOLIA_RPC_URL is required in .env}"
: "${POLICY_REGISTRY:?POLICY_REGISTRY is required (env or arg1)}"
: "${TRADER:?TRADER is required (env or arg2)}"

if [[ "$PASSWORD_FILE" != /* ]]; then
  PASSWORD_FILE="$ROOT_DIR/$PASSWORD_FILE"
fi

cast send "$POLICY_REGISTRY" \
  "setPolicy(address,uint256,uint256)" \
  "$TRADER" "$MAX_SWAP_ABS" "$COOLDOWN_SECONDS" \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --password-file "$PASSWORD_FILE"
