// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Diamond} from "../src/diamond/Diamond.sol";
import {DiamondCutFacet} from "../src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/diamond/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../src/diamond/facets/OwnershipFacet.sol";
import {CreditNFTFacet} from "../src/diamond/facets/CreditNFTFacet.sol";
import {CreditOracle} from "../src/CreditOracle.sol";
import {IDiamondCut} from "../src/diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/diamond/interfaces/IDiamondLoupe.sol";

contract DiamondCreditNFTTest is Test {
    Diamond public diamond;
    DiamondCutFacet public diamondCutFacet;
    DiamondLoupeFacet public loupeFacet;
    OwnershipFacet public ownershipFacet;
    CreditNFTFacet public creditNFTFacet;
    CreditOracle public creditOracle;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        // Deploy CreditOracle
        creditOracle = new CreditOracle();

        // Deploy DiamondCutFacet
        diamondCutFacet = new DiamondCutFacet();

        // Deploy Diamond
        diamond = new Diamond(owner, address(diamondCutFacet));

        // Deploy other facets
        loupeFacet = new DiamondLoupeFacet();
        ownershipFacet = new OwnershipFacet();
        creditNFTFacet = new CreditNFTFacet();

        // Prepare diamond cut
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](3);

        // DiamondLoupe
        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = DiamondLoupeFacet.facets.selector;
        loupeSelectors[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        loupeSelectors[2] = DiamondLoupeFacet.facetAddresses.selector;
        loupeSelectors[3] = DiamondLoupeFacet.facetAddress.selector;
        loupeSelectors[4] = DiamondLoupeFacet.supportsInterface.selector;

        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(loupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });

        // Ownership
        bytes4[] memory ownershipSelectors = new bytes4[](2);
        ownershipSelectors[0] = OwnershipFacet.transferOwnership.selector;
        ownershipSelectors[1] = OwnershipFacet.owner.selector;

        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });

        // CreditNFT
        bytes4[] memory nftSelectors = new bytes4[](16);
        nftSelectors[0] = CreditNFTFacet.version.selector;
        nftSelectors[1] = CreditNFTFacet.initializeCreditNFT.selector;
        nftSelectors[2] = CreditNFTFacet.name.selector;
        nftSelectors[3] = CreditNFTFacet.symbol.selector;
        nftSelectors[4] = CreditNFTFacet.mint.selector;
        nftSelectors[5] = CreditNFTFacet.ownerOf.selector;
        nftSelectors[6] = CreditNFTFacet.balanceOf.selector;
        nftSelectors[7] = bytes4(keccak256("transferFrom(address,address,uint256)"));
        nftSelectors[8] = bytes4(keccak256("safeTransferFrom(address,address,uint256)"));
        nftSelectors[9] = bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"));
        nftSelectors[10] = CreditNFTFacet.getTokenId.selector;
        nftSelectors[11] = CreditNFTFacet.hasNFT.selector;
        nftSelectors[12] = CreditNFTFacet.tokenURI.selector;
        nftSelectors[13] = CreditNFTFacet.getCreditScoreForToken.selector;
        nftSelectors[14] = CreditNFTFacet.setCreditOracle.selector;
        nftSelectors[15] = CreditNFTFacet.creditOracle.selector;

        cut[2] = IDiamondCut.FacetCut({
            facetAddress: address(creditNFTFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: nftSelectors
        });

        // Execute diamond cut
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");

        // Initialize Credit NFT
        CreditNFTFacet(address(diamond)).initializeCreditNFT(address(creditOracle));

        // Authorize diamond and test contract
        creditOracle.setAuthorizedUpdater(address(diamond), true);
        creditOracle.setAuthorizedUpdater(address(this), true);

        // Initialize users
        creditOracle.initializeUser(user1);
        creditOracle.initializeUser(user2);
    }

    function test_DiamondDeployment() public view {
        assertEq(OwnershipFacet(address(diamond)).owner(), owner);
        assertEq(CreditNFTFacet(address(diamond)).version(), "2.0.0-diamond");
    }

    function test_NFTInitialization() public view {
        assertEq(CreditNFTFacet(address(diamond)).name(), "Base Credit Identity");
        assertEq(CreditNFTFacet(address(diamond)).symbol(), "BCREDIT");
        assertEq(CreditNFTFacet(address(diamond)).creditOracle(), address(creditOracle));
    }

    function test_MintNFT() public {
        uint256 tokenId = CreditNFTFacet(address(diamond)).mint(user1);

        assertEq(tokenId, 1);
        assertEq(CreditNFTFacet(address(diamond)).ownerOf(tokenId), user1);
        assertEq(CreditNFTFacet(address(diamond)).balanceOf(user1), 1);
        assertTrue(CreditNFTFacet(address(diamond)).hasNFT(user1));
    }

    function test_CannotMintTwice() public {
        CreditNFTFacet(address(diamond)).mint(user1);

        vm.expectRevert("Already has NFT");
        CreditNFTFacet(address(diamond)).mint(user1);
    }

    function test_TransferNotAllowed() public {
        uint256 tokenId = CreditNFTFacet(address(diamond)).mint(user1);

        vm.prank(user1);
        vm.expectRevert(CreditNFTFacet.TransferNotAllowed.selector);
        CreditNFTFacet(address(diamond)).transferFrom(user1, user2, tokenId);
    }

    function test_TokenURI() public {
        uint256 tokenId = CreditNFTFacet(address(diamond)).mint(user1);

        string memory uri = CreditNFTFacet(address(diamond)).tokenURI(tokenId);

        assertTrue(bytes(uri).length > 0);
        console.log("Token URI length:", bytes(uri).length);
    }

    function test_GetCreditScore() public {
        uint256 tokenId = CreditNFTFacet(address(diamond)).mint(user1);

        uint256 score = CreditNFTFacet(address(diamond)).getCreditScoreForToken(tokenId);

        // New user should have minimum score
        assertEq(score, 300);
    }

    function test_UpdateCreditOracle() public {
        CreditOracle newOracle = new CreditOracle();

        CreditNFTFacet(address(diamond)).setCreditOracle(address(newOracle));

        assertEq(CreditNFTFacet(address(diamond)).creditOracle(), address(newOracle));
    }

    function test_DiamondLoupe() public view {
        IDiamondLoupe.Facet[] memory facets = IDiamondLoupe(address(diamond)).facets();

        // Should have 4 facets (DiamondCut, DiamondLoupe, Ownership, CreditNFT)
        assertEq(facets.length, 4);
    }

    function test_CanAddNewFacet() public {
        // Deploy a new test facet
        TestFacet testFacet = new TestFacet();

        // Prepare cut
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = TestFacet.testFunction.selector;

        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(testFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: selectors
        });

        // Add facet
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");

        // Test new function
        uint256 result = TestFacet(address(diamond)).testFunction();
        assertEq(result, 42);
    }

    function test_CanReplaceFacet() public {
        // Deploy new CreditNFT facet with updated logic
        CreditNFTFacetV2 newFacet = new CreditNFTFacetV2();

        // Mint NFT before upgrade
        CreditNFTFacet(address(diamond)).mint(user1);

        // Prepare cut to replace version function
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = CreditNFTFacet.version.selector;

        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(newFacet),
            action: IDiamondCut.FacetCutAction.Replace,
            functionSelectors: selectors
        });

        // Replace facet
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");

        // Verify new version
        assertEq(CreditNFTFacet(address(diamond)).version(), "2.1.0-diamond-upgraded");

        // Verify storage is preserved
        assertTrue(CreditNFTFacet(address(diamond)).hasNFT(user1));
    }

    function test_TransferOwnership() public {
        address newOwner = address(0x999);

        OwnershipFacet(address(diamond)).transferOwnership(newOwner);

        assertEq(OwnershipFacet(address(diamond)).owner(), newOwner);
    }
}

// Test facet for adding new functionality
contract TestFacet {
    function testFunction() external pure returns (uint256) {
        return 42;
    }
}

// Upgraded facet for testing replacement
contract CreditNFTFacetV2 {
    function version() external pure returns (string memory) {
        return "2.1.0-diamond-upgraded";
    }
}
