// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICreditOracle
 * @notice Interface for the Credit Oracle contract
 */
interface ICreditOracle {
    // Events
    event CreditScoreUpdated(address indexed user, uint256 newScore);
    event PaymentRecorded(address indexed user, uint256 amount, uint8 status, uint256 daysLate);
    event SavingsUpdated(address indexed user, uint256 newBalance);
    event AssetDiversityIncreased(address indexed user, address indexed asset);
    event LiquidityProvisionUpdated(address indexed user, uint256 amount);
    event AuthorizedUpdaterSet(address indexed updater, bool authorized);

    // Structs
    enum PaymentStatus {
        OnTime,
        Late,
        Default
    }

    struct UserCreditData {
        uint256 accountCreationTime;
        uint256 totalPayments;
        uint256 onTimePayments;
        uint256 latePayments;
        uint256 defaults;
        uint256 totalSavingsDeposited;
        uint256 savingsTimeWeightedBalance;
        uint256 lastSavingsUpdateTime;
        uint256 currentSavingsBalance;
        uint256 uniqueAssetsUsed;
        uint256 liquidityProvided;
        uint256 lastScoreUpdate;
        uint256 cachedScore;
    }

    // Core functions
    function initializeUser(address user) external;
    function getCreditScore(address user) external view returns (uint256);
    function updateCreditScore(address user) external;

    // Payment tracking
    function recordPayment(address user, uint256 amount, uint256 daysLate) external;

    // Savings tracking
    function updateSavingsBalance(address user, uint256 newBalance, uint256 depositAmount) external;

    // Asset diversity
    function trackAssetUsage(address user, address asset) external;

    // Liquidity provision
    function updateLiquidityProvision(address user, uint256 amount) external;

    // View functions
    function getCreditBreakdown(address user) external view returns (
        uint256 totalScore,
        uint256 paymentScore,
        uint256 savingsScore,
        uint256 timeScore,
        uint256 diversityScore,
        uint256 liquidityScore
    );

    function getUserCreditData(address user) external view returns (UserCreditData memory);

    // Admin functions
    function setAuthorizedUpdater(address updater, bool authorized) external;
}
