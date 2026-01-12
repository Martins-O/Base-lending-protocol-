// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Math
 * @notice Math library for common calculations
 */
library Math {
    uint256 public constant PRECISION = 1e18;
    uint256 public constant PERCENTAGE_FACTOR = 10000; // 100% = 10000 basis points

    /**
     * @notice Calculate percentage of a value
     * @param value The value
     * @param percentage Percentage in basis points (10000 = 100%)
     */
    function percentMul(uint256 value, uint256 percentage) internal pure returns (uint256) {
        return (value * percentage) / PERCENTAGE_FACTOR;
    }

    /**
     * @notice Calculate what percentage one value is of another
     * @param part The part value
     * @param whole The whole value
     * @return Percentage in basis points
     */
    function percentDiv(uint256 part, uint256 whole) internal pure returns (uint256) {
        require(whole != 0, "Math: division by zero");
        return (part * PERCENTAGE_FACTOR) / whole;
    }

    /**
     * @notice Calculate compound interest
     * @param principal Initial principal amount
     * @param ratePerYear Annual interest rate in basis points
     * @param time Time period in seconds
     * @return Final amount with compound interest
     */
    function compoundInterest(
        uint256 principal,
        uint256 ratePerYear,
        uint256 time
    ) internal pure returns (uint256) {
        if (time == 0) return principal;

        // Convert annual rate to per-second rate
        // rate = (1 + ratePerYear/10000)^(time/365days) - 1
        // Approximation: linearInterest for simplicity
        uint256 secondsInYear = 365 days;
        uint256 interest = (principal * ratePerYear * time) / (PERCENTAGE_FACTOR * secondsInYear);

        return principal + interest;
    }

    /**
     * @notice Calculate simple interest
     * @param principal Initial principal amount
     * @param rate Interest rate in basis points
     * @param time Time period in seconds
     * @return Interest amount
     */
    function simpleInterest(
        uint256 principal,
        uint256 rate,
        uint256 time
    ) internal pure returns (uint256) {
        uint256 secondsInYear = 365 days;
        return (principal * rate * time) / (PERCENTAGE_FACTOR * secondsInYear);
    }

    /**
     * @notice Calculate weighted average
     * @param values Array of values
     * @param weights Array of weights
     * @return Weighted average
     */
    function weightedAverage(
        uint256[] memory values,
        uint256[] memory weights
    ) internal pure returns (uint256) {
        require(values.length == weights.length, "Math: length mismatch");
        require(values.length > 0, "Math: empty arrays");

        uint256 sum = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < values.length; i++) {
            sum += values[i] * weights[i];
            totalWeight += weights[i];
        }

        require(totalWeight != 0, "Math: zero total weight");
        return sum / totalWeight;
    }

    /**
     * @notice Calculate minimum of two values
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Calculate maximum of two values
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @notice Calculate average of two values (avoiding overflow)
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
    }

    /**
     * @notice Calculate square root (Babylonian method)
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;

        uint256 z = (x + 1) / 2;
        uint256 y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }

        return y;
    }

    /**
     * @notice Scale value to 18 decimals
     */
    function scaleToDecimals(
        uint256 value,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return value;
        } else if (fromDecimals < toDecimals) {
            return value * (10 ** (toDecimals - fromDecimals));
        } else {
            return value / (10 ** (fromDecimals - toDecimals));
        }
    }

    /**
     * @notice Calculate time-weighted average
     * @param oldValue Previous value
     * @param oldTime Time of previous value
     * @param newValue New value
     * @param newTime Time of new value
     */
    function timeWeightedAverage(
        uint256 oldValue,
        uint256 oldTime,
        uint256 newValue,
        uint256 newTime
    ) internal pure returns (uint256) {
        require(newTime >= oldTime, "Math: invalid time");

        uint256 timeDelta = newTime - oldTime;
        if (timeDelta == 0) return newValue;

        return ((oldValue * oldTime) + (newValue * timeDelta)) / newTime;
    }

    /**
     * @notice Safe multiplication with overflow check
     */
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256) {
        require(denominator != 0, "Math: division by zero");

        // Overflow check
        uint256 result = a * b;
        require(result / a == b, "Math: multiplication overflow");

        return result / denominator;
    }
}
