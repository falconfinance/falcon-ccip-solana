#!/bin/bash
set -e

# =============================================================================
# Falcon CCIP - Add Solana Devnet E2E Script (TESTNET)
# =============================================================================
#
# Adds Solana Devnet support to an existing Ethereum Sepolia CCIP deployment.
# All operations are BROADCAST (direct execution, no multisig required).
#
# Architecture:
#   Ethereum Sepolia  ←── CCIP (BurnMint) ──→  Solana Devnet
#   ERC20 token + Pool                         SPL Token + Pool
#   (already deployed)                         (deployed by this script)
#
# Prerequisites:
#   1. EVM token & pool deployed on Ethereum Sepolia (via falconCCIP or Hardhat)
#   2. Solana CLI configured: solana config set --url devnet
#   3. Solana keypair funded: solana airdrop 2
#   4. Node.js + yarn installed
#   5. .env file configured (see script/env.example)
#
# Usage:
#   ./script/e2eAddSolanaTestnet.sh           # Run from step 1
#   ./script/e2eAddSolanaTestnet.sh 3         # Resume from step 3
#
# =============================================================================

# ------------- Color & Helper Functions -------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

ask_confirmation() {
    echo ""
    echo "=========================================="
    echo -e "${CYAN}$1${NC}"
    echo "=========================================="
    echo -n "Do you want to continue? (y/n): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi
    echo ""
}

ask_substep_confirmation() {
    echo ""
    echo "------------- Sub-step -------------"
    echo -e "${BLUE}$1${NC}"
    echo "-----------------------------------"
    echo -n "Execute this sub-step? (y/n/s=skip): "
    read -r response
    if [[ "$response" =~ ^[Ss]$ ]]; then
        echo -e "${YELLOW}⏭️  Skipping this sub-step...${NC}"
        return 1
    elif [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi
    return 0
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }

# ------------- Show Steps -------------

show_steps() {
    echo ""
    echo "Available steps (TESTNET - all BROADCAST):"
    echo ""
    echo "1. Create SPL Token on Solana Devnet"
    echo "   1a. Create SPL Token with metadata"
    echo "   1b. Verify token creation"
    echo ""
    echo "2. Initialize CCIP Token Pool on Solana"
    echo "   2a. Initialize BurnMint pool"
    echo "   2b. Create pool token account (ATA)"
    echo "   2c. Propose CCIP administrator"
    echo "   2d. Accept CCIP administrator role"
    echo "   2e. Transfer mint authority to Pool Signer PDA"
    echo "   2f. Verify mint authority transfer"
    echo ""
    echo "3. Cross-Chain Configuration"
    echo "   3a. Configure Solana pool → Ethereum Sepolia"
    echo "   3b. Add Ethereum pool address to Solana config"
    echo "   3c. Configure Ethereum pool → Solana Devnet (EVM Hardhat)"
    echo ""
    echo "4. Pool Registration"
    echo "   4a. Register Ethereum pool in TokenAdminRegistry (EVM Hardhat)"
    echo "   4b. Create Address Lookup Table (Solana)"
    echo "   4c. Register Solana pool in Router TokenAdminRegistry"
    echo ""
    echo "5. Pre-Transfer Setup"
    echo "   5a. Delegate token authority for fee billing"
    echo "   5b. Verify delegation"
    echo ""
    echo "6. Test Cross-Chain Transfers"
    echo "   6a. Transfer: Solana → Ethereum"
    echo "   6b. Transfer: Ethereum → Solana"
    echo ""
    echo "📡 All operations use BROADCAST mode (testnet)."
    echo ""
}

# ------------- Parse Start Step -------------

START_STEP=1
if [ "$1" != "" ]; then
    START_STEP=$1
    echo "Starting from step $START_STEP"
else
    echo "Starting from step 1 (use './script/e2eAddSolanaTestnet.sh <step>' to start from a specific step)"
    show_steps
fi

# ------------- Configuration / .env Loading -------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

if [ -f ".env" ]; then
    set -a
    source .env
    set +a
else
    print_error ".env file not found at $PROJECT_DIR/.env"
    echo "Copy script/env.example to .env and configure it."
    exit 1
fi

# ------------- Validate Required Environment Variables -------------

REQUIRED_VARS=(
    "EVM_RPC_URL"
    "EVM_PRIVATE_KEY"
    "EVM_TOKEN_ADDRESS"
    "EVM_POOL_ADDRESS"
    "CCIP_POOL_PROGRAM"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "Required environment variable $var is not set in .env"
        exit 1
    fi
done

# Testnet defaults
SOLANA_NETWORK=${SOLANA_NETWORK:-"devnet"}
EVM_NETWORK=${EVM_NETWORK:-"sepolia"}
REMOTE_CHAIN_NAME=${REMOTE_CHAIN_NAME:-"ethereum-sepolia"}
TOKEN_DECIMALS=${TOKEN_DECIMALS:-9}
EVM_TOKEN_DECIMALS=${EVM_TOKEN_DECIMALS:-18}
TOKEN_NAME=${TOKEN_NAME:-"Falcon USD"}
TOKEN_SYMBOL=${TOKEN_SYMBOL:-"USDf"}
EVM_HARDHAT_DIR=${EVM_HARDHAT_DIR:-""}

SOL_WALLET=$(solana address 2>/dev/null || echo "UNKNOWN")

# ------------- Display Configuration -------------

echo ""
echo "=========================================="
echo "🦅 Falcon CCIP - Add Solana Devnet (TESTNET)"
echo "=========================================="
echo ""
echo "📋 Configuration:"
echo "  Solana Network:       $SOLANA_NETWORK"
echo "  EVM Network:          $EVM_NETWORK ($REMOTE_CHAIN_NAME)"
echo "  EVM Token:            $EVM_TOKEN_ADDRESS"
echo "  EVM Pool:             $EVM_POOL_ADDRESS"
echo "  CCIP Pool Program:    $CCIP_POOL_PROGRAM"
echo "  Solana Wallet:        $SOL_WALLET"
echo "  Token:                $TOKEN_NAME ($TOKEN_SYMBOL) / $TOKEN_DECIMALS decimals (Solana)"
echo "  EVM Token Decimals:   $EVM_TOKEN_DECIMALS (remote chain config)"
echo ""
echo "📡 Mode: BROADCAST (testnet, no multisig)"
echo ""

# ------------- State file -------------

STATE_FILE="$PROJECT_DIR/script/output/e2e_testnet_state.env"
mkdir -p "$PROJECT_DIR/script/output"

if [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE"
    print_info "Loaded state from $STATE_FILE"
fi

save_state() {
    cat > "$STATE_FILE" << EOF
# Auto-generated by e2eAddSolanaTestnet.sh
# $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EVM_TOKEN_ADDRESS="$EVM_TOKEN_ADDRESS"
EVM_POOL_ADDRESS="$EVM_POOL_ADDRESS"
SOL_TOKEN_MINT="$SOL_TOKEN_MINT"
SOL_POOL_CONFIG_PDA="$SOL_POOL_CONFIG_PDA"
SOL_POOL_SIGNER_PDA="$SOL_POOL_SIGNER_PDA"
SOL_ALT_ADDRESS="$SOL_ALT_ADDRESS"
EOF
    echo "  State saved → $STATE_FILE"
}

# =============================================================================
# STEP 1: Create SPL Token on Solana Devnet
# =============================================================================

if [ $START_STEP -le 1 ]; then
    ask_confirmation "STEP 1: Create SPL Token on Solana Devnet [BROADCAST]
This will:
- Create SPL Token: $TOKEN_NAME ($TOKEN_SYMBOL) / $TOKEN_DECIMALS decimals
- Mint initial supply to your wallet"

    # 1a. Create token
    if ask_substep_confirmation "1a. Create SPL Token '$TOKEN_NAME' ($TOKEN_SYMBOL)"; then
        echo "Creating SPL Token..."

        OUTPUT=$(yarn svm:token:create \
            --name "$TOKEN_NAME" \
            --symbol "$TOKEN_SYMBOL" \
            --decimals "$TOKEN_DECIMALS" 2>&1) || {
            print_error "Failed to create SPL Token"
            echo "$OUTPUT"
            exit 1
        }

        echo "$OUTPUT" | tail -20

        SOL_TOKEN_MINT=$(echo "$OUTPUT" | grep -i "mint" | grep -oE '[A-Za-z0-9]{32,50}' | head -1)

        if [ -z "$SOL_TOKEN_MINT" ]; then
            print_error "Could not extract token mint address"
            echo "Please enter the token mint address manually:"
            read -r SOL_TOKEN_MINT
        fi

        print_success "Token created: $SOL_TOKEN_MINT"
        save_state
    fi

    # 1b. Verify
    if ask_substep_confirmation "1b. Verify token creation"; then
        spl-token display "$SOL_TOKEN_MINT" 2>&1 || true
        echo ""
        spl-token balance "$SOL_TOKEN_MINT" 2>&1 || true
    fi

    print_success "Step 1 completed!"
fi

# =============================================================================
# STEP 2: Initialize CCIP Token Pool on Solana
# =============================================================================

if [ $START_STEP -le 2 ]; then
    ask_confirmation "STEP 2: Initialize CCIP Token Pool [BROADCAST]
This will:
- Initialize BurnMint pool
- Create pool ATA
- Register as CCIP admin (propose + accept)
- Transfer mint authority to Pool Signer PDA (⚠️ irreversible)"

    # 2a. Initialize pool
    if ask_substep_confirmation "2a. Initialize BurnMint pool for $SOL_TOKEN_MINT"; then
        echo "Initializing pool..."

        OUTPUT=$(yarn svm:pool:initialize \
            --token-mint "$SOL_TOKEN_MINT" \
            --burn-mint-pool-program "$CCIP_POOL_PROGRAM" 2>&1) || {
            print_error "Failed to initialize pool"
            echo "$OUTPUT"
            exit 1
        }

        echo "$OUTPUT" | tail -15

        SOL_POOL_CONFIG_PDA=$(echo "$OUTPUT" | grep -i "config" | grep -i "pda" | grep -oE '[A-Za-z0-9]{32,50}' | head -1)
        if [ -z "$SOL_POOL_CONFIG_PDA" ]; then
            SOL_POOL_CONFIG_PDA=$(echo "$OUTPUT" | grep -i "state" | grep -oE '[A-Za-z0-9]{32,50}' | head -1)
        fi

        if [ -z "$SOL_POOL_CONFIG_PDA" ]; then
            echo "Please enter Pool Config PDA manually:"
            read -r SOL_POOL_CONFIG_PDA
        fi

        print_success "Pool initialized. Config PDA: $SOL_POOL_CONFIG_PDA"
        save_state
    fi

    # 2b. Create pool token account
    if ask_substep_confirmation "2b. Create pool token account (ATA)"; then
        echo "Creating pool token account..."

        OUTPUT=$(yarn svm:pool:create-token-account \
            --token-mint "$SOL_TOKEN_MINT" \
            --burn-mint-pool-program "$CCIP_POOL_PROGRAM" 2>&1) || {
            print_error "Failed to create pool token account"
            echo "$OUTPUT"
            exit 1
        }

        echo "$OUTPUT" | tail -10
        print_success "Pool token account created"
        save_state
    fi

    # 2c. Propose administrator
    if ask_substep_confirmation "2c. Propose CCIP administrator"; then
        echo "Proposing administrator..."

        OUTPUT=$(yarn svm:admin:propose-administrator \
            --token-mint "$SOL_TOKEN_MINT" 2>&1) || {
            print_error "Failed to propose administrator"
            echo "$OUTPUT"
            exit 1
        }

        echo "$OUTPUT" | tail -8
        print_success "Administrator proposed"
    fi

    # 2d. Accept admin
    if ask_substep_confirmation "2d. Accept CCIP administrator role"; then
        echo "Accepting administrator role..."

        OUTPUT=$(yarn svm:admin:accept-admin-role \
            --token-mint "$SOL_TOKEN_MINT" 2>&1) || {
            print_error "Failed to accept admin role"
            echo "$OUTPUT"
            exit 1
        }

        echo "$OUTPUT" | tail -8
        print_success "Administrator role accepted"
    fi

    # 2e. Transfer mint authority
    if ask_substep_confirmation "2e. Transfer mint authority to Pool Signer PDA (⚠️ IRREVERSIBLE)"; then
        echo "Fetching Pool Signer PDA..."
        PDA_OUTPUT=$(yarn svm:pool:get-pool-signer \
            --token-mint "$SOL_TOKEN_MINT" \
            --burn-mint-pool-program "$CCIP_POOL_PROGRAM" 2>&1) || true

        echo "$PDA_OUTPUT" | tail -5

        SOL_POOL_SIGNER_PDA=$(echo "$PDA_OUTPUT" | grep -oE '[A-Za-z0-9]{32,50}' | tail -1)

        if [ -z "$SOL_POOL_SIGNER_PDA" ]; then
            echo "Please enter Pool Signer PDA manually:"
            read -r SOL_POOL_SIGNER_PDA
        fi

        echo ""
        print_warning "Transferring mint authority to: $SOL_POOL_SIGNER_PDA"
        echo "  Token: $SOL_TOKEN_MINT"
        echo ""

        spl-token authorize "$SOL_TOKEN_MINT" mint "$SOL_POOL_SIGNER_PDA" 2>&1

        print_success "Mint authority transferred"
        save_state
    fi

    # 2f. Verify
    if ask_substep_confirmation "2f. Verify mint authority transfer"; then
        spl-token display "$SOL_TOKEN_MINT" 2>&1
    fi

    print_success "Step 2 completed!"
fi

# =============================================================================
# STEP 3: Cross-Chain Configuration
# =============================================================================

if [ $START_STEP -le 3 ]; then
    ask_confirmation "STEP 3: Cross-Chain Configuration [BROADCAST]
This will:
- Configure Solana pool → Ethereum Sepolia
- Configure Ethereum pool → Solana Devnet (EVM Hardhat)"

    # 3a. Init remote chain on Solana
    if ask_substep_confirmation "3a. Configure Solana pool → Ethereum Sepolia"; then
        echo "Initializing remote chain config..."

        OUTPUT=$(yarn svm:pool:init-chain-remote-config \
            --token-mint "$SOL_TOKEN_MINT" \
            --burn-mint-pool-program "$CCIP_POOL_PROGRAM" \
            --remote-chain "$REMOTE_CHAIN_NAME" \
            --token-address "$EVM_TOKEN_ADDRESS" \
            --decimals "$EVM_TOKEN_DECIMALS" 2>&1) || true

        echo "$OUTPUT" | tail -10
        print_success "Remote chain config initialized"
    fi

    # 3b. Add pool address
    if ask_substep_confirmation "3b. Add Ethereum pool address to Solana config"; then
        echo "Adding pool address..."

        OUTPUT=$(yarn svm:pool:edit-chain-remote-config \
            --token-mint "$SOL_TOKEN_MINT" \
            --burn-mint-pool-program "$CCIP_POOL_PROGRAM" \
            --remote-chain "$REMOTE_CHAIN_NAME" \
            --pool-addresses "$EVM_POOL_ADDRESS" \
            --token-address "$EVM_TOKEN_ADDRESS" \
            --decimals "$EVM_TOKEN_DECIMALS" 2>&1) || {
            print_error "Failed to edit chain remote config"
            echo "$OUTPUT"
            exit 1
        }

        echo "$OUTPUT" | tail -8
        print_success "Pool address added"
    fi

    # 3c. Configure EVM side
    if ask_substep_confirmation "3c. Configure Ethereum pool → Solana Devnet (EVM Hardhat)
  Pool:         $EVM_POOL_ADDRESS
  Remote Pool:  $SOL_POOL_CONFIG_PDA
  Remote Token: $SOL_TOKEN_MINT"; then

        if [ -z "$EVM_HARDHAT_DIR" ]; then
            echo "Enter path to Hardhat project (smart-contract-examples/ccip/cct/hardhat):"
            read -r EVM_HARDHAT_DIR
        fi

        if [ ! -d "$EVM_HARDHAT_DIR" ]; then
            print_error "Hardhat directory not found: $EVM_HARDHAT_DIR"
            exit 1
        fi

        echo "Applying chain updates on Ethereum Sepolia..."
        (
            cd "$EVM_HARDHAT_DIR"
            npx hardhat applyChainUpdates \
                --pooladdress "$EVM_POOL_ADDRESS" \
                --remotechain solanaDevnet \
                --remotepooladdresses "$SOL_POOL_CONFIG_PDA" \
                --remotetokenaddress "$SOL_TOKEN_MINT" \
                --network "$EVM_NETWORK" 2>&1
        ) || {
            print_error "Failed to apply chain updates on Ethereum"
            exit 1
        }

        print_success "Ethereum pool configured"
    fi

    print_success "Step 3 completed!"
fi

# =============================================================================
# STEP 4: Pool Registration
# =============================================================================

if [ $START_STEP -le 4 ]; then
    ask_confirmation "STEP 4: Pool Registration [BROADCAST]
This will:
- Register Ethereum pool in TokenAdminRegistry
- Create ALT on Solana
- Register Solana pool in Router"

    # 4a. Register EVM pool
    if ask_substep_confirmation "4a. Register Ethereum pool (EVM Hardhat)"; then
        if [ -z "$EVM_HARDHAT_DIR" ]; then
            echo "Enter path to Hardhat project:"
            read -r EVM_HARDHAT_DIR
        fi

        echo "Registering Ethereum pool..."
        (
            cd "$EVM_HARDHAT_DIR"
            npx hardhat setPool \
                --tokenaddress "$EVM_TOKEN_ADDRESS" \
                --pooladdress "$EVM_POOL_ADDRESS" \
                --network "$EVM_NETWORK" 2>&1
        ) || {
            print_error "Failed to register pool"
            exit 1
        }

        print_success "Ethereum pool registered"
    fi

    # 4b. Create ALT
    if ask_substep_confirmation "4b. Create Address Lookup Table (Solana)"; then
        echo "Creating ALT..."

        OUTPUT=$(yarn svm:admin:create-alt \
            --token-mint "$SOL_TOKEN_MINT" \
            --pool-program "$CCIP_POOL_PROGRAM" 2>&1) || {
            print_error "Failed to create ALT"
            echo "$OUTPUT"
            exit 1
        }

        echo "$OUTPUT" | tail -8

        SOL_ALT_ADDRESS=$(echo "$OUTPUT" | grep -oE '[A-Za-z0-9]{32,50}' | tail -1)

        if [ -z "$SOL_ALT_ADDRESS" ]; then
            echo "Please enter ALT address manually:"
            read -r SOL_ALT_ADDRESS
        fi

        print_success "ALT created: $SOL_ALT_ADDRESS"
        save_state
    fi

    # 4c. Register Solana pool
    if ask_substep_confirmation "4c. Register Solana pool in Router"; then
        echo "Registering Solana pool..."

        OUTPUT=$(yarn svm:admin:set-pool \
            --token-mint "$SOL_TOKEN_MINT" \
            --lookup-table "$SOL_ALT_ADDRESS" \
            --writable-indices 3,4,7 2>&1) || {
            print_error "Failed to register pool"
            echo "$OUTPUT"
            exit 1
        }

        echo "$OUTPUT" | tail -8
        print_success "Solana pool registered"
    fi

    print_success "Step 4 completed!"
fi

# =============================================================================
# STEP 5: Pre-Transfer Setup
# =============================================================================

if [ $START_STEP -le 5 ]; then
    ask_confirmation "STEP 5: Pre-Transfer Setup [BROADCAST]
This will:
- Delegate token authority for CCIP fee billing
- Verify delegation"

    # 5a. Delegate
    if ask_substep_confirmation "5a. Delegate token authority"; then
        echo "Delegating..."

        OUTPUT=$(yarn svm:token:delegate \
            --token-mint "$SOL_TOKEN_MINT" 2>&1) || {
            print_error "Failed to delegate"
            echo "$OUTPUT"
            exit 1
        }

        echo "$OUTPUT" | tail -5
        print_success "Delegated"
    fi

    # 5b. Verify
    if ask_substep_confirmation "5b. Verify delegation"; then
        OUTPUT=$(yarn svm:token:check \
            --token-mint "$SOL_TOKEN_MINT" 2>&1) || true
        echo "$OUTPUT" | tail -8
    fi

    print_success "Step 5 completed!"
fi

# =============================================================================
# STEP 6: Test Cross-Chain Transfers
# =============================================================================

if [ $START_STEP -le 6 ]; then
    ask_confirmation "STEP 6: Test Cross-Chain Transfers
- Solana → Ethereum Sepolia
- Ethereum Sepolia → Solana
💡 EVM fee token uses native ETH (not LINK)"

    # Derive ETH wallet
    ETH_WALLET=$(node -e "
        const { ethers } = require('ethers');
        const w = new ethers.Wallet('$EVM_PRIVATE_KEY');
        console.log(w.address);
    " 2>/dev/null || echo "")

    if [ -z "$ETH_WALLET" ]; then
        echo "Enter your Ethereum wallet address:"
        read -r ETH_WALLET
    fi

    # 6a. SOL → ETH
    if ask_substep_confirmation "6a. Transfer Solana → Ethereum
  Amount: 1000000 (1 token)
  Receiver: $ETH_WALLET"; then

        echo "Transferring Solana → Ethereum..."

        OUTPUT=$(yarn svm:token-transfer \
            --token-mint "$SOL_TOKEN_MINT" \
            --token-amount 1000000 \
            --receiver "$ETH_WALLET" 2>&1) || {
            print_error "Transfer failed"
            echo "$OUTPUT"
        }

        echo "$OUTPUT" | tail -15

        MSG_ID=$(echo "$OUTPUT" | grep -i "message id" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
        if [ -n "$MSG_ID" ]; then
            print_info "CCIP Explorer: https://ccip.chain.link/msg/$MSG_ID"
        fi
    fi

    # 6b. ETH → SOL
    if ask_substep_confirmation "6b. Transfer Ethereum → Solana
  Amount: 1000000000000000000 (1 token, 18 decimals)
  Receiver: $SOL_WALLET
  Fee: native ETH"; then

        echo "Transferring Ethereum → Solana..."

        OUTPUT=$(yarn evm:transfer \
            --token "$EVM_TOKEN_ADDRESS" \
            --amount 1000000000000000000 \
            --token-receiver "$SOL_WALLET" \
            --fee-token native 2>&1) || {
            print_error "Transfer failed"
            echo "$OUTPUT"
        }

        echo "$OUTPUT" | tail -15

        MSG_ID=$(echo "$OUTPUT" | grep -i "message id" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
        if [ -n "$MSG_ID" ]; then
            print_info "CCIP Explorer: https://ccip.chain.link/msg/$MSG_ID"
        fi
    fi

    print_success "Step 6 completed!"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=========================================="
echo -e "${GREEN}🎉 Falcon CCIP Testnet - Solana Added!${NC}"
echo "=========================================="
echo ""
echo "📋 Deployment Summary:"
echo "  ┌──────────────────────────────────────────────────"
echo "  │ Ethereum Sepolia"
echo "  │   Token: $EVM_TOKEN_ADDRESS"
echo "  │   Pool:  $EVM_POOL_ADDRESS"
echo "  ├──────────────────────────────────────────────────"
echo "  │ Solana Devnet"
echo "  │   Token:  $SOL_TOKEN_MINT"
echo "  │   Pool:   $SOL_POOL_CONFIG_PDA"
echo "  │   Signer: $SOL_POOL_SIGNER_PDA"
echo "  │   ALT:    $SOL_ALT_ADDRESS"
echo "  └──────────────────────────────────────────────────"
echo ""
echo "📡 All operations used BROADCAST mode (testnet)"
echo ""
echo "📝 Verification:"
echo "  yarn svm:pool:get-info --token-mint $SOL_TOKEN_MINT --burn-mint-pool-program $CCIP_POOL_PROGRAM"
echo "  yarn svm:pool:get-chain-config --token-mint $SOL_TOKEN_MINT --burn-mint-pool-program $CCIP_POOL_PROGRAM --remote-chain $REMOTE_CHAIN_NAME"
echo "  spl-token balance $SOL_TOKEN_MINT"
echo ""
echo "💡 Resume: ./script/e2eAddSolanaTestnet.sh <step>"
echo "📄 State:  $STATE_FILE"
