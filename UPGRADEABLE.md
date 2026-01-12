# SoulboundCreditNFT - Upgradeable Contract Guide

## Overview

The SoulboundCreditNFT contract has been implemented as an **upgradeable contract** using the **UUPS (Universal Upgradeable Proxy Standard)** pattern from OpenZeppelin.

## Architecture

### Components

1. **Implementation Contract**: Contains the actual business logic
2. **Proxy Contract (ERC1967Proxy)**: Delegates all calls to the implementation
3. **Storage**: Lives in the proxy contract, persists across upgrades

### Why UUPS?

- **Gas Efficient**: Upgrade logic is in the implementation, not the proxy
- **Smaller Proxy**: Lower deployment costs
- **Owner Controlled**: Only owner can authorize upgrades via `_authorizeUpgrade()`

## Key Features

### Upgradeable Implementation

```solidity
contract SoulboundCreditNFT is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
```

### Initialize Instead of Constructor

```solidity
function initialize(address _creditOracle) public initializer {
    __ERC721_init("Base Credit Identity", "BCREDIT");
    __Ownable_init(msg.sender);

    creditOracle = CreditOracle(_creditOracle);
    _nextTokenId = 1;
}
```

### Storage Gap

```solidity
uint256[47] private __gap;
```

Reserves storage slots for future state variables without breaking storage layout.

### Upgrade Authorization

```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
```

Only the contract owner can authorize upgrades.

## Deployment

### Using Forge Script

```bash
forge script script/DeployUpgradeable.s.sol:DeployUpgradeable \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast
```

### Manual Deployment Steps

1. **Deploy CreditOracle**
```solidity
CreditOracle creditOracle = new CreditOracle();
```

2. **Deploy Implementation**
```solidity
SoulboundCreditNFT implementation = new SoulboundCreditNFT();
```

3. **Prepare Initialization Data**
```solidity
bytes memory data = abi.encodeWithSelector(
    SoulboundCreditNFT.initialize.selector,
    address(creditOracle)
);
```

4. **Deploy Proxy**
```solidity
ERC1967Proxy proxy = new ERC1967Proxy(
    address(implementation),
    data
);
```

5. **Use Proxy Address**
```solidity
SoulboundCreditNFT nft = SoulboundCreditNFT(address(proxy));
```

## Upgrading the Contract

### Step 1: Deploy New Implementation

```solidity
SoulboundCreditNFT newImplementation = new SoulboundCreditNFT();
```

### Step 2: Call Upgrade Function

```solidity
// Without initialization
nft.upgradeToAndCall(address(newImplementation), "");

// With initialization (if adding new features)
bytes memory data = abi.encodeWithSelector(
    SoulboundCreditNFT.someNewInitFunction.selector,
    params
);
nft.upgradeToAndCall(address(newImplementation), data);
```

## Upgrade Safety

### ✅ Safe Operations

- Adding new functions
- Adding new state variables (at the end)
- Modifying function logic
- Adding new events

### ❌ Unsafe Operations

- Changing state variable order
- Changing state variable types
- Removing state variables
- Changing inheritance order

## Testing

Run the comprehensive test suite:

```bash
forge test --match-path test/SoulboundCreditNFT.t.sol -vv
```

### Test Coverage

- ✅ Initialization
- ✅ NFT Minting
- ✅ Soulbound transfers (blocked)
- ✅ Credit tier calculation
- ✅ Dynamic tokenURI generation
- ✅ Oracle updates
- ✅ Contract upgrades
- ✅ Access control

## Security Considerations

### 1. Initialization

- Constructor calls `_disableInitializers()` to prevent re-initialization
- `initialize()` uses `initializer` modifier

### 2. Upgrade Authorization

- Only owner can upgrade via `_authorizeUpgrade()`
- UUPS pattern means upgrade logic is in implementation

### 3. Storage Layout

- Storage gap reserves 47 slots for future variables
- Never reorder or remove existing state variables

### 4. CreditOracle Updates

- `setCreditOracle()` allows updating oracle address
- Only owner can update
- Emits `CreditOracleUpdated` event

## Version Management

```solidity
function version() external pure returns (string memory) {
    return "1.0.0";
}
```

Update this in each new implementation to track versions.

## Example: Adding New Features in V2

### Create V2 Implementation

```solidity
contract SoulboundCreditNFTV2 is SoulboundCreditNFT {
    // New state variables (at the end)
    uint256 public newFeatureData;

    // Reduce storage gap by 1 (we added 1 variable)
    uint256[46] private __gap2;

    // New function
    function newFeature() external {
        // Implementation
    }

    // Update version
    function version() external pure override returns (string memory) {
        return "2.0.0";
    }
}
```

### Deploy and Upgrade

```solidity
SoulboundCreditNFTV2 newImpl = new SoulboundCreditNFTV2();
nft.upgradeToAndCall(address(newImpl), "");
```

## OpenZeppelin Defender Integration

For production, consider using OpenZeppelin Defender for:

- Secure upgrade management
- Multi-sig upgrade proposals
- Automated security checks
- Upgrade simulations

## Additional Resources

- [OpenZeppelin UUPS Proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable)
- [Writing Upgradeable Contracts](https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable)
- [Proxy Upgrade Pattern](https://docs.openzeppelin.com/upgrades-plugins/1.x/proxies)

## Gas Costs (Estimated)

| Operation | Gas Cost |
|-----------|----------|
| Deploy Implementation | ~3,500,000 |
| Deploy Proxy | ~400,000 |
| Initialize | ~200,000 |
| Mint NFT | ~120,000 |
| Upgrade to New Implementation | ~30,000 |

## Summary

The SoulboundCreditNFT is now fully upgradeable with:

- ✅ UUPS proxy pattern
- ✅ Secure initialization
- ✅ Owner-only upgrades
- ✅ Storage layout protection
- ✅ Version tracking
- ✅ Comprehensive tests
- ✅ CreditOracle update capability

All NFT functionality (soulbound, dynamic SVG, credit tiers) is preserved and works seamlessly with the upgradeable architecture.
