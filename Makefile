.PHONY: help build test deploy demo demo-anvil

RPC_URL ?= http://127.0.0.1:8545
DEPLOY_SCRIPT := script/DeployUniswapExeGuard.s.sol:DeployUniswapExeGuard
DEMO_SCRIPT := script/DemoFlow.s.sol:DemoFlow

help:
	@echo "Targets:"
	@echo "  make build                      - Run forge build"
	@echo "  make test                       - Run forge test"
	@echo "  make deploy RPC_URL=<url>       - Broadcast deployment script"
	@echo "  make demo RPC_URL=<url>         - Broadcast local demo flow"
	@echo "  make demo-anvil                 - Start local Anvil node"
	@echo ""
	@echo "Required env vars for deploy: PRIVATE_KEY ENS_REGISTRY POOL_MANAGER"
	@echo "Optional env vars for deploy: DEFAULT_MAX_SWAP_ABS DEFAULT_COOLDOWN_SECONDS"
	@echo "Required env vars for demo: PRIVATE_KEY"
	@echo "Optional env vars for demo: DEMO_TRADER"

build:
	forge build

test:
	forge test

deploy:
	forge script $(DEPLOY_SCRIPT) --rpc-url $(RPC_URL) --broadcast

demo:
	forge script $(DEMO_SCRIPT) --rpc-url $(RPC_URL) --broadcast

demo-anvil:
	anvil --host 127.0.0.1 --port 8545
