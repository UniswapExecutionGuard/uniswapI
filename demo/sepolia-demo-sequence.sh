#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${TRADER:?TRADER must be set for demo sequence}"

"$ROOT_DIR/demo/sepolia-policy-set.sh"
"$ROOT_DIR/demo/sepolia-policy-read.sh"
"$ROOT_DIR/demo/sepolia-hook-config.sh"

echo "Demo sequence complete."
echo "- Policy set for TRADER=$TRADER"
echo "- Policy read output printed above"
echo "- Hook defaults updated"
