# Base Credit Lending Protocol

A decentralized lending protocol on Base that uses on-chain credit scoring to offer dynamic collateral ratios (110-200%) based on user behavior and reputation.

## 🎯 Features

- **Multi-Factor Credit Scoring** (300-850 range, FICO-like)
- **Soulbound Credit NFTs** with dynamic SVG visualization
- **Dynamic Collateral Ratios** based on creditworthiness
- **Savings Vault** with credit score boosting
- **Diamond Standard (EIP-2535)** upgradeable architecture

## 🏗️ Architecture

### Upgradeable Pattern: Diamond Standard (EIP-2535)

This protocol uses the **Diamond Standard** for maximum flexibility:

✅ **Unlimited Contract Size** - No 24KB limit
✅ **Modular Facets** - Independent upgrade of components
✅ **Add Features Post-Deploy** - Extend without redeployment
✅ **Transparent Upgrades** - Clear upgrade history

See **[DIAMOND.md](DIAMOND.md)** for complete documentation.

### Core Contracts

| Contract | Description | Status |
|----------|-------------|--------|
| **CreditOracle** | Multi-factor credit scoring engine | ✅ Implemented |
| **Diamond** | Main proxy with facet routing | ✅ Implemented |
| **CreditNFTFacet** | Soulbound NFT logic | ✅ Implemented |
| **DiamondCutFacet** | Upgrade management | ✅ Implemented |
| **DiamondLoupeFacet** | Introspection | ✅ Implemented |
| **OwnershipFacet** | ERC-173 ownership | ✅ Implemented |
| **PriceOracle** | Chainlink price feeds | 🔄 Planned |
| **SavingsVault** | Interest-bearing deposits | 🔄 Planned |
| **LendingPool** | Core lending/borrowing | 🔄 Planned |

## 📊 Credit Scoring

### Scoring Factors

Total Score = 850 × Weighted Sum of:

1. **Payment History (35%)** - On-time repayments, late penalties
2. **Savings Consistency (30%)** - Regular deposits, maintained balance
3. **Time in Protocol (20%)** - Account age (0-180 days)
4. **Diversity Score (10%)** - Multiple asset types used
5. **Liquidity Provision (5%)** - LP token staking

### Credit Tiers

| Tier | Score Range | Collateral Ratio | NFT Color |
|------|-------------|------------------|-----------|
| **Platinum** | 750-850 | 110% | Silver |
| **Gold** | 650-749 | 130% | Gold |
| **Silver** | 550-649 | 150% | Light Gray |
| **Bronze** | 300-549 | 200% | Bronze |

## 🚀 Quick Start

### Installation

```bash
# Clone repository
git clone <repo-url>
cd lending-protocol

# Install dependencies (Foundry required)
forge install

# Build contracts
forge build

# Run tests
forge test
```

### Deployment

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
export RPC_URL=https://base-mainnet.g.alchemy.com/v2/your-api-key

# Deploy Diamond
forge script script/DeployDiamond.s.sol:DeployDiamond \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify
```

### Usage

```solidity
// Interact with Diamond
CreditNFTFacet nft = CreditNFTFacet(diamondAddress);

// Mint NFT
uint256 tokenId = nft.mint(userAddress);

// Get credit score
uint256 score = nft.getCreditScoreForToken(tokenId);

// View dynamic metadata
string memory uri = nft.tokenURI(tokenId);
```

## 🧪 Testing

```bash
# Run all tests
forge test

# Run Diamond tests
forge test --match-path test/DiamondCreditNFT.t.sol -vv

# Run with gas report
forge test --gas-report

# Coverage
forge coverage
```

### Test Results

```
✅ 13/13 Diamond tests passing
✅ Diamond deployment
✅ Facet upgrades (add/replace)
✅ Soulbound transfers (blocked)
✅ Dynamic token URIs
✅ Credit score integration
✅ Ownership management
```

## 📁 Project Structure

```
lending-protocol/
├── src/
│   ├── diamond/
│   │   ├── Diamond.sol              # Main Diamond proxy
│   │   ├── facets/
│   │   │   ├── DiamondCutFacet.sol  # Upgrade management
│   │   │   ├── DiamondLoupeFacet.sol # Introspection
│   │   │   ├── OwnershipFacet.sol   # ERC-173 ownership
│   │   │   └── CreditNFTFacet.sol   # NFT logic
│   │   ├── libraries/
│   │   │   ├── LibDiamond.sol       # Core Diamond logic
│   │   │   └── LibCreditNFT.sol     # NFT storage
│   │   └── interfaces/
│   │       ├── IDiamondCut.sol
│   │       ├── IDiamondLoupe.sol
│   │       └── IERC173.sol
│   ├── CreditOracle.sol             # Credit scoring engine
│   └── SoulboundCreditNFT.sol       # Legacy UUPS version
├── script/
│   ├── DeployDiamond.s.sol          # Diamond deployment
│   └── DeployUpgradeable.s.sol      # UUPS deployment (legacy)
├── test/
│   ├── DiamondCreditNFT.t.sol       # Diamond tests
│   └── SoulboundCreditNFT.t.sol     # UUPS tests (legacy)
├── DIAMOND.md                        # Diamond documentation
├── UPGRADEABLE.md                    # UUPS documentation (legacy)
└── README.md                         # This file
```

## 🔄 Upgrade Process

### Add New Facet

```solidity
// 1. Deploy new facet
NewFeatureFacet facet = new NewFeatureFacet();

// 2. Prepare FacetCut
IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
cut[0] = IDiamondCut.FacetCut({
    facetAddress: address(facet),
    action: IDiamondCut.FacetCutAction.Add,
    functionSelectors: [selectors]
});

// 3. Execute
IDiamondCut(diamond).diamondCut(cut, address(0), "");
```

### Replace Functions

```solidity
// Deploy updated facet
CreditNFTFacetV2 newFacet = new CreditNFTFacetV2();

// Prepare Replace cut
cut[0].action = IDiamondCut.FacetCutAction.Replace;

// Execute
IDiamondCut(diamond).diamondCut(cut, address(0), "");
```

See **[DIAMOND.md](DIAMOND.md)** for detailed upgrade patterns.

## 🛡️ Security

### Best Practices
✅ Diamond Storage pattern (prevents collisions)
✅ Owner-only upgrades
✅ Function selector validation
✅ Delegatecall protection
✅ Comprehensive test coverage

### Production Checklist
- [ ] Multi-sig ownership
- [ ] Timelock on upgrades
- [ ] Emergency pause mechanism
- [ ] Monitoring & alerts
- [ ] External audit
- [ ] Bug bounty program

## 📈 Gas Costs

| Operation | Gas Cost |
|-----------|----------|
| Deploy Diamond | ~500,000 |
| Deploy CreditOracle | ~3,500,000 |
| Deploy Facet | ~1-3M |
| Mint NFT | ~120,000 |
| Add Facet | ~100,000 |
| Replace Function | ~50,000 |
| Get Credit Score | ~50,000 |

## 🎨 NFT Features

### Dynamic SVG
- **Real-time credit score display**
- **Tier-based color gradients**
- **Soulbound (non-transferable)**
- **Base64-encoded on-chain metadata**

### Tier Visuals

| Tier | Gradient | Theme |
|------|----------|-------|
| Platinum | Silver-Gray | Elite |
| Gold | Gold-Orange | Premium |
| Silver | Gray-Dark | Standard |
| Bronze | Bronze-Brown | Entry |

## 📚 Documentation

- **[DIAMOND.md](DIAMOND.md)** - Complete Diamond Standard guide
- **[UPGRADEABLE.md](UPGRADEABLE.md)** - Legacy UUPS implementation
- **[CreditOracle.sol](src/CreditOracle.sol)** - Credit scoring algorithm

## 📄 License

MIT License

## ⚠️ Disclaimer

This is experimental software under active development. Use at your own risk. Not audited for production use.

---

Built with ❤️ for the Base ecosystem using the Diamond Standard (EIP-2535) 💎
