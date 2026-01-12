// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Errors
 * @notice Library containing all custom errors used in the protocol
 * @dev Using custom errors saves gas compared to require strings
 */
library Errors {
    // ========== Credit Oracle Errors ==========
    error NotAuthorized(address caller);
    error UserNotInitialized(address user);
    error InvalidCreditScore(uint256 score);
    error PaymentRecordNotFound(address user, uint256 index);

    // ========== NFT Errors ==========
    error TransferNotAllowed();
    error AlreadyHasNFT(address user);
    error TokenDoesNotExist(uint256 tokenId);
    error NotNFTOwner(address caller, uint256 tokenId);
    error InvalidOracleAddress();

    // ========== Lending Pool Errors ==========
    error InsufficientCollateral(uint256 required, uint256 provided);
    error BorrowLimitExceeded(uint256 limit, uint256 requested);
    error PositionNotLiquidatable(uint256 healthFactor);
    error InvalidToken(address token);
    error TokenNotSupported(address token);
    error BorrowingDisabled(address token);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error PositionNotFound(address user, address token);

    // ========== Savings Vault Errors ==========
    error InsufficientBalance(uint256 requested, uint256 available);
    error InvalidAmount(uint256 amount);
    error ZeroShares();
    error ZeroAssets();
    error WithdrawFailed();

    // ========== Price Oracle Errors ==========
    error PriceFeedNotSet(address token);
    error StalePrice(address token, uint256 lastUpdate, uint256 maxStale);
    error InvalidPrice(address token, int256 price);
    error NegativePrice(address token, int256 price);
    error PriceOracleNotSet();

    // ========== General Errors ==========
    error ZeroAddress();
    error InvalidParameter(string param);
    error Unauthorized(address caller);
    error Reentrancy();
    error Paused();
    error NotPaused();
    error TransferFailed(address token, address from, address to);
    error ApprovalFailed(address token, address spender);

    // ========== Math Errors ==========
    error DivisionByZero();
    error Overflow(uint256 value);
    error Underflow(uint256 value);
    error InvalidPercentage(uint256 percentage);

    // ========== Diamond Errors ==========
    error FunctionDoesNotExist(bytes4 selector);
    error SelectorAlreadyExists(bytes4 selector);
    error FacetAddressIsZero();
    error FacetHasNoCode(address facet);
    error InvalidFacetCutAction(uint8 action);
    error CannotRemoveImmutableFunction(bytes4 selector);

    // ========== Time-based Errors ==========
    error DeadlinePassed(uint256 deadline, uint256 current);
    error TooEarly(uint256 available, uint256 current);
    error LockPeriodActive(uint256 unlockTime, uint256 current);

    // ========== Access Control Errors ==========
    error NotOwner(address caller);
    error NotAdmin(address caller);
    error NotGovernance(address caller);
    error NotEmergencyAdmin(address caller);

    // ========== Liquidation Errors ==========
    error HealthFactorOk(uint256 healthFactor);
    error InvalidLiquidationBonus(uint256 bonus);
    error LiquidationAmountTooHigh(uint256 requested, uint256 max);
    error SelfLiquidation();

    // ========== Interest Rate Errors ==========
    error InvalidInterestRate(uint256 rate);
    error UtilizationTooHigh(uint256 utilization);
    error RateModelNotSet();
}
