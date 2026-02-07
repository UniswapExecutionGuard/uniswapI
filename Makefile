.PHONY: help build test local-node local-demo sepolia-import sepolia-deploy deploy

ifneq (,$(wildcard .env))
include .env
export
endif

LOCAL_RPC_URL ?= http://127.0.0.1:8545
ACCOUNT ?= sepolia-deployer
PASSWORD_FILE ?= .password
DEPLOY_SCRIPT := script/DeployUniswapExeGuard.s.sol:DeployUniswapExeGuard
DEMO_SCRIPT := script/DemoFlow.s.sol:DemoFlow

help:
	@echo "Core:"
	@echo "  make build                 Compile contracts"
	@echo "  make test                  Run tests"
	@echo ""
	@echo "Local Anvil demo:"
	@echo "  make local-node            Start Anvil at $(LOCAL_RPC_URL)"
	@echo "  make local-demo            Run demo script against local Anvil (requires PRIVATE_KEY_ANVIL)"
	@echo ""
	@echo "Sepolia deploy:"
	@echo "  make sepolia-import        Import deployer wallet interactively (ACCOUNT=$(ACCOUNT))"
	@echo "  make sepolia-deploy        Deploy using --account + --password-file"
	@echo ""
	@echo "Required .env vars for sepolia-deploy: SEPOLIA_RPC_URL ENS_REGISTRY POOL_MANAGER"
	@echo "Password file for sepolia-deploy: $(PASSWORD_FILE)"

build:
	forge build

test:
	forge test

deploy: ## generic deploy with raw private key (manual usage)
	@if [ -z "$$PRIVATE_KEY" ]; then \
		echo "Missing PRIVATE_KEY for make deploy"; \
		exit 1; \
	fi
	forge script $(DEPLOY_SCRIPT) --rpc-url $(LOCAL_RPC_URL) --private-key $$PRIVATE_KEY --broadcast

sepolia-deploy:
	@if [ -z "$(SEPOLIA_RPC_URL)" ]; then \
		echo "Missing SEPOLIA_RPC_URL in .env"; \
		exit 1; \
	fi
	@if [ -z "$$ENS_REGISTRY" ] || [ -z "$$POOL_MANAGER" ]; then \
		echo "Missing required env vars: ENS_REGISTRY POOL_MANAGER"; \
		exit 1; \
	fi
	@if [ ! -f "$(PASSWORD_FILE)" ]; then \
		echo "Missing password file: $(PASSWORD_FILE)"; \
		exit 1; \
	fi
	forge script $(DEPLOY_SCRIPT) --rpc-url $(SEPOLIA_RPC_URL) --account $(ACCOUNT) --password-file $(PASSWORD_FILE) --broadcast

sepolia-import:
	cast wallet import $(ACCOUNT) --interactive

local-demo:
	@if [ -z "$$PRIVATE_KEY_ANVIL" ]; then \
		echo "Missing PRIVATE_KEY_ANVIL in .env"; \
		exit 1; \
	fi
	@cast chain-id --rpc-url $(LOCAL_RPC_URL) >/dev/null 2>&1 || ( \
		echo "RPC not reachable at $(LOCAL_RPC_URL). Start Anvil first with: make local-node"; \
		exit 1 \
	)
	forge script $(DEMO_SCRIPT) --rpc-url $(LOCAL_RPC_URL) --private-key $$PRIVATE_KEY_ANVIL --broadcast

local-node:
	anvil --host 127.0.0.1 --port 8545
