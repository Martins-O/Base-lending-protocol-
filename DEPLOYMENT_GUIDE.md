# Deployment Guide - Base Credit Lending Protocol

## Prerequisites

Before deploying, ensure you have:

1. **Testnet ETH** (for Sepolia deployment)
   - Get from: https://www.alchemy.com/faucets/base-sepolia
   - Or: https://docs.base.org/docs/tools/network-faucets/

2. **Private Key or Hardware Wallet**
   - MetaMask: Account Details → Export Private Key
   - Or use Ledger/Trezor

3. **Basescan API Key** (optional, for contract verification)
   - Get from: https://basescan.org/myapikey

## Deployment Methods

### Method 1: Interactive Mode (Recommended - Most Secure)

The forge tool will securely prompt for your private key:

```bash
./deploy-sepolia-interactive.sh
```

Or manually:
```bash
forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
  --rpc-url https://sepolia.base.org \
  --interactive \
  --broadcast \
  -vvv
```

### Method 2: Encrypted Keystore (Recommended for Repeated Deployments)

First, create an encrypted wallet:
```bash
./setup-wallet.sh
```

Then deploy with:
```bash
forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
  --rpc-url https://sepolia.base.org \
  --account deployer \
  --sender YOUR_WALLET_ADDRESS \
  --broadcast \
  -vvv
```

### Method 3: Hardware Wallet (Most Secure)

For Ledger users:
```bash
./deploy-sepolia-ledger.sh
```

### Method 4: Direct Private Key (Quick but Less Secure)

```bash
forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
  --rpc-url https://sepolia.base.org \
  --private-key 0xYOUR_PRIVATE_KEY \
  --broadcast \
  -vvv
```

**⚠️ Warning:** Never commit private keys to git!

## What Gets Deployed

The deployment will create:

1. **Test Tokens** (Sepolia only)
   - Test USDC (tUSDC)
   - Test WETH (tWETH)
   - Test cbETH (tcbETH)

2. **Core Contracts**
   - CreditOracle (credit scoring engine)
   - PriceOracle (price feeds)
   - Diamond (upgradeable proxy)
   - 4 Diamond Facets

3. **DeFi Components**
   - 3 SavingsVaults (USDC, WETH, cbETH)
   - LendingPool (lending/borrowing)

4. **Configuration**
   - Authorization setup
   - Supported tokens
   - Interest rates (5%)
   - Price feeds

## Post-Deployment

After deployment completes:

1. **Check deployment file**:
   ```bash
   cat deployments/base-sepolia.json
   ```

2. **Verify contracts on Basescan** (if not auto-verified):
   ```bash
   forge verify-contract ADDRESS CONTRACT_NAME \
     --chain-id 84532 \
     --watch
   ```

3. **Test the deployment**:
   - Use test tokens faucet
   - Try depositing to vaults
   - Test borrowing functionality

## Mainnet Deployment

After testing on Sepolia, deploy to mainnet:

```bash
./deploy-mainnet.sh
```

**⚠️ WARNING:** Mainnet deployment costs real ETH (~$31.50)

## Troubleshooting

### "Insufficient funds for gas"
- Get more testnet ETH from faucets
- Check balance: `cast balance YOUR_ADDRESS --rpc-url https://sepolia.base.org`

### "Failed to get EIP-1559 fees"
- Try adding `--legacy` flag to use legacy transactions

### "Private key format error"
- Ensure private key starts with `0x`
- Should be 64 hex characters (66 with 0x prefix)

### "RPC connection failed"
- Check your internet connection
- Try different RPC: `--rpc-url https://base-sepolia.blockpi.network/v1/rpc/public`

## Support

- Documentation: See DEPLOYMENT.md
- Issues: https://github.com/Martins-O/Base-lending-protocol-/issues
