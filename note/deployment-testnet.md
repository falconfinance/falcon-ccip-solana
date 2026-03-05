# USDf CCIP Cross-Chain Deployment — Testnet

**Date:** 2026-03-03  
**Networks:** Ethereum Sepolia ↔ Solana Devnet  
**Token:** Falcon USD (USDf)  
**CCIP Pattern:** BurnMint (Direct Mint Authority)

---

## Deployed Addresses

### Ethereum Sepolia

| Component | Address |
|-----------|---------|
| Token (ERC20 BurnMint) | `0x3e34bfc2872534c331b6db2e4b3593fa7eaeddfd` |
| Token Pool | `0x215Db3842Aba71B3Ef257841C7195b244Fa506AE` |
| Deployer / Admin | `0x50FAD3de9F0C113312065cB50c267fcEB59a76CB` |
| TokenAdminRegistry | `0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82` |
| Decimals | **18** |

### Solana Devnet

| Component | Address |
|-----------|---------|
| Token Mint (SPL Token) | `CxFvc8BXoq7TwPYiBBvN7yvTXVYRGhKgsfmZC4RNpWc1` |
| Token Program | `TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA` (legacy SPL) |
| Token Account (Deployer ATA) | `AXnGQawNHoxvFm7mwapxEsF8tASoducBPcPHD9jFac8j` |
| Pool Config PDA | `94CzGygp7v7VV691fuM8bFLoicW9Hrnf8TxqFrZETijf` |
| Pool Signer PDA | `5UmpEE9WsnpFTktu2bfLaPn1Jz6XgaNyj2WFxrHXwudL` |
| Pool Token Account (ATA) | `5aVas16d14j4zZLRvFjvQxxm5HLQYNmfJQnHnbuEzeXM` |
| Address Lookup Table | `F7v7MoCvuwexXtV1LUkEdyyCXk7GLvy3zqcBeNGtAphz` |
| CCIP BurnMint Pool Program | `41FGToCmdaWa1dgZLKFAjvmx6e6AjVTX7SVRibvsMGVB` |
| Deployer / Wallet | `C5RCy9inYHkzyfsVZ2We1s4YfNHEhLADq7W3FimQZPCA` |
| Decimals | **9** |
| Initial Supply | 1,000 tokens (1000000000000 raw) |

---

## Decimal Configuration

| Chain | Decimals | 1 Token Raw Value |
|-------|----------|-------------------|
| Ethereum Sepolia | 18 | 1000000000000000000 |
| Solana Devnet | 9 | 1000000000 |

Remote chain config `--decimals` is set to **18** (EVM remote decimals), enabling correct cross-chain decimal conversion by the CCIP pool.

**Mainnet recommendation:** Use the same decimals on both chains (e.g., 9 on EVM and 9 on Solana) to eliminate conversion risk entirely, per [Chainlink guidance](https://docs.chain.link/ccip/concepts/cross-chain-token/svm/tokens#decimal-planning).

---

## Authority & Permissions

| Authority | Status |
|-----------|--------|
| Solana Mint Authority | Transferred to Pool Signer PDA (`5UmpEE9WsnpFTktu2bfLaPn1Jz6XgaNyj2WFxrHXwudL`) — **irreversible** |
| Solana Freeze Authority | `C5RCy9inYHkzyfsVZ2We1s4YfNHEhLADq7W3FimQZPCA` (deployer) |
| Solana CCIP Admin | `C5RCy9inYHkzyfsVZ2We1s4YfNHEhLADq7W3FimQZPCA` |
| EVM CCIP Admin | `0x50FAD3de9F0C113312065cB50c267fcEB59a76CB` |
| EVM Token Owner | `0x50FAD3de9F0C113312065cB50c267fcEB59a76CB` |
| Token Delegate (fee billing) | Delegated, amount: u64::MAX |

---

## Cross-Chain Configuration

| Setting | Value |
|---------|-------|
| Remote Chain Selector (Solana Devnet) | `16423721717087811551` |
| Remote Chain Name | `solanaDevnet` / `ethereum-sepolia` |
| Remote Decimals (Solana pool config) | 18 (EVM token decimals) |
| Rate Limiter (Outbound) | Disabled |
| Rate Limiter (Inbound) | Disabled |
| EVM Fee Token | Native ETH |
| ALT Writable Indices | 3, 4, 7 |

---

## Test Transfers

### Test 1: Solana → Ethereum ✅

| Field | Value |
|-------|-------|
| Amount | 1,000,000 raw (0.001 token, 9 dp) |
| Sender | `C5RCy9inYHkzyfsVZ2We1s4YfNHEhLADq7W3FimQZPCA` |
| Receiver | `0x9d087fC03ae39b088326b67fA3C788236645b717` |
| Solana TX | [`riyZVnyd...Q48UiB`](https://explorer.solana.com/tx/riyZVnydiE7gmeYveZhD75L2W5VCkfRRpA5YrbZ3C1UyXg2ifT4qKwJAcJZjb2zx6hn5knnK7ANvQvCuJQ48UiB?cluster=devnet) |
| CCIP Message ID | [`0xa52d6931...f73b49`](https://ccip.chain.link/msg/0xa52d693145d1623194ee780df8e2e58f78521469ce2a12b4eaaedee56bf73b49) |
| Fee | SOL (native) |
| Status | ✅ Success |

### Test 2: Ethereum → Solana ✅

| Field | Value |
|-------|-------|
| Amount | 1,000,000,000,000,000,000 raw (1 token, 18 dp) |
| Sender | `0x50FAD3de9F0C113312065cB50c267fcEB59a76CB` |
| Receiver | `C5RCy9inYHkzyfsVZ2We1s4YfNHEhLADq7W3FimQZPCA` |
| ETH TX | [`0x644e5a...659a`](https://sepolia.etherscan.io/tx/0x644e5a22a46009ae5b9085af38764dab2b961d5582b2bb03f1764a26c5e3659a) |
| CCIP Message ID | [`0xb52500...17b7f`](https://ccip.chain.link/msg/0xb5250067defbfe1189574aa6ae4035327e532c88b489e62effa6eb8034917b7f) |
| CCIP Sequence Number | 6351 |
| Fee | Native ETH |
| Status | ✅ Success |

---

## Key Transactions (Deployment)

| Step | TX |
|------|-----|
| SPL Token Create | [`4wodut5j...Rw6Tus`](https://explorer.solana.com/tx/4wodut5jGPUP5FJs8a5PMLZRPjpDKmJu1wG91ThJcKrR27VqhjXRbp31T5oVCag1ULzNiBzcW8gknBzVbaRw6Tus?cluster=devnet) |
| Mint Authority Transfer | [`3H1Rw6Wn...Hg9Yf`](https://explorer.solana.com/tx/3H1Rw6Wn1M26CQH2G5WzHku6BVDYF7EAbzGNyjVa8hyaJB7jEcVKT8Ueencw9AjCi3Jg6DYP5p3K3UFqRx4Hg9Yf?cluster=devnet) |
| EVM applyChainUpdates | [`0xfe515c...bcdc`](https://sepolia.etherscan.io/tx/0xfe515cbe0abdf3d1c52eb7a440076c0d48f21171ec4b3bb46493119345efbcdc) |
| EVM setPool | [`0xcd367d...56bd`](https://sepolia.etherscan.io/tx/0xcd367d31e9dd027ed8ae2355f51d86d2d766eb46c58ce6a2484538e2b67e56bd) |
| Token Delegate | [`5Z51F9gM...uLVQ`](https://explorer.solana.com/tx/5Z51F9gMBQ51yV4BrqAsF65mRJznqMVxCV8QBATrm8cXrs5JnYJNNfXrk1DbnW9mGT2mdThwoQm8xM6ZQ4tUuLVQ?cluster=devnet) |

---

## Notes

- This is a **redeployment** — Solana side was fully redeployed with new token/pool; EVM side reused the same token (`0x3e34bf...`) and pool (`0x215Db3...`). The old Solana chain config on the EVM pool was removed via `applyChainUpdates` before adding the new one.
- The previous deployment had a decimal misconfiguration (`--decimals 9` instead of `18` in Solana remote chain config). This redeployment correctly uses `--decimals 18`, and both directions of cross-chain transfer have been verified.
- Mint authority on Solana is permanently transferred to the Pool Signer PDA — no manual minting possible. All new supply comes from cross-chain bridge inflows.
- Rate limiters are disabled for testnet. Must be configured for mainnet.
- For mainnet, strongly recommend deploying EVM USDf with **9 decimals** (same as Solana) to eliminate all precision conversion risk.
