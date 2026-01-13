// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/CreditOracle.sol";
import "../../src/PriceOracle.sol";
import "../../src/SavingsVault.sol";
import "../../src/LendingPool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ProtocolIntegration
 * @notice Comprehensive integration tests simulating real user flows
 * @dev Tests end-to-end scenarios across all protocol components
 */
contract ProtocolIntegrationTest is Test {
    CreditOracle public creditOracle;
    PriceOracle public priceOracle;
    SavingsVault public vault;
    LendingPool public pool;
    MockERC20 public usdc;
    MockERC20 public collateralToken;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    address public liquidator;

    uint256 constant INITIAL_BALANCE = 100000 * 10**6; // 100k USDC

    event UserJourney(string stage, address user, uint256 creditScore);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        liquidator = makeAddr("liquidator");

        // Deploy tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        collateralToken = new MockERC20("Collateral", "COL", 6);

        // Deploy protocol contracts
        creditOracle = new CreditOracle();
        priceOracle = new PriceOracle(owner);
        vault = new SavingsVault(
            usdc,
            "Credit Vault",
            "cvUSDC",
            owner,
            address(creditOracle),
            500 // 5% base APY
        );
        pool = new LendingPool(owner, address(creditOracle), address(priceOracle));

        // Configure protocol
        priceOracle.setManualPrice(address(collateralToken), 1 * 10**18); // $1 per token
        priceOracle.setManualPrice(address(usdc), 1 * 10**18);

        pool.setSupportedToken(address(collateralToken), true);
        pool.setInterestRate(address(collateralToken), 500); // 5%

        // Mint tokens to users
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);
        usdc.mint(charlie, INITIAL_BALANCE);
        usdc.mint(liquidator, INITIAL_BALANCE);

        collateralToken.mint(alice, INITIAL_BALANCE);
        collateralToken.mint(bob, INITIAL_BALANCE);
        collateralToken.mint(charlie, INITIAL_BALANCE);

        // Provide liquidity to pool
        collateralToken.mint(address(pool), 1000000 * 10**6);
    }

    /// @notice Test: Complete user journey from new user to trusted borrower
    function test_Integration_UserJourneyNewToTrusted() public {
        emit log_string("=== Alice's Journey: New User to Trusted Borrower ===");

        // Stage 1: Alice is a new user with default credit score
        uint256 initialScore = creditOracle.getCreditScore(alice);
        emit UserJourney("New User", alice, initialScore);
        assertEq(initialScore, 300, "New user should have minimum score");

        // Stage 2: Alice deposits to savings vault (builds savings consistency)
        vm.startPrank(alice);
        usdc.approve(address(vault), 10000 * 10**6);
        vault.deposit(10000 * 10**6, alice);
        vm.stopPrank();

        // Simulate time passing (builds time in protocol)
        vm.warp(block.timestamp + 30 days);

        // Stage 3: Alice deposits collateral with poor credit (200% ratio)
        vm.startPrank(alice);
        collateralToken.approve(address(pool), 20000 * 10**6);
        pool.depositCollateral(address(collateralToken), 20000 * 10**6);

        // Can only borrow 50% of collateral value due to 200% ratio
        uint256 maxBorrow1 = pool.getMaxBorrowAmount(alice, address(collateralToken));
        assertApproxEqAbs(maxBorrow1, 10000 * 10**6, 100 * 10**6, "Initial borrow limit");

        pool.borrow(address(collateralToken), 8000 * 10**6);
        vm.stopPrank();

        emit log_string("Stage 1: Borrowed 8k with 200% ratio (poor credit)");

        // Stage 4: Alice repays on time (builds payment history)
        vm.warp(block.timestamp + 30 days);

        vm.startPrank(alice);
        LendingPool.UserPosition memory pos = pool.getUserPosition(alice, address(collateralToken));
        uint256 debt = pos.borrowedAmount + pos.accruedInterest;
        collateralToken.approve(address(pool), debt);
        pool.repay(address(collateralToken), debt);
        vm.stopPrank();

        emit log_string("Stage 2: Repaid loan on time (improves payment history)");

        // Stage 5: Time passes, credit score improves
        vm.warp(block.timestamp + 60 days);

        uint256 improvedScore = creditOracle.getCreditScore(alice);
        emit UserJourney("After 120 days activity", alice, improvedScore);
        assertGt(improvedScore, initialScore, "Score should improve");

        // Stage 6: Alice can now borrow more with better ratio
        vm.startPrank(alice);
        uint256 maxBorrow2 = pool.getMaxBorrowAmount(alice, address(collateralToken));
        assertGt(maxBorrow2, maxBorrow1, "Improved credit allows more borrowing");

        pool.borrow(address(collateralToken), 12000 * 10**6);
        vm.stopPrank();

        emit log_string("Stage 3: Borrowed 12k with improved ratio");

        // Verify final state
        LendingPool.UserPosition memory finalPos = pool.getUserPosition(alice, address(collateralToken));
        assertLt(finalPos.collateralRatio, 200, "Better collateral ratio achieved");
        emit log_named_uint("Final Collateral Ratio", finalPos.collateralRatio);
    }

    /// @notice Test: Multi-user lending pool with liquidations
    function test_Integration_MultiUserLiquidation() public {
        emit log_string("=== Multi-User Scenario with Liquidation ===");

        // Bob deposits and borrows
        vm.startPrank(bob);
        collateralToken.approve(address(pool), 30000 * 10**6);
        pool.depositCollateral(address(collateralToken), 30000 * 10**6);
        pool.borrow(address(collateralToken), 12000 * 10**6);
        vm.stopPrank();

        // Charlie deposits and borrows
        vm.startPrank(charlie);
        collateralToken.approve(address(pool), 25000 * 10**6);
        pool.depositCollateral(address(collateralToken), 25000 * 10**6);
        pool.borrow(address(collateralToken), 10000 * 10**6);
        vm.stopPrank();

        emit log_string("Bob and Charlie both borrowed successfully");

        // Price drops significantly
        priceOracle.setManualPrice(address(collateralToken), 0.6 * 10**18); // 40% drop

        // Check liquidation status
        bool bobLiquidatable = pool.isLiquidatable(bob, address(collateralToken));
        bool charlieLiquidatable = pool.isLiquidatable(charlie, address(collateralToken));

        emit log_string("After 40% price drop:");
        emit log_named_string("Bob liquidatable", bobLiquidatable ? "YES" : "NO");
        emit log_named_string("Charlie liquidatable", charlieLiquidatable ? "YES" : "NO");

        // Liquidator liquidates Bob
        if (bobLiquidatable) {
            vm.startPrank(liquidator);
            collateralToken.approve(address(pool), 12000 * 10**6);

            uint256 liquidatorBalanceBefore = collateralToken.balanceOf(liquidator);
            pool.liquidate(bob, address(collateralToken), 12000 * 10**6);
            uint256 liquidatorBalanceAfter = collateralToken.balanceOf(liquidator);

            uint256 profit = liquidatorBalanceAfter - liquidatorBalanceBefore;
            emit log_named_uint("Liquidator profit (with bonus)", profit);

            vm.stopPrank();
        }

        // Verify Charlie is unaffected
        LendingPool.UserPosition memory charliePos = pool.getUserPosition(charlie, address(collateralToken));
        assertEq(charliePos.borrowedAmount, 10000 * 10**6, "Charlie's position unchanged");

        emit log_string("Liquidation completed, other users unaffected");
    }

    /// @notice Test: Vault deposits boosting credit scores
    function test_Integration_VaultCreditBoost() public {
        emit log_string("=== Savings Vault Credit Score Boost ===");

        uint256 aliceInitialScore = creditOracle.getCreditScore(alice);
        uint256 bobInitialScore = creditOracle.getCreditScore(bob);

        // Alice makes consistent vault deposits
        vm.startPrank(alice);
        usdc.approve(address(vault), 50000 * 10**6);

        // Deposit 1
        vault.deposit(10000 * 10**6, alice);
        vm.warp(block.timestamp + 15 days);

        // Deposit 2
        vault.deposit(10000 * 10**6, alice);
        vm.warp(block.timestamp + 15 days);

        // Deposit 3
        vault.deposit(10000 * 10**6, alice);
        vm.warp(block.timestamp + 15 days);

        vm.stopPrank();

        // Bob makes no deposits
        vm.warp(block.timestamp + 15 days);

        uint256 aliceFinalScore = creditOracle.getCreditScore(alice);
        uint256 bobFinalScore = creditOracle.getCreditScore(bob);

        emit log_named_uint("Alice initial score", aliceInitialScore);
        emit log_named_uint("Alice final score", aliceFinalScore);
        emit log_named_uint("Bob score (no activity)", bobFinalScore);

        assertGt(aliceFinalScore, aliceInitialScore, "Vault deposits improve credit");
        assertEq(bobFinalScore, bobInitialScore, "No activity = no change");
    }

    /// @notice Test: Interest accumulation over time
    function test_Integration_InterestAccumulation() public {
        emit log_string("=== Interest Accumulation Test ===");

        // Alice borrows
        vm.startPrank(alice);
        collateralToken.approve(address(pool), 20000 * 10**6);
        pool.depositCollateral(address(collateralToken), 20000 * 10**6);
        pool.borrow(address(collateralToken), 8000 * 10**6);
        vm.stopPrank();

        LendingPool.UserPosition memory pos1 = pool.getUserPosition(alice, address(collateralToken));
        uint256 initialDebt = pos1.borrowedAmount + pos1.accruedInterest;
        emit log_named_uint("Initial debt", initialDebt);

        // 1 year passes
        vm.warp(block.timestamp + 365 days);

        LendingPool.UserPosition memory pos2 = pool.getUserPosition(alice, address(collateralToken));
        uint256 debtAfter1Year = pos2.borrowedAmount + pos2.accruedInterest;
        emit log_named_uint("Debt after 1 year", debtAfter1Year);

        uint256 interest = debtAfter1Year - initialDebt;
        emit log_named_uint("Interest accrued", interest);

        // Interest should be approximately 5% (400 USDC)
        assertApproxEqAbs(interest, 400 * 10**6, 50 * 10**6, "5% annual interest");
    }

    /// @notice Test: Health factor monitoring
    function test_Integration_HealthFactorMonitoring() public {
        emit log_string("=== Health Factor Monitoring ===");

        // Alice deposits and borrows at max capacity
        vm.startPrank(alice);
        collateralToken.approve(address(pool), 20000 * 10**6);
        pool.depositCollateral(address(collateralToken), 20000 * 10**6);

        uint256 maxBorrow = pool.getMaxBorrowAmount(alice, address(collateralToken));
        pool.borrow(address(collateralToken), maxBorrow * 98 / 100); // 98% of max
        vm.stopPrank();

        uint256 initialHF = pool.getHealthFactor(alice, address(collateralToken));
        emit log_named_uint("Initial health factor (x100)", initialHF);
        assertGt(initialHF, 100, "Should be healthy");

        // Price drops 10%
        priceOracle.setManualPrice(address(collateralToken), 0.9 * 10**18);

        uint256 hfAfterDrop = pool.getHealthFactor(alice, address(collateralToken));
        emit log_named_uint("HF after 10% drop (x100)", hfAfterDrop);
        assertLt(hfAfterDrop, initialHF, "HF should decrease");

        // Price drops another 10%
        priceOracle.setManualPrice(address(collateralToken), 0.8 * 10**18);

        uint256 hfCritical = pool.getHealthFactor(alice, address(collateralToken));
        emit log_named_uint("HF after 20% drop (x100)", hfCritical);

        bool liquidatable = pool.isLiquidatable(alice, address(collateralToken));
        emit log_named_string("Liquidatable", liquidatable ? "YES" : "NO");

        if (hfCritical < 100) {
            emit log_string("WARNING: Position is now liquidatable!");
        }
    }

    /// @notice Test: Cross-protocol composability
    function test_Integration_CrossProtocolComposability() public {
        emit log_string("=== Cross-Protocol Composability ===");

        // Alice deposits to vault
        vm.startPrank(alice);
        usdc.approve(address(vault), 10000 * 10**6);
        uint256 shares = vault.deposit(10000 * 10**6, alice);
        vm.stopPrank();

        emit log_named_uint("Vault shares received", shares);

        // Shares can be transferred (ERC20 compliant)
        vm.prank(alice);
        vault.transfer(bob, shares / 2);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        emit log_named_uint("Alice shares", aliceShares);
        emit log_named_uint("Bob shares", bobShares);

        assertEq(aliceShares, shares / 2, "Alice has half");
        assertEq(bobShares, shares / 2, "Bob has half");

        // Both can redeem independently
        vm.prank(alice);
        uint256 aliceWithdraw = vault.redeem(aliceShares, alice, alice);

        vm.prank(bob);
        uint256 bobWithdraw = vault.redeem(bobShares, bob, bob);

        emit log_named_uint("Alice withdrew", aliceWithdraw);
        emit log_named_uint("Bob withdrew", bobWithdraw);

        assertApproxEqAbs(aliceWithdraw + bobWithdraw, 10000 * 10**6, 10, "Total matches deposit");
    }

    /// @notice Test: Stress test with many users
    function test_Integration_StressTestManyUsers() public {
        emit log_string("=== Stress Test: 10 Users ===");

        address[] memory users = new address[](10);

        // Create and fund 10 users
        for (uint256 i = 0; i < 10; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            collateralToken.mint(users[i], 50000 * 10**6);
        }

        // All users deposit and borrow
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(users[i]);
            collateralToken.approve(address(pool), 20000 * 10**6);
            pool.depositCollateral(address(collateralToken), 20000 * 10**6);
            pool.borrow(address(collateralToken), 5000 * 10**6);
            vm.stopPrank();
        }

        emit log_string("All 10 users deposited and borrowed");

        // Verify pool state
        uint256 totalCollateral = pool.totalCollateral(address(collateralToken));
        uint256 totalBorrowed = pool.totalBorrowed(address(collateralToken));

        emit log_named_uint("Total collateral", totalCollateral);
        emit log_named_uint("Total borrowed", totalBorrowed);

        assertEq(totalCollateral, 200000 * 10**6, "All collateral tracked");
        assertEq(totalBorrowed, 50000 * 10**6, "All borrows tracked");

        // Users repay
        vm.warp(block.timestamp + 30 days);

        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(users[i]);
            LendingPool.UserPosition memory userPos = pool.getUserPosition(users[i], address(collateralToken));
            uint256 debt = userPos.borrowedAmount + userPos.accruedInterest;
            collateralToken.approve(address(pool), debt);
            pool.repay(address(collateralToken), debt);
            vm.stopPrank();
        }

        emit log_string("All users repaid successfully");

        // Verify final state
        uint256 finalBorrowed = pool.totalBorrowed(address(collateralToken));
        assertEq(finalBorrowed, 0, "All debt cleared");
    }

    /// @notice Test: Recovery from liquidation
    function test_Integration_RecoveryFromLiquidation() public {
        emit log_string("=== User Recovery After Liquidation ===");

        // Alice gets liquidated
        vm.startPrank(alice);
        collateralToken.approve(address(pool), 20000 * 10**6);
        pool.depositCollateral(address(collateralToken), 20000 * 10**6);
        pool.borrow(address(collateralToken), 9000 * 10**6);
        vm.stopPrank();

        // Price drops - liquidation occurs
        priceOracle.setManualPrice(address(collateralToken), 0.5 * 10**18);

        vm.startPrank(liquidator);
        collateralToken.approve(address(pool), 9000 * 10**6);
        pool.liquidate(alice, address(collateralToken), 9000 * 10**6);
        vm.stopPrank();

        emit log_string("Alice was liquidated");

        // Price recovers
        priceOracle.setManualPrice(address(collateralToken), 1 * 10**18);

        // Alice can start fresh
        vm.startPrank(alice);
        collateralToken.approve(address(pool), 15000 * 10**6);
        pool.depositCollateral(address(collateralToken), 15000 * 10**6);

        uint256 maxBorrow = pool.getMaxBorrowAmount(alice, address(collateralToken));
        assertGt(maxBorrow, 0, "Can borrow again");

        pool.borrow(address(collateralToken), 5000 * 10**6);
        vm.stopPrank();

        emit log_string("Alice recovered and borrowed again");

        LendingPool.UserPosition memory newPos = pool.getUserPosition(alice, address(collateralToken));
        assertEq(newPos.borrowedAmount, 5000 * 10**6, "New position established");
    }
}

/**
 * @title MockERC20
 * @notice Simple ERC20 for testing
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
