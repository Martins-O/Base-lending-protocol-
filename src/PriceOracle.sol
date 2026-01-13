// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AggregatorV3Interface
 * @notice Chainlink Aggregator Interface
 */
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/**
 * @title PriceOracle
 * @notice Chainlink-based price oracle for Base network
 * @dev Provides USD prices for various tokens using Chainlink price feeds
 *
 * Features:
 * - Multi-token price feed support
 * - Stale price detection
 * - Fallback manual price mechanism
 * - Configurable staleness threshold
 *
 * Base Network Chainlink Price Feeds:
 * - ETH/USD: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70
 * - USDC/USD: 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B
 * - USDT/USD: (Not yet available on Base)
 * - BTC/USD: 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F
 */
contract PriceOracle is Ownable {

    // Events
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);
    event MaxStalePeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event ManualPriceSet(address indexed token, uint256 price);

    // Errors
    error PriceFeedNotSet(address token);
    error StalePrice(address token, uint256 lastUpdate);
    error InvalidPrice(address token, int256 price);
    error InvalidPriceFeed(address priceFeed);
    error ZeroAddress();
    error InvalidStalePeriod();

    // State variables
    mapping(address => address) public priceFeeds; // token => Chainlink price feed
    mapping(address => uint256) public manualPrices; // token => manual override price
    mapping(address => bool) public useManualPrice; // token => use manual price flag

    uint256 public maxStalePeriod; // Maximum allowed age for price data (seconds)

    uint8 private constant PRICE_DECIMALS = 18; // Normalize all prices to 18 decimals

    /**
     * @notice Constructor
     * @param initialOwner Owner address
     */
    constructor(address initialOwner) Ownable(initialOwner) {
        maxStalePeriod = 1 hours; // Default: 1 hour staleness threshold
    }

    /**
     * @notice Get the current price of a token in USD
     * @param token Token address
     * @return price Price in USD (18 decimals)
     */
    function getPrice(address token) external view returns (uint256) {
        if (token == address(0)) revert ZeroAddress();

        // Check if manual price override is set
        if (useManualPrice[token]) {
            return manualPrices[token];
        }

        address feed = priceFeeds[token];
        if (feed == address(0)) revert PriceFeedNotSet(token);

        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // Validate price data
        if (answer <= 0) revert InvalidPrice(token, answer);
        if (updatedAt == 0) revert StalePrice(token, 0);
        if (answeredInRound < roundId) revert StalePrice(token, updatedAt);

        // Check if price is stale
        if (block.timestamp - updatedAt > maxStalePeriod) {
            revert StalePrice(token, updatedAt);
        }

        // Normalize price to 18 decimals
        uint8 feedDecimals = priceFeed.decimals();
        uint256 price = uint256(answer);

        if (feedDecimals < PRICE_DECIMALS) {
            price = price * (10 ** (PRICE_DECIMALS - feedDecimals));
        } else if (feedDecimals > PRICE_DECIMALS) {
            price = price / (10 ** (feedDecimals - PRICE_DECIMALS));
        }

        return price;
    }

    /**
     * @notice Get the USD value of a token amount
     * @param token Token address
     * @param amount Token amount (in token's native decimals)
     * @return usdValue USD value (18 decimals)
     */
    function getPriceInUSD(address token, uint256 amount) external view returns (uint256) {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) return 0;

        // Check if manual price override is set
        uint256 price;
        if (useManualPrice[token]) {
            price = manualPrices[token];
        } else {
            address feed = priceFeeds[token];
            if (feed == address(0)) revert PriceFeedNotSet(token);

            AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);

            (
                uint80 roundId,
                int256 answer,
                ,
                uint256 updatedAt,
                uint80 answeredInRound
            ) = priceFeed.latestRoundData();

            // Validate price data
            if (answer <= 0) revert InvalidPrice(token, answer);
            if (updatedAt == 0) revert StalePrice(token, 0);
            if (answeredInRound < roundId) revert StalePrice(token, updatedAt);

            // Check if price is stale
            if (block.timestamp - updatedAt > maxStalePeriod) {
                revert StalePrice(token, updatedAt);
            }

            // Normalize price to 18 decimals
            uint8 feedDecimals = priceFeed.decimals();
            price = uint256(answer);

            if (feedDecimals < PRICE_DECIMALS) {
                price = price * (10 ** (PRICE_DECIMALS - feedDecimals));
            } else if (feedDecimals > PRICE_DECIMALS) {
                price = price / (10 ** (feedDecimals - PRICE_DECIMALS));
            }
        }

        // Calculate USD value
        // Assumes amount is in token's native decimals (e.g., 18 for WETH, 6 for USDC)
        // Result is in 18 decimals
        return (amount * price) / (10 ** PRICE_DECIMALS);
    }

    /**
     * @notice Get latest price with metadata
     * @param token Token address
     * @return price Price in USD (18 decimals)
     * @return timestamp Last update timestamp
     * @return decimals Price decimals (always 18)
     */
    function getLatestPrice(address token)
        external
        view
        returns (
            uint256 price,
            uint256 timestamp,
            uint256 decimals
        )
    {
        if (token == address(0)) revert ZeroAddress();

        // Check if manual price override is set
        if (useManualPrice[token]) {
            return (manualPrices[token], block.timestamp, PRICE_DECIMALS);
        }

        address feed = priceFeeds[token];
        if (feed == address(0)) revert PriceFeedNotSet(token);

        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // Validate price data
        if (answer <= 0) revert InvalidPrice(token, answer);
        if (updatedAt == 0) revert StalePrice(token, 0);
        if (answeredInRound < roundId) revert StalePrice(token, updatedAt);

        // Check if price is stale
        if (block.timestamp - updatedAt > maxStalePeriod) {
            revert StalePrice(token, updatedAt);
        }

        // Normalize price to 18 decimals
        uint8 feedDecimals = priceFeed.decimals();
        price = uint256(answer);

        if (feedDecimals < PRICE_DECIMALS) {
            price = price * (10 ** (PRICE_DECIMALS - feedDecimals));
        } else if (feedDecimals > PRICE_DECIMALS) {
            price = price / (10 ** (feedDecimals - PRICE_DECIMALS));
        }

        return (price, updatedAt, PRICE_DECIMALS);
    }

    /**
     * @notice Set Chainlink price feed for a token
     * @param token Token address
     * @param priceFeed Chainlink price feed address
     */
    function setPriceFeed(address token, address priceFeed) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (priceFeed == address(0)) revert InvalidPriceFeed(priceFeed);

        // Validate price feed by checking if it implements AggregatorV3Interface
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);
        try feed.latestRoundData() returns (uint80, int256, uint256, uint256, uint80) {
            // Price feed is valid
        } catch {
            revert InvalidPriceFeed(priceFeed);
        }

        priceFeeds[token] = priceFeed;

        // Disable manual price if it was set
        if (useManualPrice[token]) {
            useManualPrice[token] = false;
        }

        emit PriceFeedUpdated(token, priceFeed);
    }

    /**
     * @notice Set manual price override for a token
     * @param token Token address
     * @param price Manual price (18 decimals)
     * @dev Use this as fallback when Chainlink feed is unavailable
     */
    function setManualPrice(address token, uint256 price) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (price == 0) revert InvalidPrice(token, 0);

        manualPrices[token] = price;
        useManualPrice[token] = true;

        emit ManualPriceSet(token, price);
    }

    /**
     * @notice Disable manual price override for a token
     * @param token Token address
     */
    function disableManualPrice(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();

        useManualPrice[token] = false;
    }

    /**
     * @notice Set maximum stale period for price data
     * @param period Maximum stale period in seconds
     */
    function setMaxStalePeriod(uint256 period) external onlyOwner {
        if (period == 0) revert InvalidStalePeriod();

        uint256 oldPeriod = maxStalePeriod;
        maxStalePeriod = period;

        emit MaxStalePeriodUpdated(oldPeriod, period);
    }

    /**
     * @notice Get price feed address for a token
     * @param token Token address
     * @return priceFeed Price feed address
     */
    function getPriceFeed(address token) external view returns (address) {
        return priceFeeds[token];
    }

    /**
     * @notice Check if price is stale
     * @param token Token address
     * @return isStale True if price is stale
     */
    function isPriceStale(address token) external view returns (bool) {
        if (token == address(0)) return false;

        // Manual prices are never stale
        if (useManualPrice[token]) {
            return false;
        }

        address feed = priceFeeds[token];
        if (feed == address(0)) return true;

        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);

        try priceFeed.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (answer <= 0) return true;
            if (updatedAt == 0) return true;
            if (answeredInRound < roundId) return true;
            if (block.timestamp - updatedAt > maxStalePeriod) return true;

            return false;
        } catch {
            return true;
        }
    }

    /**
     * @notice Check if manual price is being used for a token
     * @param token Token address
     * @return isManual True if manual price is active
     */
    function isUsingManualPrice(address token) external view returns (bool) {
        return useManualPrice[token];
    }
}
