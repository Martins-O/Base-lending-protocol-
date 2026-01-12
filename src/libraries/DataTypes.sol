// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DataTypes
 * @notice Common data structures used across the protocol
 */
library DataTypes {
    /**
     * @notice User's credit information
     */
    struct CreditInfo {
        uint256 score;              // Credit score (300-850)
        uint256 tier;               // Tier level (0=Bronze, 1=Silver, 2=Gold, 3=Platinum)
        uint256 collateralRatio;    // Collateral ratio in basis points
        uint256 lastUpdate;         // Last score update timestamp
        bool initialized;           // Whether user has been initialized
    }

    /**
     * @notice Lending position details
     */
    struct LendingPosition {
        uint256 collateralAmount;   // Amount of collateral deposited
        address collateralToken;    // Token used as collateral
        uint256 borrowedAmount;     // Amount borrowed
        address borrowedToken;      // Token borrowed
        uint256 borrowTimestamp;    // When the borrow occurred
        uint256 lastInterestUpdate; // Last time interest was calculated
        uint256 accruedInterest;    // Interest accrued since last update
        uint256 healthFactor;       // Position health (1e18 = 100%)
    }

    /**
     * @notice Savings account details
     */
    struct SavingsAccount {
        uint256 principal;          // Initial deposit amount
        uint256 shares;             // Vault shares owned
        uint256 lastDepositTime;    // Last deposit timestamp
        uint256 totalDeposited;     // Lifetime deposits
        uint256 totalWithdrawn;     // Lifetime withdrawals
        uint256 earnedInterest;     // Total interest earned
    }

    /**
     * @notice Reserve configuration
     */
    struct ReserveConfig {
        address token;              // Token address
        uint8 decimals;             // Token decimals
        bool isActive;              // Whether reserve is active
        bool borrowingEnabled;      // Whether borrowing is enabled
        uint256 baseBorrowRate;     // Base borrow rate in bps
        uint256 optimalUtilization; // Optimal utilization ratio
        uint256 liquidationThreshold; // Liquidation threshold in bps
        uint256 liquidationBonus;   // Liquidation bonus in bps
        address priceOracle;        // Price oracle address
    }

    /**
     * @notice Interest rate model parameters
     */
    struct InterestRateModel {
        uint256 baseRate;           // Base rate when utilization is 0
        uint256 optimalRate;        // Rate at optimal utilization
        uint256 maxRate;            // Max rate at 100% utilization
        uint256 optimalUtilization; // Optimal utilization point (in bps)
    }

    /**
     * @notice Liquidation info
     */
    struct LiquidationInfo {
        address borrower;           // Address being liquidated
        address liquidator;         // Address performing liquidation
        address collateralToken;    // Collateral token seized
        address debtToken;          // Debt token repaid
        uint256 collateralAmount;   // Amount of collateral seized
        uint256 debtAmount;         // Amount of debt repaid
        uint256 bonus;              // Liquidation bonus
        uint256 timestamp;          // Liquidation timestamp
    }

    /**
     * @notice Payment record for credit history
     */
    struct PaymentRecord {
        uint256 amount;             // Payment amount
        uint256 timestamp;          // Payment timestamp
        uint8 status;               // 0=OnTime, 1=Late, 2=Default
        uint256 daysLate;           // Number of days late
        address token;              // Token used for payment
    }

    /**
     * @notice Asset diversity tracking
     */
    struct AssetUsage {
        address token;              // Token address
        uint256 firstUsed;          // First usage timestamp
        uint256 totalVolume;        // Total volume transacted
        uint256 transactionCount;   // Number of transactions
    }

    /**
     * @notice Protocol statistics
     */
    struct ProtocolStats {
        uint256 totalValueLocked;   // Total value locked in protocol
        uint256 totalBorrowed;      // Total amount borrowed
        uint256 totalCollateral;    // Total collateral deposited
        uint256 averageCreditScore; // Average credit score of users
        uint256 totalUsers;         // Total number of users
        uint256 totalLiquidations;  // Total liquidations performed
    }

    /**
     * @notice Time period for calculations
     */
    struct TimePeriod {
        uint256 start;              // Period start timestamp
        uint256 end;                // Period end timestamp
        uint256 duration;           // Duration in seconds
    }

    /**
     * @notice Price information
     */
    struct PriceData {
        uint256 price;              // Price in USD (18 decimals)
        uint256 timestamp;          // Price timestamp
        uint8 decimals;             // Price decimals
        bool isValid;               // Whether price is valid
    }
}
