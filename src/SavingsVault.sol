// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SavingsVault
 * @notice ERC-4626 compliant savings vault with credit score boosting
 * @dev High-yield savings vault that integrates with CreditOracle to boost credit scores
 *
 * Features:
 * - ERC-4626 tokenized vault standard
 * - Compound interest accrual
 * - Credit score boosting based on savings consistency
 * - Time-weighted deposit tracking
 * - APY calculation and display
 *
 * Credit Score Integration:
 * - Longer deposit duration = higher credit boost
 * - Larger deposits = higher credit boost
 * - Regular deposits = consistency bonus
 * - Automatic credit oracle updates
 */
contract SavingsVault is ERC4626, Ownable, ReentrancyGuard {
    // State variables
    address public creditOracle;
    uint256 public baseAPY; // Annual percentage yield (in basis points, e.g., 500 = 5%)
    uint256 public lastAccrualTime;
    uint256 public accruedInterest;

    // User tracking
    struct UserInfo {
        uint256 firstDepositTime; // Timestamp of first deposit
        uint256 totalDeposited; // Cumulative deposits
        uint256 depositCount; // Number of deposits
        uint256 lastDepositTime; // Last deposit timestamp
        uint256 averageBalance; // Time-weighted average balance
        uint256 lastUpdateTime; // Last balance update
    }

    mapping(address => UserInfo) public userInfo;

    // Constants
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant MIN_CREDIT_BOOST = 0; // Minimum credit boost points
    uint256 private constant MAX_CREDIT_BOOST = 50; // Maximum credit boost points

    // Events
    event InterestAccrued(uint256 totalInterest, uint256 timestamp);
    event CreditScoreBoosted(address indexed user, uint256 boost);
    event APYUpdated(uint256 oldAPY, uint256 newAPY);
    event CreditOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event UserDeposit(address indexed user, uint256 amount, uint256 shares, uint256 timestamp);
    event UserWithdraw(address indexed user, uint256 amount, uint256 shares, uint256 timestamp);

    // Errors
    error InvalidAmount();
    error InvalidAPY();
    error InvalidAddress();
    error InsufficientBalance(uint256 requested, uint256 available);

    /**
     * @notice Constructor
     * @param asset_ Underlying asset (e.g., USDC)
     * @param name_ Vault token name
     * @param symbol_ Vault token symbol
     * @param initialOwner Owner address
     * @param creditOracle_ CreditOracle address
     * @param baseAPY_ Initial APY in basis points
     */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address initialOwner,
        address creditOracle_,
        uint256 baseAPY_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(initialOwner) {
        if (creditOracle_ == address(0)) revert InvalidAddress();
        if (baseAPY_ == 0 || baseAPY_ > BASIS_POINTS) revert InvalidAPY();

        creditOracle = creditOracle_;
        baseAPY = baseAPY_;
        lastAccrualTime = block.timestamp;
    }

    /**
     * @notice Deposit assets and receive vault shares
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver)
        public
        virtual
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert InvalidAmount();

        // Accrue interest before deposit
        _accrueInterest();

        // Update user info
        _updateUserInfo(receiver, assets, true);

        // Standard ERC-4626 deposit
        shares = super.deposit(assets, receiver);

        emit UserDeposit(receiver, assets, shares, block.timestamp);

        // Update credit score
        _updateCreditScore(receiver);

        return shares;
    }

    /**
     * @notice Mint shares and deposit required assets
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @return assets Amount of assets deposited
     */
    function mint(uint256 shares, address receiver)
        public
        virtual
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert InvalidAmount();

        // Accrue interest before mint
        _accrueInterest();

        // Calculate required assets
        assets = previewMint(shares);

        // Update user info
        _updateUserInfo(receiver, assets, true);

        // Standard ERC-4626 mint
        assets = super.mint(shares, receiver);

        emit UserDeposit(receiver, assets, shares, block.timestamp);

        // Update credit score
        _updateCreditScore(receiver);

        return assets;
    }

    /**
     * @notice Withdraw assets by redeeming shares
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive assets
     * @param owner Address whose shares are being redeemed
     * @return shares Amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert InvalidAmount();

        // Accrue interest before withdrawal
        _accrueInterest();

        // Check balance
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert InsufficientBalance(assets, maxAssets);
        }

        // Update user info
        _updateUserInfo(owner, assets, false);

        // Standard ERC-4626 withdraw
        shares = super.withdraw(assets, receiver, owner);

        emit UserWithdraw(owner, assets, shares, block.timestamp);

        // Update credit score
        _updateCreditScore(owner);

        return shares;
    }

    /**
     * @notice Redeem shares for assets
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets
     * @param owner Address whose shares are being redeemed
     * @return assets Amount of assets withdrawn
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert InvalidAmount();

        // Accrue interest before redemption
        _accrueInterest();

        // Check balance
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert InsufficientBalance(shares, maxShares);
        }

        // Calculate assets
        assets = previewRedeem(shares);

        // Update user info
        _updateUserInfo(owner, assets, false);

        // Standard ERC-4626 redeem
        assets = super.redeem(shares, receiver, owner);

        emit UserWithdraw(owner, assets, shares, block.timestamp);

        // Update credit score
        _updateCreditScore(owner);

        return assets;
    }

    /**
     * @notice Withdraw all assets for a user
     * @return assets Amount of assets withdrawn
     */
    function withdrawAll() external returns (uint256 assets) {
        uint256 shares = balanceOf(msg.sender);
        if (shares == 0) revert InsufficientBalance(1, 0);

        return redeem(shares, msg.sender, msg.sender);
    }

    /**
     * @notice Get current APY
     * @return apy Annual percentage yield in basis points
     */
    function getAPY() external view returns (uint256) {
        return baseAPY;
    }

    /**
     * @notice Get user's pending yield
     * @param user User address
     * @return yield Pending yield amount
     */
    function getUserYield(address user) external view returns (uint256) {
        uint256 shares = balanceOf(user);
        if (shares == 0) return 0;

        // Calculate current value including pending interest
        uint256 currentAssets = convertToAssets(shares);
        UserInfo memory info = userInfo[user];

        // If no deposits, return 0
        if (info.totalDeposited == 0) return 0;

        // Yield is current value minus total deposited
        if (currentAssets > info.totalDeposited) {
            return currentAssets - info.totalDeposited;
        }

        return 0;
    }

    /**
     * @notice Calculate credit boost for a user
     * @param user User address
     * @return boost Credit boost points (0-50)
     */
    function getCreditBoost(address user) public view returns (uint256) {
        UserInfo memory info = userInfo[user];

        if (info.firstDepositTime == 0) return 0;

        // Calculate time factor (longer = better)
        uint256 timeInVault = block.timestamp - info.firstDepositTime;
        uint256 timeFactor = (timeInVault * 100) / (180 days); // Max boost at 6 months
        if (timeFactor > 100) timeFactor = 100;

        // Calculate amount factor (more = better)
        uint256 shares = balanceOf(user);
        uint256 assets = shares > 0 ? convertToAssets(shares) : 0;
        uint256 amountFactor = (assets * 100) / (10000 * 10**6); // Assuming 6 decimals (USDC)
        if (amountFactor > 100) amountFactor = 100;

        // Calculate consistency factor (regular deposits = better)
        uint256 consistencyFactor = 0;
        if (info.depositCount > 0) {
            uint256 avgTimeBetweenDeposits = timeInVault / info.depositCount;
            if (avgTimeBetweenDeposits <= 30 days) {
                consistencyFactor = 100;
            } else if (avgTimeBetweenDeposits <= 60 days) {
                consistencyFactor = 70;
            } else if (avgTimeBetweenDeposits <= 90 days) {
                consistencyFactor = 40;
            }
        }

        // Weighted calculation: 40% time, 40% amount, 20% consistency
        uint256 boost = ((timeFactor * 40) + (amountFactor * 40) + (consistencyFactor * 20)) / 100;

        // Scale to max boost
        boost = (boost * MAX_CREDIT_BOOST) / 100;

        return boost;
    }

    /**
     * @notice Update credit score for a user via CreditOracle
     * @param user User address
     */
    function updateCreditScore(address user) external {
        _updateCreditScore(user);
    }

    /**
     * @notice Set new APY (owner only)
     * @param newAPY New APY in basis points
     */
    function setAPY(uint256 newAPY) external onlyOwner {
        if (newAPY == 0 || newAPY > BASIS_POINTS) revert InvalidAPY();

        uint256 oldAPY = baseAPY;
        baseAPY = newAPY;

        emit APYUpdated(oldAPY, newAPY);
    }

    /**
     * @notice Set new credit oracle (owner only)
     * @param newOracle New CreditOracle address
     */
    function setCreditOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert InvalidAddress();

        address oldOracle = creditOracle;
        creditOracle = newOracle;

        emit CreditOracleUpdated(oldOracle, newOracle);
    }

    /**
     * @notice Accrue interest to the vault
     * @dev Called before every state-changing operation
     */
    function accrueInterest() external {
        _accrueInterest();
    }

    /**
     * @notice Get total shares in vault
     * @return Total supply of shares
     */
    function totalShares() external view returns (uint256) {
        return totalSupply();
    }

    // ============ Internal Functions ============

    /**
     * @notice Internal function to accrue interest
     */
    function _accrueInterest() internal {
        uint256 timeDelta = block.timestamp - lastAccrualTime;
        if (timeDelta == 0) return;

        uint256 totalAssetsBefore = totalAssets();
        if (totalAssetsBefore == 0) {
            lastAccrualTime = block.timestamp;
            return;
        }

        // Calculate interest: principal * rate * time / (365 days * 10000)
        uint256 interest = (totalAssetsBefore * baseAPY * timeDelta) / (SECONDS_PER_YEAR * BASIS_POINTS);

        if (interest > 0) {
            accruedInterest += interest;
            lastAccrualTime = block.timestamp;

            emit InterestAccrued(interest, block.timestamp);
        }
    }

    /**
     * @notice Update user information
     * @param user User address
     * @param amount Amount deposited or withdrawn
     * @param isDeposit True for deposit, false for withdrawal
     */
    function _updateUserInfo(address user, uint256 amount, bool isDeposit) internal {
        UserInfo storage info = userInfo[user];

        // Update time-weighted average balance
        if (info.lastUpdateTime > 0) {
            uint256 timeElapsed = block.timestamp - info.lastUpdateTime;
            uint256 currentShares = balanceOf(user);
            uint256 currentAssets = currentShares > 0 ? convertToAssets(currentShares) : 0;

            // Update average: (old_avg * old_time + current_balance * new_time) / total_time
            uint256 totalTime = (block.timestamp - info.firstDepositTime);
            if (totalTime > 0) {
                info.averageBalance = (info.averageBalance * (totalTime - timeElapsed) + currentAssets * timeElapsed) / totalTime;
            }
        }

        if (isDeposit) {
            // First deposit
            if (info.firstDepositTime == 0) {
                info.firstDepositTime = block.timestamp;
            }

            info.totalDeposited += amount;
            info.depositCount += 1;
            info.lastDepositTime = block.timestamp;
        }

        info.lastUpdateTime = block.timestamp;
    }

    /**
     * @notice Update credit score via oracle
     * @param user User address
     */
    function _updateCreditScore(address user) internal {
        if (creditOracle == address(0)) return;

        uint256 boost = getCreditBoost(user);
        if (boost == 0) return;

        // Get user's current balance
        uint256 shares = balanceOf(user);
        uint256 assets = shares > 0 ? convertToAssets(shares) : 0;

        // Call credit oracle to update savings balance
        // This will indirectly boost the credit score
        (bool success,) = creditOracle.call(
            abi.encodeWithSignature(
                "updateSavingsBalance(address,uint256,uint256)",
                user,
                assets,
                userInfo[user].totalDeposited
            )
        );

        if (success) {
            emit CreditScoreBoosted(user, boost);
        }
    }

    /**
     * @notice Override total assets to include accrued interest
     */
    function totalAssets() public view virtual override returns (uint256) {
        return super.totalAssets() + accruedInterest;
    }
}
