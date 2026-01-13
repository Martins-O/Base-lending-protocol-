// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PriceOracle.sol";

/**
 * @title PriceOracleTest
 * @notice Comprehensive test suite for PriceOracle contract
 */
contract PriceOracleTest is Test {
    PriceOracle public oracle;
    address public owner;
    address public user;

    // Mock token addresses
    address public constant WETH = address(0x1);
    address public constant USDC = address(0x2);
    address public constant WBTC = address(0x3);

    // Mock Chainlink price feed
    MockAggregatorV3 public ethUsdFeed;
    MockAggregatorV3 public usdcUsdFeed;
    MockAggregatorV3 public btcUsdFeed;

    // Events to test
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);
    event MaxStalePeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event ManualPriceSet(address indexed token, uint256 price);

    function setUp() public {
        owner = address(this);
        user = address(0x123);

        // Deploy oracle
        oracle = new PriceOracle(owner);

        // Deploy mock price feeds
        ethUsdFeed = new MockAggregatorV3(8); // ETH/USD with 8 decimals
        usdcUsdFeed = new MockAggregatorV3(8); // USDC/USD with 8 decimals
        btcUsdFeed = new MockAggregatorV3(8); // BTC/USD with 8 decimals

        // Set initial prices
        ethUsdFeed.setPrice(2000_00000000); // $2000.00
        usdcUsdFeed.setPrice(1_00000000); // $1.00
        btcUsdFeed.setPrice(50000_00000000); // $50000.00
    }

    // ============ Constructor Tests ============

    function test_Constructor() public {
        assertEq(oracle.owner(), owner);
        assertEq(oracle.maxStalePeriod(), 1 hours);
    }

    // ============ SetPriceFeed Tests ============

    function test_SetPriceFeed() public {
        vm.expectEmit(true, true, false, true);
        emit PriceFeedUpdated(WETH, address(ethUsdFeed));

        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        assertEq(oracle.getPriceFeed(WETH), address(ethUsdFeed));
    }

    function test_SetPriceFeed_RevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        oracle.setPriceFeed(WETH, address(ethUsdFeed));
    }

    function test_SetPriceFeed_RevertsOnZeroTokenAddress() public {
        vm.expectRevert(PriceOracle.ZeroAddress.selector);
        oracle.setPriceFeed(address(0), address(ethUsdFeed));
    }

    function test_SetPriceFeed_RevertsOnZeroPriceFeedAddress() public {
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.InvalidPriceFeed.selector, address(0)));
        oracle.setPriceFeed(WETH, address(0));
    }

    function test_SetPriceFeed_RevertsOnInvalidPriceFeed() public {
        address invalidFeed = address(0x999);
        vm.expectRevert(); // Generic revert for non-contract call
        oracle.setPriceFeed(WETH, invalidFeed);
    }

    // ============ GetPrice Tests ============

    function test_GetPrice() public {
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        uint256 price = oracle.getPrice(WETH);

        // Expected: 2000.00 * 10^18 (normalized to 18 decimals)
        assertEq(price, 2000 * 10**18);
    }

    function test_GetPrice_RevertsOnZeroAddress() public {
        vm.expectRevert(PriceOracle.ZeroAddress.selector);
        oracle.getPrice(address(0));
    }

    function test_GetPrice_RevertsWhenPriceFeedNotSet() public {
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.PriceFeedNotSet.selector, WETH));
        oracle.getPrice(WETH);
    }

    function test_GetPrice_RevertsOnNegativePrice() public {
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        ethUsdFeed.setPrice(-1);

        vm.expectRevert(abi.encodeWithSelector(PriceOracle.InvalidPrice.selector, WETH, int256(-1)));
        oracle.getPrice(WETH);
    }

    function test_GetPrice_RevertsOnZeroPrice() public {
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        ethUsdFeed.setPrice(0);

        vm.expectRevert(abi.encodeWithSelector(PriceOracle.InvalidPrice.selector, WETH, int256(0)));
        oracle.getPrice(WETH);
    }

    function test_GetPrice_RevertsOnStalePrice() public {
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        // Advance time beyond stale period
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(abi.encodeWithSelector(PriceOracle.StalePrice.selector, WETH, block.timestamp - 2 hours));
        oracle.getPrice(WETH);
    }

    function test_GetPrice_WithDifferentDecimals() public {
        // Create feed with 6 decimals (like some feeds)
        MockAggregatorV3 feed6Decimals = new MockAggregatorV3(6);
        feed6Decimals.setPrice(2000_000000); // $2000.00 with 6 decimals

        oracle.setPriceFeed(WETH, address(feed6Decimals));

        uint256 price = oracle.getPrice(WETH);

        // Should normalize to 18 decimals
        assertEq(price, 2000 * 10**18);
    }

    function test_GetPrice_WithHigherDecimals() public {
        // Create feed with 20 decimals
        MockAggregatorV3 feed20Decimals = new MockAggregatorV3(20);
        feed20Decimals.setPrice(2000 * 10**20); // $2000.00 with 20 decimals

        oracle.setPriceFeed(WETH, address(feed20Decimals));

        uint256 price = oracle.getPrice(WETH);

        // Should normalize to 18 decimals
        assertEq(price, 2000 * 10**18);
    }

    // ============ GetPriceInUSD Tests ============

    function test_GetPriceInUSD() public {
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        // 1 WETH = $2000
        uint256 usdValue = oracle.getPriceInUSD(WETH, 1 ether);

        assertEq(usdValue, 2000 ether);
    }

    function test_GetPriceInUSD_PartialAmount() public {
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        // 0.5 WETH = $1000
        uint256 usdValue = oracle.getPriceInUSD(WETH, 0.5 ether);

        assertEq(usdValue, 1000 ether);
    }

    function test_GetPriceInUSD_ZeroAmount() public {
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        uint256 usdValue = oracle.getPriceInUSD(WETH, 0);

        assertEq(usdValue, 0);
    }

    function test_GetPriceInUSD_RevertsOnZeroAddress() public {
        vm.expectRevert(PriceOracle.ZeroAddress.selector);
        oracle.getPriceInUSD(address(0), 1 ether);
    }

    // ============ GetLatestPrice Tests ============

    function test_GetLatestPrice() public {
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        (uint256 price, uint256 timestamp, uint256 decimals) = oracle.getLatestPrice(WETH);

        assertEq(price, 2000 * 10**18);
        assertEq(timestamp, block.timestamp);
        assertEq(decimals, 18);
    }

    function test_GetLatestPrice_RevertsOnZeroAddress() public {
        vm.expectRevert(PriceOracle.ZeroAddress.selector);
        oracle.getLatestPrice(address(0));
    }

    // ============ Manual Price Tests ============

    function test_SetManualPrice() public {
        uint256 manualPrice = 2500 * 10**18; // $2500

        vm.expectEmit(true, false, false, true);
        emit ManualPriceSet(WETH, manualPrice);

        oracle.setManualPrice(WETH, manualPrice);

        assertTrue(oracle.isUsingManualPrice(WETH));
    }

    function test_SetManualPrice_OverridesChainlinkFeed() public {
        // Set Chainlink feed first
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        uint256 chainlinkPrice = oracle.getPrice(WETH);
        assertEq(chainlinkPrice, 2000 * 10**18);

        // Set manual price
        uint256 manualPrice = 2500 * 10**18;
        oracle.setManualPrice(WETH, manualPrice);

        uint256 price = oracle.getPrice(WETH);
        assertEq(price, manualPrice);
        assertTrue(oracle.isUsingManualPrice(WETH));
    }

    function test_SetManualPrice_RevertsOnZeroAddress() public {
        vm.expectRevert(PriceOracle.ZeroAddress.selector);
        oracle.setManualPrice(address(0), 2000 * 10**18);
    }

    function test_SetManualPrice_RevertsOnZeroPrice() public {
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.InvalidPrice.selector, WETH, int256(0)));
        oracle.setManualPrice(WETH, 0);
    }

    function test_DisableManualPrice() public {
        // Set manual price
        oracle.setManualPrice(WETH, 2500 * 10**18);
        assertTrue(oracle.isUsingManualPrice(WETH));

        // Disable manual price
        oracle.disableManualPrice(WETH);
        assertFalse(oracle.isUsingManualPrice(WETH));
    }

    function test_DisableManualPrice_RevertsOnZeroAddress() public {
        vm.expectRevert(PriceOracle.ZeroAddress.selector);
        oracle.disableManualPrice(address(0));
    }

    function test_SetPriceFeed_DisablesManualPrice() public {
        // Set manual price first
        oracle.setManualPrice(WETH, 2500 * 10**18);
        assertTrue(oracle.isUsingManualPrice(WETH));

        // Set price feed - should disable manual price
        oracle.setPriceFeed(WETH, address(ethUsdFeed));
        assertFalse(oracle.isUsingManualPrice(WETH));
    }

    // ============ MaxStalePeriod Tests ============

    function test_SetMaxStalePeriod() public {
        uint256 newPeriod = 2 hours;

        vm.expectEmit(false, false, false, true);
        emit MaxStalePeriodUpdated(1 hours, newPeriod);

        oracle.setMaxStalePeriod(newPeriod);

        assertEq(oracle.maxStalePeriod(), newPeriod);
    }

    function test_SetMaxStalePeriod_RevertsOnZero() public {
        vm.expectRevert(PriceOracle.InvalidStalePeriod.selector);
        oracle.setMaxStalePeriod(0);
    }

    function test_SetMaxStalePeriod_RevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        oracle.setMaxStalePeriod(2 hours);
    }

    // ============ IsPriceStale Tests ============

    function test_IsPriceStale_FreshPrice() public {
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        bool isStale = oracle.isPriceStale(WETH);

        assertFalse(isStale);
    }

    function test_IsPriceStale_StalePrice() public {
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        // Advance time beyond stale period
        vm.warp(block.timestamp + 2 hours);

        bool isStale = oracle.isPriceStale(WETH);

        assertTrue(isStale);
    }

    function test_IsPriceStale_NoPriceFeed() public {
        bool isStale = oracle.isPriceStale(WETH);

        assertTrue(isStale);
    }

    function test_IsPriceStale_ManualPriceNeverStale() public {
        oracle.setManualPrice(WETH, 2000 * 10**18);

        // Advance time significantly
        vm.warp(block.timestamp + 365 days);

        bool isStale = oracle.isPriceStale(WETH);

        assertFalse(isStale);
    }

    function test_IsPriceStale_ZeroAddress() public {
        bool isStale = oracle.isPriceStale(address(0));

        assertFalse(isStale);
    }

    // ============ Integration Tests ============

    function test_MultipleTokens() public {
        // Set up multiple price feeds
        oracle.setPriceFeed(WETH, address(ethUsdFeed));
        oracle.setPriceFeed(USDC, address(usdcUsdFeed));
        oracle.setPriceFeed(WBTC, address(btcUsdFeed));

        // Get prices
        uint256 ethPrice = oracle.getPrice(WETH);
        uint256 usdcPrice = oracle.getPrice(USDC);
        uint256 btcPrice = oracle.getPrice(WBTC);

        assertEq(ethPrice, 2000 * 10**18);
        assertEq(usdcPrice, 1 * 10**18);
        assertEq(btcPrice, 50000 * 10**18);
    }

    function test_PriceUpdate() public {
        oracle.setPriceFeed(WETH, address(ethUsdFeed));

        uint256 initialPrice = oracle.getPrice(WETH);
        assertEq(initialPrice, 2000 * 10**18);

        // Update feed price
        ethUsdFeed.setPrice(2500_00000000); // $2500.00

        uint256 newPrice = oracle.getPrice(WETH);
        assertEq(newPrice, 2500 * 10**18);
    }

    function test_ComplexScenario() public {
        // Setup
        oracle.setPriceFeed(WETH, address(ethUsdFeed));
        oracle.setMaxStalePeriod(30 minutes);

        uint256 startTime = block.timestamp;

        // Check initial state
        assertEq(oracle.getPrice(WETH), 2000 * 10**18);
        assertFalse(oracle.isPriceStale(WETH));

        // Time passes but within stale period
        vm.warp(startTime + 20 minutes);
        assertFalse(oracle.isPriceStale(WETH));

        // Price becomes stale
        vm.warp(startTime + 40 minutes); // Total: 40 minutes (> 30 min threshold)
        assertTrue(oracle.isPriceStale(WETH));

        // Set manual price as fallback
        oracle.setManualPrice(WETH, 2100 * 10**18);

        // Should use manual price now
        assertEq(oracle.getPrice(WETH), 2100 * 10**18);
        assertFalse(oracle.isPriceStale(WETH)); // Manual prices never stale

        // Chainlink feed updates
        ethUsdFeed.updateTimestamp();

        // Disable manual price to use Chainlink again
        oracle.disableManualPrice(WETH);

        assertEq(oracle.getPrice(WETH), 2000 * 10**18);
        assertFalse(oracle.isPriceStale(WETH));
    }
}

/**
 * @title MockAggregatorV3
 * @notice Mock Chainlink price feed for testing
 */
contract MockAggregatorV3 {
    uint8 private _decimals;
    int256 private _price;
    uint256 private _updatedAt;
    uint80 private _roundId;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }

    function setPrice(int256 price) external {
        _price = price;
        _updatedAt = block.timestamp;
        _roundId++;
    }

    function updateTimestamp() external {
        _updatedAt = block.timestamp;
        _roundId++;
    }
}
