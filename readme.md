# Pink Chainsaw

A decentralized imageboard on Gnosis Chain with Ethereum Swarm storage.

Users post images, comment, and vote using xBZZ tokens. A social score system rewards good content with lower fees and penalizes bad content with higher fees. Anonymous users can browse all content via a public Swarm gateway without a wallet.

## Architecture

- **Smart Contract**: Solidity 0.8.20, built with Foundry
- **Frontend**: React 19 + TypeScript + Vite SPA (hash router for Swarm hosting)
- **Chain**: Gnosis Chain (xDAI for gas, xBZZ for fees)
- **Storage**: Ethereum Swarm (images + comment text)
- **ENS**: [pinkchainsaw.eth](https://app.ens.domains/pinkchainsaw.eth)
- **Wallet**: `0x798EF0F261BD5C18FA9Ddaa197341074bDedaAD4`

## Features

- Browse images and comments without a wallet (read-only via gateway)
- Connect wallet to post, comment, and vote
- Auto chain-switch prompt from mainnet to Gnosis Chain
- Create image threads (uploaded to Swarm, referenced on-chain)
- Nested comments with threaded replies
- Upvote / downvote with xBZZ token fees
- Social score system (higher score = lower fees)
- Lottery: fees split between post owner and random user
- Onboarding checklist modal (xDAI, xBZZ, Bee node, postage stamps)
- Dark UI with dense tile grid and pink accent

## Read vs Write

| Action | Requires wallet | Requires Bee node |
|---|---|---|
| Browse images | No (gateway) | No |
| Read comments | No (gateway) | No |
| Upload images | Yes + xBZZ | Yes + postage stamp |
| Post comments | Yes + xBZZ | Yes + postage stamp |
| Vote | Yes + xBZZ | No |

If a local Bee node is running, reads also go through it (faster). Otherwise the public gateway (`gateway.ethswarm.org`) is used.

## Contracts

| Contract | Description |
|---|---|
| `Pinkchainsaw.sol` | Main imageboard contract |
| `AddrArrayLib.sol` | Address array utility library |

**BZZ Token (xBZZ)**: `0xdBF3Ea6F5beE45c02255B2c26a16F300502F68da`

## Prerequisites

- [Foundry](https://getfoundry.sh/) (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- Node.js 20+
- [Swarm Desktop](https://www.ethswarm.org/build/desktop) (for uploading images/comments)
- MetaMask or injected wallet

## Quick Start

```bash
# Install all dependencies
make install

# Run unit tests
make test

# Run all tests against Gnosis Chain fork
make test-fork
```

### Local Development

```bash
# Terminal 1: start Anvil fork of Gnosis Chain
make anvil

# Terminal 2: fund wallets + deploy contract
make anvil-init

# Terminal 3: start frontend dev server
make dev
```

After `make anvil-init`, copy the contract address from `contract-address.txt` into `frontend/.env`:

```
VITE_CONTRACT_ADDRESS=0x...
VITE_RPC_URL=http://localhost:8545
VITE_BEE_GATEWAY_URL=https://gateway.ethswarm.org
VITE_BEE_API_URL=http://localhost:1633
```

## Deploy

### Contract

```bash
make deploy-contract        # Deploy to Gnosis Chain (prompts for key)
make verify-contract CONTRACT=0x...  # Verify on Blockscout
```

### Frontend

```bash
make deploy-frontend        # Build + upload to Swarm
```

Prints the Swarm hash. Update the content hash on [pinkchainsaw.eth](https://app.ens.domains/pinkchainsaw.eth) to `bzz://<hash>`.

After ENS update, the app is live at:
- `https://pinkchainsaw.eth.bzz.link`
- `https://pinkchainsaw.eth.limo`

### Full Deploy

```bash
make deploy-all             # Contract + frontend
```

## All Make Commands

```
make help                   # Show all commands

# Setup
make install                # Install contracts + frontend deps

# Development
make anvil                  # Start local Anvil fork of Gnosis Chain
make anvil-init             # Fund wallets + deploy contract to local Anvil
make dev                    # Start frontend dev server

# Testing
make test                   # Run unit tests
make test-fork              # Run all tests against Gnosis Chain fork
make test-unit              # Run only unit tests (no fork)
make test-gas               # Run tests with gas report
make coverage               # Run test coverage

# Build
make build                  # Build contracts
make build-frontend         # Build frontend for production
make build-all              # Build contracts + frontend
make abi                    # Extract ABI to frontend
make typecheck              # Type-check frontend

# Deploy
make deploy-contract        # Deploy contract to Gnosis Chain
make deploy-contract-local  # Deploy contract to local Anvil
make deploy-frontend        # Build + upload frontend to Swarm
make deploy-all             # Contract + frontend to production
make verify-contract        # Verify on Blockscout (CONTRACT=0x...)

# Utilities
make clean                  # Remove build artifacts
make fmt                    # Format Solidity code
make snapshot               # Create gas snapshot
```

## Project Structure

```
pinkchainsaw/
├── src/
│   ├── Pinkchainsaw.sol          # Main contract
│   └── AddrArrayLib.sol          # Address array library
├── test/
│   ├── Pinkchainsaw.t.sol        # Unit + fork tests (16 tests)
│   └── MockBZZ.sol               # Mock ERC20 for unit tests
├── frontend/
│   ├── src/
│   │   ├── components/           # Nav, ThreadList, ThreadTile, ThreadDetails,
│   │   │                         # CommentItem, Modal, ChainGuard
│   │   ├── hooks/                # useBee, BeeContext
│   │   ├── config/               # wagmi, contract addresses + ABIs
│   │   └── abi/                  # Contract ABI (from forge build)
│   └── index.html
├── anvil-init.sh                 # Fund wallets + deploy to local fork
├── Makefile                      # Dev, test, build, deploy commands
└── foundry.toml                  # Foundry config
```

## Bug Fixes (from Imageboard prototype)

1. **getMultiplier fallback** — scores below -2 now return multiplier 5 (was returning 0 = free posts)
2. **Pagination off-by-one** — `>=` boundary check prevents empty array allocation
3. **Fee rounding** — `otherHalf = fee - halfFee` ensures no wei is lost
4. **Self-voting blocked** — users cannot vote on their own posts
5. **Duplicate thread prevention** — same user + same hash cannot overwrite existing thread
6. **Weak randomness** — acknowledged, acceptable for small-fee Gnosis Chain use case

## Tech Stack

| Layer | Technology |
|---|---|
| Smart Contracts | Solidity 0.8.20, Foundry |
| Frontend | React 19, TypeScript, Vite, Tailwind CSS 4 |
| Web3 | wagmi v2, viem |
| Swarm SDK | @ethersphere/bee-js v11 |
| Routing | React Router 7 (hash router) |
| Chain | Gnosis Chain (ID: 100) |
| Storage | Ethereum Swarm |
| Hosting | Swarm + ENS |
