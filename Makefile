.PHONY: help build test deploy demo demo-anvil

RPC_URL ?= http://127.0.0.1:8545

help:
	@echo "Targets:"
	@echo "  make build                  Run forge build"
	@echo "  make test                   Run forge test"
	@echo "  make deploy RPC_URL=<url>   Broadcast deploy script"
	@echo "  make demo RPC_URL=<url>     Broadcast local demo flow"
	@echo "  make demo-anvil             Start local Anvil node"
	@echo ""
	@echo "Required env vars for deploy: PRIVATE_KEY ENS_REGISTRY POOL_MANAGER"
	@echo "Optional env vars for deploy: DEFAULT_MAX_SWAP_ABS DEFAULT_COOLDOWN_SECONDS"
	@echo "Required env vars for demo: PRIVATE_KEY"

build:
	forge build

test:
	forge test

deploy:
	forge script script/DeployUniswapExeGuard.s.sol:DeployUniswapExeGuard --rpc-url $(RPC_URL) --broadcast

demo:
	@if [ -z "$$PRIVATE_KEY" ]; then \
		echo "Missing PRIVATE_KEY. Example: export PRIVATE_KEY=<anvil_private_key>"; \
		exit 1; \
	fi
	@cast chain-id --rpc-url $(RPC_URL) >/dev/null 2>&1 || ( \
		echo "RPC not reachable at $(RPC_URL). Start Anvil first with: make demo-anvil"; \
		exit 1 \
	)
	forge script script/DemoFlow.s.sol:DemoFlow --rpc-url $(RPC_URL) --broadcast

demo-anvil:
	anvil --host 127.0.0.1 --port 8545
