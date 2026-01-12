# Interfaces & Libraries Documentation

This document covers all protocol interfaces and utility libraries.

## 📦 Interfaces (`src/interfaces/`)

### ICreditOracle.sol

Interface for the credit scoring oracle.

**Key Functions:**
- `getCreditScore(address user)` - Get user's credit score (300-850)
- `recordPayment(address user, uint256 amount, uint256 daysLate)` - Record payment
- `updateSavingsBalance(address user, uint256 balance, uint256 deposit)` - Update savings
- `trackAssetUsage(address user, address asset)` - Track asset diversity
- `getCreditBreakdown(address user)` - Get detailed score breakdown

**Events:**
- `CreditScoreUpdated` - Score changed
- `PaymentRecorded` - Payment logged
- `SavingsUpdated` - Savings changed

**Usage:**
```solidity
ICreditOracle oracle = ICreditOracle(oracleAddress);
uint256 score = oracle.getCreditScore(userAddress);
```

---

### ICreditNFT.sol

Interface for the Soulbound Credit NFT.

**Key Functions:**
- `mint(address to)` - Mint NFT for user
- `getTokenId(address user)` - Get user's token ID
- `hasNFT(address user)` - Check if user has NFT
- `getCreditScoreForToken(uint256 tokenId)` - Get score for NFT
- `getTierForToken(uint256 tokenId)` - Get tier (Bronze/Silver/Gold/Platinum)
- `tokenURI(uint256 tokenId)` - Get dynamic metadata

**Errors:**
- `TransferNotAllowed()` - Cannot transfer soulbound NFT
- `AlreadyHasNFT()` - User already has an NFT
- `TokenDoesNotExist()` - Invalid token ID

**Usage:**
```solidity
ICreditNFT nft = ICreditNFT(nftAddress);
uint256 tokenId = nft.mint(userAddress);
string memory tier = nft.getTierForToken(tokenId);
```

---

### ILendingPool.sol

Interface for the main lending pool with credit-based collateral ratios.

**Key Functions:**
- `depositCollateral(address token, uint256 amount)` - Deposit collateral
- `borrow(address token, uint256 amount)` - Borrow against collateral
- `repay(address token, uint256 amount)` - Repay borrowed amount
- `liquidate(address borrower, address token, uint256 debt)` - Liquidate position
- `getHealthFactor(address user, address token)` - Get position health
- `getCollateralRatio(address user)` - Get credit-based ratio

**Structs:**
```solidity
struct UserPosition {
    uint256 collateralAmount;
    uint256 borrowedAmount;
    uint256 collateralRatio;  // Dynamic based on credit
    uint256 lastUpdateTime;
    uint256 accruedInterest;
}
```

**Usage:**
```solidity
ILendingPool pool = ILendingPool(poolAddress);
pool.depositCollateral(tokenAddress, 1000e18);
uint256 maxBorrow = pool.getMaxBorrowAmount(user, token);
pool.borrow(token, maxBorrow);
```

---

### IPriceOracle.sol

Interface for Chainlink price oracle integration.

**Key Functions:**
- `getPrice(address token)` - Get current token price in USD
- `getPriceInUSD(address token, uint256 amount)` - Convert amount to USD
- `setPriceFeed(address token, address feed)` - Set Chainlink feed
- `isPriceStale(address token)` - Check if price is outdated

**Errors:**
- `PriceFeedNotSet(address token)` - No feed configured
- `StalePrice(address token, uint256 lastUpdate)` - Price too old
- `InvalidPrice(address token, int256 price)` - Invalid price data

**Usage:**
```solidity
IPriceOracle oracle = IPriceOracle(oracleAddress);
uint256 price = oracle.getPrice(tokenAddress);
uint256 valueInUSD = oracle.getPriceInUSD(token, amount);
```

---

### ISavingsVault.sol

Interface for high-yield savings vault that builds credit.

**Key Functions:**
- `deposit(uint256 amount)` - Deposit to vault
- `withdraw(uint256 shares)` - Withdraw from vault
- `balanceOf(address user)` - Get user balance
- `getAPY()` - Get current annual percentage yield
- `getCreditBoost(address user)` - Get credit score boost from savings

**Usage:**
```solidity
ISavingsVault vault = ISavingsVault(vaultAddress);
uint256 shares = vault.deposit(1000e18);
uint256 apy = vault.getAPY();
```

---

## 📚 Libraries (`src/libraries/`)

### CreditScore.sol

Utility library for credit score calculations.

**Constants:**
```solidity
MIN_SCORE = 300
MAX_SCORE = 850
PLATINUM_THRESHOLD = 750
GOLD_THRESHOLD = 650
SILVER_THRESHOLD = 550
```

**Key Functions:**

#### `getTierName(uint256 score) → string`
Get tier name from score.

```solidity
string memory tier = CreditScore.getTierName(720); // "Gold"
```

#### `getCollateralRatio(uint256 score) → uint256`
Get collateral ratio in basis points.

```solidity
uint256 ratio = CreditScore.getCollateralRatio(780); // 11000 (110%)
```

#### `calculateMaxBorrow(uint256 collateral, uint256 score) → uint256`
Calculate max borrow based on collateral and score.

```solidity
uint256 maxBorrow = CreditScore.calculateMaxBorrow(
    1000e18,  // $1000 collateral
    750       // Platinum score
);
// Returns: ~909e18 ($909 max borrow at 110% ratio)
```

#### `calculateHealthFactor(uint256 collateral, uint256 borrowed, uint256 score) → uint256`
Calculate position health factor (1e18 = 100%).

```solidity
uint256 health = CreditScore.calculateHealthFactor(
    1000e18,  // $1000 collateral
    800e18,   // $800 borrowed
    750       // Platinum score
);
// Returns: ~1.1e18 (110% health)
```

#### `applyInterestDiscount(uint256 baseRate, uint256 score) → uint256`
Apply interest rate discount based on credit score.

```solidity
uint256 rate = CreditScore.applyInterestDiscount(
    500,  // 5% base rate
    780   // Platinum score
);
// Returns: 250 (2.5% - 50% discount)
```

---

### Math.sol

General purpose math library.

**Constants:**
```solidity
PRECISION = 1e18
PERCENTAGE_FACTOR = 10000  // 100% in basis points
```

**Key Functions:**

#### `percentMul(uint256 value, uint256 percentage) → uint256`
Calculate percentage of value.

```solidity
uint256 result = Math.percentMul(1000e18, 2500); // 25% of 1000 = 250
```

#### `compoundInterest(uint256 principal, uint256 rate, uint256 time) → uint256`
Calculate compound interest.

```solidity
uint256 final = Math.compoundInterest(
    1000e18,     // $1000 principal
    500,         // 5% annual rate
    365 days     // 1 year
);
// Returns: ~1050e18 ($1050)
```

#### `weightedAverage(uint256[] values, uint256[] weights) → uint256`
Calculate weighted average.

```solidity
uint256[] memory values = [100, 200, 300];
uint256[] memory weights = [1, 2, 3];
uint256 avg = Math.weightedAverage(values, weights);
// Returns: 233 ((100*1 + 200*2 + 300*3) / (1+2+3))
```

#### `sqrt(uint256 x) → uint256`
Calculate square root (Babylonian method).

```solidity
uint256 root = Math.sqrt(144); // 12
```

#### `scaleToDecimals(uint256 value, uint8 from, uint8 to) → uint256`
Convert between decimal formats.

```solidity
uint256 scaled = Math.scaleToDecimals(
    1000,  // USDC amount (6 decimals)
    6,     // from decimals
    18     // to decimals
);
// Returns: 1000e18
```

---

### DataTypes.sol

Common data structures used across the protocol.

**Key Structs:**

#### `CreditInfo`
User credit information.

```solidity
struct CreditInfo {
    uint256 score;           // 300-850
    uint256 tier;            // 0-3
    uint256 collateralRatio; // in bps
    uint256 lastUpdate;
    bool initialized;
}
```

#### `LendingPosition`
User lending position details.

```solidity
struct LendingPosition {
    uint256 collateralAmount;
    address collateralToken;
    uint256 borrowedAmount;
    address borrowedToken;
    uint256 borrowTimestamp;
    uint256 lastInterestUpdate;
    uint256 accruedInterest;
    uint256 healthFactor;
}
```

#### `ReserveConfig`
Token reserve configuration.

```solidity
struct ReserveConfig {
    address token;
    uint8 decimals;
    bool isActive;
    bool borrowingEnabled;
    uint256 baseBorrowRate;
    uint256 optimalUtilization;
    uint256 liquidationThreshold;
    uint256 liquidationBonus;
    address priceOracle;
}
```

#### `InterestRateModel`
Interest rate parameters.

```solidity
struct InterestRateModel {
    uint256 baseRate;
    uint256 optimalRate;
    uint256 maxRate;
    uint256 optimalUtilization;
}
```

---

### Errors.sol

Protocol-wide custom errors (gas-efficient).

**Categories:**

#### Credit Oracle Errors
```solidity
error NotAuthorized(address caller);
error UserNotInitialized(address user);
error InvalidCreditScore(uint256 score);
```

#### NFT Errors
```solidity
error TransferNotAllowed();
error AlreadyHasNFT(address user);
error TokenDoesNotExist(uint256 tokenId);
```

#### Lending Pool Errors
```solidity
error InsufficientCollateral(uint256 required, uint256 provided);
error BorrowLimitExceeded(uint256 limit, uint256 requested);
error PositionNotLiquidatable(uint256 healthFactor);
```

#### Price Oracle Errors
```solidity
error PriceFeedNotSet(address token);
error StalePrice(address token, uint256 lastUpdate, uint256 maxStale);
error InvalidPrice(address token, int256 price);
```

**Usage:**
```solidity
import {Errors} from "./libraries/Errors.sol";

function borrow(uint256 amount) external {
    if (amount > maxBorrow) {
        revert Errors.BorrowLimitExceeded(maxBorrow, amount);
    }
}
```

---

## 🔧 Usage Examples

### Complete Lending Flow

```solidity
// 1. Get user's credit score
ICreditOracle oracle = ICreditOracle(oracleAddress);
uint256 score = oracle.getCreditScore(user);

// 2. Calculate collateral ratio
uint256 ratio = CreditScore.getCollateralRatio(score);

// 3. Deposit collateral
ILendingPool pool = ILendingPool(poolAddress);
pool.depositCollateral(WETH, 10 ether);

// 4. Calculate max borrow
uint256 collateralValue = 10 ether * wethPrice / 1e18;
uint256 maxBorrow = CreditScore.calculateMaxBorrow(collateralValue, score);

// 5. Borrow
pool.borrow(USDC, maxBorrow);

// 6. Monitor health
uint256 health = pool.getHealthFactor(user, USDC);
require(health >= 1e18, "Unhealthy position");
```

### Credit Score Calculation

```solidity
// Get detailed breakdown
(
    uint256 total,
    uint256 payment,
    uint256 savings,
    uint256 time,
    uint256 diversity,
    uint256 liquidity
) = oracle.getCreditBreakdown(user);

// Check tier
string memory tier = CreditScore.getTierName(total);

// Calculate benefits
uint256 ratio = CreditScore.getCollateralRatio(total);
uint256 discountRate = CreditScore.applyInterestDiscount(baseRate, total);
```

---

## 📊 Summary

| Category | Files | Purpose |
|----------|-------|---------|
| **Interfaces** | 5 | Protocol contract interfaces |
| **Libraries** | 4 | Utility functions & data types |
| **Total** | 9 | Core protocol infrastructure |

### Interfaces
- ✅ ICreditOracle - Credit scoring
- ✅ ICreditNFT - Soulbound NFTs
- ✅ ILendingPool - Lending/borrowing
- ✅ IPriceOracle - Price feeds
- ✅ ISavingsVault - Savings deposits

### Libraries
- ✅ CreditScore - Credit calculations
- ✅ Math - General math utils
- ✅ DataTypes - Common structs
- ✅ Errors - Custom errors

All interfaces and libraries are ready for implementation! 🚀
