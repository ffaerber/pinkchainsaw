SHELL := /bin/bash
-include .env
export

# === Config ===
BEE_API_URL    ?= http://localhost:1633
RPC_URL        ?= https://rpc.gnosischain.com
LOCAL_RPC_URL  ?= http://localhost:8545
# Mainnet, used only for the ENS content hash update. Deliberately not named ETH_RPC_URL:
# that name is picked up by forge/cast and by anvil-init.sh as a default endpoint.
MAINNET_RPC_URL ?= https://mainnet.ffaerber.duckdns.org
ENS_NAME       ?= pinkchainsaw.eth
# Keep in sync with fork_block_number in foundry.toml. The tests rely on a postage batch
# that exists at this block, so an unpinned run against latest can fail.
FORK_BLOCK      = 45615500
ENS_REGISTRY    = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e
BZZ_TOKEN       = 0xdBF3Ea6F5beE45c02255B2c26a16F300502F68da
POSTAGE_STAMP   = 0x45a1502382541Cd610CC9068e88727426b696293
BATCH_ID       ?= $(shell curl -s -H "x-api-key: $(BEE_MANAGER_KEY)" $(BEE_API_URL)/stamps 2>/dev/null \
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

# Every test forks Gnosis Chain: foundry.toml pins eth_rpc_url and fork_block_number, and
# the suite reads live BZZ and PostageStamp state. There is no offline test path.
.PHONY: test
test: ## Run all tests (forks Gnosis Chain at the pinned block)
	forge test -vvv

.PHONY: test-fork
test-fork: ## Run all tests against Gnosis Chain at the pinned fork block
	forge test --fork-url $(RPC_URL) --fork-block-number $(FORK_BLOCK) -vvv

.PHONY: test-unit
test-unit: ## Run only the Pinkchainsaw test contract (still forks)
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
# The recipe lines below are @-silenced on purpose: make echoes a command
# before running it, and these carry $(MNEMONIC) on the command line. Without
# the @ the seed phrase is printed to the terminal, into CI logs, and into the
# scrollback of whoever ran it.
#
# FOUNDRY_FORK_BLOCK_NUMBER is set to the live head because foundry.toml pins
# fork_block_number for tests, and a deploy inherits it -- a pruned node then
# refuses with "No state available for block 45615500". A [profile.deploy]
# does not help: profiles inherit from default, so leaving the key out keeps
# the pin.
deploy-contract: build ## Deploy contract (impl + proxy) to Gnosis Chain
	@test -n "$(MNEMONIC)" || { echo "Error: set MNEMONIC in .env"; exit 1; }
	@BZZ_TOKEN=$(BZZ_TOKEN) POSTAGE_STAMP=$(POSTAGE_STAMP) \
	FOUNDRY_FORK_BLOCK_NUMBER=$$(cast block-number --rpc-url $(RPC_URL)) \
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $(RPC_URL) \
		--mnemonics "$(MNEMONIC)" \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url https://gnosis.blockscout.com/api/

.PHONY: deploy-contract-local
deploy-contract-local: build ## Deploy contract (impl + proxy) to local Anvil
	@BZZ_TOKEN=$(BZZ_TOKEN) POSTAGE_STAMP=$(POSTAGE_STAMP) \
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
# BEE_API_URL is a bee-manager façade now, not a bare Bee node: uploads need
# BEE_MANAGER_KEY as x-api-key, and the batch header is ignored -- the key
# identifies the app and the façade stamps with that app's own batch. The
# header is left in place because it costs nothing and a bare node still
# needs it.
deploy-frontend: build-frontend ## Build + upload frontend to Swarm
	@echo "Uploading frontend/dist to Swarm..."
	@REFERENCE=$$(curl -s -X POST \
		"$(BEE_API_URL)/bzz?name=pinkchainsaw" \
		-H "x-api-key: $(BEE_MANAGER_KEY)" \
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
		--rpc-url $(MAINNET_RPC_URL)) && \
	CONTENT_HASH=0x$$(python3 -c "print('e40101fa011b20' + '$(SWARM_HASH)')") && \
	echo "Updating $(ENS_NAME) content hash..." && \
	echo "  Resolver: $$RESOLVER" && \
	echo "  Content:  bzz://$(SWARM_HASH)" && \
	cast send $$RESOLVER \
		"setContenthash(bytes32,bytes)" $$NAMEHASH $$CONTENT_HASH \
		--mnemonic "$(MNEMONIC)" \
		--rpc-url $(MAINNET_RPC_URL) && \
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
