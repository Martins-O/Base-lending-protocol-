// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ISavingsVault
 * @notice Interface for high-yield savings vault that builds credit
 */
interface ISavingsVault {
    // Events
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);
    event InterestAccrued(uint256 totalInterest, uint256 newRate);
    event CreditScoreBoosted(address indexed user, uint256 oldScore, uint256 newScore);

    // Errors
    error InsufficientBalance(uint256 requested, uint256 available);
    error InvalidAmount();
    error TransferFailed();

    // Core functions
    function deposit(uint256 amount) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 amount);
    function withdrawAll() external returns (uint256 amount);

    // View functions
    function balanceOf(address user) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function totalShares() external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function getAPY() external view returns (uint256);
    function getUserYield(address user) external view returns (uint256);

    // Credit integration
    function getCreditBoost(address user) external view returns (uint256);
    function updateCreditScore(address user) external;
}
