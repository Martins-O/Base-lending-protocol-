// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CreditOracle
 * @notice Calculates and maintains user credit scores (300-850 range)
 * @dev Multi-factor scoring algorithm with time-weighted calculations
 */
contract CreditOracle is Ownable {
    // Score constants
    uint256 public constant MIN_SCORE = 300;
    uint256 public constant MAX_SCORE = 850;
    uint256 public constant SCORE_RANGE = MAX_SCORE - MIN_SCORE; // 550

    // Weight constants (sum to 100)
    uint256 public constant PAYMENT_HISTORY_WEIGHT = 35;
    uint256 public constant SAVINGS_CONSISTENCY_WEIGHT = 30;
    uint256 public constant TIME_IN_PROTOCOL_WEIGHT = 20;
    uint256 public constant DIVERSITY_WEIGHT = 10;
    uint256 public constant LIQUIDITY_PROVISION_WEIGHT = 5;

    // Time constants
    uint256 public constant PAYMENT_DECAY_PERIOD = 730 days; // 2 years
    uint256 public constant FULL_TIME_BONUS_DAYS = 180 days; // 6 months for max time score

    // Payment history constants
    uint256 public constant ON_TIME_POINTS = 100;
    uint256 public constant LATE_7_30_PENALTY = 20;
    uint256 public constant LATE_30_PLUS_PENALTY = 50;
    uint256 public constant DEFAULT_PENALTY = 100;

    struct PaymentRecord {
        uint256 timestamp;
        uint256 amount;
        PaymentStatus status;
        uint256 daysLate;
    }

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
        uint256 savingsTimeWeightedBalance; // For consistency calculation
        uint256 lastSavingsUpdateTime;
        uint256 currentSavingsBalance;
        uint256 uniqueAssetsUsed; // For diversity score
        uint256 liquidityProvided; // LP tokens staked
        uint256 lastScoreUpdate;
        uint256 cachedScore;
    }

    // Storage
    mapping(address => UserCreditData) public userCreditData;
    mapping(address => PaymentRecord[]) public paymentHistory;
    mapping(address => mapping(address => bool)) public userAssetUsage; // user => asset => used

    // Authorized contracts that can update credit data
    mapping(address => bool) public authorizedUpdaters;

    // Events
    event CreditScoreUpdated(address indexed user, uint256 newScore);
    event PaymentRecorded(address indexed user, uint256 amount, PaymentStatus status, uint256 daysLate);
    event SavingsUpdated(address indexed user, uint256 newBalance);
    event AssetDiversityIncreased(address indexed user, address indexed asset);
    event LiquidityProvisionUpdated(address indexed user, uint256 amount);
    event AuthorizedUpdaterSet(address indexed updater, bool authorized);

    constructor() Ownable(msg.sender) {}

    // Modifiers
    modifier onlyAuthorized() {
        require(authorizedUpdaters[msg.sender], "Not authorized");
        _;
    }

    /**
     * @notice Set authorized updater contracts
     */
    function setAuthorizedUpdater(address updater, bool authorized) external onlyOwner {
        authorizedUpdaters[updater] = authorized;
        emit AuthorizedUpdaterSet(updater, authorized);
    }

    /**
     * @notice Initialize a new user account
     */
    function initializeUser(address user) external onlyAuthorized {
        if (userCreditData[user].accountCreationTime == 0) {
            userCreditData[user].accountCreationTime = block.timestamp;
            userCreditData[user].lastSavingsUpdateTime = block.timestamp;
            userCreditData[user].lastScoreUpdate = block.timestamp;
            userCreditData[user].cachedScore = MIN_SCORE;
        }
    }

    /**
     * @notice Record a payment
     */
    function recordPayment(
        address user,
        uint256 amount,
        uint256 daysLate
    ) external onlyAuthorized {
        UserCreditData storage userData = userCreditData[user];

        PaymentStatus status;
        if (daysLate == 0) {
            status = PaymentStatus.OnTime;
            userData.onTimePayments++;
        } else if (daysLate < 30) {
            status = PaymentStatus.Late;
            userData.latePayments++;
        } else {
            status = PaymentStatus.Default;
            userData.defaults++;
        }

        userData.totalPayments++;

        paymentHistory[user].push(PaymentRecord({
            timestamp: block.timestamp,
            amount: amount,
            status: status,
            daysLate: daysLate
        }));

        emit PaymentRecorded(user, amount, status, daysLate);

        // Update cached score
        _updateCachedScore(user);
    }

    /**
     * @notice Update savings balance (called by SavingsVault)
     */
    function updateSavingsBalance(
        address user,
        uint256 newBalance,
        uint256 depositAmount
    ) external onlyAuthorized {
        UserCreditData storage userData = userCreditData[user];

        // Update time-weighted balance
        uint256 timeDelta = block.timestamp - userData.lastSavingsUpdateTime;
        if (timeDelta > 0) {
            userData.savingsTimeWeightedBalance += userData.currentSavingsBalance * timeDelta;
        }

        userData.currentSavingsBalance = newBalance;
        userData.totalSavingsDeposited += depositAmount;
        userData.lastSavingsUpdateTime = block.timestamp;

        emit SavingsUpdated(user, newBalance);

        // Update cached score
        _updateCachedScore(user);
    }

    /**
     * @notice Track asset usage for diversity score
     */
    function trackAssetUsage(address user, address asset) external onlyAuthorized {
        if (!userAssetUsage[user][asset]) {
            userAssetUsage[user][asset] = true;
            userCreditData[user].uniqueAssetsUsed++;
            emit AssetDiversityIncreased(user, asset);
            _updateCachedScore(user);
        }
    }

    /**
     * @notice Update liquidity provision amount
     */
    function updateLiquidityProvision(address user, uint256 amount) external onlyAuthorized {
        userCreditData[user].liquidityProvided = amount;
        emit LiquidityProvisionUpdated(user, amount);
        _updateCachedScore(user);
    }

    /**
     * @notice Get current credit score for a user
     */
    function getCreditScore(address user) external view returns (uint256) {
        UserCreditData storage userData = userCreditData[user];

        // Return cached score if recently updated (within 1 hour)
        if (block.timestamp - userData.lastScoreUpdate < 1 hours) {
            return userData.cachedScore;
        }

        return _calculateCreditScore(user);
    }

    /**
     * @notice Force update the cached credit score
     */
    function updateCreditScore(address user) external {
        _updateCachedScore(user);
    }

    /**
     * @notice Internal function to update cached score
     */
    function _updateCachedScore(address user) internal {
        uint256 newScore = _calculateCreditScore(user);
        userCreditData[user].cachedScore = newScore;
        userCreditData[user].lastScoreUpdate = block.timestamp;
        emit CreditScoreUpdated(user, newScore);
    }

    /**
     * @notice Calculate credit score based on all factors
     */
    function _calculateCreditScore(address user) internal view returns (uint256) {
        UserCreditData storage userData = userCreditData[user];

        // If account doesn't exist, return minimum score
        if (userData.accountCreationTime == 0) {
            return MIN_SCORE;
        }

        // Calculate each component (0-100 scale)
        uint256 paymentScore = _calculatePaymentHistoryScore(user);
        uint256 savingsScore = _calculateSavingsConsistencyScore(user);
        uint256 timeScore = _calculateTimeInProtocolScore(user);
        uint256 diversityScore = _calculateDiversityScore(user);
        uint256 liquidityScore = _calculateLiquidityProvisionScore(user);

        // Weighted sum
        uint256 weightedScore = (
            paymentScore * PAYMENT_HISTORY_WEIGHT +
            savingsScore * SAVINGS_CONSISTENCY_WEIGHT +
            timeScore * TIME_IN_PROTOCOL_WEIGHT +
            diversityScore * DIVERSITY_WEIGHT +
            liquidityScore * LIQUIDITY_PROVISION_WEIGHT
        ) / 100;

        // Scale to 300-850 range
        uint256 finalScore = MIN_SCORE + (weightedScore * SCORE_RANGE) / 100;

        return finalScore;
    }

    /**
     * @notice Calculate payment history score (35% weight)
     */
    function _calculatePaymentHistoryScore(address user) internal view returns (uint256) {
        UserCreditData storage userData = userCreditData[user];

        if (userData.totalPayments == 0) {
            return 50; // Neutral score for no payment history
        }

        PaymentRecord[] storage records = paymentHistory[user];
        uint256 weightedPoints = 0;
        uint256 totalWeight = 0;

        // Time-weighted scoring (recent payments matter more)
        for (uint256 i = 0; i < records.length; i++) {
            PaymentRecord storage record = records[i];

            // Calculate time decay weight
            uint256 age = block.timestamp - record.timestamp;
            uint256 weight = age < PAYMENT_DECAY_PERIOD
                ? PAYMENT_DECAY_PERIOD - age
                : 1; // Minimum weight of 1

            uint256 points;
            if (record.status == PaymentStatus.OnTime) {
                points = ON_TIME_POINTS;
            } else if (record.status == PaymentStatus.Late) {
                if (record.daysLate < 30) {
                    points = ON_TIME_POINTS - LATE_7_30_PENALTY;
                } else {
                    points = ON_TIME_POINTS - LATE_30_PLUS_PENALTY;
                }
            } else {
                // Default
                points = 0;
            }

            weightedPoints += points * weight;
            totalWeight += weight * ON_TIME_POINTS;
        }

        if (totalWeight == 0) return 50;

        return (weightedPoints * 100) / totalWeight;
    }

    /**
     * @notice Calculate savings consistency score (30% weight)
     */
    function _calculateSavingsConsistencyScore(address user) internal view returns (uint256) {
        UserCreditData storage userData = userCreditData[user];

        if (userData.totalSavingsDeposited == 0) {
            return 0;
        }

        // Calculate time-weighted average balance
        uint256 timeDelta = block.timestamp - userData.lastSavingsUpdateTime;
        uint256 totalTimeWeighted = userData.savingsTimeWeightedBalance +
            (userData.currentSavingsBalance * timeDelta);

        uint256 totalTime = block.timestamp - userData.accountCreationTime;
        if (totalTime == 0) return 0;

        uint256 averageBalance = totalTimeWeighted / totalTime;

        // Score based on average balance relative to total deposited
        // Higher average balance = better consistency
        if (averageBalance >= userData.totalSavingsDeposited) {
            return 100; // Perfect consistency
        }

        uint256 consistencyRatio = (averageBalance * 100) / userData.totalSavingsDeposited;

        // Boost for having current balance
        if (userData.currentSavingsBalance > 0) {
            consistencyRatio = (consistencyRatio * 120) / 100; // 20% bonus
            if (consistencyRatio > 100) consistencyRatio = 100;
        }

        return consistencyRatio;
    }

    /**
     * @notice Calculate time in protocol score (20% weight)
     */
    function _calculateTimeInProtocolScore(address user) internal view returns (uint256) {
        UserCreditData storage userData = userCreditData[user];

        uint256 timeInProtocol = block.timestamp - userData.accountCreationTime;

        if (timeInProtocol >= FULL_TIME_BONUS_DAYS) {
            return 100;
        }

        return (timeInProtocol * 100) / FULL_TIME_BONUS_DAYS;
    }

    /**
     * @notice Calculate diversity score (10% weight)
     */
    function _calculateDiversityScore(address user) internal view returns (uint256) {
        UserCreditData storage userData = userCreditData[user];

        // Score based on number of unique assets (cap at 5 for max score)
        uint256 uniqueAssets = userData.uniqueAssetsUsed;
        if (uniqueAssets >= 5) {
            return 100;
        }

        return (uniqueAssets * 100) / 5;
    }

    /**
     * @notice Calculate liquidity provision score (5% weight)
     */
    function _calculateLiquidityProvisionScore(address user) internal view returns (uint256) {
        UserCreditData storage userData = userCreditData[user];

        // Simple presence check (can be enhanced with amount-based scoring)
        if (userData.liquidityProvided > 0) {
            return 100;
        }

        return 0;
    }

    /**
     * @notice Get detailed credit breakdown for a user
     */
    function getCreditBreakdown(address user) external view returns (
        uint256 totalScore,
        uint256 paymentScore,
        uint256 savingsScore,
        uint256 timeScore,
        uint256 diversityScore,
        uint256 liquidityScore
    ) {
        paymentScore = _calculatePaymentHistoryScore(user);
        savingsScore = _calculateSavingsConsistencyScore(user);
        timeScore = _calculateTimeInProtocolScore(user);
        diversityScore = _calculateDiversityScore(user);
        liquidityScore = _calculateLiquidityProvisionScore(user);
        totalScore = _calculateCreditScore(user);
    }

    /**
     * @notice Get user credit data
     */
    function getUserCreditData(address user) external view returns (UserCreditData memory) {
        return userCreditData[user];
    }

    /**
     * @notice Get payment history length
     */
    function getPaymentHistoryLength(address user) external view returns (uint256) {
        return paymentHistory[user].length;
    }

    /**
     * @notice Get specific payment record
     */
    function getPaymentRecord(address user, uint256 index) external view returns (PaymentRecord memory) {
        return paymentHistory[user][index];
    }
}
