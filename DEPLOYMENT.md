# Deployment Guide

Complete guide for deploying the Base Credit Lending Protocol to Base mainnet and testnet.

## Prerequisites

### Required Tools

- **Foundry** - Smart contract development toolkit
- **Git** - Version control
- **Node.js** (optional) - For frontend integration

### Required Accounts

- **Base RPC Provider** - Alchemy, Infura, or QuickNode
- **Basescan API Key** - For contract verification
- **Wallet with ETH** - For gas fees on Base

## Environment Setup

Create a `.env` file in the project root:

```bash
# Base Mainnet
BASE_RPC_URL=https://mainnet.base.org
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org

# Private Keys (NEVER commit these!)
PRIVATE_KEY=your_private_key_here

# API Keys
ETHERSCAN_API_KEY=your_basescan_api_key
```

**Security Warning:** Never commit `.env` files or private keys to version control!

## Deployment Options

### Option 1: Base Sepolia Testnet (Recommended First)

Deploy to testnet for testing before mainnet.

#### Step 1: Get Testnet ETH

Get Base Sepolia ETH from:
- [Base Sepolia Faucet](https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet)
- [Alchemy Faucet](https://sepoliafaucet.com/)

#### Step 2: Deploy to Testnet

```bash
# Load environment variables
source .env

# Run deployment script
forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    -vvvv
```

#### Step 3: Test the Deployment

The deployment script automatically:
- Deploys all contracts
- Creates test tokens with faucet functionality
- Configures the protocol
- Provides initial liquidity
- Saves addresses to `deployments/base-sepolia-{timestamp}.json`

#### Step 4: Interact with Testnet Contracts

```bash
# Mint test tokens
cast send <TEST_USDC_ADDRESS> "faucet()" \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Check balance
cast call <TEST_USDC_ADDRESS> "balanceOf(address)(uint256)" <YOUR_ADDRESS> \
    --rpc-url $BASE_SEPOLIA_RPC_URL
```

### Option 2: Base Mainnet Production

Deploy to mainnet after thorough testing on testnet.

#### Pre-Deployment Checklist

- [ ] All tests passing (165+ tests)
- [ ] Testnet deployment successful
- [ ] Testnet testing completed
- [ ] Security audit completed
- [ ] Multi-sig wallet prepared (Gnosis Safe)
- [ ] Sufficient ETH for deployment (~0.5 ETH estimated)
- [ ] Contract verification API key ready

#### Step 1: Review Configuration

Edit `script/DeployBaseMainnet.s.sol` if needed:
- Interest rates
- Supported tokens
- Oracle configurations
- Initial settings

#### Step 2: Dry Run (Simulation)

```bash
# Simulate deployment without broadcasting
forge script script/DeployBaseMainnet.s.sol:DeployBaseMainnet \
    --rpc-url $BASE_RPC_URL \
    -vvvv
```

Review the output carefully!

#### Step 3: Deploy to Mainnet

```bash
# Deploy with broadcasting and verification
forge script script/DeployBaseMainnet.s.sol:DeployBaseMainnet \
    --rpc-url $BASE_RPC_URL \
    --broadcast \
    --verify \
    --slow \
    -vvvv
```

**Note:** `--slow` adds delays between transactions to ensure proper ordering.

#### Step 4: Verify Deployment

The script will output all contract addresses. Verify on Basescan:
- Check contract verification status
- Verify owner addresses
- Check token configurations

#### Step 5: Transfer to Multi-Sig

**Critical:** Immediately transfer ownership to a multi-sig wallet:

```bash
# For each ownable contract
cast send <CONTRACT_ADDRESS> "transferOwnership(address)" <GNOSIS_SAFE_ADDRESS> \
    --rpc-url $BASE_RPC_URL \
    --private-key $PRIVATE_KEY
```

Contracts to transfer:
- CreditOracle
- PriceOracle
- Diamond (via OwnershipFacet)
- USDC Vault
- WETH Vault
- LendingPool

## Post-Deployment Steps

### 1. Provide Initial Liquidity

The protocol needs liquidity to function:

```bash
# Approve tokens
cast send <TOKEN_ADDRESS> "approve(address,uint256)" \
    <LENDING_POOL_ADDRESS> <AMOUNT> \
    --rpc-url $BASE_RPC_URL \
    --private-key $PRIVATE_KEY

# Transfer liquidity to pool
cast send <TOKEN_ADDRESS> "transfer(address,uint256)" \
    <LENDING_POOL_ADDRESS> <AMOUNT> \
    --rpc-url $BASE_RPC_URL \
    --private-key $PRIVATE_KEY
```

### 2. Set Up Monitoring

Configure monitoring tools:

**Tenderly:**
```bash
# Add project to Tenderly
tenderly login
tenderly push
```

**OpenZeppelin Defender:**
- Add contracts to Defender
- Set up Autotasks for monitoring
- Configure alerts for critical events

### 3. Configure Timelock (Recommended)

For additional security, set up a timelock:

```solidity
// Deploy OpenZeppelin TimelockController
// Configure with 24-48 hour delay
// Make timelock the owner of all contracts
```

### 4. Set Up Emergency Pause

Implement pause functionality:

```bash
# Add pause mechanism to critical functions
# Configure pause guardian (multi-sig)
```

## Deployment Costs

### Estimated Gas Costs (Base Mainnet)

| Contract | Estimated Gas | Cost (@0.5 gwei, $3000 ETH) |
|----------|---------------|------------------------------|
| CreditOracle | ~3,500,000 | ~$5.25 |
| PriceOracle | ~2,000,000 | ~$3.00 |
| Diamond + Facets | ~5,000,000 | ~$7.50 |
| USDC Vault | ~3,000,000 | ~$4.50 |
| WETH Vault | ~3,000,000 | ~$4.50 |
| LendingPool | ~4,500,000 | ~$6.75 |
| **Total** | **~21,000,000** | **~$31.50** |

**Note:** Actual costs may vary based on gas prices and network conditions.

### Verification Costs

Contract verification on Basescan is free!

## Troubleshooting

### Common Issues

#### Issue: "Insufficient funds for gas"
**Solution:** Ensure deployer wallet has enough ETH on Base.

#### Issue: "Nonce too low"
**Solution:**
```bash
# Reset nonce
cast nonce <YOUR_ADDRESS> --rpc-url $BASE_RPC_URL
```

#### Issue: "Contract verification failed"
**Solution:**
```bash
# Manually verify contract
forge verify-contract <CONTRACT_ADDRESS> <CONTRACT_NAME> \
    --chain-id 8453 \
    --compiler-version v0.8.24 \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

#### Issue: "Transaction reverted"
**Solution:** Add `-vvvv` flag to see detailed revert reasons.

### Getting Help

- **GitHub Issues**: [Report deployment issues](https://github.com/Martins-O/Base-lending-protocol-/issues)
- **Discord**: Join the Base Discord for support
- **Documentation**: Review all `.md` files in the repository

## Security Best Practices

### Before Mainnet Launch

1. **Multi-Sig Setup**
   - Use Gnosis Safe with 3-5 signers
   - Require 60% threshold for actions
   - Include trusted team members

2. **Timelock Configuration**
   - 24-48 hour delay for upgrades
   - 6-12 hour delay for parameter changes
   - Emergency pause with shorter delay

3. **Access Control**
   - Remove deployer wallet as owner
   - Transfer to multi-sig immediately
   - Document all admin functions

4. **Monitoring**
   - Set up Tenderly alerts
   - Configure Defender Autotasks
   - Monitor critical events:
     - Large deposits/withdrawals
     - Liquidations
     - Interest rate changes
     - Oracle price updates

5. **Rate Limiting**
   - Consider implementing daily limits
   - Add circuit breakers for extreme conditions
   - Monitor TVL growth

### After Launch

1. **Bug Bounty Program**
   - Launch on Immunefi
   - Offer competitive rewards
   - Define scope clearly

2. **Regular Audits**
   - Conduct audits before major upgrades
   - Use multiple audit firms
   - Publish audit reports

3. **Community Engagement**
   - Announce deployment on Twitter/Discord
   - Create user guides
   - Provide support channels

## Upgrade Process

To upgrade contracts after deployment:

### For Diamond (NFT Contract)

```bash
# 1. Deploy new facet
forge create src/diamond/facets/NewFacet.sol:NewFacet \
    --rpc-url $BASE_RPC_URL \
    --private-key $PRIVATE_KEY

# 2. Prepare diamondCut with new facet address
# 3. Execute via multi-sig
```

### For Other Contracts

Protocol uses transparent upgradeability:
1. Deploy new implementation
2. Propose upgrade via multi-sig
3. Wait for timelock delay
4. Execute upgrade
5. Verify upgrade success

## Rollback Plan

If issues arise post-deployment:

1. **Immediate Actions**
   - Pause affected contracts
   - Notify users via Discord/Twitter
   - Investigate root cause

2. **Recovery Steps**
   - If Diamond: Replace facet with previous version
   - If others: Deploy fix and upgrade
   - Conduct thorough testing

3. **Communication**
   - Publish incident report
   - Explain fixes implemented
   - Provide timeline for resolution

## Deployment Checklist

### Pre-Deployment
- [ ] All tests passing (165+ tests)
- [ ] Code reviewed and audited
- [ ] Deployment scripts tested on testnet
- [ ] Multi-sig wallet configured
- [ ] Monitoring tools ready
- [ ] Documentation complete
- [ ] Gas funds available

### During Deployment
- [ ] Deploy all contracts
- [ ] Verify contracts on Basescan
- [ ] Configure protocol parameters
- [ ] Provide initial liquidity
- [ ] Transfer ownership to multi-sig
- [ ] Save all deployment addresses

### Post-Deployment
- [ ] Set up monitoring
- [ ] Configure alerts
- [ ] Implement timelock
- [ ] Add emergency pause
- [ ] Launch bug bounty
- [ ] Announce to community
- [ ] Create user guides
- [ ] Monitor initial transactions

## Next Steps After Deployment

1. **Integration Testing** - Test all user flows end-to-end
2. **Frontend Development** - Build user interface
3. **Documentation** - Create comprehensive user guides
4. **Marketing** - Announce launch, create content
5. **Community Building** - Discord, Twitter, blog posts
6. **Partnerships** - Integrate with other DeFi protocols
7. **Gradual Rollout** - Start with TVL caps, increase gradually

---

## Support

For deployment assistance:
- Open an issue on GitHub
- Contact the team on Discord
- Review the documentation in this repository

**Remember:** Always test on testnet first! 🧪
