#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "$ROOT_DIR/.env"
set +a

ACCOUNT="${ACCOUNT:-sepolia-deployer}"
PASSWORD_FILE="${PASSWORD_FILE:-.password}"
UNISWAP_EXE_GUARD="${UNISWAP_EXE_GUARD:-${1:-}}"
DEFAULT_MAX_SWAP_ABS="${DEFAULT_MAX_SWAP_ABS:-${2:-1000000000000000000}}"
DEFAULT_COOLDOWN_SECONDS="${DEFAULT_COOLDOWN_SECONDS:-${3:-60}}"

: "${SEPOLIA_RPC_URL:?SEPOLIA_RPC_URL is required in .env}"
: "${UNISWAP_EXE_GUARD:?UNISWAP_EXE_GUARD is required (env or arg1)}"

if [[ "$PASSWORD_FILE" != /* ]]; then
  PASSWORD_FILE="$ROOT_DIR/$PASSWORD_FILE"
fi

ACCOUNT_ADDRESS=$(cast wallet address --account "$ACCOUNT" --password-file "$PASSWORD_FILE")
HOOK_OWNER=$(cast call "$UNISWAP_EXE_GUARD" "owner()(address)" --rpc-url "$SEPOLIA_RPC_URL")

if [[ "${ACCOUNT_ADDRESS,,}" != "${HOOK_OWNER,,}" ]]; then
  echo "Account mismatch:"
  echo "- signer account : $ACCOUNT_ADDRESS"
  echo "- hook owner     : $HOOK_OWNER"
  echo "Use the owner account, or redeploy hook with ownership transferred to your signer."
  echo "(With updated Makefile: run make sepolia-deploy again.)"
  exit 1
fi

cast send "$UNISWAP_EXE_GUARD" \
  "setDefaults(uint256,uint256)" \
  "$DEFAULT_MAX_SWAP_ABS" "$DEFAULT_COOLDOWN_SECONDS" \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --password-file "$PASSWORD_FILE"
