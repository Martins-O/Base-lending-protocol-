// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Diamond} from "../src/diamond/Diamond.sol";
import {DiamondCutFacet} from "../src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/diamond/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../src/diamond/facets/OwnershipFacet.sol";
import {CreditNFTFacet} from "../src/diamond/facets/CreditNFTFacet.sol";
import {CreditOracle} from "../src/CreditOracle.sol";
import {IDiamondCut} from "../src/diamond/interfaces/IDiamondCut.sol";

/**
 * @title DeployDiamond
 * @notice Deploy Diamond Standard Credit NFT
 * @dev Usage: forge script script/DeployDiamond.s.sol:DeployDiamond --rpc-url <your_rpc_url> --broadcast
 */
contract DeployDiamond is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("\n=== Deploying Diamond Standard Credit NFT ===\n");

        // 1. Deploy CreditOracle
        console.log("1. Deploying CreditOracle...");
        CreditOracle creditOracle = new CreditOracle();
        console.log("   CreditOracle:", address(creditOracle));

        // 2. Deploy DiamondCutFacet
        console.log("\n2. Deploying DiamondCutFacet...");
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        console.log("   DiamondCutFacet:", address(diamondCutFacet));

        // 3. Deploy Diamond
        console.log("\n3. Deploying Diamond...");
        Diamond diamond = new Diamond(deployer, address(diamondCutFacet));
        console.log("   Diamond:", address(diamond));

        // 4. Deploy facets
        console.log("\n4. Deploying Facets...");
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        console.log("   DiamondLoupeFacet:", address(loupeFacet));

        OwnershipFacet ownershipFacet = new OwnershipFacet();
        console.log("   OwnershipFacet:", address(ownershipFacet));

        CreditNFTFacet creditNFTFacet = new CreditNFTFacet();
        console.log("   CreditNFTFacet:", address(creditNFTFacet));

        // 5. Prepare diamond cut
        console.log("\n5. Preparing Diamond Cut...");
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](3);

        // DiamondLoupe facet
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

        // Ownership facet
        bytes4[] memory ownershipSelectors = new bytes4[](2);
        ownershipSelectors[0] = OwnershipFacet.transferOwnership.selector;
        ownershipSelectors[1] = OwnershipFacet.owner.selector;

        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });

        // CreditNFT facet
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

        // 6. Execute diamond cut
        console.log("\n6. Executing Diamond Cut...");
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");
        console.log("   Diamond Cut complete!");

        // 7. Initialize Credit NFT
        console.log("\n7. Initializing Credit NFT...");
        CreditNFTFacet(address(diamond)).initializeCreditNFT(address(creditOracle));
        console.log("   Initialization complete!");

        // 8. Set Diamond as authorized updater in CreditOracle
        console.log("\n8. Authorizing Diamond in CreditOracle...");
        creditOracle.setAuthorizedUpdater(address(diamond), true);
        console.log("   Authorization complete!");

        // 9. Verify deployment
        console.log("\n=== Deployment Summary ===");
        console.log("CreditOracle:        ", address(creditOracle));
        console.log("Diamond:             ", address(diamond));
        console.log("DiamondCutFacet:     ", address(diamondCutFacet));
        console.log("DiamondLoupeFacet:   ", address(loupeFacet));
        console.log("OwnershipFacet:      ", address(ownershipFacet));
        console.log("CreditNFTFacet:      ", address(creditNFTFacet));
        console.log("\nDiamond Owner:       ", OwnershipFacet(address(diamond)).owner());
        console.log("NFT Name:            ", CreditNFTFacet(address(diamond)).name());
        console.log("NFT Symbol:          ", CreditNFTFacet(address(diamond)).symbol());
        console.log("Version:             ", CreditNFTFacet(address(diamond)).version());

        console.log("\n=== Usage ===");
        console.log("Use the Diamond address for all interactions:", address(diamond));
        console.log("\nTo add/replace facets:");
        console.log("1. Deploy new facet contract");
        console.log("2. Prepare FacetCut array with selectors");
        console.log("3. Call diamondCut(facetCut[], initAddress, initCalldata)");

        vm.stopBroadcast();
    }
}
