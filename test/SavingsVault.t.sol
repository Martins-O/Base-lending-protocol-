// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SavingsVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title SavingsVaultTest
 * @notice Comprehensive test suite for SavingsVault contract
 */
contract SavingsVaultTest is Test {
    SavingsVault public vault;
    MockERC20 public asset;
    MockCreditOracle public creditOracle;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_APY = 500; // 5%
    uint256 public constant INITIAL_BALANCE = 100000 * 10**6; // 100k USDC

    // Events to test
    event InterestAccrued(uint256 totalInterest, uint256 timestamp);
    event CreditScoreBoosted(address indexed user, uint256 boost);
    event APYUpdated(uint256 oldAPY, uint256 newAPY);
    event CreditOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event UserDeposit(address indexed user, uint256 amount, uint256 shares, uint256 timestamp);
    event UserWithdraw(address indexed user, uint256 amount, uint256 shares, uint256 timestamp);

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        // Deploy mock USDC (6 decimals)
        asset = new MockERC20("USD Coin", "USDC", 6);

        // Deploy mock credit oracle
        creditOracle = new MockCreditOracle();

        // Deploy vault
        vault = new SavingsVault(
            IERC20(address(asset)),
            "Savings Vault USDC",
            "svUSDC",
            owner,
            address(creditOracle),
            INITIAL_APY
        );

        // Mint tokens to users
        asset.mint(user1, INITIAL_BALANCE);
        asset.mint(user2, INITIAL_BALANCE);

        // Approve vault
        vm.prank(user1);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(user2);
        asset.approve(address(vault), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor() public {
        assertEq(vault.owner(), owner);
        assertEq(address(vault.asset()), address(asset));
        assertEq(vault.creditOracle(), address(creditOracle));
        assertEq(vault.baseAPY(), INITIAL_APY);
        assertEq(vault.name(), "Savings Vault USDC");
        assertEq(vault.symbol(), "svUSDC");
    }

    function test_Constructor_RevertsOnZeroOracle() public {
        vm.expectRevert(SavingsVault.InvalidAddress.selector);
        new SavingsVault(
            IERC20(address(asset)),
            "Vault",
            "sV",
            owner,
            address(0),
            INITIAL_APY
        );
    }

    function test_Constructor_RevertsOnZeroAPY() public {
        vm.expectRevert(SavingsVault.InvalidAPY.selector);
        new SavingsVault(
            IERC20(address(asset)),
            "Vault",
            "sV",
            owner,
            address(creditOracle),
            0
        );
    }

    function test_Constructor_RevertsOnHighAPY() public {
        vm.expectRevert(SavingsVault.InvalidAPY.selector);
        new SavingsVault(
            IERC20(address(asset)),
            "Vault",
            "sV",
            owner,
            address(creditOracle),
            10001 // > 100%
        );
    }

    // ============ Deposit Tests ============

    function test_Deposit() public {
        uint256 depositAmount = 1000 * 10**6; // 1000 USDC

        vm.prank(user1);
        uint256 shares = vault.deposit(depositAmount, user1);

        assertEq(vault.balanceOf(user1), shares);
        assertEq(vault.totalAssets(), depositAmount);
        assertEq(asset.balanceOf(address(vault)), depositAmount);
        assertGt(shares, 0);
    }

    function test_Deposit_EmitsEvent() public {
        uint256 depositAmount = 1000 * 10**6;

        vm.prank(user1);
        vm.expectEmit(true, false, false, false);
        emit UserDeposit(user1, depositAmount, 0, 0);
        vault.deposit(depositAmount, user1);
    }

    function test_Deposit_UpdatesUserInfo() public {
        uint256 depositAmount = 1000 * 10**6;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        (
            uint256 firstDepositTime,
            uint256 totalDeposited,
            uint256 depositCount,
            uint256 lastDepositTime,
            ,
        ) = vault.userInfo(user1);

        assertEq(firstDepositTime, block.timestamp);
        assertEq(totalDeposited, depositAmount);
        assertEq(depositCount, 1);
        assertEq(lastDepositTime, block.timestamp);
    }

    function test_Deposit_MultipleDeposits() public {
        uint256 depositAmount = 1000 * 10**6;

        // First deposit
        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Advance time
        vm.warp(block.timestamp + 30 days);

        // Second deposit
        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        (,uint256 totalDeposited, uint256 depositCount,,, ) = vault.userInfo(user1);

        assertEq(totalDeposited, depositAmount * 2);
        assertEq(depositCount, 2);
    }

    function test_Deposit_RevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(SavingsVault.InvalidAmount.selector);
        vault.deposit(0, user1);
    }

    // ============ Mint Tests ============

    function test_Mint() public {
        uint256 sharesToMint = 1000 * 10**6;

        vm.prank(user1);
        uint256 assets = vault.mint(sharesToMint, user1);

        assertEq(vault.balanceOf(user1), sharesToMint);
        assertGt(assets, 0);
    }

    function test_Mint_RevertsOnZeroShares() public {
        vm.prank(user1);
        vm.expectRevert(SavingsVault.InvalidAmount.selector);
        vault.mint(0, user1);
    }

    // ============ Withdraw Tests ============

    function test_Withdraw() public {
        uint256 depositAmount = 1000 * 10**6;

        // Deposit first
        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 initialBalance = asset.balanceOf(user1);

        // Withdraw half
        uint256 withdrawAmount = 500 * 10**6;
        vm.prank(user1);
        uint256 shares = vault.withdraw(withdrawAmount, user1, user1);

        assertEq(asset.balanceOf(user1), initialBalance + withdrawAmount);
        assertGt(shares, 0);
    }

    function test_Withdraw_EmitsEvent() public {
        uint256 depositAmount = 1000 * 10**6;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 withdrawAmount = 500 * 10**6;

        vm.prank(user1);
        vm.expectEmit(true, false, false, false);
        emit UserWithdraw(user1, withdrawAmount, 0, 0);
        vault.withdraw(withdrawAmount, user1, user1);
    }

    function test_Withdraw_RevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(SavingsVault.InvalidAmount.selector);
        vault.withdraw(0, user1, user1);
    }

    function test_Withdraw_RevertsOnInsufficientBalance() public {
        uint256 depositAmount = 1000 * 10**6;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 excessAmount = 2000 * 10**6;

        vm.prank(user1);
        vm.expectRevert();
        vault.withdraw(excessAmount, user1, user1);
    }

    // ============ Redeem Tests ============

    function test_Redeem() public {
        uint256 depositAmount = 1000 * 10**6;

        vm.prank(user1);
        uint256 shares = vault.deposit(depositAmount, user1);

        uint256 initialBalance = asset.balanceOf(user1);

        // Redeem half of shares
        uint256 sharesToRedeem = shares / 2;
        vm.prank(user1);
        uint256 assets = vault.redeem(sharesToRedeem, user1, user1);

        assertGt(asset.balanceOf(user1), initialBalance);
        assertGt(assets, 0);
    }

    function test_Redeem_RevertsOnZeroShares() public {
        vm.prank(user1);
        vm.expectRevert(SavingsVault.InvalidAmount.selector);
        vault.redeem(0, user1, user1);
    }

    function test_Redeem_RevertsOnInsufficientShares() public {
        uint256 depositAmount = 1000 * 10**6;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 excessShares = 2000 * 10**6;

        vm.prank(user1);
        vm.expectRevert();
        vault.redeem(excessShares, user1, user1);
    }

    // ============ WithdrawAll Tests ============

    function test_WithdrawAll() public {
        uint256 depositAmount = 1000 * 10**6;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 initialBalance = asset.balanceOf(user1);

        vm.prank(user1);
        uint256 assets = vault.withdrawAll();

        assertEq(vault.balanceOf(user1), 0);
        assertGt(asset.balanceOf(user1), initialBalance);
        assertGt(assets, 0);
    }

    function test_WithdrawAll_RevertsOnZeroBalance() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.withdrawAll();
    }

    // ============ Interest Accrual Tests ============

    function test_AccrueInterest() public {
        uint256 depositAmount = 10000 * 10**6; // 10k USDC

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 initialAssets = vault.totalAssets();

        // Advance time by 1 year
        vm.warp(block.timestamp + 365 days);

        // Accrue interest
        vault.accrueInterest();

        uint256 finalAssets = vault.totalAssets();

        // Should have earned approximately 5% interest
        assertGt(finalAssets, initialAssets);

        // Check interest is roughly 5% (allowing for small rounding differences)
        uint256 expectedInterest = (depositAmount * INITIAL_APY) / 10000;
        uint256 actualInterest = finalAssets - initialAssets;

        assertApproxEqRel(actualInterest, expectedInterest, 0.01e18); // 1% tolerance
    }

    function test_AccrueInterest_EmitsEvent() public {
        uint256 depositAmount = 10000 * 10**6;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        vm.warp(block.timestamp + 365 days);

        vm.expectEmit(false, false, false, false);
        emit InterestAccrued(0, 0);
        vault.accrueInterest();
    }

    function test_AccrueInterest_NoInterestWithZeroAssets() public {
        uint256 assetsBefore = vault.totalAssets();

        vm.warp(block.timestamp + 365 days);
        vault.accrueInterest();

        uint256 assetsAfter = vault.totalAssets();

        assertEq(assetsBefore, assetsAfter);
    }

    // ============ APY Tests ============

    function test_GetAPY() public {
        assertEq(vault.getAPY(), INITIAL_APY);
    }

    function test_SetAPY() public {
        uint256 newAPY = 750; // 7.5%

        vm.expectEmit(false, false, false, true);
        emit APYUpdated(INITIAL_APY, newAPY);

        vault.setAPY(newAPY);

        assertEq(vault.baseAPY(), newAPY);
        assertEq(vault.getAPY(), newAPY);
    }

    function test_SetAPY_RevertsOnZero() public {
        vm.expectRevert(SavingsVault.InvalidAPY.selector);
        vault.setAPY(0);
    }

    function test_SetAPY_RevertsOnTooHigh() public {
        vm.expectRevert(SavingsVault.InvalidAPY.selector);
        vault.setAPY(10001);
    }

    function test_SetAPY_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vault.setAPY(750);
    }

    // ============ User Yield Tests ============

    function test_GetUserYield() public {
        uint256 depositAmount = 10000 * 10**6;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Initial yield should be 0
        assertEq(vault.getUserYield(user1), 0);

        // Advance time and accrue interest
        vm.warp(block.timestamp + 365 days);
        vault.accrueInterest();

        // Should have some yield now
        uint256 yield = vault.getUserYield(user1);
        assertGt(yield, 0);
    }

    function test_GetUserYield_ZeroForNoDeposit() public {
        assertEq(vault.getUserYield(user1), 0);
    }

    // ============ Credit Boost Tests ============

    function test_GetCreditBoost_NewUser() public {
        assertEq(vault.getCreditBoost(user1), 0);
    }

    function test_GetCreditBoost_WithDeposit() public {
        uint256 depositAmount = 10000 * 10**6;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Should have some boost immediately
        uint256 boost = vault.getCreditBoost(user1);
        assertGt(boost, 0);
    }

    function test_GetCreditBoost_IncreasesWithTime() public {
        uint256 depositAmount = 10000 * 10**6;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        uint256 initialBoost = vault.getCreditBoost(user1);

        // Advance time
        vm.warp(block.timestamp + 90 days);

        uint256 laterBoost = vault.getCreditBoost(user1);

        assertGt(laterBoost, initialBoost);
    }

    function test_GetCreditBoost_IncreasesWithAmount() public {
        uint256 smallDeposit = 1000 * 10**6;
        uint256 largeDeposit = 50000 * 10**6;

        // User1 deposits small amount
        vm.prank(user1);
        vault.deposit(smallDeposit, user1);

        // User2 deposits large amount
        vm.prank(user2);
        vault.deposit(largeDeposit, user2);

        uint256 boost1 = vault.getCreditBoost(user1);
        uint256 boost2 = vault.getCreditBoost(user2);

        assertGt(boost2, boost1);
    }

    function test_GetCreditBoost_MaxBoost() public {
        uint256 largeDeposit = 100000 * 10**6; // 100k USDC

        vm.prank(user1);
        vault.deposit(largeDeposit, user1);

        // Advance time to max boost period
        vm.warp(block.timestamp + 365 days);

        uint256 boost = vault.getCreditBoost(user1);

        // Boost should be capped at MAX_CREDIT_BOOST (50)
        assertLe(boost, 50);
    }

    // ============ Credit Oracle Integration Tests ============

    function test_UpdateCreditScore() public {
        uint256 depositAmount = 10000 * 10**6;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Should update credit score
        vault.updateCreditScore(user1);

        // Check oracle was called
        assertTrue(creditOracle.updateCalled(user1));
    }

    function test_SetCreditOracle() public {
        MockCreditOracle newOracle = new MockCreditOracle();

        vm.expectEmit(true, true, false, true);
        emit CreditOracleUpdated(address(creditOracle), address(newOracle));

        vault.setCreditOracle(address(newOracle));

        assertEq(vault.creditOracle(), address(newOracle));
    }

    function test_SetCreditOracle_RevertsOnZeroAddress() public {
        vm.expectRevert(SavingsVault.InvalidAddress.selector);
        vault.setCreditOracle(address(0));
    }

    function test_SetCreditOracle_RevertsIfNotOwner() public {
        MockCreditOracle newOracle = new MockCreditOracle();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vault.setCreditOracle(address(newOracle));
    }

    // ============ ERC-4626 Compliance Tests ============

    function test_TotalAssets() public {
        assertEq(vault.totalAssets(), 0);

        uint256 depositAmount = 1000 * 10**6;

        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_TotalShares() public {
        assertEq(vault.totalShares(), 0);

        uint256 depositAmount = 1000 * 10**6;

        vm.prank(user1);
        uint256 shares = vault.deposit(depositAmount, user1);

        assertEq(vault.totalShares(), shares);
    }

    function test_ConvertToShares() public {
        uint256 assets = 1000 * 10**6;
        uint256 shares = vault.convertToShares(assets);

        assertGt(shares, 0);
    }

    function test_ConvertToAssets() public {
        uint256 depositAmount = 1000 * 10**6;

        vm.prank(user1);
        uint256 shares = vault.deposit(depositAmount, user1);

        uint256 assets = vault.convertToAssets(shares);

        assertEq(assets, depositAmount);
    }

    // ============ Integration Tests ============

    function test_FullLifecycle() public {
        uint256 depositAmount = 10000 * 10**6;

        // User1 deposits
        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Advance time
        vm.warp(block.timestamp + 90 days);

        // User2 deposits (different amount)
        vm.prank(user2);
        vault.deposit(depositAmount / 2, user2);

        // Advance time significantly to accrue interest for both users
        vm.warp(block.timestamp + 180 days);
        vault.accrueInterest();

        // Check yields
        uint256 yield1 = vault.getUserYield(user1);
        uint256 yield2 = vault.getUserYield(user2);

        assertGt(yield1, 0);
        assertGt(yield2, 0);
        assertGt(yield1, yield2); // User1 should have more yield

        // Check credit boosts
        uint256 boost1 = vault.getCreditBoost(user1);
        uint256 boost2 = vault.getCreditBoost(user2);

        assertGt(boost1, 0);
        assertGt(boost2, 0);
        assertGt(boost1, boost2); // User1 should have higher boost

        // User1 withdraws all
        vm.prank(user1);
        vault.withdrawAll();

        assertEq(vault.balanceOf(user1), 0);
        assertGt(vault.balanceOf(user2), 0);
    }
}

/**
 * @title MockERC20
 * @notice Mock ERC20 token for testing
 */
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

/**
 * @title MockCreditOracle
 * @notice Mock CreditOracle for testing
 */
contract MockCreditOracle {
    mapping(address => bool) public updateCalled;

    function updateSavingsBalance(
        address user,
        uint256 /* newBalance */,
        uint256 /* depositAmount */
    ) external {
        updateCalled[user] = true;
    }
}
