// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICreditNFT
 * @notice Interface for Soulbound Credit NFT
 */
interface ICreditNFT {
    // Events
    event CreditNFTMinted(address indexed user, uint256 indexed tokenId);
    event CreditScoreUpdated(address indexed user, uint256 newScore, string newTier);
    event CreditOracleUpdated(address indexed oldOracle, address indexed newOracle);

    // Errors
    error TransferNotAllowed();
    error AlreadyHasNFT();
    error TokenDoesNotExist();

    // Core NFT functions
    function mint(address to) external returns (uint256);
    function getTokenId(address user) external view returns (uint256);
    function hasNFT(address user) external view returns (bool);

    // Credit functions
    function getCreditScoreForToken(uint256 tokenId) external view returns (uint256);
    function getTierForToken(uint256 tokenId) external view returns (string memory);
    function getCreditTier(uint256 score) external view returns (string memory);

    // Configuration
    function setCreditOracle(address _creditOracle) external;
    function creditOracle() external view returns (address);
    function version() external pure returns (string memory);

    // ERC721 Standard
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
}
