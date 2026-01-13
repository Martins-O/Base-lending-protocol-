// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/CreditOracle.sol";
import "../src/PriceOracle.sol";
import "../src/SavingsVault.sol";
import "../src/LendingPool.sol";
import "../src/diamond/Diamond.sol";
import "../src/diamond/facets/DiamondCutFacet.sol";
import "../src/diamond/facets/DiamondLoupeFacet.sol";
import "../src/diamond/facets/OwnershipFacet.sol";
import "../src/diamond/facets/CreditNFTFacet.sol";
import "../src/diamond/interfaces/IDiamondCut.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployBaseMainnet
 * @notice Deployment script for Base mainnet
 * @dev Deploys full protocol stack with proper configuration
 *
 * Usage:
 *   forge script script/DeployBaseMainnet.s.sol:DeployBaseMainnet \
 *     --rpc-url $BASE_RPC_URL \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 *
 * Environment variables needed:
 *   BASE_RPC_URL - Base mainnet RPC endpoint
 *   PRIVATE_KEY - Deployer private key
 *   ETHERSCAN_API_KEY - Basescan API key for verification
 */
contract DeployBaseMainnet is Script {
    // Base mainnet Chainlink price feeds
    address constant ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant USDC_USD_FEED = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address constant BTC_USD_FEED = 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F;

    // Base mainnet token addresses
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant CBETH = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;

    // Deployment configuration
    uint256 constant INITIAL_INTEREST_RATE = 500; // 5%
    uint256 constant MAX_STALE_PERIOD = 3600; // 1 hour

    struct DeploymentAddresses {
        address creditOracle;
        address priceOracle;
        address diamond;
        address diamondCutFacet;
        address diamondLoupeFacet;
        address ownershipFacet;
        address creditNFTFacet;
        address usdcVault;
        address wethVault;
        address lendingPool;
    }

    function run() external {
        // Try to read private key - handles both with and without 0x prefix
        uint256 deployerPrivateKey;
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
        } catch {
            // If envUint fails, try reading as bytes32 and converting
            bytes32 pkBytes = vm.envBytes32("PRIVATE_KEY");
            deployerPrivateKey = uint256(pkBytes);
        }
        address deployer = vm.addr(deployerPrivateKey);

        console.log("============================================================");
        console.log("Deploying Base Credit Lending Protocol to Base Mainnet");
        console.log("============================================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        DeploymentAddresses memory addrs;

        // Step 1: Deploy CreditOracle
        console.log("1. Deploying CreditOracle...");
        addrs.creditOracle = address(new CreditOracle());
        console.log("   CreditOracle deployed at:", addrs.creditOracle);

        // Step 2: Deploy PriceOracle
        console.log("2. Deploying PriceOracle...");
        addrs.priceOracle = address(new PriceOracle(deployer));
        console.log("   PriceOracle deployed at:", addrs.priceOracle);

        // Step 3: Configure PriceOracle with Chainlink feeds
        console.log("3. Configuring PriceOracle...");
        PriceOracle priceOracle = PriceOracle(addrs.priceOracle);

        priceOracle.setPriceFeed(WETH, ETH_USD_FEED);
        console.log("   - WETH feed configured");

        priceOracle.setPriceFeed(USDC, USDC_USD_FEED);
        console.log("   - USDC feed configured");

        priceOracle.setPriceFeed(CBETH, BTC_USD_FEED);
        console.log("   - cbETH feed configured");

        priceOracle.setMaxStalePeriod(MAX_STALE_PERIOD);
        console.log("   - Max stale period set to", MAX_STALE_PERIOD, "seconds");

        // Step 4: Deploy Diamond facets
        console.log("4. Deploying Diamond facets...");
        addrs.diamondCutFacet = address(new DiamondCutFacet());
        addrs.diamondLoupeFacet = address(new DiamondLoupeFacet());
        addrs.ownershipFacet = address(new OwnershipFacet());
        addrs.creditNFTFacet = address(new CreditNFTFacet());
        console.log("   - DiamondCutFacet:", addrs.diamondCutFacet);
        console.log("   - DiamondLoupeFacet:", addrs.diamondLoupeFacet);
        console.log("   - OwnershipFacet:", addrs.ownershipFacet);
        console.log("   - CreditNFTFacet:", addrs.creditNFTFacet);

        // Step 5: Prepare Diamond cuts
        console.log("5. Preparing Diamond cuts...");
        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](4);

        // DiamondCutFacet
        bytes4[] memory cutSelectors = new bytes4[](1);
        cutSelectors[0] = IDiamondCut.diamondCut.selector;
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: addrs.diamondCutFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: cutSelectors
        });

        // DiamondLoupeFacet
        bytes4[] memory loupeSelectors = new bytes4[](4);
        loupeSelectors[0] = 0xcdffacc6; // facets()
        loupeSelectors[1] = 0x52ef6b2c; // facetFunctionSelectors()
        loupeSelectors[2] = 0xadfca15e; // facetAddresses()
        loupeSelectors[3] = 0x7a0ed627; // facetAddress()
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: addrs.diamondLoupeFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });

        // OwnershipFacet
        bytes4[] memory ownershipSelectors = new bytes4[](2);
        ownershipSelectors[0] = 0x8da5cb5b; // owner()
        ownershipSelectors[1] = 0xf2fde38b; // transferOwnership()
        cuts[2] = IDiamondCut.FacetCut({
            facetAddress: addrs.ownershipFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });

        // CreditNFTFacet
        bytes4[] memory nftSelectors = new bytes4[](8);
        nftSelectors[0] = 0x40c10f19; // mint()
        nftSelectors[1] = 0x6352211e; // ownerOf()
        nftSelectors[2] = 0x70a08231; // balanceOf()
        nftSelectors[3] = 0xc87b56dd; // tokenURI()
        nftSelectors[4] = 0x095ea7b3; // approve()
        nftSelectors[5] = 0x23b872dd; // transferFrom()
        nftSelectors[6] = 0xa22cb465; // setApprovalForAll()
        nftSelectors[7] = 0x01ffc9a7; // supportsInterface()
        cuts[3] = IDiamondCut.FacetCut({
            facetAddress: addrs.creditNFTFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: nftSelectors
        });

        // Step 6: Deploy Diamond
        console.log("6. Deploying Diamond...");
        addrs.diamond = address(new Diamond(deployer, addrs.diamondCutFacet));
        console.log("   Diamond deployed at:", addrs.diamond);

        // Add remaining facets
        console.log("   Adding facets to Diamond...");
        IDiamondCut.FacetCut[] memory additionalCuts = new IDiamondCut.FacetCut[](3);
        additionalCuts[0] = cuts[1]; // Loupe
        additionalCuts[1] = cuts[2]; // Ownership
        additionalCuts[2] = cuts[3]; // CreditNFT

        IDiamondCut(addrs.diamond).diamondCut(additionalCuts, address(0), "");
        console.log("   All facets added");

        // Step 7: Initialize CreditNFT in Diamond
        console.log("7. Initializing CreditNFT...");
        CreditNFTFacet nft = CreditNFTFacet(addrs.diamond);
        nft.initializeCreditNFT(addrs.creditOracle);
        console.log("   CreditNFT initialized");

        // Step 8: Deploy Savings Vaults
        console.log("8. Deploying Savings Vaults...");
        addrs.usdcVault = address(new SavingsVault(
            IERC20(USDC),
            "Base Credit USDC Vault",
            "bcvUSDC",
            deployer,
            addrs.creditOracle,
            500 // 5% base APY
        ));
        console.log("   - USDC Vault deployed at:", addrs.usdcVault);

        addrs.wethVault = address(new SavingsVault(
            IERC20(WETH),
            "Base Credit WETH Vault",
            "bcvWETH",
            deployer,
            addrs.creditOracle,
            500 // 5% base APY
        ));
        console.log("   - WETH Vault deployed at:", addrs.wethVault);

        // Step 9: Deploy LendingPool
        console.log("9. Deploying LendingPool...");
        addrs.lendingPool = address(new LendingPool(deployer, addrs.creditOracle, addrs.priceOracle));
        console.log("   LendingPool deployed at:", addrs.lendingPool);

        // Step 10: Configure LendingPool
        console.log("10. Configuring LendingPool...");
        LendingPool pool = LendingPool(addrs.lendingPool);

        pool.setSupportedToken(USDC, true);
        pool.setInterestRate(USDC, INITIAL_INTEREST_RATE);
        console.log("   - USDC added with", INITIAL_INTEREST_RATE / 100, "% interest");

        pool.setSupportedToken(WETH, true);
        pool.setInterestRate(WETH, INITIAL_INTEREST_RATE);
        console.log("   - WETH added with", INITIAL_INTEREST_RATE / 100, "% interest");

        pool.setSupportedToken(CBETH, true);
        pool.setInterestRate(CBETH, INITIAL_INTEREST_RATE);
        console.log("   - cbETH added with", INITIAL_INTEREST_RATE / 100, "% interest");

        vm.stopBroadcast();

        // Print deployment summary
        console.log("");
        console.log("============================================================");
        console.log("DEPLOYMENT COMPLETE!");
        console.log("============================================================");
        console.log("");
        printDeploymentSummary(addrs, deployer);

        // Save deployment addresses
        saveDeploymentAddresses(addrs);
    }

    function printDeploymentSummary(DeploymentAddresses memory addrs, address deployer) internal view {
        console.log("Contract Addresses:");
        console.log("------------------------------------------------------------");
        console.log("CreditOracle:        ", addrs.creditOracle);
        console.log("PriceOracle:         ", addrs.priceOracle);
        console.log("Diamond (NFT):       ", addrs.diamond);
        console.log("  - DiamondCutFacet: ", addrs.diamondCutFacet);
        console.log("  - DiamondLoupeFacet:", addrs.diamondLoupeFacet);
        console.log("  - OwnershipFacet:  ", addrs.ownershipFacet);
        console.log("  - CreditNFTFacet:  ", addrs.creditNFTFacet);
        console.log("USDC Vault:          ", addrs.usdcVault);
        console.log("WETH Vault:          ", addrs.wethVault);
        console.log("LendingPool:         ", addrs.lendingPool);
        console.log("");
        console.log("Owner/Admin:         ", deployer);
        console.log("");
        console.log("Supported Tokens:");
        console.log("------------------------------------------------------------");
        console.log("USDC:                ", USDC);
        console.log("WETH:                ", WETH);
        console.log("cbETH:               ", CBETH);
        console.log("");
        console.log("Next Steps:");
        console.log("------------------------------------------------------------");
        console.log("1. Verify contracts on Basescan");
        console.log("2. Transfer ownership to multi-sig (Gnosis Safe)");
        console.log("3. Add liquidity to LendingPool");
        console.log("4. Set up monitoring (Tenderly/Defender)");
        console.log("5. Announce deployment to community");
        console.log("");
    }

    function saveDeploymentAddresses(DeploymentAddresses memory addrs) internal {
        string memory json = "deployment";

        vm.serializeAddress(json, "creditOracle", addrs.creditOracle);
        vm.serializeAddress(json, "priceOracle", addrs.priceOracle);
        vm.serializeAddress(json, "diamond", addrs.diamond);
        vm.serializeAddress(json, "diamondCutFacet", addrs.diamondCutFacet);
        vm.serializeAddress(json, "diamondLoupeFacet", addrs.diamondLoupeFacet);
        vm.serializeAddress(json, "ownershipFacet", addrs.ownershipFacet);
        vm.serializeAddress(json, "creditNFTFacet", addrs.creditNFTFacet);
        vm.serializeAddress(json, "usdcVault", addrs.usdcVault);
        vm.serializeAddress(json, "wethVault", addrs.wethVault);
        string memory output = vm.serializeAddress(json, "lendingPool", addrs.lendingPool);

        string memory filename = string.concat(
            "./deployments/base-mainnet-",
            vm.toString(block.timestamp),
            ".json"
        );

        vm.writeJson(output, filename);
        console.log("Deployment addresses saved to:", filename);
    }
}
