// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibCreditNFT} from "../libraries/LibCreditNFT.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {CreditOracle} from "../../CreditOracle.sol";

/**
 * @title CreditNFTFacet
 * @notice Facet for Credit NFT functionality
 * @dev Implements soulbound NFT with dynamic credit scoring
 */
contract CreditNFTFacet {
    using Strings for uint256;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event CreditNFTMinted(address indexed user, uint256 indexed tokenId);
    event CreditOracleUpdated(address indexed oldOracle, address indexed newOracle);

    error TransferNotAllowed();
    error AlreadyHasNFT();
    error TokenDoesNotExist();

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "2.0.0-diamond";
    }

    /**
     * @notice Initialize the NFT storage
     */
    function initializeCreditNFT(address _creditOracle) external {
        LibDiamond.enforceIsContractOwner();
        LibCreditNFT.initializeStorage(_creditOracle);
    }

    /**
     * @notice ERC721 name
     */
    function name() external view returns (string memory) {
        return LibCreditNFT.creditNFTStorage().name;
    }

    /**
     * @notice ERC721 symbol
     */
    function symbol() external view returns (string memory) {
        return LibCreditNFT.creditNFTStorage().symbol;
    }

    /**
     * @notice Mint a soulbound credit NFT
     */
    function mint(address to) external returns (uint256) {
        LibCreditNFT.CreditNFTStorage storage s = LibCreditNFT.creditNFTStorage();

        require(s.userToTokenId[to] == 0, "Already has NFT");

        uint256 tokenId = s.nextTokenId++;
        s.userToTokenId[to] = tokenId;
        s.tokenIdToUser[tokenId] = to;
        s.owners[tokenId] = to;
        s.balances[to] += 1;

        emit Transfer(address(0), to, tokenId);
        emit CreditNFTMinted(to, tokenId);

        return tokenId;
    }

    /**
     * @notice Get token owner
     */
    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner_ = LibCreditNFT.creditNFTStorage().owners[tokenId];
        require(owner_ != address(0), "Token does not exist");
        return owner_;
    }

    /**
     * @notice Get balance of address
     */
    function balanceOf(address owner_) external view returns (uint256) {
        require(owner_ != address(0), "Zero address");
        return LibCreditNFT.creditNFTStorage().balances[owner_];
    }

    /**
     * @notice Transfer function (disabled for soulbound)
     */
    function transferFrom(address, address, uint256) external pure {
        revert TransferNotAllowed();
    }

    /**
     * @notice Safe transfer function (disabled for soulbound)
     */
    function safeTransferFrom(address, address, uint256) external pure {
        revert TransferNotAllowed();
    }

    /**
     * @notice Safe transfer with data (disabled for soulbound)
     */
    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert TransferNotAllowed();
    }

    /**
     * @notice Get token ID for user
     */
    function getTokenId(address user) external view returns (uint256) {
        return LibCreditNFT.creditNFTStorage().userToTokenId[user];
    }

    /**
     * @notice Check if user has NFT
     */
    function hasNFT(address user) external view returns (bool) {
        return LibCreditNFT.creditNFTStorage().userToTokenId[user] != 0;
    }

    /**
     * @notice Get credit tier name
     */
    function getCreditTier(uint256 score) public view returns (string memory) {
        LibCreditNFT.CreditNFTStorage storage s = LibCreditNFT.creditNFTStorage();
        if (score >= s.platinumThreshold) return "Platinum";
        if (score >= s.goldThreshold) return "Gold";
        if (score >= s.silverThreshold) return "Silver";
        return "Bronze";
    }

    /**
     * @notice Get tier gradient colors
     */
    function getTierGradient(uint256 score) public view returns (string memory, string memory) {
        LibCreditNFT.CreditNFTStorage storage s = LibCreditNFT.creditNFTStorage();
        if (score >= s.platinumThreshold) return ("#E5E4E2", "#B9B8B5");
        if (score >= s.goldThreshold) return ("#FFD700", "#FFA500");
        if (score >= s.silverThreshold) return ("#C0C0C0", "#808080");
        return ("#CD7F32", "#8B4513");
    }

    /**
     * @notice Generate SVG for the NFT
     */
    function generateSVG(address user, uint256 score) internal view returns (string memory) {
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
                '</defs>',
                '<rect width="400" height="600" fill="url(#bgGradient)" rx="20"/>',
                '<text x="200" y="80" font-family="Arial" font-size="28" font-weight="bold" fill="url(#tierGradient)" text-anchor="middle">BASE CREDIT</text>',
                '<circle cx="200" cy="220" r="80" fill="none" stroke="url(#tierGradient)" stroke-width="4"/>',
                '<text x="200" y="235" font-family="Arial" font-size="48" font-weight="bold" fill="url(#tierGradient)" text-anchor="middle">', score.toString(), '</text>',
                '<text x="200" y="320" font-family="Arial" font-size="24" font-weight="bold" fill="url(#tierGradient)" text-anchor="middle">', tier, ' Tier</text>',
                '<text x="200" y="570" font-family="Arial" font-size="10" fill="#64748B" text-anchor="middle">Soulbound - Non-Transferable</text>',
                '</svg>'
            )
        );
    }

    /**
     * @notice Generate token URI with dynamic metadata
     */
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        LibCreditNFT.CreditNFTStorage storage s = LibCreditNFT.creditNFTStorage();
        address user = s.tokenIdToUser[tokenId];
        require(user != address(0), "Token does not exist");

        uint256 creditScore = s.creditOracle.getCreditScore(user);
        string memory tier = getCreditTier(creditScore);
        string memory svg = generateSVG(user, creditScore);

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "Base Credit Identity #', tokenId.toString(), '",',
                        '"description": "Soulbound credit identity NFT on Diamond Standard",',
                        '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
                        '"attributes": [',
                        '{"trait_type": "Credit Score", "value": ', creditScore.toString(), '},',
                        '{"trait_type": "Tier", "value": "', tier, '"},',
                        '{"trait_type": "Soulbound", "value": "Yes"},',
                        '{"trait_type": "Standard", "value": "EIP-2535 Diamond"}',
                        ']}'
                    )
                )
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    /**
     * @notice Get credit score for token
     */
    function getCreditScoreForToken(uint256 tokenId) external view returns (uint256) {
        LibCreditNFT.CreditNFTStorage storage s = LibCreditNFT.creditNFTStorage();
        address user = s.tokenIdToUser[tokenId];
        require(user != address(0), "Token does not exist");
        return s.creditOracle.getCreditScore(user);
    }

    /**
     * @notice Get tier for token
     */
    function getTierForToken(uint256 tokenId) external view returns (string memory) {
        LibCreditNFT.CreditNFTStorage storage s = LibCreditNFT.creditNFTStorage();
        address user = s.tokenIdToUser[tokenId];
        require(user != address(0), "Token does not exist");
        uint256 score = s.creditOracle.getCreditScore(user);
        return getCreditTier(score);
    }

    /**
     * @notice Update CreditOracle address (owner only)
     */
    function setCreditOracle(address _creditOracle) external {
        LibDiamond.enforceIsContractOwner();
        LibCreditNFT.CreditNFTStorage storage s = LibCreditNFT.creditNFTStorage();
        require(_creditOracle != address(0), "Invalid address");

        address oldOracle = address(s.creditOracle);
        s.creditOracle = CreditOracle(_creditOracle);

        emit CreditOracleUpdated(oldOracle, _creditOracle);
    }

    /**
     * @notice Get CreditOracle address
     */
    function creditOracle() external view returns (address) {
        return address(LibCreditNFT.creditNFTStorage().creditOracle);
    }
}
