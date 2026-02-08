#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "$ROOT_DIR/.env"
set +a

ACCOUNT="${ACCOUNT:-sepolia-deployer}"
PASSWORD_FILE="${PASSWORD_FILE:-.password}"
POLICY_REGISTRY="${POLICY_REGISTRY:-${1:-}}"
ENS_NAME="${ENS_NAME:-${2:-}}"
MAX_SWAP_ABS="${MAX_SWAP_ABS:-${3:-1000000000000000000}}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-${4:-60}}"

: "${SEPOLIA_RPC_URL:?SEPOLIA_RPC_URL is required in .env}"
: "${POLICY_REGISTRY:?POLICY_REGISTRY is required (env or arg1)}"
: "${ENS_NAME:?ENS_NAME is required (env or arg2)}"
: "${ENS_REGISTRY:?ENS_REGISTRY is required in .env}"

# Normalize input to avoid hidden CR/whitespace from .env edits.
ENS_NAME=$(printf "%s" "$ENS_NAME" | tr -d '\r' | tr -d '[:space:]')

if [[ "$PASSWORD_FILE" != /* ]]; then
  PASSWORD_FILE="$ROOT_DIR/$PASSWORD_FILE"
fi

ACCOUNT_ADDRESS=$(cast wallet address --account "$ACCOUNT" --password-file "$PASSWORD_FILE")
REGISTRY_OWNER=$(cast call "$POLICY_REGISTRY" "owner()(address)" --rpc-url "$SEPOLIA_RPC_URL")

if [[ "${ACCOUNT_ADDRESS,,}" != "${REGISTRY_OWNER,,}" ]]; then
  echo "Account mismatch:"
  echo "- signer account       : $ACCOUNT_ADDRESS"
  echo "- PolicyRegistry owner : $REGISTRY_OWNER"
  echo "setPolicyForENS is onlyOwner. Use the owner account."
  exit 1
fi

if ! NODE=$(cast namehash "$ENS_NAME" 2>/dev/null); then
  echo "Could not compute ENS namehash for: $ENS_NAME"
  echo "Use a valid ENS name like alice.eth"
  exit 1
fi

RESOLVER=$(cast call "$ENS_REGISTRY" "resolver(bytes32)(address)" "$NODE" --rpc-url "$SEPOLIA_RPC_URL")
if [[ "${RESOLVER,,}" == "0x0000000000000000000000000000000000000000" ]]; then
  echo "ENS name has no resolver on this network: $ENS_NAME"
  echo "Set a resolver for this name on Sepolia ENS first."
  exit 1
fi

RESOLVED_ADDRESS=$(cast call "$RESOLVER" "addr(bytes32)(address)" "$NODE" --rpc-url "$SEPOLIA_RPC_URL")
if [[ "${RESOLVED_ADDRESS,,}" == "0x0000000000000000000000000000000000000000" ]]; then
  echo "ENS resolver returns zero address for: $ENS_NAME"
  echo "Set the address record for this name on Sepolia ENS first."
  exit 1
fi

cast send "$POLICY_REGISTRY" \
  "setPolicyForNode(bytes32,uint256,uint256)" \
  "$NODE" "$MAX_SWAP_ABS" "$COOLDOWN_SECONDS" \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --password-file "$PASSWORD_FILE"
