// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {CreditOracle} from "./CreditOracle.sol";

/**
 * @title SoulboundCreditNFT
 * @notice Non-transferable NFT representing user credit identity
 * @dev Upgradeable contract using UUPS pattern, generates dynamic SVG based on credit score tier
 */
contract SoulboundCreditNFT is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using Strings for uint256;

    CreditOracle public creditOracle;
    uint256 private _nextTokenId;

    // Tier thresholds
    uint256 public constant PLATINUM_THRESHOLD = 750;
    uint256 public constant GOLD_THRESHOLD = 650;
    uint256 public constant SILVER_THRESHOLD = 550;
    // Below 550 = Bronze

    // Mapping from address to token ID
    mapping(address => uint256) public userToTokenId;
    mapping(uint256 => address) public tokenIdToUser;

    // Storage gap for future upgrades
    uint256[47] private __gap;

    // Events
    event CreditNFTMinted(address indexed user, uint256 indexed tokenId);
    event CreditScoreUpdated(address indexed user, uint256 newScore, string newTier);
    event CreditOracleUpdated(address indexed oldOracle, address indexed newOracle);

    error TransferNotAllowed();
    error AlreadyHasNFT();
    error NotNFTOwner();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (replaces constructor)
     * @param _creditOracle Address of the CreditOracle contract
     */
    function initialize(address _creditOracle) public initializer {
        __ERC721_init("Base Credit Identity", "BCREDIT");
        __Ownable_init(msg.sender);

        creditOracle = CreditOracle(_creditOracle);
        _nextTokenId = 1; // Start from 1
    }

    /**
     * @notice Authorize upgrade (required by UUPSUpgradeable)
     * @dev Only owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Update the CreditOracle address
     * @param _creditOracle New CreditOracle address
     */
    function setCreditOracle(address _creditOracle) external onlyOwner {
        require(_creditOracle != address(0), "Invalid address");
        address oldOracle = address(creditOracle);
        creditOracle = CreditOracle(_creditOracle);
        emit CreditOracleUpdated(oldOracle, _creditOracle);
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /**
     * @notice Mint a soulbound credit NFT for a user
     */
    function mint(address to) external returns (uint256) {
        require(userToTokenId[to] == 0, "Already has NFT");

        uint256 tokenId = _nextTokenId++;
        userToTokenId[to] = tokenId;
        tokenIdToUser[tokenId] = to;

        _safeMint(to, tokenId);

        emit CreditNFTMinted(to, tokenId);

        return tokenId;
    }

    /**
     * @notice Override transfer functions to make soulbound
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);

        // Allow minting (from == address(0)) and burning (to == address(0))
        // Disallow transfers between addresses
        if (from != address(0) && to != address(0)) {
            revert TransferNotAllowed();
        }

        return super._update(to, tokenId, auth);
    }

    /**
     * @notice Get credit tier name
     */
    function getCreditTier(uint256 score) public pure returns (string memory) {
        if (score >= PLATINUM_THRESHOLD) return "Platinum";
        if (score >= GOLD_THRESHOLD) return "Gold";
        if (score >= SILVER_THRESHOLD) return "Silver";
        return "Bronze";
    }

    /**
     * @notice Get tier color
     */
    function getTierColor(uint256 score) public pure returns (string memory) {
        if (score >= PLATINUM_THRESHOLD) return "#E5E4E2"; // Platinum
        if (score >= GOLD_THRESHOLD) return "#FFD700"; // Gold
        if (score >= SILVER_THRESHOLD) return "#C0C0C0"; // Silver
        return "#CD7F32"; // Bronze
    }

    /**
     * @notice Get tier gradient
     */
    function getTierGradient(uint256 score) public pure returns (string memory, string memory) {
        if (score >= PLATINUM_THRESHOLD) return ("#E5E4E2", "#B9B8B5");
        if (score >= GOLD_THRESHOLD) return ("#FFD700", "#FFA500");
        if (score >= SILVER_THRESHOLD) return ("#C0C0C0", "#808080");
        return ("#CD7F32", "#8B4513");
    }

    /**
     * @notice Generate SVG for the NFT
     */
    function generateSVG(address user, uint256 score) internal pure returns (string memory) {
        string memory tier = getCreditTier(score);
        (string memory color1, string memory color2) = getTierGradient(score);

        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600" style="background:#0F172A">',
                '<defs>',
                '<linearGradient id="tierGradient" x1="0%" y1="0%" x2="100%" y2="100%">',
                '<stop offset="0%" style="stop-color:', color1, ';stop-opacity:1" />',
                '<stop offset="100%" style="stop-color:', color2, ';stop-opacity:1" />',
                '</linearGradient>',
                '<linearGradient id="bgGradient" x1="0%" y1="0%" x2="0%" y2="100%">',
                '<stop offset="0%" style="stop-color:#1E293B;stop-opacity:1" />',
                '<stop offset="100%" style="stop-color:#0F172A;stop-opacity:1" />',
                '</linearGradient>',
                '</defs>',
                '<rect width="400" height="600" fill="url(#bgGradient)" rx="20"/>',
                '<rect x="20" y="20" width="360" height="560" fill="none" stroke="url(#tierGradient)" stroke-width="3" rx="15" opacity="0.5"/>',
                '<text x="200" y="80" font-family="Arial, sans-serif" font-size="28" font-weight="bold" fill="url(#tierGradient)" text-anchor="middle">BASE CREDIT</text>',
                '<text x="200" y="110" font-family="Arial, sans-serif" font-size="14" fill="#94A3B8" text-anchor="middle">Identity Protocol</text>',
                '<circle cx="200" cy="220" r="80" fill="none" stroke="url(#tierGradient)" stroke-width="4"/>',
                '<text x="200" y="235" font-family="Arial, sans-serif" font-size="48" font-weight="bold" fill="url(#tierGradient)" text-anchor="middle">', score.toString(), '</text>',
                '<text x="200" y="320" font-family="Arial, sans-serif" font-size="24" font-weight="bold" fill="url(#tierGradient)" text-anchor="middle">', tier, ' Tier</text>',
                '<rect x="40" y="360" width="320" height="180" fill="#1E293B" rx="10" opacity="0.7"/>',
                '<text x="60" y="390" font-family="monospace" font-size="12" fill="#94A3B8">Address:</text>',
                '<text x="60" y="415" font-family="monospace" font-size="11" fill="#E2E8F0">', substring(addressToString(user), 0, 20), '</text>',
                '<text x="60" y="435" font-family="monospace" font-size="11" fill="#E2E8F0">', substring(addressToString(user), 20, 42), '</text>',
                '<text x="60" y="470" font-family="Arial, sans-serif" font-size="12" fill="#94A3B8">Credit Range:</text>',
                '<text x="60" y="495" font-family="Arial, sans-serif" font-size="14" fill="#E2E8F0">300 - 850</text>',
                '<text x="200" y="570" font-family="Arial, sans-serif" font-size="10" fill="#64748B" text-anchor="middle">Soulbound Token - Non-Transferable</text>',
                '</svg>'
            )
        );
    }

    /**
     * @notice Helper to get substring
     */
    function substring(string memory str, uint256 startIndex, uint256 endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    /**
     * @notice Convert address to string
     */
    function addressToString(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory data = abi.encodePacked(addr);
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    /**
     * @notice Generate token URI with dynamic metadata
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        address user = tokenIdToUser[tokenId];
        require(user != address(0), "Token does not exist");

        uint256 creditScore = creditOracle.getCreditScore(user);
        string memory tier = getCreditTier(creditScore);
        string memory svg = generateSVG(user, creditScore);

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "Base Credit Identity #', tokenId.toString(), '",',
                        '"description": "Soulbound credit identity NFT representing on-chain creditworthiness. This token is non-transferable and dynamically reflects your credit score.",',
                        '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
                        '"attributes": [',
                        '{"trait_type": "Credit Score", "value": ', creditScore.toString(), '},',
                        '{"trait_type": "Tier", "value": "', tier, '"},',
                        '{"trait_type": "Soulbound", "value": "Yes"},',
                        '{"trait_type": "Address", "value": "', addressToString(user), '"}',
                        ']}'
                    )
                )
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    /**
     * @notice Get token ID for a user
     */
    function getTokenId(address user) external view returns (uint256) {
        return userToTokenId[user];
    }

    /**
     * @notice Check if user has NFT
     */
    function hasNFT(address user) external view returns (bool) {
        return userToTokenId[user] != 0;
    }

    /**
     * @notice Get credit score for NFT holder
     */
    function getCreditScoreForToken(uint256 tokenId) external view returns (uint256) {
        address user = tokenIdToUser[tokenId];
        require(user != address(0), "Token does not exist");
        return creditOracle.getCreditScore(user);
    }

    /**
     * @notice Get tier for NFT holder
     */
    function getTierForToken(uint256 tokenId) external view returns (string memory) {
        address user = tokenIdToUser[tokenId];
        require(user != address(0), "Token does not exist");
        uint256 score = creditOracle.getCreditScore(user);
        return getCreditTier(score);
    }
}
