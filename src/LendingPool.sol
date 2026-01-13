// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title LendingPool
 * @notice Core lending protocol with dynamic collateral ratios based on credit scores
 * @dev Allows users to deposit collateral, borrow assets, and manages liquidations
 *
 * Features:
 * - Dynamic collateral ratios (110-200%) based on credit scores
 * - Multi-token collateral support
 * - Interest accrual on borrowed positions
 * - Liquidation engine for undercollateralized positions
 * - Integration with CreditOracle and PriceOracle
 * - Health factor monitoring
 *
 * Credit Score Impact:
 * - 800-850: 110% collateral ratio (highest creditworthiness)
 * - 750-799: 120% collateral ratio
 * - 700-749: 130% collateral ratio
 * - 650-699: 140% collateral ratio
 * - 600-649: 150% collateral ratio
 * - 300-599: 200% collateral ratio (lowest creditworthiness)
 */
contract LendingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State variables
    address public creditOracle;
    address public priceOracle;

    // Token configuration
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public interestRates; // Annual interest rate in basis points
    mapping(address => uint256) public totalBorrowed; // Total borrowed per token
    mapping(address => uint256) public totalCollateral; // Total collateral per token

    // User positions: user => token => position
    mapping(address => mapping(address => UserPosition)) public userPositions;

    // Liquidation configuration
    uint256 public liquidationThreshold; // Health factor threshold (e.g., 1.0 = 100%)
    uint256 public liquidationBonus; // Bonus for liquidators in basis points

    // Constants
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_CREDIT_SCORE = 300;
    uint256 private constant MAX_CREDIT_SCORE = 850;
    uint256 private constant MIN_COLLATERAL_RATIO = 110; // 110%
    uint256 private constant MAX_COLLATERAL_RATIO = 200; // 200%

    // Structs
    struct UserPosition {
        uint256 collateralAmount;
        uint256 borrowedAmount;
        uint256 collateralRatio; // Personalized based on credit score
        uint256 lastUpdateTime;
        uint256 accruedInterest;
    }

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
    event InterestRateUpdated(address indexed token, uint256 oldRate, uint256 newRate);
    event TokenSupportUpdated(address indexed token, bool supported);
    event LiquidationThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // Errors
    error InsufficientCollateral(uint256 required, uint256 provided);
    error BorrowLimitExceeded(uint256 limit, uint256 requested);
    error PositionNotLiquidatable(uint256 healthFactor);
    error InvalidToken(address token);
    error TransferFailed();
    error InvalidAddress();
    error InvalidAmount();
    error NoDebtToRepay();
    error InsufficientLiquidity();

    /**
     * @notice Constructor
     * @param initialOwner Owner address
     * @param creditOracle_ CreditOracle address
     * @param priceOracle_ PriceOracle address
     */
    constructor(
        address initialOwner,
        address creditOracle_,
        address priceOracle_
    ) Ownable(initialOwner) {
        if (creditOracle_ == address(0) || priceOracle_ == address(0)) {
            revert InvalidAddress();
        }

        creditOracle = creditOracle_;
        priceOracle = priceOracle_;
        liquidationThreshold = 100; // 1.0 health factor
        liquidationBonus = 500; // 5% liquidation bonus
    }

    /**
     * @notice Deposit collateral
     * @param token Collateral token address
     * @param amount Amount to deposit
     */
    function depositCollateral(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert InvalidToken(token);
        if (amount == 0) revert InvalidAmount();

        UserPosition storage position = userPositions[msg.sender][token];

        // Update interest before modifying position
        _accrueInterest(msg.sender, token);

        // Update collateral ratio based on credit score
        _updateUserCollateralRatio(msg.sender, token);

        // Transfer tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Update position
        position.collateralAmount += amount;
        totalCollateral[token] += amount;

        emit Deposit(msg.sender, token, amount);
    }

    /**
     * @notice Withdraw collateral
     * @param token Collateral token address
     * @param amount Amount to withdraw
     */
    function withdrawCollateral(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert InvalidToken(token);
        if (amount == 0) revert InvalidAmount();

        UserPosition storage position = userPositions[msg.sender][token];

        // Update interest before modifying position
        _accrueInterest(msg.sender, token);

        if (position.collateralAmount < amount) {
            revert InsufficientCollateral(amount, position.collateralAmount);
        }

        // Calculate health factor after withdrawal
        uint256 newCollateral = position.collateralAmount - amount;
        uint256 totalDebt = position.borrowedAmount + position.accruedInterest;

        if (totalDebt > 0) {
            uint256 newHealthFactor = _calculateHealthFactor(
                newCollateral,
                totalDebt,
                token,
                position.collateralRatio
            );

            if (newHealthFactor < (liquidationThreshold * PRECISION) / 100) {
                revert InsufficientCollateral(amount, position.collateralAmount);
            }
        }

        // Update position
        position.collateralAmount = newCollateral;
        totalCollateral[token] -= amount;

        // Transfer tokens
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, token, amount);
    }

    /**
     * @notice Borrow assets
     * @param token Token to borrow
     * @param amount Amount to borrow
     */
    function borrow(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert InvalidToken(token);
        if (amount == 0) revert InvalidAmount();

        UserPosition storage position = userPositions[msg.sender][token];

        // Update interest before borrowing
        _accrueInterest(msg.sender, token);

        // Update collateral ratio based on credit score
        _updateUserCollateralRatio(msg.sender, token);

        // Check if pool has sufficient liquidity
        uint256 available = IERC20(token).balanceOf(address(this)) - totalCollateral[token];
        if (available < amount) revert InsufficientLiquidity();

        // Calculate max borrow amount
        uint256 maxBorrow = _calculateMaxBorrow(
            position.collateralAmount,
            position.borrowedAmount + position.accruedInterest,
            token,
            position.collateralRatio
        );

        if (amount > maxBorrow) {
            revert BorrowLimitExceeded(maxBorrow, amount);
        }

        // Update position
        position.borrowedAmount += amount;
        totalBorrowed[token] += amount;

        // Transfer tokens
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Borrow(msg.sender, token, amount, position.collateralRatio);

        // Record payment activity in credit oracle
        _recordBorrowActivity(msg.sender);
    }

    /**
     * @notice Repay borrowed assets
     * @param token Token to repay
     * @param amount Amount to repay
     */
    function repay(address token, uint256 amount) external nonReentrant {
        if (!supportedTokens[token]) revert InvalidToken(token);
        if (amount == 0) revert InvalidAmount();

        UserPosition storage position = userPositions[msg.sender][token];

        // Update interest before repayment
        _accrueInterest(msg.sender, token);

        uint256 totalDebt = position.borrowedAmount + position.accruedInterest;
        if (totalDebt == 0) revert NoDebtToRepay();

        // Calculate actual repayment amount
        uint256 repayAmount = amount > totalDebt ? totalDebt : amount;

        // Transfer tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), repayAmount);

        // Update position
        if (repayAmount >= position.accruedInterest) {
            // Pay interest first, then principal
            repayAmount -= position.accruedInterest;
            position.accruedInterest = 0;
            position.borrowedAmount -= repayAmount;
            totalBorrowed[token] -= repayAmount;
        } else {
            // Only paying partial interest
            position.accruedInterest -= repayAmount;
        }

        position.lastUpdateTime = block.timestamp;

        emit Repay(msg.sender, token, repayAmount);

        // Record payment in credit oracle
        _recordRepayment(msg.sender, repayAmount);
    }

    /**
     * @notice Liquidate undercollateralized position
     * @param borrower Address of borrower to liquidate
     * @param collateralToken Collateral token address
     * @param debtAmount Amount of debt to repay
     */
    function liquidate(
        address borrower,
        address collateralToken,
        uint256 debtAmount
    ) external nonReentrant {
        if (!supportedTokens[collateralToken]) revert InvalidToken(collateralToken);
        if (debtAmount == 0) revert InvalidAmount();

        UserPosition storage position = userPositions[borrower][collateralToken];

        // Update interest
        _accrueInterest(borrower, collateralToken);

        // Check if position is liquidatable
        uint256 healthFactor = _getHealthFactor(borrower, collateralToken);
        if (healthFactor >= (liquidationThreshold * PRECISION) / 100) {
            revert PositionNotLiquidatable(healthFactor);
        }

        uint256 totalDebt = position.borrowedAmount + position.accruedInterest;
        if (debtAmount > totalDebt) debtAmount = totalDebt;

        // Calculate collateral to seize (with liquidation bonus)
        uint256 collateralValue = _getCollateralToSeize(
            collateralToken,
            debtAmount
        );

        if (collateralValue > position.collateralAmount) {
            collateralValue = position.collateralAmount;
        }

        // Transfer debt repayment from liquidator
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), debtAmount);

        // Update position
        if (debtAmount >= position.accruedInterest) {
            debtAmount -= position.accruedInterest;
            position.accruedInterest = 0;
            position.borrowedAmount -= debtAmount;
            totalBorrowed[collateralToken] -= debtAmount;
        } else {
            position.accruedInterest -= debtAmount;
        }

        position.collateralAmount -= collateralValue;
        totalCollateral[collateralToken] -= collateralValue;

        // Transfer collateral to liquidator
        IERC20(collateralToken).safeTransfer(msg.sender, collateralValue);

        emit Liquidation(borrower, msg.sender, collateralToken, collateralValue, debtAmount);

        // Record late payment in credit oracle
        _recordLatePayment(borrower);
    }

    /**
     * @notice Get user position
     * @param user User address
     * @param token Token address
     * @return position User position struct
     */
    function getUserPosition(address user, address token)
        external
        view
        returns (UserPosition memory position)
    {
        position = userPositions[user][token];

        // Calculate pending interest
        if (position.borrowedAmount > 0) {
            uint256 timeDelta = block.timestamp - position.lastUpdateTime;
            uint256 rate = interestRates[token];
            uint256 interest = (position.borrowedAmount * rate * timeDelta) /
                (SECONDS_PER_YEAR * BASIS_POINTS);
            position.accruedInterest += interest;
        }

        return position;
    }

    /**
     * @notice Get health factor for a position
     * @param user User address
     * @param token Token address
     * @return healthFactor Health factor (1e18 precision)
     */
    function getHealthFactor(address user, address token) external view returns (uint256) {
        return _getHealthFactor(user, token);
    }

    /**
     * @notice Get maximum borrow amount for a user
     * @param user User address
     * @param token Token address
     * @return maxBorrow Maximum borrowable amount
     */
    function getMaxBorrowAmount(address user, address token) external view returns (uint256) {
        UserPosition memory position = userPositions[user][token];

        return _calculateMaxBorrow(
            position.collateralAmount,
            position.borrowedAmount + position.accruedInterest,
            token,
            position.collateralRatio
        );
    }

    /**
     * @notice Get user's collateral ratio
     * @param user User address
     * @return ratio Collateral ratio percentage
     */
    function getCollateralRatio(address user) external view returns (uint256) {
        return _getUserCollateralRatio(user);
    }

    /**
     * @notice Calculate pending interest
     * @param user User address
     * @param token Token address
     * @return interest Pending interest amount
     */
    function calculateInterest(address user, address token) external view returns (uint256) {
        UserPosition memory position = userPositions[user][token];

        if (position.borrowedAmount == 0) return position.accruedInterest;

        uint256 timeDelta = block.timestamp - position.lastUpdateTime;
        uint256 rate = interestRates[token];
        uint256 newInterest = (position.borrowedAmount * rate * timeDelta) /
            (SECONDS_PER_YEAR * BASIS_POINTS);

        return position.accruedInterest + newInterest;
    }

    /**
     * @notice Check if position is liquidatable
     * @param user User address
     * @param token Token address
     * @return liquidatable True if position can be liquidated
     */
    function isLiquidatable(address user, address token) external view returns (bool) {
        uint256 healthFactor = _getHealthFactor(user, token);
        return healthFactor < (liquidationThreshold * PRECISION) / 100;
    }

    /**
     * @notice Update user's collateral ratio based on credit score
     * @param user User address
     */
    function updateUserCollateralRatio(address user) external {
        // Update for all supported tokens where user has a position
        // In practice, you'd iterate through user's positions
        // For simplicity, this is a public function that can be called per token
    }

    /**
     * @notice Get dynamic collateral ratio based on credit score
     * @param creditScore Credit score (300-850)
     * @return ratio Collateral ratio percentage
     */
    function getDynamicCollateralRatio(uint256 creditScore) public pure returns (uint256) {
        if (creditScore >= 800) return 110; // 110%
        if (creditScore >= 750) return 120; // 120%
        if (creditScore >= 700) return 130; // 130%
        if (creditScore >= 650) return 140; // 140%
        if (creditScore >= 600) return 150; // 150%
        return 200; // 200% for scores < 600
    }

    // ============ Admin Functions ============

    /**
     * @notice Set interest rate for a token
     * @param token Token address
     * @param rate Annual interest rate in basis points
     */
    function setInterestRate(address token, uint256 rate) external onlyOwner {
        if (rate > BASIS_POINTS) revert InvalidAmount();

        uint256 oldRate = interestRates[token];
        interestRates[token] = rate;

        emit InterestRateUpdated(token, oldRate, rate);
    }

    /**
     * @notice Set token support status
     * @param token Token address
     * @param supported Support status
     */
    function setSupportedToken(address token, bool supported) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();

        supportedTokens[token] = supported;

        emit TokenSupportUpdated(token, supported);
    }

    /**
     * @notice Set liquidation threshold
     * @param threshold New threshold (e.g., 100 = 1.0)
     */
    function setLiquidationThreshold(uint256 threshold) external onlyOwner {
        if (threshold == 0) revert InvalidAmount();

        uint256 oldThreshold = liquidationThreshold;
        liquidationThreshold = threshold;

        emit LiquidationThresholdUpdated(oldThreshold, threshold);
    }

    /**
     * @notice Set liquidation bonus
     * @param bonus Bonus in basis points
     */
    function setLiquidationBonus(uint256 bonus) external onlyOwner {
        if (bonus > BASIS_POINTS) revert InvalidAmount();
        liquidationBonus = bonus;
    }

    /**
     * @notice Set credit oracle address
     * @param newOracle New credit oracle address
     */
    function setCreditOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert InvalidAddress();
        creditOracle = newOracle;
    }

    /**
     * @notice Set price oracle address
     * @param newOracle New price oracle address
     */
    function setPriceOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert InvalidAddress();
        priceOracle = newOracle;
    }

    // ============ Internal Functions ============

    /**
     * @notice Accrue interest for a position
     */
    function _accrueInterest(address user, address token) internal {
        UserPosition storage position = userPositions[user][token];

        if (position.borrowedAmount == 0) return;

        uint256 timeDelta = block.timestamp - position.lastUpdateTime;
        if (timeDelta == 0) return;

        uint256 rate = interestRates[token];
        uint256 interest = (position.borrowedAmount * rate * timeDelta) /
            (SECONDS_PER_YEAR * BASIS_POINTS);

        position.accruedInterest += interest;
        position.lastUpdateTime = block.timestamp;
    }

    /**
     * @notice Update user's collateral ratio
     */
    function _updateUserCollateralRatio(address user, address token) internal {
        UserPosition storage position = userPositions[user][token];

        uint256 newRatio = _getUserCollateralRatio(user);

        if (position.collateralRatio != newRatio) {
            uint256 oldRatio = position.collateralRatio;
            position.collateralRatio = newRatio;

            emit CollateralRatioUpdated(user, oldRatio, newRatio);
        }
    }

    /**
     * @notice Get user's collateral ratio from credit score
     */
    function _getUserCollateralRatio(address user) internal view returns (uint256) {
        // Get credit score from oracle
        (bool success, bytes memory data) = creditOracle.staticcall(
            abi.encodeWithSignature("getCreditScore(address)", user)
        );

        if (!success || data.length == 0) {
            return MAX_COLLATERAL_RATIO; // Default to highest ratio if no score
        }

        uint256 creditScore = abi.decode(data, (uint256));
        return getDynamicCollateralRatio(creditScore);
    }

    /**
     * @notice Calculate health factor
     */
    function _calculateHealthFactor(
        uint256 collateralAmount,
        uint256 debtAmount,
        address token,
        uint256 collateralRatio
    ) internal view returns (uint256) {
        if (debtAmount == 0) return type(uint256).max;

        // Get collateral value in USD
        uint256 collateralValue = _getTokenValue(token, collateralAmount);

        // Health factor = (collateralValue / debtValue) / (collateralRatio / 100)
        // Simplified: collateralValue * 100 / (debtValue * collateralRatio)
        uint256 debtValue = _getTokenValue(token, debtAmount);

        return (collateralValue * 100 * PRECISION) / (debtValue * collateralRatio);
    }

    /**
     * @notice Get health factor for user
     */
    function _getHealthFactor(address user, address token) internal view returns (uint256) {
        UserPosition memory position = userPositions[user][token];

        // Calculate current interest
        uint256 timeDelta = block.timestamp - position.lastUpdateTime;
        uint256 rate = interestRates[token];
        uint256 pendingInterest = (position.borrowedAmount * rate * timeDelta) /
            (SECONDS_PER_YEAR * BASIS_POINTS);

        uint256 totalDebt = position.borrowedAmount + position.accruedInterest + pendingInterest;

        return _calculateHealthFactor(
            position.collateralAmount,
            totalDebt,
            token,
            position.collateralRatio == 0 ? MAX_COLLATERAL_RATIO : position.collateralRatio
        );
    }

    /**
     * @notice Calculate maximum borrow amount
     */
    function _calculateMaxBorrow(
        uint256 collateralAmount,
        uint256 currentDebt,
        address token,
        uint256 collateralRatio
    ) internal view returns (uint256) {
        if (collateralRatio == 0) collateralRatio = MAX_COLLATERAL_RATIO;

        uint256 collateralValue = _getTokenValue(token, collateralAmount);

        // Max borrow = (collateralValue * 100 / collateralRatio) - currentDebt
        uint256 maxBorrowValue = (collateralValue * 100) / collateralRatio;
        uint256 currentDebtValue = _getTokenValue(token, currentDebt);

        if (maxBorrowValue <= currentDebtValue) return 0;

        uint256 maxBorrowUSD = maxBorrowValue - currentDebtValue;

        // Convert USD value back to token amount
        return _getTokenAmount(token, maxBorrowUSD);
    }

    /**
     * @notice Get token value in USD
     */
    function _getTokenValue(address token, uint256 amount) internal view returns (uint256) {
        (bool success, bytes memory data) = priceOracle.staticcall(
            abi.encodeWithSignature("getPriceInUSD(address,uint256)", token, amount)
        );

        if (!success || data.length == 0) return 0;

        return abi.decode(data, (uint256));
    }

    /**
     * @notice Get token amount from USD value
     */
    function _getTokenAmount(address token, uint256 usdValue) internal view returns (uint256) {
        (bool success, bytes memory data) = priceOracle.staticcall(
            abi.encodeWithSignature("getPrice(address)", token)
        );

        if (!success || data.length == 0) return 0;

        uint256 price = abi.decode(data, (uint256));
        if (price == 0) return 0;

        return (usdValue * PRECISION) / price;
    }

    /**
     * @notice Calculate collateral to seize during liquidation
     */
    function _getCollateralToSeize(address token, uint256 debtAmount)
        internal
        view
        returns (uint256)
    {
        uint256 debtValue = _getTokenValue(token, debtAmount);

        // Add liquidation bonus
        uint256 valueToSeize = (debtValue * (BASIS_POINTS + liquidationBonus)) / BASIS_POINTS;

        return _getTokenAmount(token, valueToSeize);
    }

    /**
     * @notice Record borrow activity in credit oracle
     */
    function _recordBorrowActivity(address user) internal {
        creditOracle.call(
            abi.encodeWithSignature("recordBorrow(address)", user)
        );
    }

    /**
     * @notice Record repayment in credit oracle
     */
    function _recordRepayment(address user, uint256 amount) internal {
        creditOracle.call(
            abi.encodeWithSignature("recordPayment(address,uint256,uint256)", user, amount, 0)
        );
    }

    /**
     * @notice Record late payment in credit oracle
     */
    function _recordLatePayment(address user) internal {
        creditOracle.call(
            abi.encodeWithSignature("recordPayment(address,uint256,uint256)", user, 0, 30)
        );
    }
}
