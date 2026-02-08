.PHONY: help build test local-node local-demo sepolia-import sepolia-deploy deploy \
	ui-config ui-pages ui-demo sepolia-policy-set sepolia-policy-set-ens sepolia-policy-read sepolia-hook-config sepolia-demo-sequence sepolia-live-swap

ifneq (,$(wildcard .env))
include .env
export
endif

LOCAL_RPC_URL ?= http://127.0.0.1:8545
ACCOUNT ?= sepolia-deployer
PASSWORD_FILE ?= .password
DEPLOY_SCRIPT := script/DeployUniswapExeGuard.s.sol:DeployUniswapExeGuard
DEMO_SCRIPT := script/DemoFlow.s.sol:DemoFlow
LIVE_SWAP_SCRIPT := script/SepoliaLiveSwapDemo.s.sol:SepoliaLiveSwapDemo

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
	@echo "  make sepolia-policy-set    Set policy for TRADER on POLICY_REGISTRY"
	@echo "  make sepolia-policy-set-ens Set policy for ENS_NAME on POLICY_REGISTRY"
	@echo "  make sepolia-policy-read   Read policy for TRADER from POLICY_REGISTRY"
	@echo "  make sepolia-hook-config   Set defaults on UNISWAP_EXE_GUARD"
	@echo "  make sepolia-demo-sequence Run set/read/config sequence (requires TRADER)"
	@echo "  make sepolia-live-swap     Run real PoolManager live swap demo (init + liquidity + allowed/blocked swap)"
	@echo ""
	@echo "Required .env vars for sepolia-deploy: SEPOLIA_RPC_URL ENS_REGISTRY POOL_MANAGER"
	@echo "Recommended .env vars for demo scripts: POLICY_REGISTRY UNISWAP_EXE_GUARD TRADER ENS_NAME"
	@echo "Password file for sepolia-deploy: $(PASSWORD_FILE)"
	@echo ""
	@echo "UI:"
	@echo "  make ui-config             Generate demo-ui/config.js and docs/config.js from .env values"
	@echo "  make ui-pages              Sync demo-ui/ into docs/ for GitHub Pages"
	@echo "  make ui-demo               Serve demo UI at http://127.0.0.1:4173"

build:
	forge build

test:
	forge test

deploy: ## generic deploy with raw private key (manual usage)
	@if [ -z "$$PRIVATE_KEY" ]; then \
		echo "Missing PRIVATE_KEY for make deploy"; \
		exit 1; \
	fi
	OWNER=$$(cast wallet address --private-key $$PRIVATE_KEY) \
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
	OWNER=$$(cast wallet address --account $(ACCOUNT) --password-file $(PASSWORD_FILE)) \
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

ui-config:
	@mkdir -p demo-ui docs
	@printf '%s\n' \
	'window.DEMO_UI_CONFIG = {' \
	'  POLICY_REGISTRY: "$(POLICY_REGISTRY)",' \
	'  UNISWAP_EXE_GUARD: "$(UNISWAP_EXE_GUARD)",' \
	'  TRADER: "$(TRADER)",' \
	'  ENS_NAME: "$(ENS_NAME)",' \
	'  DEFAULT_MAX_SWAP_ABS: "$(DEFAULT_MAX_SWAP_ABS)",' \
	'  DEFAULT_COOLDOWN_SECONDS: "$(DEFAULT_COOLDOWN_SECONDS)",' \
	'  MAX_SWAP_ABS: "$(MAX_SWAP_ABS)",' \
	'  COOLDOWN_SECONDS: "$(COOLDOWN_SECONDS)",' \
	'  LIVE_SWAP_ROUTER: "$(LIVE_SWAP_ROUTER)",' \
	'  LIVE_TOKEN0: "$(LIVE_TOKEN0)",' \
	'  LIVE_TOKEN1: "$(LIVE_TOKEN1)",' \
	'  LIVE_POOL_FEE: "$(LIVE_POOL_FEE)",' \
	'  LIVE_TICK_SPACING: "$(LIVE_TICK_SPACING)",' \
	'  LIVE_ALLOWED_INPUT: "$(LIVE_ALLOWED_INPUT)",' \
	'  LIVE_BLOCKED_INPUT: "$(LIVE_BLOCKED_INPUT)"' \
	'};' | tee demo-ui/config.js > docs/config.js
	@echo "Wrote demo-ui/config.js and docs/config.js from .env"

ui-pages: ui-config
	@mkdir -p docs
	cp demo-ui/index.html docs/index.html
	cp demo-ui/app.js docs/app.js
	cp demo-ui/styles.css docs/styles.css
	@echo "Synced demo-ui/ -> docs/ for GitHub Pages"

ui-demo: ui-config
	python3 -m http.server 4173 --directory demo-ui

sepolia-policy-set:
	./demo/sepolia-policy-set.sh

sepolia-policy-set-ens:
	./demo/sepolia-policy-set-ens.sh

sepolia-policy-read:
	./demo/sepolia-policy-read.sh

sepolia-hook-config:
	./demo/sepolia-hook-config.sh

sepolia-demo-sequence:
	./demo/sepolia-demo-sequence.sh

sepolia-live-swap:
	@if [ -z "$(SEPOLIA_RPC_URL)" ]; then \
		echo "Missing SEPOLIA_RPC_URL in .env"; \
		exit 1; \
	fi
	@if [ -z "$$POOL_MANAGER" ] || [ -z "$$POLICY_REGISTRY" ] || [ -z "$$UNISWAP_EXE_GUARD" ]; then \
		echo "Missing required env vars: POOL_MANAGER POLICY_REGISTRY UNISWAP_EXE_GUARD"; \
		exit 1; \
	fi
	@if [ ! -f "$(PASSWORD_FILE)" ]; then \
		echo "Missing password file: $(PASSWORD_FILE)"; \
		exit 1; \
	fi
	OWNER=$$(cast wallet address --account $(ACCOUNT) --password-file $(PASSWORD_FILE)) \
	forge script $(LIVE_SWAP_SCRIPT) --rpc-url $(SEPOLIA_RPC_URL) --account $(ACCOUNT) --password-file $(PASSWORD_FILE) --broadcast
