# USDf Bridge Testing Guide (Testnet)

**Networks:** Ethereum Sepolia ↔ Solana Devnet  
**Token:** USDf (Falcon USD)  
**Protocol:** Chainlink CCIP (BurnMint)

---

## Contract Addresses

### Ethereum Sepolia

| Component | Address |
|-----------|---------|
| USDf Token (ERC20) | `0x3e34bfc2872534c331b6db2e4b3593fa7eaeddfd` |
| CCIP Token Pool | `0x215Db3842Aba71B3Ef257841C7195b244Fa506AE` |
| CCIP Router | `0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59` |
| Chain Selector | `16015286601757825753` |
| Decimals | **18** |

### Solana Devnet

| Component | Address |
|-----------|---------|
| USDf Token Mint (SPL) | `CxFvc8BXoq7TwPYiBBvN7yvTXVYRGhKgsfmZC4RNpWc1` |
| CCIP Pool Config PDA | `94CzGygp7v7VV691fuM8bFLoicW9Hrnf8TxqFrZETijf` |
| Pool Signer PDA (Mint Authority) | `5UmpEE9WsnpFTktu2bfLaPn1Jz6XgaNyj2WFxrHXwudL` |
| CCIP Router Program | `Ccip842gzYHhvdDkSyi2YVCoAWPbYJoApMFzSxQroE9C` |
| CCIP BurnMint Pool Program | `41FGToCmdaWa1dgZLKFAjvmx6e6AjVTX7SVRibvsMGVB` |
| Fee Quoter Program | `FeeQPGkKDeRV1MgoYfMH6L8o3KeuYjwUZrgn4LRKfjHi` |
| Address Lookup Table | `F7v7MoCvuwexXtV1LUkEdyyCXk7GLvy3zqcBeNGtAphz` |
| Chain Selector | `16423721717087811551` |
| Decimals | **9** |

---

## Decimal Conversion

| Direction | Send Amount (Raw) | Receive Amount (Raw) | Human Readable |
|-----------|-------------------|----------------------|----------------|
| ETH → SOL | `1000000000000000000` (18 dp) | `1000000000` (9 dp) | 1 USDf |
| SOL → ETH | `1000000000` (9 dp) | `1000000000000000000` (18 dp) | 1 USDf |
| ETH → SOL | `100000000000000000` (18 dp) | `100000000` (9 dp) | 0.1 USDf |
| SOL → ETH | `1000000` (9 dp) | `1000000000000000` (18 dp) | 0.001 USDf |

**Important:** CCIP automatically handles the 18↔9 decimal conversion. Frontend only needs to submit amounts in the source chain's decimals.

---

## Testing: Ethereum → Solana

### Prerequisites
- EVM wallet with Sepolia ETH (for gas + CCIP fee)
- EVM wallet holds USDf tokens on Sepolia
- Receiver has a Solana wallet address (no need to pre-create ATA — CCIP handles it)

### Using CLI Script

```bash
cd falcon-ccip-solana

# Bridge 1 USDf from Sepolia to Solana
yarn evm:transfer \
  --token 0x3e34bfc2872534c331b6db2e4b3593fa7eaeddfd \
  --amount 1000000000000000000 \
  --token-receiver <SOLANA_WALLET_ADDRESS> \
  --fee-token native

# Bridge 0.1 USDf
yarn evm:transfer \
  --token 0x3e34bfc2872534c331b6db2e4b3593fa7eaeddfd \
  --amount 100000000000000000 \
  --token-receiver <SOLANA_WALLET_ADDRESS> \
  --fee-token native
```

### Using Helper Script

```bash
# Bridge 1 USDf (default)
./script/bridgeTest.sh eth2sol <SOLANA_WALLET_ADDRESS>

# Bridge custom amount (raw 18dp)
./script/bridgeTest.sh eth2sol <SOLANA_WALLET_ADDRESS> 500000000000000000
```

### Direct Contract Interaction (for frontend integration)

1. **Approve** USDf to CCIP Router:
   ```
   Token:   0x3e34bfc2872534c331b6db2e4b3593fa7eaeddfd
   Spender: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59 (CCIP Router)
   Amount:  <transfer amount in 18dp>
   ```

2. **Call** `ccipSend` on CCIP Router (`0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59`):
   ```
   destinationChainSelector: 16423721717087811551  (Solana Devnet)
   message:
     receiver: <Solana wallet address, left-padded to 32 bytes>
     data: 0x
     tokenAmounts: [{ token: 0x3e34bf..., amount: <raw 18dp> }]
     feeToken: address(0)   // native ETH
     extraArgs: 0x181dcf100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
   value: <CCIP fee in ETH>  // query getFee() first
   ```

3. **Get Fee** estimate:
   ```bash
   yarn evm:check-fee \
     --token 0x3e34bfc2872534c331b6db2e4b3593fa7eaeddfd \
     --amount 1000000000000000000 \
     --token-receiver <SOLANA_WALLET_ADDRESS>
   ```

---

## Testing: Solana → Ethereum

### Prerequisites
- Solana wallet with SOL (for tx fee + CCIP fee, ~0.01 SOL)
- Solana wallet holds USDf tokens on Devnet
- **Token delegation** must be done first (one-time setup):
  ```bash
  yarn svm:token:delegate --token-mint CxFvc8BXoq7TwPYiBBvN7yvTXVYRGhKgsfmZC4RNpWc1
  ```

### Using CLI Script

```bash
cd falcon-ccip-solana

# Bridge 1 USDf from Solana to Sepolia
yarn svm:token-transfer \
  --token-mint CxFvc8BXoq7TwPYiBBvN7yvTXVYRGhKgsfmZC4RNpWc1 \
  --token-amount 1000000000 \
  --receiver-address <EVM_WALLET_ADDRESS>

# Bridge 0.001 USDf
yarn svm:token-transfer \
  --token-mint CxFvc8BXoq7TwPYiBBvN7yvTXVYRGhKgsfmZC4RNpWc1 \
  --token-amount 1000000 \
  --receiver-address <EVM_WALLET_ADDRESS>
```

### Using Helper Script

```bash
# Bridge 1 USDf (default)
./script/bridgeTest.sh sol2eth <EVM_WALLET_ADDRESS>

# Bridge custom amount (raw 9dp)
./script/bridgeTest.sh sol2eth <EVM_WALLET_ADDRESS> 500000000
```

### Solana → EVM One-Time Setup

Before the first Solana → EVM transfer, the sender wallet must **delegate** the USDf token to CCIP's fee-billing signer PDA. This is a one-time `spl-token approve` operation:

```bash
yarn svm:token:delegate --token-mint CxFvc8BXoq7TwPYiBBvN7yvTXVYRGhKgsfmZC4RNpWc1
```

Verify delegation:
```bash
yarn svm:token:check --token-mint CxFvc8BXoq7TwPYiBBvN7yvTXVYRGhKgsfmZC4RNpWc1
```

---

## Monitoring & Verification

### Track Cross-Chain Message

After sending, the script outputs a **CCIP Message ID**. Track it at:

```
https://ccip.chain.link/msg/<MESSAGE_ID>
```

Typical finality times:
- **ETH → SOL**: ~20 min (Ethereum finality + CCIP DON processing)
- **SOL → ETH**: ~3-5 min (Solana finality is faster)

### Verify Balances

```bash
# Solana balance
spl-token balance CxFvc8BXoq7TwPYiBBvN7yvTXVYRGhKgsfmZC4RNpWc1

# EVM balance (cast)
cast call 0x3e34bfc2872534c331b6db2e4b3593fa7eaeddfd \
  "balanceOf(address)(uint256)" <EVM_WALLET> --rpc-url https://eth-sepolia.api.onfinality.io/public
```

### Explorer Links

| Chain | Explorer |
|-------|----------|
| Solana Devnet | `https://explorer.solana.com/tx/<TX>?cluster=devnet` |
| Ethereum Sepolia | `https://sepolia.etherscan.io/tx/<TX>` |
| CCIP Message | `https://ccip.chain.link/msg/<MSG_ID>` |

---

## Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| `insufficient funds` on EVM | Not enough Sepolia ETH | Get from [Sepolia Faucet](https://sepoliafaucet.com) |
| `insufficient balance` on Solana | Not enough SOL for fees | `solana airdrop 2` |
| `delegate not found` on SOL→ETH | Token not delegated | Run `yarn svm:token:delegate --token-mint CxFvc8BXoq7TwPYiBBvN7yvTXVYRGhKgsfmZC4RNpWc1` |
| Transfer stuck / pending | CCIP DON processing | Wait 20-30 min, check CCIP Explorer |
| Wrong amount received | Decimal mismatch | Ensure you're using correct decimals (18 on EVM, 9 on Solana) |

---

## Quick Test Checklist

- [ ] **ETH → SOL**: Send 1 USDf from Sepolia, verify ~1 USDf arrives on Solana Devnet
- [ ] **SOL → ETH**: Send 1 USDf from Solana Devnet, verify ~1 USDf arrives on Sepolia
- [ ] **Small amount**: Send 0.001 USDf both directions, verify precision is preserved
- [ ] **Balance check**: Confirm no dust or precision loss after round-trip
- [ ] **Fee check**: Confirm CCIP fee is reasonable (~0.001-0.01 ETH / ~0.005 SOL)
