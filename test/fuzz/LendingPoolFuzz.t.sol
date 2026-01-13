// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/LendingPool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title LendingPoolFuzzTest
 * @notice Fuzz tests for LendingPool to test edge cases
 * @dev Tests various input combinations to find vulnerabilities
 */
contract LendingPoolFuzzTest is Test {
    LendingPool public pool;
    MockERC20 public collateralToken;
    MockCreditOracle public creditOracle;
    MockPriceOracle public priceOracle;

    address public user1 = address(0x1);
    address public user2 = address(0x2);

    uint256 public constant INITIAL_BALANCE = 1000000 * 10**6;
    uint256 public constant PRICE = 2000 * 10**18;

    function setUp() public {
        collateralToken = new MockERC20("USDC", "USDC", 6);
        creditOracle = new MockCreditOracle();
        priceOracle = new MockPriceOracle();

        pool = new LendingPool(address(this), address(creditOracle), address(priceOracle));

        pool.setSupportedToken(address(collateralToken), true);
        pool.setInterestRate(address(collateralToken), 500);

        priceOracle.setPrice(address(collateralToken), PRICE);

        // Setup users
        collateralToken.mint(user1, INITIAL_BALANCE);
        collateralToken.mint(user2, INITIAL_BALANCE);
        collateralToken.mint(address(pool), INITIAL_BALANCE);

        vm.prank(user1);
        collateralToken.approve(address(pool), type(uint256).max);

        vm.prank(user2);
        collateralToken.approve(address(pool), type(uint256).max);

        creditOracle.setCreditScore(user1, 750);
        creditOracle.setCreditScore(user2, 600);
    }

    /// @notice Fuzz test: Deposit should never break accounting
    function testFuzz_Deposit(uint256 amount) public {
        // Bound amount to reasonable range
        amount = bound(amount, 1, INITIAL_BALANCE);

        uint256 balanceBefore = collateralToken.balanceOf(user1);
        uint256 totalCollateralBefore = pool.totalCollateral(address(collateralToken));

        vm.prank(user1);
        pool.depositCollateral(address(collateralToken), amount);

        // Check accounting
        assertEq(
            collateralToken.balanceOf(user1),
            balanceBefore - amount,
            "User balance should decrease by amount"
        );

        assertEq(
            pool.totalCollateral(address(collateralToken)),
            totalCollateralBefore + amount,
            "Total collateral should increase by amount"
        );

        LendingPool.UserPosition memory position = pool.getUserPosition(user1, address(collateralToken));
        assertEq(position.collateralAmount, amount, "User collateral should equal deposit");
    }

    /// @notice Fuzz test: Borrow amount should respect collateral ratio
    function testFuzz_BorrowRespectCollateral(uint256 collateralAmount, uint256 borrowAmount) public {
        // Bound inputs
        collateralAmount = bound(collateralAmount, 1000 * 10**6, 100000 * 10**6);
        borrowAmount = bound(borrowAmount, 100 * 10**6, 50000 * 10**6);

        vm.startPrank(user1);
        pool.depositCollateral(address(collateralToken), collateralAmount);

        uint256 maxBorrow = pool.getMaxBorrowAmount(user1, address(collateralToken));

        if (borrowAmount <= maxBorrow) {
            // Should succeed
            pool.borrow(address(collateralToken), borrowAmount);

            LendingPool.UserPosition memory position = pool.getUserPosition(
                user1,
                address(collateralToken)
            );
            assertEq(position.borrowedAmount, borrowAmount, "Borrowed amount should be recorded");
        } else {
            // Should fail
            vm.expectRevert();
            pool.borrow(address(collateralToken), borrowAmount);
        }

        vm.stopPrank();
    }

    /// @notice Fuzz test: Repay should never exceed debt
    function testFuzz_RepayHandlesExcessAmount(
        uint256 borrowAmount,
        uint256 repayAmount
    ) public {
        borrowAmount = bound(borrowAmount, 1000 * 10**6, 5000 * 10**6);
        repayAmount = bound(repayAmount, 100 * 10**6, 20000 * 10**6);

        // Setup: deposit and borrow
        vm.startPrank(user1);
        pool.depositCollateral(address(collateralToken), 10000 * 10**6);
        pool.borrow(address(collateralToken), borrowAmount);

        uint256 balanceBefore = collateralToken.balanceOf(user1);

        // Repay (may be more than debt)
        pool.repay(address(collateralToken), repayAmount);

        LendingPool.UserPosition memory position = pool.getUserPosition(user1, address(collateralToken));

        if (repayAmount >= borrowAmount) {
            // Should repay all debt
            assertEq(position.borrowedAmount, 0, "Debt should be fully repaid");
            assertLe(
                balanceBefore - collateralToken.balanceOf(user1),
                borrowAmount + 100, // Allow for tiny interest
                "Should not transfer more than debt"
            );
        } else {
            // Should repay partial
            assertApproxEqAbs(
                position.borrowedAmount,
                borrowAmount - repayAmount,
                100, // Allow for small rounding
                "Debt should be reduced by repay amount"
            );
        }

        vm.stopPrank();
    }

    /// @notice Fuzz test: Interest calculation should be consistent
    function testFuzz_InterestCalculation(uint256 borrowAmount, uint256 timeDelta) public {
        borrowAmount = bound(borrowAmount, 1000 * 10**6, 5000 * 10**6);
        timeDelta = bound(timeDelta, 1 hours, 365 days);

        // Setup
        vm.startPrank(user1);
        pool.depositCollateral(address(collateralToken), 10000 * 10**6);
        pool.borrow(address(collateralToken), borrowAmount);
        vm.stopPrank();

        // Warp time
        vm.warp(block.timestamp + timeDelta);

        uint256 interest = pool.calculateInterest(user1, address(collateralToken));

        // Interest should be positive and reasonable
        assertGt(interest, 0, "Interest should be positive");

        // Interest should not exceed principal * rate * time
        uint256 maxInterest = (borrowAmount * 500 * timeDelta) / (365 days * 10000);
        assertLe(interest, maxInterest + borrowAmount / 1000, "Interest should be reasonable");
    }

    /// @notice Fuzz test: Health factor calculation should be consistent
    function testFuzz_HealthFactor(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 priceChange
    ) public {
        collateralAmount = bound(collateralAmount, 10000 * 10**6, 100000 * 10**6);
        borrowAmount = bound(borrowAmount, 1000 * 10**6, 50000 * 10**6);
        priceChange = bound(priceChange, 50, 200); // 50% to 200% of current price

        // Setup
        vm.startPrank(user1);
        pool.depositCollateral(address(collateralToken), collateralAmount);

        uint256 maxBorrow = pool.getMaxBorrowAmount(user1, address(collateralToken));
        if (borrowAmount > maxBorrow) {
            vm.stopPrank();
            return; // Skip if invalid borrow
        }

        pool.borrow(address(collateralToken), borrowAmount);
        vm.stopPrank();

        // Change price
        uint256 newPrice = (PRICE * priceChange) / 100;
        priceOracle.setPrice(address(collateralToken), newPrice);

        // Check health factor
        uint256 healthFactor = pool.getHealthFactor(user1, address(collateralToken));

        if (priceChange < 100) {
            // Price dropped - health factor should decrease
            // May become liquidatable
            bool isLiquidatable = pool.isLiquidatable(user1, address(collateralToken));

            if (isLiquidatable) {
                assertLt(healthFactor, 1e18, "Liquidatable positions should have HF < 1.0");
            } else {
                assertGe(healthFactor, 1e18, "Safe positions should have HF >= 1.0");
            }
        } else {
            // Price increased - should be safe
            assertGt(healthFactor, 0, "Health factor should be positive");
        }
    }

    /// @notice Fuzz test: Dynamic collateral ratio should work correctly
    function testFuzz_DynamicCollateralRatio(uint256 creditScore) public {
        creditScore = bound(creditScore, 300, 850);

        uint256 ratio = pool.getDynamicCollateralRatio(creditScore);

        // Check ratio is in expected range
        assertGe(ratio, 110, "Ratio should be at least 110%");
        assertLe(ratio, 200, "Ratio should be at most 200%");

        // Check ratio decreases with better credit
        if (creditScore >= 800) {
            assertEq(ratio, 110, "Best credit should get 110%");
        } else if (creditScore < 600) {
            assertEq(ratio, 200, "Worst credit should get 200%");
        }
    }

    /// @notice Fuzz test: Multiple users should not affect each other
    function testFuzz_UserIsolation(
        uint256 user1Collateral,
        uint256 user2Collateral,
        uint256 user1Borrow,
        uint256 user2Borrow
    ) public {
        user1Collateral = bound(user1Collateral, 10000 * 10**6, 50000 * 10**6);
        user2Collateral = bound(user2Collateral, 10000 * 10**6, 50000 * 10**6);
        user1Borrow = bound(user1Borrow, 1000 * 10**6, 20000 * 10**6);
        user2Borrow = bound(user2Borrow, 1000 * 10**6, 20000 * 10**6);

        // User1 operations
        vm.startPrank(user1);
        pool.depositCollateral(address(collateralToken), user1Collateral);

        uint256 maxBorrow1 = pool.getMaxBorrowAmount(user1, address(collateralToken));
        if (user1Borrow <= maxBorrow1) {
            pool.borrow(address(collateralToken), user1Borrow);
        }
        vm.stopPrank();

        // User2 operations should not affect user1
        LendingPool.UserPosition memory user1PosBefore = pool.getUserPosition(
            user1,
            address(collateralToken)
        );

        vm.startPrank(user2);
        pool.depositCollateral(address(collateralToken), user2Collateral);

        uint256 maxBorrow2 = pool.getMaxBorrowAmount(user2, address(collateralToken));
        if (user2Borrow <= maxBorrow2) {
            pool.borrow(address(collateralToken), user2Borrow);
        }
        vm.stopPrank();

        LendingPool.UserPosition memory user1PosAfter = pool.getUserPosition(
            user1,
            address(collateralToken)
        );

        // User1's position should be unchanged
        assertEq(
            user1PosBefore.collateralAmount,
            user1PosAfter.collateralAmount,
            "User1 collateral should be unchanged"
        );
        assertEq(
            user1PosBefore.borrowedAmount,
            user1PosAfter.borrowedAmount,
            "User1 debt should be unchanged"
        );
    }

    /// @notice Fuzz test: Liquidation should not drain pool
    function testFuzz_LiquidationSafety(uint256 collateralAmount, uint256 borrowAmount) public {
        collateralAmount = bound(collateralAmount, 10000 * 10**6, 50000 * 10**6);
        borrowAmount = bound(borrowAmount, 5000 * 10**6, 20000 * 10**6);

        // Setup position
        vm.startPrank(user1);
        pool.depositCollateral(address(collateralToken), collateralAmount);

        uint256 maxBorrow = pool.getMaxBorrowAmount(user1, address(collateralToken));
        if (borrowAmount > maxBorrow) {
            vm.stopPrank();
            return;
        }

        pool.borrow(address(collateralToken), borrowAmount);
        vm.stopPrank();

        uint256 poolBalanceBefore = collateralToken.balanceOf(address(pool));
        uint256 totalCollateralBefore = pool.totalCollateral(address(collateralToken));

        // Drop price significantly to make liquidatable
        priceOracle.setPrice(address(collateralToken), PRICE / 5);

        // Attempt liquidation
        if (pool.isLiquidatable(user1, address(collateralToken))) {
            vm.prank(user2);
            try pool.liquidate(user1, address(collateralToken), borrowAmount) {
                // Check pool is not drained
                uint256 poolBalanceAfter = collateralToken.balanceOf(address(pool));
                uint256 totalCollateralAfter = pool.totalCollateral(address(collateralToken));

                assertGe(
                    poolBalanceAfter,
                    totalCollateralAfter,
                    "Pool should maintain collateral after liquidation"
                );
            } catch {
                // Liquidation failed, that's ok
            }
        }
    }
}

// Mock contracts
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
