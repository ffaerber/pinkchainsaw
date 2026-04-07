SHELL := /bin/bash
-include .env
export

# === Config ===
BEE_API_URL    ?= http://localhost:1633
RPC_URL        ?= https://rpc.gnosischain.com
LOCAL_RPC_URL  ?= http://localhost:8545
ETH_RPC_URL    ?= https://mainnet.ffaerber.duckdns.org
ENS_NAME       ?= pinkchainsaw.eth
ENS_REGISTRY    = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e
BZZ_TOKEN       = 0xdBF3Ea6F5beE45c02255B2c26a16F300502F68da
POSTAGE_STAMP   = 0x45a1502382541Cd610CC9068e88727426b696293
BATCH_ID       ?= $(shell curl -s $(BEE_API_URL)/stamps 2>/dev/null \
                   | python3 -c "import sys,json; s=json.load(sys.stdin).get('stamps',[]); print(s[0]['batchID'] if s else '')" 2>/dev/null)

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ============================================================
#  Setup
# ============================================================

.PHONY: install
install: ## Install all dependencies (contracts + frontend)
	forge install
	cd frontend && npm install

# ============================================================
#  Development
# ============================================================

.PHONY: anvil
anvil: ## Start local Anvil fork of Gnosis Chain
	anvil --fork-url $(RPC_URL) --chain-id 100 --port 8545

.PHONY: anvil-init
anvil-init: ## Fund wallets + deploy contract to local Anvil
	sh anvil-init.sh

.PHONY: dev
dev: ## Start frontend dev server
	cd frontend && npm run dev

.PHONY: dev-all
dev-all: ## Start Anvil, init, and frontend (run in separate terminals)
	@echo "Run these in 3 terminals:"
	@echo "  make anvil"
	@echo "  make anvil-init"
	@echo "  make dev"

# ============================================================
#  Testing
# ============================================================

.PHONY: test
test: ## Run unit tests
	forge test -vvv

.PHONY: test-fork
test-fork: ## Run all tests against Gnosis Chain fork
	forge test --fork-url $(RPC_URL) -vvv

.PHONY: test-unit
test-unit: ## Run only unit tests (no fork)
	forge test --match-contract PinkchainsawTest -vvv

.PHONY: test-gas
test-gas: ## Run tests with gas report
	forge test --gas-report

.PHONY: coverage
coverage: ## Run test coverage
	forge coverage

# ============================================================
#  Build
# ============================================================

.PHONY: build
build: ## Build contracts
	forge build

.PHONY: build-frontend
build-frontend: ## Build frontend for production
	cd frontend && npm run build

.PHONY: build-all
build-all: build build-frontend ## Build contracts + frontend

.PHONY: abi
abi: build ## Extract ABI to frontend
	python3 -c "import json; d=json.load(open('out/Pinkchainsaw.sol/Pinkchainsaw.json')); json.dump(d['abi'], open('frontend/src/abi/Pinkchainsaw.json','w'), indent=2)"
	@echo "ABI written to frontend/src/abi/Pinkchainsaw.json"

.PHONY: typecheck
typecheck: ## Type-check frontend
	cd frontend && npx tsc --noEmit

# ============================================================
#  Deploy: Contract
# ============================================================

.PHONY: deploy-contract
deploy-contract: build ## Deploy contract (impl + proxy) to Gnosis Chain
	@test -n "$(MNEMONIC)" || { echo "Error: set MNEMONIC in .env"; exit 1; }
	BZZ_TOKEN=$(BZZ_TOKEN) POSTAGE_STAMP=$(POSTAGE_STAMP) \
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $(RPC_URL) \
		--mnemonics "$(MNEMONIC)" \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://gnosis.blockscout.com/api/

.PHONY: deploy-contract-local
deploy-contract-local: build ## Deploy contract (impl + proxy) to local Anvil
	BZZ_TOKEN=$(BZZ_TOKEN) POSTAGE_STAMP=$(POSTAGE_STAMP) \
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $(LOCAL_RPC_URL) \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast

.PHONY: verify-contract
verify-contract: ## Verify existing contract on Blockscout (CONTRACT=0x...)
	forge verify-contract $(CONTRACT) src/Pinkchainsaw.sol:Pinkchainsaw \
		--rpc-url $(RPC_URL) \
		--verifier blockscout \
		--verifier-url https://gnosis.blockscout.com/api/

# ============================================================
#  Deploy: Frontend to Swarm
# ============================================================

.PHONY: deploy-frontend
deploy-frontend: build-frontend ## Build + upload frontend to Swarm
	@echo "Uploading frontend/dist to Swarm..."
	@REFERENCE=$$(curl -s -X POST \
		"$(BEE_API_URL)/bzz?name=pinkchainsaw" \
		-H "Swarm-Postage-Batch-Id: $(BATCH_ID)" \
		-H "Swarm-Collection: true" \
		-H "Swarm-Index-Document: index.html" \
		-H "Swarm-Error-Document: index.html" \
		-H "Content-Type: application/x-tar" \
		--data-binary @<(cd frontend/dist && tar cf - .) \
		| python3 -c "import sys,json; print(json.load(sys.stdin)['reference'])") && \
	echo "" && \
	echo "Swarm hash: $$REFERENCE" && \
	echo "Preview:    $(BEE_API_URL)/bzz/$$REFERENCE/" && \
	$(MAKE) update-ens SWARM_HASH=$$REFERENCE

.PHONY: update-ens
update-ens: ## Update ENS content hash on mainnet (SWARM_HASH=...)
	@test -n "$(SWARM_HASH)" || { echo "Error: set SWARM_HASH=<hash>"; exit 1; }
	@test -n "$(MNEMONIC)" || { echo "Error: set MNEMONIC in .env"; exit 1; }
	@NAMEHASH=$$(cast namehash $(ENS_NAME)) && \
	RESOLVER=$$(cast call $(ENS_REGISTRY) \
		"resolver(bytes32)(address)" $$NAMEHASH \
		--rpc-url $(ETH_RPC_URL)) && \
	CONTENT_HASH=0x$$(python3 -c "print('e40101fa011b20' + '$(SWARM_HASH)')") && \
	echo "Updating $(ENS_NAME) content hash..." && \
	echo "  Resolver: $$RESOLVER" && \
	echo "  Content:  bzz://$(SWARM_HASH)" && \
	cast send $$RESOLVER \
		"setContenthash(bytes32,bytes)" $$NAMEHASH $$CONTENT_HASH \
		--mnemonic "$(MNEMONIC)" \
		--rpc-url $(ETH_RPC_URL) && \
	echo "" && \
	echo "ENS updated! Live at:" && \
	echo "  https://$(ENS_NAME).bzz.link" && \
	echo "  https://$(ENS_NAME).limo"

# ============================================================
#  Deploy: Full (contract + frontend)
# ============================================================

.PHONY: deploy-all
deploy-all: deploy-contract deploy-frontend ## Deploy contract + frontend to production

# ============================================================
#  Utilities
# ============================================================

.PHONY: clean
clean: ## Remove build artifacts
	forge clean
	rm -rf frontend/dist frontend/node_modules/.vite

.PHONY: fmt
fmt: ## Format Solidity code
	forge fmt

.PHONY: snapshot
snapshot: ## Create gas snapshot
	forge snapshot
