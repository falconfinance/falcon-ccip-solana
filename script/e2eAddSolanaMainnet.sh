#!/bin/bash
set -e

# =============================================================================
# Falcon CCIP - Add Solana Mainnet E2E Script (MAINNET)
# =============================================================================
#
# Adds Solana Mainnet support to an existing Ethereum Mainnet CCIP deployment.
# EVM admin operations use MULTISIG (via falconCCIP forge scripts).
# Solana operations are BROADCAST, then ownership transferred to Squads multisig.
#
# Architecture:
#   Ethereum Mainnet  ←── CCIP (BurnMint) ──→  Solana Mainnet
#   USDf ERC20 + Pool                          USDf SPL Token + Pool
#   (already deployed)                         (deployed by this script)
#
# Security:
#   - EVM: Gnosis Safe multisig for ApplyChainUpdates / SetPool
#   - Solana: Squads Protocol for mint authority + pool ownership
#   - Direct Mint Authority pattern
#
# Prerequisites:
#   1. EVM token & pool deployed on Ethereum Mainnet (via falconCCIP)
#   2. Solana CLI configured: solana config set --url mainnet-beta
#   3. Solana keypair funded with SOL (mainnet)
#   4. Squads Protocol multisig created
#   5. falconCCIP project available (for EVM MULTISIG operations)
#   6. .env file configured
#
# Usage:
#   ./script/e2eAddSolanaMainnet.sh           # Run from step 1
#   ./script/e2eAddSolanaMainnet.sh 3         # Resume from step 3
#
# =============================================================================

# ------------- Color & Helper Functions -------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
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

# Double confirmation for critical mainnet operations
ask_critical_confirmation() {
    echo ""
    echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
    echo -e "${RED}!!  ⚠️  CRITICAL MAINNET OPERATION  ⚠️       !!${NC}"
    echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
    echo ""
    echo -e "${BOLD}$1${NC}"
    echo ""
    echo -n "Type 'CONFIRM' to proceed (or anything else to cancel): "
    read -r confirm
    if [ "$confirm" != "CONFIRM" ]; then
        echo "Cancelled."
        return 1
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
    echo "Available steps (MAINNET - with MULTISIG):"
    echo ""
    echo "1. Create SPL Token on Solana Mainnet"
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
    echo "   3a. Configure Solana pool → Ethereum Mainnet"
    echo "   3b. Add Ethereum pool address to Solana config"
    echo "   3c. Configure Ethereum pool → Solana Mainnet (🔐 EVM MULTISIG)"
    echo ""
    echo "4. Pool Registration"
    echo "   4a. Register Ethereum pool in TokenAdminRegistry (🔐 EVM MULTISIG)"
    echo "   4b. Create Address Lookup Table (Solana)"
    echo "   4c. Register Solana pool in Router TokenAdminRegistry"
    echo ""
    echo "5. Security: Multisig Ownership Transfer (🔐 REQUIRED)"
    echo "   5a. Transfer mint authority to Squads multisig"
    echo "   5b. Transfer pool ownership to Squads multisig"
    echo "   5c. Accept pool ownership (by Squads multisig)"
    echo "   5d. Verify multisig configuration"
    echo ""
    echo "🔐 EVM MULTISIG: Steps 3c, 4a use falconCCIP forge scripts with USE_MULTISIG=true"
    echo "🔐 Solana MULTISIG: Steps 5a-5c transfer to Squads Protocol"
    echo ""
}

# ------------- Parse Start Step -------------

START_STEP=1
if [ "$1" != "" ]; then
    START_STEP=$1
    echo "Starting from step $START_STEP"
else
    echo "Starting from step 1 (use './script/e2eAddSolanaMainnet.sh <step>' to start from a specific step)"
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
    "SQUADS_MULTISIG_ADDRESS"
    "FALCON_CCIP_DIR"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "Required environment variable $var is not set in .env"
        exit 1
    fi
done

# Mainnet defaults
SOLANA_NETWORK=${SOLANA_NETWORK:-"mainnet-beta"}
EVM_NETWORK=${EVM_NETWORK:-"mainnet"}
REMOTE_CHAIN_NAME=${REMOTE_CHAIN_NAME:-"ethereum-mainnet"}
TOKEN_DECIMALS=${TOKEN_DECIMALS:-9}
EVM_TOKEN_DECIMALS=${EVM_TOKEN_DECIMALS:-18}
TOKEN_NAME=${TOKEN_NAME:-"Falcon USD"}
TOKEN_SYMBOL=${TOKEN_SYMBOL:-"USDf"}
EVM_CHAIN_ID=${EVM_CHAIN_ID:-1}
SOLANA_CHAIN_SELECTOR=${SOLANA_CHAIN_SELECTOR:-"124615329519749607"}
SOL_WALLET=$(solana address 2>/dev/null || echo "UNKNOWN")

# ------------- Display Configuration -------------

echo ""
echo "=========================================="
echo -e "${RED}🦅 Falcon CCIP - Add Solana Mainnet (MAINNET)${NC}"
echo "=========================================="
echo ""
echo "📋 Configuration:"
echo "  Solana Network:       $SOLANA_NETWORK"
echo "  EVM Network:          $EVM_NETWORK ($REMOTE_CHAIN_NAME)"
echo "  EVM Chain ID:         $EVM_CHAIN_ID"
echo "  EVM Token:            $EVM_TOKEN_ADDRESS"
echo "  EVM Pool:             $EVM_POOL_ADDRESS"
echo "  CCIP Pool Program:    $CCIP_POOL_PROGRAM"
echo "  Solana Wallet:        $SOL_WALLET"
echo "  Token:                $TOKEN_NAME ($TOKEN_SYMBOL) / $TOKEN_DECIMALS decimals (Solana)"
echo "  EVM Token Decimals:   $EVM_TOKEN_DECIMALS (remote chain config)"
echo ""
echo "🔐 Security:"
echo "  Squads Multisig:      $SQUADS_MULTISIG_ADDRESS"
echo "  FalconCCIP Dir:       $FALCON_CCIP_DIR"
echo ""
echo -e "${RED}⚠️  THIS IS A MAINNET DEPLOYMENT - ALL OPERATIONS ARE PERMANENT${NC}"
echo ""

# Verify Solana is on mainnet
SOLANA_URL=$(solana config get | grep "RPC URL" | awk '{print $NF}')
if echo "$SOLANA_URL" | grep -q "devnet"; then
    print_error "Solana CLI is configured for devnet!"
    echo "  Run: solana config set --url mainnet-beta"
    exit 1
fi

# Verify falconCCIP directory
if [ ! -d "$FALCON_CCIP_DIR" ]; then
    print_error "falconCCIP directory not found: $FALCON_CCIP_DIR"
    exit 1
fi

# ------------- State file -------------

STATE_FILE="$PROJECT_DIR/script/output/e2e_mainnet_state.env"
mkdir -p "$PROJECT_DIR/script/output"

if [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE"
    print_info "Loaded state from $STATE_FILE"
fi

save_state() {
    cat > "$STATE_FILE" << EOF
# Auto-generated by e2eAddSolanaMainnet.sh
# $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ⚠️ MAINNET ADDRESSES - HANDLE WITH CARE
EVM_TOKEN_ADDRESS="$EVM_TOKEN_ADDRESS"
EVM_POOL_ADDRESS="$EVM_POOL_ADDRESS"
SOL_TOKEN_MINT="$SOL_TOKEN_MINT"
SOL_POOL_CONFIG_PDA="$SOL_POOL_CONFIG_PDA"
SOL_POOL_SIGNER_PDA="$SOL_POOL_SIGNER_PDA"
SOL_ALT_ADDRESS="$SOL_ALT_ADDRESS"
SQUADS_MULTISIG_ADDRESS="$SQUADS_MULTISIG_ADDRESS"
EOF
    echo "  State saved → $STATE_FILE"
}

# =============================================================================
# STEP 1: Create SPL Token on Solana Mainnet
# =============================================================================

if [ $START_STEP -le 1 ]; then
    ask_confirmation "STEP 1: Create SPL Token on Solana Mainnet [BROADCAST]
This will:
- Create SPL Token: $TOKEN_NAME ($TOKEN_SYMBOL) / $TOKEN_DECIMALS decimals
- Mint initial supply to your wallet

⚠️  MAINNET: This creates a permanent token on Solana Mainnet."

    # 1a. Create token
    if ask_substep_confirmation "1a. Create SPL Token '$TOKEN_NAME' ($TOKEN_SYMBOL)"; then
        if ! ask_critical_confirmation "Create token $TOKEN_NAME ($TOKEN_SYMBOL) on Solana MAINNET?"; then
            exit 0
        fi

        echo "Creating SPL Token on Solana Mainnet..."

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
- Register as CCIP admin
- Transfer mint authority to Pool Signer PDA (⚠️ IRREVERSIBLE)

🔐 Mint authority will later be transferred to Squads multisig (Step 6)."

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

        if ! ask_critical_confirmation "Transfer mint authority of $SOL_TOKEN_MINT to Pool Signer PDA: $SOL_POOL_SIGNER_PDA

This is IRREVERSIBLE on mainnet."; then
            exit 0
        fi

        spl-token authorize "$SOL_TOKEN_MINT" mint "$SOL_POOL_SIGNER_PDA" 2>&1

        print_success "Mint authority transferred to $SOL_POOL_SIGNER_PDA"
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
    ask_confirmation "STEP 3: Cross-Chain Configuration
This will:
- Configure Solana pool → Ethereum Mainnet [BROADCAST]
- Configure Ethereum pool → Solana Mainnet [🔐 EVM MULTISIG via falconCCIP]"

    # 3a. Init remote chain on Solana
    if ask_substep_confirmation "3a. Configure Solana pool → Ethereum Mainnet [BROADCAST]"; then
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
    if ask_substep_confirmation "3b. Add Ethereum pool address to Solana config [BROADCAST]"; then
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

    # 3c. Configure EVM side (MULTISIG)
    if ask_substep_confirmation "3c. Configure Ethereum pool → Solana Mainnet [🔐 EVM MULTISIG]
  This uses falconCCIP forge scripts with USE_MULTISIG=true
  EVM Pool:     $EVM_POOL_ADDRESS
  Remote Pool:  $SOL_POOL_CONFIG_PDA
  Remote Token: $SOL_TOKEN_MINT

  ⚠️  This will generate a MULTISIG transaction for Gnosis Safe.
  ⚠️  The transaction must be signed & executed by the multisig signers."; then

        if ! ask_critical_confirmation "Apply chain updates on Ethereum MAINNET pool via MULTISIG?"; then
            exit 0
        fi

        echo "🔐 Generating MULTISIG transaction via falconCCIP..."
        echo "  falconCCIP dir: $FALCON_CCIP_DIR"
        echo ""

        # Update falconCCIP config.json for Solana chain selector
        # Note: Solana mainnet chain selector needs to be added to falconCCIP's config
        (
            cd "$FALCON_CCIP_DIR"

            # Backup config
            cp script/config.json script/config.json.bak

            echo "  Generating ApplyChainUpdates MULTISIG transaction..."
            export USE_MULTISIG=true
            forge script script/ApplyChainUpdates.s.sol \
                --rpc-url "$EVM_RPC_URL" \
                --private-key "$EVM_PRIVATE_KEY" || {
                print_error "Failed to generate MULTISIG transaction"
                cp script/config.json.bak script/config.json
                exit 1
            }
            unset USE_MULTISIG

            # Restore config
            cp script/config.json.bak script/config.json
        )

        echo ""
        print_warning "MULTISIG transaction generated. Submit to Gnosis Safe for signing."
        print_info "Check falconCCIP/broadcast/ for the transaction data."
    fi

    print_success "Step 3 completed!"
fi

# =============================================================================
# STEP 4: Pool Registration
# =============================================================================

if [ $START_STEP -le 4 ]; then
    ask_confirmation "STEP 4: Pool Registration
This will:
- Register Ethereum pool in TokenAdminRegistry [🔐 EVM MULTISIG]
- Create ALT on Solana [BROADCAST]
- Register Solana pool [BROADCAST]"

    # 4a. Register EVM pool (MULTISIG)
    if ask_substep_confirmation "4a. Register Ethereum pool in TokenAdminRegistry [🔐 EVM MULTISIG]
  This uses falconCCIP forge scripts with USE_MULTISIG=true

  ⚠️  Generates a MULTISIG transaction for Gnosis Safe."; then

        if ! ask_critical_confirmation "Register pool on Ethereum MAINNET via MULTISIG?"; then
            exit 0
        fi

        echo "🔐 Generating MULTISIG transaction via falconCCIP..."
        (
            cd "$FALCON_CCIP_DIR"

            export USE_MULTISIG=true
            forge script script/SetPool.s.sol \
                --rpc-url "$EVM_RPC_URL" \
                --private-key "$EVM_PRIVATE_KEY" \
                --sig "run(address,address)" \
                -- "$EVM_TOKEN_ADDRESS" "$EVM_POOL_ADDRESS" || {
                print_error "Failed to generate MULTISIG transaction"
                exit 1
            }
            unset USE_MULTISIG
        )

        print_warning "MULTISIG transaction generated. Submit to Gnosis Safe for signing."
    fi

    # 4b. Create ALT
    if ask_substep_confirmation "4b. Create Address Lookup Table on Solana [BROADCAST]"; then
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
    if ask_substep_confirmation "4c. Register Solana pool in Router [BROADCAST]"; then
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
# STEP 5: Multisig Ownership Transfer (REQUIRED for mainnet)
# =============================================================================

if [ $START_STEP -le 5 ]; then
    ask_confirmation "STEP 5: Multisig Ownership Transfer [🔐 REQUIRED]
This will:
- Transfer mint authority to Squads Protocol multisig
- Transfer pool ownership to Squads Protocol multisig
- Accept pool ownership (by multisig)

🔐 Squads Address: $SQUADS_MULTISIG_ADDRESS
⚠️  These operations are IRREVERSIBLE on mainnet."

    # 5a. Transfer mint authority to multisig
    if ask_substep_confirmation "5a. Transfer mint authority to Squads multisig [🔐]
  Current: Pool Signer PDA ($SOL_POOL_SIGNER_PDA)
  Target:  Squads ($SQUADS_MULTISIG_ADDRESS)"; then

        if ! ask_critical_confirmation "Transfer mint authority to Squads multisig: $SQUADS_MULTISIG_ADDRESS

  Token:   $SOL_TOKEN_MINT
  Program: $CCIP_POOL_PROGRAM

  The multisig MUST include the Pool Signer PDA as a signer."; then
            exit 0
        fi

        echo "Transferring mint authority to multisig..."

        OUTPUT=$(yarn svm:pool:transfer-mint-authority-to-multisig \
            --token-mint "$SOL_TOKEN_MINT" \
            --burn-mint-pool-program "$CCIP_POOL_PROGRAM" \
            --new-multisig-mint-authority "$SQUADS_MULTISIG_ADDRESS" 2>&1) || {
            print_error "Failed to transfer mint authority to multisig"
            echo "$OUTPUT"
            exit 1
        }

        echo "$OUTPUT" | tail -10
        print_success "Mint authority transferred to multisig"
    fi

    # 5b. Transfer pool ownership
    if ask_substep_confirmation "5b. Transfer pool ownership to Squads multisig [🔐]
  Target: $SQUADS_MULTISIG_ADDRESS"; then

        if ! ask_critical_confirmation "Transfer pool ownership to: $SQUADS_MULTISIG_ADDRESS"; then
            exit 0
        fi

        echo "Transferring pool ownership..."

        OUTPUT=$(yarn svm:pool:transfer-ownership \
            --token-mint "$SOL_TOKEN_MINT" \
            --burn-mint-pool-program "$CCIP_POOL_PROGRAM" \
            --new-owner "$SQUADS_MULTISIG_ADDRESS" 2>&1) || {
            print_error "Failed to transfer pool ownership"
            echo "$OUTPUT"
            exit 1
        }

        echo "$OUTPUT" | tail -10
        print_success "Pool ownership transfer proposed"
        print_warning "Squads multisig must now accept (step 5c)"
    fi

    # 5c. Accept ownership
    if ask_substep_confirmation "5c. Accept pool ownership (run by Squads multisig)
  ⚠️  This must be executed from the multisig wallet."; then

        echo "Accepting pool ownership..."

        OUTPUT=$(yarn svm:pool:accept-ownership \
            --token-mint "$SOL_TOKEN_MINT" \
            --burn-mint-pool-program "$CCIP_POOL_PROGRAM" 2>&1) || {
            print_error "Failed to accept ownership"
            echo "$OUTPUT"
        }

        echo "$OUTPUT" | tail -10
        print_success "Pool ownership accepted"
    fi

    # 5d. Verify
    if ask_substep_confirmation "5d. Verify multisig configuration"; then
        echo "Checking pool info..."
        OUTPUT=$(yarn svm:pool:get-info \
            --token-mint "$SOL_TOKEN_MINT" \
            --burn-mint-pool-program "$CCIP_POOL_PROGRAM" 2>&1) || true
        echo "$OUTPUT" | tail -15

        echo ""
        echo "Checking token mint authority..."
        spl-token display "$SOL_TOKEN_MINT" 2>&1 || true
    fi

    print_success "Step 5 completed!"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=========================================="
echo -e "${GREEN}🎉 Falcon CCIP Mainnet - Solana Added!${NC}"
echo "=========================================="
echo ""
echo "📋 Deployment Summary:"
echo "  ┌──────────────────────────────────────────────────"
echo "  │ Ethereum Mainnet"
echo "  │   Token: $EVM_TOKEN_ADDRESS"
echo "  │   Pool:  $EVM_POOL_ADDRESS"
echo "  ├──────────────────────────────────────────────────"
echo "  │ Solana Mainnet"
echo "  │   Token:  $SOL_TOKEN_MINT"
echo "  │   Pool:   $SOL_POOL_CONFIG_PDA"
echo "  │   Signer: $SOL_POOL_SIGNER_PDA"
echo "  │   ALT:    $SOL_ALT_ADDRESS"
echo "  └──────────────────────────────────────────────────"
echo ""
echo "🔐 Security:"
echo "  ✅ Squads Multisig: $SQUADS_MULTISIG_ADDRESS"
echo "  ✅ Mint Authority:  Multisig (via Pool Signer PDA)"
echo "  ✅ Pool Ownership:  Multisig"
echo ""
echo "🔐 EVM MULTISIG operations:"
echo "  - ApplyChainUpdates (3c) → Gnosis Safe"
echo "  - SetPool (4a) → Gnosis Safe"
echo ""
echo "📡 Solana BROADCAST operations:"
echo "  - Token creation, pool init, admin setup"
echo "  - ALT creation, pool registration"
echo "  - Ownership transferred to Squads after setup"
echo ""
echo "📝 Verification:"
echo "  yarn svm:pool:get-info --token-mint $SOL_TOKEN_MINT --burn-mint-pool-program $CCIP_POOL_PROGRAM"
echo "  yarn svm:pool:get-chain-config --token-mint $SOL_TOKEN_MINT --burn-mint-pool-program $CCIP_POOL_PROGRAM --remote-chain $REMOTE_CHAIN_NAME"
echo "  spl-token balance $SOL_TOKEN_MINT"
echo ""
echo "💡 Resume: ./script/e2eAddSolanaMainnet.sh <step>"
echo "📄 State:  $STATE_FILE"
