// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/LendingPool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title LendingPoolInvariantTest
 * @notice Invariant tests for LendingPool to ensure protocol safety
 * @dev Tests critical invariants that must always hold true
 */
contract LendingPoolInvariantTest is Test {
    LendingPool public pool;
    MockERC20 public collateralToken;
    MockCreditOracle public creditOracle;
    MockPriceOracle public priceOracle;

    Handler public handler;

    function setUp() public {
        // Deploy contracts
        collateralToken = new MockERC20("USD Coin", "USDC", 6);
        creditOracle = new MockCreditOracle();
        priceOracle = new MockPriceOracle();

        pool = new LendingPool(
            address(this),
            address(creditOracle),
            address(priceOracle)
        );

        // Configure pool
        pool.setSupportedToken(address(collateralToken), true);
        pool.setInterestRate(address(collateralToken), 500); // 5% APY

        // Set price
        priceOracle.setPrice(address(collateralToken), 2000 * 10**18);

        // Deploy handler for invariant testing
        handler = new Handler(pool, collateralToken, creditOracle, priceOracle);

        // Mint initial tokens to handler
        collateralToken.mint(address(handler), 1000000 * 10**6);
        collateralToken.mint(address(pool), 1000000 * 10**6);

        // Target handler for invariant testing
        targetContract(address(handler));
    }

    /// @notice Invariant: Pool's collateral balance >= sum of all user collateral
    function invariant_collateralBalance() public {
        uint256 poolBalance = collateralToken.balanceOf(address(pool));
        uint256 totalUserCollateral = pool.totalCollateral(address(collateralToken));
        uint256 totalBorrowed = pool.totalBorrowed(address(collateralToken));

        // Pool balance should be >= total collateral + borrowed amount still in pool
        assertGe(
            poolBalance + totalBorrowed,
            totalUserCollateral,
            "Pool balance should cover all user collateral"
        );
    }

    /// @notice Invariant: Total borrowed <= total collateral value / min collateral ratio
    function invariant_borrowLimit() public {
        uint256 totalCollateral = pool.totalCollateral(address(collateralToken));
        uint256 totalBorrowed = pool.totalBorrowed(address(collateralToken));

        // With 110% min ratio, max borrow should be ~90% of collateral value
        // totalBorrowed * 110 <= totalCollateral * 100
        if (totalCollateral > 0) {
            assertLe(
                totalBorrowed * 110,
                totalCollateral * 100,
                "Total borrowed should not exceed max LTV"
            );
        }
    }

    /// @notice Invariant: User's borrowed amount should never exceed their collateral value / their ratio
    function invariant_userBorrowLimit() public {
        address[] memory users = handler.getUsers();

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            LendingPool.UserPosition memory position = pool.getUserPosition(
                user,
                address(collateralToken)
            );

            if (position.collateralAmount > 0 && position.collateralRatio > 0) {
                // borrowed * ratio <= collateral * 100
                uint256 maxBorrow = (position.collateralAmount * 100) / position.collateralRatio;
                uint256 totalDebt = position.borrowedAmount + position.accruedInterest;

                assertLe(
                    totalDebt,
                    maxBorrow,
                    "User debt should not exceed their max borrow capacity"
                );
            }
        }
    }

    /// @notice Invariant: Health factor should be >= 1.0 for all non-liquidatable positions
    function invariant_healthFactor() public {
        address[] memory users = handler.getUsers();

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            // Skip if no position
            LendingPool.UserPosition memory position = pool.getUserPosition(
                user,
                address(collateralToken)
            );

            if (position.borrowedAmount == 0) continue;

            uint256 healthFactor = pool.getHealthFactor(user, address(collateralToken));
            bool isLiquidatable = pool.isLiquidatable(user, address(collateralToken));

            // If not liquidatable, health factor should be >= threshold
            if (!isLiquidatable) {
                assertGe(
                    healthFactor,
                    1e18, // 1.0 in 18 decimals
                    "Non-liquidatable positions should have health factor >= 1.0"
                );
            }
        }
    }

    /// @notice Invariant: Sum of all user collateral == totalCollateral
    function invariant_collateralAccounting() public {
        address[] memory users = handler.getUsers();
        uint256 sumUserCollateral = 0;

        for (uint256 i = 0; i < users.length; i++) {
            LendingPool.UserPosition memory position = pool.getUserPosition(
                users[i],
                address(collateralToken)
            );
            sumUserCollateral += position.collateralAmount;
        }

        assertEq(
            sumUserCollateral,
            pool.totalCollateral(address(collateralToken)),
            "Sum of user collateral should equal total collateral"
        );
    }

    /// @notice Invariant: Sum of all user borrowed == totalBorrowed
    function invariant_borrowAccounting() public {
        address[] memory users = handler.getUsers();
        uint256 sumUserBorrowed = 0;

        for (uint256 i = 0; i < users.length; i++) {
            LendingPool.UserPosition memory position = pool.getUserPosition(
                users[i],
                address(collateralToken)
            );
            sumUserBorrowed += position.borrowedAmount;
        }

        assertEq(
            sumUserBorrowed,
            pool.totalBorrowed(address(collateralToken)),
            "Sum of user borrowed should equal total borrowed"
        );
    }

    /// @notice Invariant: Interest never decreases for a position
    function invariant_interestMonotonic() public {
        // This is checked in handler - interest should never decrease
        assertTrue(handler.interestAlwaysIncreases(), "Interest should only increase");
    }

    /// @notice Invariant: Pool cannot be drained
    function invariant_poolNotDrained() public {
        uint256 poolBalance = collateralToken.balanceOf(address(pool));
        uint256 totalCollateral = pool.totalCollateral(address(collateralToken));

        // Pool should always have at least the collateral
        assertGe(
            poolBalance,
            totalCollateral,
            "Pool should never have less than total collateral"
        );
    }
}

/**
 * @title Handler
 * @notice Handler contract for invariant testing
 * @dev Performs random but valid operations on the protocol
 */
contract Handler is Test {
    LendingPool public pool;
    MockERC20 public token;
    MockCreditOracle public creditOracle;
    MockPriceOracle public priceOracle;

    address[] public users;
    mapping(address => uint256) public lastInterest;
    bool public interestAlwaysIncreases = true;

    uint256 public constant MAX_USERS = 10;

    constructor(
        LendingPool _pool,
        MockERC20 _token,
        MockCreditOracle _creditOracle,
        MockPriceOracle _priceOracle
    ) {
        pool = _pool;
        token = _token;
        creditOracle = _creditOracle;
        priceOracle = _priceOracle;

        // Create test users
        for (uint256 i = 0; i < MAX_USERS; i++) {
            address user = address(uint160(0x1000 + i));
            users.push(user);

            // Give users tokens
            token.mint(user, 100000 * 10**6);

            // Approve pool
            vm.prank(user);
            token.approve(address(pool), type(uint256).max);

            // Set random credit scores
            uint256 score = 600 + (i * 50); // Scores from 600-1050
            if (score > 850) score = 850;
            creditOracle.setCreditScore(user, score);
        }
    }

    function getUsers() external view returns (address[] memory) {
        return users;
    }

    function depositCollateral(uint256 userIndex, uint256 amount) external {
        userIndex = bound(userIndex, 0, users.length - 1);
        amount = bound(amount, 100 * 10**6, 10000 * 10**6); // 100 - 10k USDC

        address user = users[userIndex];

        vm.prank(user);
        try pool.depositCollateral(address(token), amount) {
            // Success
        } catch {
            // Ignore failures
        }
    }

    function borrow(uint256 userIndex, uint256 amount) external {
        userIndex = bound(userIndex, 0, users.length - 1);
        amount = bound(amount, 100 * 10**6, 5000 * 10**6); // 100 - 5k USDC

        address user = users[userIndex];

        vm.prank(user);
        try pool.borrow(address(token), amount) {
            // Success
        } catch {
            // Ignore failures
        }
    }

    function repay(uint256 userIndex, uint256 amount) external {
        userIndex = bound(userIndex, 0, users.length - 1);
        amount = bound(amount, 100 * 10**6, 5000 * 10**6);

        address user = users[userIndex];

        vm.prank(user);
        try pool.repay(address(token), amount) {
            // Check interest monotonicity
            uint256 currentInterest = pool.calculateInterest(user, address(token));
            if (currentInterest < lastInterest[user]) {
                interestAlwaysIncreases = false;
            }
            lastInterest[user] = currentInterest;
        } catch {
            // Ignore failures
        }
    }

    function withdrawCollateral(uint256 userIndex, uint256 amount) external {
        userIndex = bound(userIndex, 0, users.length - 1);
        amount = bound(amount, 100 * 10**6, 5000 * 10**6);

        address user = users[userIndex];

        vm.prank(user);
        try pool.withdrawCollateral(address(token), amount) {
            // Success
        } catch {
            // Ignore failures
        }
    }

    function warpTime(uint256 timeDelta) external {
        timeDelta = bound(timeDelta, 1 hours, 30 days);
        vm.warp(block.timestamp + timeDelta);
    }

    function changeCreditScore(uint256 userIndex, uint256 score) external {
        userIndex = bound(userIndex, 0, users.length - 1);
        score = bound(score, 300, 850);

        creditOracle.setCreditScore(users[userIndex], score);
    }

    function changePrice(uint256 priceChange) external {
        // Price can change between 50% and 150% of current
        priceChange = bound(priceChange, 50, 150);

        uint256 currentPrice = priceOracle.getPrice(address(token));
        uint256 newPrice = (currentPrice * priceChange) / 100;

        priceOracle.setPrice(address(token), newPrice);
    }
}

// Mock contracts (reuse from main tests)
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockCreditOracle {
    mapping(address => uint256) private creditScores;

    function setCreditScore(address user, uint256 score) external {
        creditScores[user] = score;
    }

    function getCreditScore(address user) external view returns (uint256) {
        uint256 score = creditScores[user];
        return score == 0 ? 300 : score;
    }

    function recordPayment(address, uint256, uint256) external pure {}
    function recordBorrow(address) external pure {}
}

contract MockPriceOracle {
    mapping(address => uint256) private prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getPrice(address token) external view returns (uint256) {
        return prices[token];
    }

    function getPriceInUSD(address token, uint256 amount) external view returns (uint256) {
        uint256 price = prices[token];
        return (amount * price) / 1e18;
    }
}
