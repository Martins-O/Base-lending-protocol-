// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPriceOracle
 * @notice Interface for price oracle (Chainlink integration)
 */
interface IPriceOracle {
    // Events
    event PriceFeedUpdated(address indexed token, address indexed priceFeed);
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);

    // Errors
    error PriceFeedNotSet(address token);
    error StalePrice(address token, uint256 lastUpdate);
    error InvalidPrice(address token, int256 price);

    // Core functions
    function getPrice(address token) external view returns (uint256);
    function getPriceInUSD(address token, uint256 amount) external view returns (uint256);
    function getLatestPrice(address token) external view returns (
        uint256 price,
        uint256 timestamp,
        uint256 decimals
    );

    // Admin functions
    function setPriceFeed(address token, address priceFeed) external;
    function setMaxStalePeriod(uint256 period) external;

    // View functions
    function getPriceFeed(address token) external view returns (address);
    function isPriceStale(address token) external view returns (bool);
}
