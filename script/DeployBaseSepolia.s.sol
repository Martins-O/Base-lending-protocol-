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
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title DeployBaseSepolia
 * @notice Deployment script for Base Sepolia testnet
 * @dev Deploys full protocol stack with test tokens for testing
 *
 * Usage:
 *   forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 *
 * Environment variables needed:
 *   BASE_SEPOLIA_RPC_URL - Base Sepolia RPC endpoint
 *   PRIVATE_KEY - Deployer private key
 *   ETHERSCAN_API_KEY - Basescan API key for verification
 */
contract DeployBaseSepolia is Script {
    // Testnet configuration
    uint256 constant INITIAL_INTEREST_RATE = 500; // 5%
    uint256 constant MAX_STALE_PERIOD = 3600; // 1 hour
    uint256 constant TEST_TOKEN_SUPPLY = 1000000 * 10**6; // 1M tokens

    struct DeploymentAddresses {
        address creditOracle;
        address priceOracle;
        address diamond;
        address diamondCutFacet;
        address diamondLoupeFacet;
        address ownershipFacet;
        address creditNFTFacet;
        address testUSDC;
        address testWETH;
        address testCollateral;
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
        console.log("Deploying to Base Sepolia Testnet");
        console.log("============================================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        DeploymentAddresses memory addrs;

        // Step 1: Deploy test tokens
        console.log("1. Deploying test tokens...");
        addrs.testUSDC = address(new TestToken("Test USDC", "tUSDC", 6, deployer, TEST_TOKEN_SUPPLY));
        console.log("   - Test USDC:", addrs.testUSDC);

        addrs.testWETH = address(new TestToken("Test WETH", "tWETH", 18, deployer, TEST_TOKEN_SUPPLY * 10**12));
        console.log("   - Test WETH:", addrs.testWETH);

        addrs.testCollateral = address(new TestToken("Test Collateral", "tCOL", 6, deployer, TEST_TOKEN_SUPPLY));
        console.log("   - Test Collateral:", addrs.testCollateral);

        // Step 2: Deploy CreditOracle
        console.log("2. Deploying CreditOracle...");
        addrs.creditOracle = address(new CreditOracle());
        console.log("   CreditOracle deployed at:", addrs.creditOracle);

        // Step 3: Deploy PriceOracle
        console.log("3. Deploying PriceOracle...");
        addrs.priceOracle = address(new PriceOracle(deployer));
        console.log("   PriceOracle deployed at:", addrs.priceOracle);

        // Step 4: Configure PriceOracle with manual prices for testing
        console.log("4. Configuring PriceOracle with test prices...");
        PriceOracle priceOracle = PriceOracle(addrs.priceOracle);

        priceOracle.setManualPrice(addrs.testUSDC, 1 * 10**18); // $1
        console.log("   - Test USDC price: $1");

        priceOracle.setManualPrice(addrs.testWETH, 3000 * 10**18); // $3000
        console.log("   - Test WETH price: $3000");

        priceOracle.setManualPrice(addrs.testCollateral, 1 * 10**18); // $1
        console.log("   - Test Collateral price: $1");

        priceOracle.setMaxStalePeriod(MAX_STALE_PERIOD);

        // Step 5: Deploy Diamond facets
        console.log("5. Deploying Diamond facets...");
        addrs.diamondCutFacet = address(new DiamondCutFacet());
        addrs.diamondLoupeFacet = address(new DiamondLoupeFacet());
        addrs.ownershipFacet = address(new OwnershipFacet());
        addrs.creditNFTFacet = address(new CreditNFTFacet());
        console.log("   All facets deployed");

        // Step 6: Prepare Diamond cuts
        console.log("6. Preparing Diamond cuts...");
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
        loupeSelectors[0] = 0xcdffacc6;
        loupeSelectors[1] = 0x52ef6b2c;
        loupeSelectors[2] = 0xadfca15e;
        loupeSelectors[3] = 0x7a0ed627;
        cuts[1] = IDiamondCut.FacetCut({
            facetAddress: addrs.diamondLoupeFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });

        // OwnershipFacet
        bytes4[] memory ownershipSelectors = new bytes4[](2);
        ownershipSelectors[0] = 0x8da5cb5b;
        ownershipSelectors[1] = 0xf2fde38b;
        cuts[2] = IDiamondCut.FacetCut({
            facetAddress: addrs.ownershipFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });

        // CreditNFTFacet
        bytes4[] memory nftSelectors = new bytes4[](8);
        nftSelectors[0] = 0x40c10f19;
        nftSelectors[1] = 0x6352211e;
        nftSelectors[2] = 0x70a08231;
        nftSelectors[3] = 0xc87b56dd;
        nftSelectors[4] = 0x095ea7b3;
        nftSelectors[5] = 0x23b872dd;
        nftSelectors[6] = 0xa22cb465;
        nftSelectors[7] = 0x01ffc9a7;
        cuts[3] = IDiamondCut.FacetCut({
            facetAddress: addrs.creditNFTFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: nftSelectors
        });

        // Step 7: Deploy Diamond
        console.log("7. Deploying Diamond...");
        addrs.diamond = address(new Diamond(deployer, addrs.diamondCutFacet));
        console.log("   Diamond deployed at:", addrs.diamond);

        // Add remaining facets
        IDiamondCut.FacetCut[] memory additionalCuts = new IDiamondCut.FacetCut[](3);
        additionalCuts[0] = cuts[1]; // Loupe
        additionalCuts[1] = cuts[2]; // Ownership
        additionalCuts[2] = cuts[3]; // CreditNFT

        IDiamondCut(addrs.diamond).diamondCut(additionalCuts, address(0), "");
        console.log("   All facets added");

        // Step 8: Initialize CreditNFT
        console.log("8. Initializing CreditNFT...");
        CreditNFTFacet nft = CreditNFTFacet(addrs.diamond);
        nft.initializeCreditNFT(addrs.creditOracle);
        console.log("   CreditNFT initialized");

        // Step 9: Deploy Savings Vaults
        console.log("9. Deploying Savings Vaults...");
        addrs.usdcVault = address(new SavingsVault(
            IERC20(addrs.testUSDC),
            "Test USDC Vault",
            "tvUSDC",
            deployer,
            addrs.creditOracle,
            500 // 5% base APY
        ));
        console.log("   - USDC Vault:", addrs.usdcVault);

        addrs.wethVault = address(new SavingsVault(
            IERC20(addrs.testWETH),
            "Test WETH Vault",
            "tvWETH",
            deployer,
            addrs.creditOracle,
            500 // 5% base APY
        ));
        console.log("   - WETH Vault:", addrs.wethVault);

        // Step 10: Deploy LendingPool
        console.log("10. Deploying LendingPool...");
        addrs.lendingPool = address(new LendingPool(deployer, addrs.creditOracle, addrs.priceOracle));
        console.log("   LendingPool deployed at:", addrs.lendingPool);

        // Step 11: Configure LendingPool
        console.log("11. Configuring LendingPool...");
        LendingPool pool = LendingPool(addrs.lendingPool);

        pool.setSupportedToken(addrs.testUSDC, true);
        pool.setInterestRate(addrs.testUSDC, INITIAL_INTEREST_RATE);

        pool.setSupportedToken(addrs.testWETH, true);
        pool.setInterestRate(addrs.testWETH, INITIAL_INTEREST_RATE);

        pool.setSupportedToken(addrs.testCollateral, true);
        pool.setInterestRate(addrs.testCollateral, INITIAL_INTEREST_RATE);

        console.log("   All tokens configured");

        // Step 12: Provide initial liquidity to LendingPool
        console.log("12. Providing initial liquidity...");
        TestToken(addrs.testUSDC).approve(addrs.lendingPool, 100000 * 10**6);
        TestToken(addrs.testUSDC).transfer(addrs.lendingPool, 100000 * 10**6);
        console.log("   - 100k USDC added to pool");

        TestToken(addrs.testCollateral).approve(addrs.lendingPool, 100000 * 10**6);
        TestToken(addrs.testCollateral).transfer(addrs.lendingPool, 100000 * 10**6);
        console.log("   - 100k Collateral added to pool");

        vm.stopBroadcast();

        // Print deployment summary
        console.log("");
        console.log("============================================================");
        console.log("TESTNET DEPLOYMENT COMPLETE!");
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
        console.log("USDC Vault:          ", addrs.usdcVault);
        console.log("WETH Vault:          ", addrs.wethVault);
        console.log("LendingPool:         ", addrs.lendingPool);
        console.log("");
        console.log("Test Tokens:");
        console.log("------------------------------------------------------------");
        console.log("Test USDC:           ", addrs.testUSDC);
        console.log("Test WETH:           ", addrs.testWETH);
        console.log("Test Collateral:     ", addrs.testCollateral);
        console.log("");
        console.log("Owner/Admin:         ", deployer);
        console.log("");
        console.log("Test Token Faucet:");
        console.log("------------------------------------------------------------");
        console.log("Request test tokens by calling mint() on test token contracts");
        console.log("Each user can mint up to 10k tokens for testing");
        console.log("");
        console.log("Quick Start Guide:");
        console.log("------------------------------------------------------------");
        console.log("1. Mint test tokens: TestToken(address).mint(yourAddress, amount)");
        console.log("2. Approve vault: USDC.approve(vaultAddress, amount)");
        console.log("3. Deposit to vault: Vault.deposit(amount, recipient)");
        console.log("4. Deposit collateral: Pool.depositCollateral(token, amount)");
        console.log("5. Borrow: Pool.borrow(token, amount)");
        console.log("");
        console.log("Basescan URLs:");
        console.log("------------------------------------------------------------");
        console.log("Diamond: https://sepolia.basescan.org/address/", addrs.diamond);
        console.log("Pool:    https://sepolia.basescan.org/address/", addrs.lendingPool);
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
        vm.serializeAddress(json, "testUSDC", addrs.testUSDC);
        vm.serializeAddress(json, "testWETH", addrs.testWETH);
        vm.serializeAddress(json, "testCollateral", addrs.testCollateral);
        vm.serializeAddress(json, "usdcVault", addrs.usdcVault);
        vm.serializeAddress(json, "wethVault", addrs.wethVault);
        string memory output = vm.serializeAddress(json, "lendingPool", addrs.lendingPool);

        string memory filename = string.concat(
            "./deployments/base-sepolia-",
            vm.toString(block.timestamp),
            ".json"
        );

        vm.writeJson(output, filename);
        console.log("Deployment addresses saved to:", filename);
    }
}

/**
 * @title TestToken
 * @notice Simple ERC20 with public minting for testnet
 */
contract TestToken is ERC20 {
    uint8 private _decimals;
    mapping(address => uint256) public mintedAmount;
    uint256 public constant MAX_MINT_PER_USER = 10000 * 10**6;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        address initialOwner,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(initialOwner, initialSupply);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        require(mintedAmount[to] + amount <= MAX_MINT_PER_USER, "Exceeds max mint");
        mintedAmount[to] += amount;
        _mint(to, amount);
    }

    function faucet() external {
        uint256 amount = 1000 * 10**uint256(_decimals);
        require(mintedAmount[msg.sender] + amount <= MAX_MINT_PER_USER, "Exceeds max mint");
        mintedAmount[msg.sender] += amount;
        _mint(msg.sender, amount);
    }
}
