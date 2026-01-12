// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CreditScore
 * @notice Library for credit score calculations and tier mappings
 */
library CreditScore {
    // Score constants
    uint256 public constant MIN_SCORE = 300;
    uint256 public constant MAX_SCORE = 850;
    uint256 public constant SCORE_RANGE = MAX_SCORE - MIN_SCORE; // 550

    // Tier thresholds
    uint256 public constant PLATINUM_THRESHOLD = 750;
    uint256 public constant GOLD_THRESHOLD = 650;
    uint256 public constant SILVER_THRESHOLD = 550;

    // Collateral ratio constants (in basis points, 10000 = 100%)
    uint256 public constant PLATINUM_COLLATERAL = 11000; // 110%
    uint256 public constant GOLD_COLLATERAL = 13000;     // 130%
    uint256 public constant SILVER_COLLATERAL = 15000;   // 150%
    uint256 public constant BRONZE_COLLATERAL = 20000;   // 200%

    /**
     * @notice Get credit tier name from score
     */
    function getTierName(uint256 score) internal pure returns (string memory) {
        if (score >= PLATINUM_THRESHOLD) return "Platinum";
        if (score >= GOLD_THRESHOLD) return "Gold";
        if (score >= SILVER_THRESHOLD) return "Silver";
        return "Bronze";
    }

    /**
     * @notice Get collateral ratio based on credit score
     * @param score Credit score (300-850)
     * @return Collateral ratio in basis points (11000 = 110%)
     */
    function getCollateralRatio(uint256 score) internal pure returns (uint256) {
        if (score >= PLATINUM_THRESHOLD) return PLATINUM_COLLATERAL;
        if (score >= GOLD_THRESHOLD) return GOLD_COLLATERAL;
        if (score >= SILVER_THRESHOLD) return SILVER_COLLATERAL;
        return BRONZE_COLLATERAL;
    }

    /**
     * @notice Calculate max borrow amount based on collateral and credit score
     * @param collateralValue Total collateral value in USD
     * @param creditScore User's credit score
     * @return Max borrow amount in USD
     */
    function calculateMaxBorrow(
        uint256 collateralValue,
        uint256 creditScore
    ) internal pure returns (uint256) {
        uint256 collateralRatio = getCollateralRatio(creditScore);
        // maxBorrow = collateral * 10000 / collateralRatio
        return (collateralValue * 10000) / collateralRatio;
    }

    /**
     * @notice Calculate required collateral for borrow amount
     * @param borrowAmount Amount to borrow in USD
     * @param creditScore User's credit score
     * @return Required collateral in USD
     */
    function calculateRequiredCollateral(
        uint256 borrowAmount,
        uint256 creditScore
    ) internal pure returns (uint256) {
        uint256 collateralRatio = getCollateralRatio(creditScore);
        // requiredCollateral = borrowAmount * collateralRatio / 10000
        return (borrowAmount * collateralRatio) / 10000;
    }

    /**
     * @notice Calculate health factor for a position
     * @param collateralValue Total collateral value in USD
     * @param borrowedValue Total borrowed value in USD
     * @param creditScore User's credit score
     * @return Health factor (1e18 = 100%, <1e18 = liquidatable)
     */
    function calculateHealthFactor(
        uint256 collateralValue,
        uint256 borrowedValue,
        uint256 creditScore
    ) internal pure returns (uint256) {
        if (borrowedValue == 0) return type(uint256).max;

        uint256 collateralRatio = getCollateralRatio(creditScore);
        // healthFactor = (collateralValue * 10000) / (borrowedValue * collateralRatio)
        // Multiply by 1e18 for precision
        return (collateralValue * 10000 * 1e18) / (borrowedValue * collateralRatio);
    }

    /**
     * @notice Check if position is liquidatable
     * @param healthFactor Position health factor
     * @return True if health factor < 1.0 (1e18)
     */
    function isLiquidatable(uint256 healthFactor) internal pure returns (bool) {
        return healthFactor < 1e18;
    }

    /**
     * @notice Validate credit score is within valid range
     */
    function isValidScore(uint256 score) internal pure returns (bool) {
        return score >= MIN_SCORE && score <= MAX_SCORE;
    }

    /**
     * @notice Normalize score to valid range
     */
    function normalizeScore(uint256 score) internal pure returns (uint256) {
        if (score < MIN_SCORE) return MIN_SCORE;
        if (score > MAX_SCORE) return MAX_SCORE;
        return score;
    }

    /**
     * @notice Calculate score percentage (0-100)
     */
    function getScorePercentage(uint256 score) internal pure returns (uint256) {
        if (score <= MIN_SCORE) return 0;
        if (score >= MAX_SCORE) return 100;
        return ((score - MIN_SCORE) * 100) / SCORE_RANGE;
    }

    /**
     * @notice Get tier level (0=Bronze, 1=Silver, 2=Gold, 3=Platinum)
     */
    function getTierLevel(uint256 score) internal pure returns (uint256) {
        if (score >= PLATINUM_THRESHOLD) return 3;
        if (score >= GOLD_THRESHOLD) return 2;
        if (score >= SILVER_THRESHOLD) return 1;
        return 0;
    }

    /**
     * @notice Calculate interest rate discount based on credit score
     * @param baseRate Base interest rate in basis points
     * @param creditScore User's credit score
     * @return Discounted interest rate in basis points
     */
    function applyInterestDiscount(
        uint256 baseRate,
        uint256 creditScore
    ) internal pure returns (uint256) {
        uint256 discount;

        if (creditScore >= PLATINUM_THRESHOLD) {
            discount = 50; // 50% discount (0.5%)
        } else if (creditScore >= GOLD_THRESHOLD) {
            discount = 30; // 30% discount (0.3%)
        } else if (creditScore >= SILVER_THRESHOLD) {
            discount = 15; // 15% discount (0.15%)
        } else {
            discount = 0; // No discount
        }

        return baseRate - (baseRate * discount / 100);
    }
}
