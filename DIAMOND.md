// DIAMOND Standard (EIP-2535) Implementation Guide

## Overview

The SoulboundCreditNFT has been implemented using the **Diamond Standard (EIP-2535)**, which provides:

- ✅ **Unlimited Contract Size** - No 24KB bytecode limit
- ✅ **Modular Architecture** - Separate facets for different functionality
- ✅ **Upgrade Flexibility** - Add, replace, or remove functions independently
- ✅ **Single Address** - One address for all functionality
- ✅ **Transparent Upgrades** - Clear upgrade history via events
- ✅ **Gas Efficient** - Optimized delegatecall routing

## Architecture

### Diamond Contract Structure

```
Diamond (Main Contract)
├── DiamondCutFacet      → Upgrade management
├── DiamondLoupeFacet    → Introspection (view facets/selectors)
├── OwnershipFacet       → ERC-173 ownership
└── CreditNFTFacet       → NFT logic & credit scoring
```

### Storage Pattern

Uses **Diamond Storage** pattern to avoid storage collisions:

```solidity
// Each facet has its own storage namespace
bytes32 constant DIAMOND_STORAGE = keccak256("diamond.standard.diamond.storage");
bytes32 constant CREDIT_NFT_STORAGE = keccak256("diamond.standard.credit.nft.storage");
```

## Key Components

### 1. Diamond.sol
Main proxy contract that:
- Routes function calls to appropriate facets via `fallback()`
- Stores facet mappings in DiamondStorage
- Initialized with DiamondCutFacet for upgrade capability

### 2. LibDiamond.sol
Core library providing:
- Storage management
- Facet add/replace/remove logic
- Ownership enforcement
- Initialization handling

### 3. DiamondCutFacet
Manages upgrades through:
- `diamondCut()` - Add/replace/remove function selectors
- Only callable by contract owner
- Emits `DiamondCut` event for transparency

### 4. DiamondLoupeFacet
Inspection functions:
- `facets()` - Get all facets and their selectors
- `facetFunctionSelectors()` - Get selectors for specific facet
- `facetAddresses()` - Get all facet addresses
- `facetAddress()` - Get facet for specific selector
- `supportsInterface()` - ERC-165 support

### 5. OwnershipFacet
ERC-173 ownership:
- `owner()` - Get current owner
- `transferOwnership()` - Transfer ownership

### 6. CreditNFTFacet
NFT functionality:
- `mint()` - Mint soulbound NFT
- `tokenURI()` - Dynamic metadata
- `ownerOf()`, `balanceOf()` - ERC-721 views
- `getCreditScoreForToken()` - Credit integration
- `setCreditOracle()` - Update oracle address

### 7. LibCreditNFT.sol
NFT storage library:
- Isolated storage namespace
- ERC-721 state variables
- Credit-specific mappings
- Tier thresholds

## Deployment

### Using Forge Script

```bash
forge script script/DeployDiamond.s.sol:DeployDiamond \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

### Manual Deployment Steps

```solidity
// 1. Deploy CreditOracle
CreditOracle oracle = new CreditOracle();

// 2. Deploy DiamondCutFacet
DiamondCutFacet cutFacet = new DiamondCutFacet();

// 3. Deploy Diamond with DiamondCutFacet
Diamond diamond = new Diamond(owner, address(cutFacet));

// 4. Deploy other facets
DiamondLoupeFacet loupe = new DiamondLoupeFacet();
OwnershipFacet ownership = new OwnershipFacet();
CreditNFTFacet nft = new CreditNFTFacet();

// 5. Prepare FacetCut array
IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](3);

// Add loupe facet
cut[0] = IDiamondCut.FacetCut({
    facetAddress: address(loupe),
    action: IDiamondCut.FacetCutAction.Add,
    functionSelectors: [loupe selectors]
});

// Add ownership facet
cut[1] = IDiamondCut.FacetCut({
    facetAddress: address(ownership),
    action: IDiamondCut.FacetCutAction.Add,
    functionSelectors: [ownership selectors]
});

// Add NFT facet
cut[2] = IDiamondCut.FacetCut({
    facetAddress: address(nft),
    action: IDiamondCut.FacetCutAction.Add,
    functionSelectors: [nft selectors]
});

// 6. Execute diamond cut
IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");

// 7. Initialize NFT
CreditNFTFacet(address(diamond)).initializeCreditNFT(address(oracle));
```

## Upgrading the Diamond

### Adding New Functions

```solidity
// 1. Deploy new facet
NewFeatureFacet newFacet = new NewFeatureFacet();

// 2. Prepare cut
IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
bytes4[] memory selectors = new bytes4[](2);
selectors[0] = NewFeatureFacet.newFunction1.selector;
selectors[1] = NewFeatureFacet.newFunction2.selector;

cut[0] = IDiamondCut.FacetCut({
    facetAddress: address(newFacet),
    action: IDiamondCut.FacetCutAction.Add,
    functionSelectors: selectors
});

// 3. Execute
IDiamondCut(diamond).diamondCut(cut, address(0), "");
```

### Replacing Functions

```solidity
// 1. Deploy updated facet
CreditNFTFacetV2 newNFT = new CreditNFTFacetV2();

// 2. Prepare cut with Replace action
cut[0] = IDiamondCut.FacetCut({
    facetAddress: address(newNFT),
    action: IDiamondCut.FacetCutAction.Replace,
    functionSelectors: [selectors to replace]
});

// 3. Execute
IDiamondCut(diamond).diamondCut(cut, address(0), "");
```

### Removing Functions

```solidity
// Prepare cut with Remove action
cut[0] = IDiamondCut.FacetCut({
    facetAddress: address(0), // Must be address(0) for Remove
    action: IDiamondCut.FacetCutAction.Remove,
    functionSelectors: [selectors to remove]
});

IDiamondCut(diamond).diamondCut(cut, address(0), "");
```

### Upgrading with Initialization

```solidity
// Deploy init contract
DiamondInit init = new DiamondInit();

// Prepare initialization data
bytes memory initData = abi.encodeWithSelector(
    DiamondInit.init.selector,
    arg1,
    arg2
);

// Execute cut with initialization
IDiamondCut(diamond).diamondCut(cut, address(init), initData);
```

## Testing

Run comprehensive Diamond tests:

```bash
forge test --match-path test/DiamondCreditNFT.t.sol -vv
```

### Test Coverage

✅ Diamond deployment
✅ Facet initialization
✅ NFT minting
✅ Soulbound transfer prevention
✅ Token URI generation
✅ Credit score integration
✅ Oracle updates
✅ Diamond introspection (loupe)
✅ Adding new facets
✅ Replacing existing facets
✅ Ownership transfers

## Usage Examples

### Mint NFT

```solidity
CreditNFTFacet nft = CreditNFTFacet(diamondAddress);
uint256 tokenId = nft.mint(userAddress);
```

### Get Credit Score

```solidity
uint256 score = nft.getCreditScoreForToken(tokenId);
```

### View Token Metadata

```solidity
string memory uri = nft.tokenURI(tokenId);
// Returns data URI with dynamic SVG and metadata
```

### Inspect Diamond

```solidity
IDiamondLoupe loupe = IDiamondLoupe(diamondAddress);

// Get all facets
IDiamondLoupe.Facet[] memory facets = loupe.facets();

// Get specific facet
address facet = loupe.facetAddress(functionSelector);
```

## Advantages Over UUPS

| Feature | UUPS | Diamond |
|---------|------|---------|
| Contract Size | 24KB limit | Unlimited |
| Upgrade Granularity | All or nothing | Per-function |
| Multiple Implementations | No | Yes (facets) |
| Add Functions Post-Deploy | No | Yes |
| Remove Functions | No | Yes |
| Function Collision Risk | Higher | Lower |
| Gas Cost (Calls) | ~2,600 | ~2,800 |
| Upgrade Complexity | Lower | Higher |

## Security Considerations

### 1. Storage Collisions

✅ **Mitigated** via Diamond Storage pattern
- Each facet uses unique storage namespace
- Keccak256 hashes prevent collisions

### 2. Selector Clashing

✅ **Prevented** by LibDiamond checks
- Cannot add duplicate selectors
- Replace action requires different facet

### 3. Upgrade Authorization

✅ **Owner-only** via `enforceIsContractOwner()`
- DiamondCut requires ownership
- Consider multi-sig for production

### 4. Initialization

✅ **Protected** via custom logic
- `initializeCreditNFT()` checks ownership
- One-time initialization pattern

### 5. Delegatecall Security

✅ **Validated** via `enforceHasContractCode()`
- Checks facet has code before adding
- Prevents delegatecall to EOA

## Gas Costs

| Operation | Gas Cost |
|-----------|----------|
| Deploy Diamond | ~500,000 |
| Deploy Facet | ~1,000,000 - 3,000,000 |
| Add Facet (1 function) | ~100,000 |
| Replace Function | ~50,000 |
| Remove Function | ~30,000 |
| Mint NFT | ~120,000 |
| Function Call Overhead | ~2,800 |

## Comparison: UUPS vs Diamond

### When to use UUPS
- Simple upgrade requirements
- Single implementation logic
- Lower complexity preference
- Smaller contract size acceptable

### When to use Diamond
- ✅ Need unlimited contract size
- ✅ Want modular architecture
- ✅ Require selective function upgrades
- ✅ Complex protocol with multiple modules
- ✅ Need to add features post-launch
- ✅ Want clear separation of concerns

## Production Checklist

- [ ] Multi-sig for diamond ownership
- [ ] Thorough facet testing
- [ ] Storage layout documentation
- [ ] Upgrade simulation
- [ ] Timelocks on upgrades
- [ ] Event monitoring
- [ ] Facet verification on Etherscan
- [ ] Emergency pause mechanism
- [ ] Upgrade governance process
- [ ] OpenZeppelin Defender integration

## Resources

- [EIP-2535 Specification](https://eips.ethereum.org/EIPS/eip-2535)
- [Nick Mudge's Diamond Implementation](https://github.com/mudgen/diamond)
- [Diamond Storage Pattern](https://dev.to/mudgen/how-diamond-storage-works-90e)
- [Awesome Diamonds](https://github.com/mudgen/awesome-diamonds)

## Conclusion

The Diamond Standard provides:

1. **Unlimited Growth** - No 24KB limit
2. **Surgical Upgrades** - Replace only what's needed
3. **Modular Design** - Clear separation of concerns
4. **Future-Proof** - Add features without redeployment
5. **Transparent** - All changes via events

Perfect for the Base Credit Lending Protocol's long-term evolution! 💎
