// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SoulboundCreditNFT} from "../src/SoulboundCreditNFT.sol";
import {CreditOracle} from "../src/CreditOracle.sol";

contract SoulboundCreditNFTTest is Test {
    SoulboundCreditNFT public nft;
    SoulboundCreditNFT public implementation;
    CreditOracle public creditOracle;
    ERC1967Proxy public proxy;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        // Deploy CreditOracle
        creditOracle = new CreditOracle();

        // Deploy implementation
        implementation = new SoulboundCreditNFT();

        // Deploy proxy
        bytes memory data = abi.encodeWithSelector(
            SoulboundCreditNFT.initialize.selector,
            address(creditOracle)
        );

        proxy = new ERC1967Proxy(address(implementation), data);

        // Wrap proxy
        nft = SoulboundCreditNFT(address(proxy));

        // Authorize NFT and test contract in credit oracle
        creditOracle.setAuthorizedUpdater(address(nft), true);
        creditOracle.setAuthorizedUpdater(address(this), true);

        // Initialize users in credit oracle
        creditOracle.initializeUser(user1);
        creditOracle.initializeUser(user2);
    }

    function test_Initialization() public view {
        assertEq(nft.owner(), owner);
        assertEq(address(nft.creditOracle()), address(creditOracle));
        assertEq(nft.version(), "1.0.0");
    }

    function test_MintNFT() public {
        uint256 tokenId = nft.mint(user1);

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(tokenId), user1);
        assertEq(nft.getTokenId(user1), tokenId);
        assertTrue(nft.hasNFT(user1));
    }

    function test_CannotMintTwice() public {
        nft.mint(user1);

        vm.expectRevert("Already has NFT");
        nft.mint(user1);
    }

    function test_TransferNotAllowed() public {
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        vm.expectRevert(SoulboundCreditNFT.TransferNotAllowed.selector);
        nft.transferFrom(user1, user2, tokenId);
    }

    function test_GetCreditTier() public view {
        assertEq(nft.getCreditTier(300), "Bronze");
        assertEq(nft.getCreditTier(550), "Silver");
        assertEq(nft.getCreditTier(650), "Gold");
        assertEq(nft.getCreditTier(750), "Platinum");
    }

    function test_TokenURI() public {
        uint256 tokenId = nft.mint(user1);

        string memory uri = nft.tokenURI(tokenId);

        // Should start with data:application/json;base64,
        assertTrue(bytes(uri).length > 0);

        // Log for inspection
        console.log("Token URI length:", bytes(uri).length);
    }

    function test_GetCreditScoreForToken() public {
        uint256 tokenId = nft.mint(user1);

        uint256 score = nft.getCreditScoreForToken(tokenId);

        // New user should have minimum score
        assertEq(score, 300);
    }

    function test_UpdateCreditOracle() public {
        CreditOracle newOracle = new CreditOracle();

        nft.setCreditOracle(address(newOracle));

        assertEq(address(nft.creditOracle()), address(newOracle));
    }

    function test_CannotUpdateCreditOracleAsNonOwner() public {
        CreditOracle newOracle = new CreditOracle();

        vm.prank(user1);
        vm.expectRevert();
        nft.setCreditOracle(address(newOracle));
    }

    function test_UpgradeContract() public {
        // Mint an NFT before upgrade
        uint256 tokenId = nft.mint(user1);
        assertEq(nft.ownerOf(tokenId), user1);

        // Deploy new implementation
        SoulboundCreditNFT newImplementation = new SoulboundCreditNFT();

        // Upgrade
        nft.upgradeToAndCall(address(newImplementation), "");

        // Verify state is preserved
        assertEq(nft.ownerOf(tokenId), user1);
        assertEq(nft.getTokenId(user1), tokenId);
        assertTrue(nft.hasNFT(user1));
    }

    function test_CannotUpgradeAsNonOwner() public {
        SoulboundCreditNFT newImplementation = new SoulboundCreditNFT();

        vm.prank(user1);
        vm.expectRevert();
        nft.upgradeToAndCall(address(newImplementation), "");
    }
}
