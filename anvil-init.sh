#!/bin/sh
set -e

RPC_URL="${ETH_RPC_URL:-http://localhost:8545}"
BZZ_TOKEN="0xdBF3Ea6F5beE45c02255B2c26a16F300502F68da"

# Anvil deterministic wallets
DEPLOYER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
ALICE="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
BOB="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
CAROL="0x90F79bf6EB2c4f870365E785982E1f101E93b906"
DAVE="0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"

# Your project wallet
PROJECT_WALLET="0x798EF0F261BD5C18FA9Ddaa197341074bDedaAD4"

# BZZ whale on Gnosis Chain (Postage Stamp contract)
BZZ_WHALE="0x781c6D1f0eaE6F1Da1F604c6cDCcdB8B76428ba7"

echo "=== Funding wallets with xDAI ==="
for WALLET in $DEPLOYER $ALICE $BOB $CAROL $DAVE $PROJECT_WALLET; do
    cast rpc --rpc-url $RPC_URL anvil_setBalance "$WALLET" 0x8AC7230489E80000
    echo "Funded $WALLET with 10 xDAI"
done

echo "=== Funding wallets with real BZZ via whale impersonation ==="
cast rpc --rpc-url $RPC_URL anvil_impersonateAccount "$BZZ_WHALE"

WHALE_BALANCE=$(cast call --rpc-url $RPC_URL $BZZ_TOKEN "balanceOf(address)(uint256)" $BZZ_WHALE)
echo "BZZ Whale balance: $WHALE_BALANCE"

# Transfer 1 BZZ (16 decimals) to each wallet
BZZ_AMOUNT="10000000000000000"
for WALLET in $DEPLOYER $ALICE $BOB $CAROL $DAVE $PROJECT_WALLET; do
    cast send --rpc-url $RPC_URL --from $BZZ_WHALE $BZZ_TOKEN \
        "transfer(address,uint256)" $WALLET $BZZ_AMOUNT \
        --unlocked
    echo "Sent 1 BZZ to $WALLET"
done

cast rpc --rpc-url $RPC_URL anvil_stopImpersonatingAccount "$BZZ_WHALE"

echo "=== Deploying Pinkchainsaw contract ==="
DEPLOYED=$(forge create --rpc-url $RPC_URL \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    src/Pinkchainsaw.sol:Pinkchainsaw \
    --constructor-args $BZZ_TOKEN)

CONTRACT_ADDRESS=$(echo "$DEPLOYED" | grep "Deployed to:" | awk '{print $3}')
echo "Pinkchainsaw deployed at: $CONTRACT_ADDRESS"

echo "$CONTRACT_ADDRESS" > contract-address.txt

echo "=== Approving BZZ for all wallets ==="
MAX_UINT256="115792089237316195423570985008687907853269984665640564039457584007913129639935"

KEYS="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"

for KEY in $KEYS; do
    cast send --rpc-url $RPC_URL --private-key $KEY $BZZ_TOKEN \
        "approve(address,uint256)" $CONTRACT_ADDRESS $MAX_UINT256
done
echo "All wallets approved BZZ spending"

echo "=== Init complete ==="
echo "Contract: $CONTRACT_ADDRESS"
echo "BZZ Token: $BZZ_TOKEN"
echo "Chain: Gnosis (forked)"
echo ""
echo "Set in frontend/.env:"
echo "  VITE_CONTRACT_ADDRESS=$CONTRACT_ADDRESS"
