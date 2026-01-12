// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ILendingPool
 * @notice Interface for the lending pool with dynamic collateral ratios
 */
interface ILendingPool {
    // Events
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, address indexed token, uint256 amount, uint256 collateralRatio);
    event Repay(address indexed user, address indexed token, uint256 amount);
    event Liquidation(
        address indexed borrower,
        address indexed liquidator,
        address indexed collateralToken,
        uint256 collateralAmount,
        uint256 debtRepaid
    );
    event CollateralRatioUpdated(address indexed user, uint256 oldRatio, uint256 newRatio);

    // Errors
    error InsufficientCollateral(uint256 required, uint256 provided);
    error BorrowLimitExceeded(uint256 limit, uint256 requested);
    error PositionNotLiquidatable(uint256 healthFactor);
    error InvalidToken(address token);
    error TransferFailed();

    // Structs
    struct UserPosition {
        uint256 collateralAmount;
        uint256 borrowedAmount;
        uint256 collateralRatio;
        uint256 lastUpdateTime;
        uint256 accruedInterest;
    }

    // Core lending functions
    function depositCollateral(address token, uint256 amount) external;
    function withdrawCollateral(address token, uint256 amount) external;
    function borrow(address token, uint256 amount) external;
    function repay(address token, uint256 amount) external;
    function liquidate(address borrower, address collateralToken, uint256 debtAmount) external;

    // View functions
    function getUserPosition(address user, address token) external view returns (UserPosition memory);
    function getHealthFactor(address user, address token) external view returns (uint256);
    function getMaxBorrowAmount(address user, address token) external view returns (uint256);
    function getCollateralRatio(address user) external view returns (uint256);
    function calculateInterest(address user, address token) external view returns (uint256);
    function isLiquidatable(address user, address token) external view returns (bool);

    // Credit-based functions
    function updateUserCollateralRatio(address user) external;
    function getDynamicCollateralRatio(uint256 creditScore) external pure returns (uint256);

    // Configuration
    function setInterestRate(address token, uint256 rate) external;
    function setSupportedToken(address token, bool supported) external;
    function setLiquidationThreshold(uint256 threshold) external;
}
