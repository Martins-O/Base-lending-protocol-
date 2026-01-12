// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SoulboundCreditNFT} from "../src/SoulboundCreditNFT.sol";
import {CreditOracle} from "../src/CreditOracle.sol";

/**
 * @title DeployUpgradeable
 * @notice Script to deploy upgradeable SoulboundCreditNFT using UUPS proxy
 * @dev Usage: forge script script/DeployUpgradeable.s.sol:DeployUpgradeable --rpc-url <your_rpc_url> --broadcast
 */
contract DeployUpgradeable is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy CreditOracle
        console.log("Deploying CreditOracle...");
        CreditOracle creditOracle = new CreditOracle();
        console.log("CreditOracle deployed at:", address(creditOracle));

        // 2. Deploy the implementation contract
        console.log("Deploying SoulboundCreditNFT implementation...");
        SoulboundCreditNFT implementation = new SoulboundCreditNFT();
        console.log("Implementation deployed at:", address(implementation));

        // 3. Encode the initializer function call
        bytes memory data = abi.encodeWithSelector(
            SoulboundCreditNFT.initialize.selector,
            address(creditOracle)
        );

        // 4. Deploy the proxy contract
        console.log("Deploying ERC1967Proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            data
        );
        console.log("Proxy deployed at:", address(proxy));

        // 5. Wrap the proxy address with the implementation ABI
        SoulboundCreditNFT nft = SoulboundCreditNFT(address(proxy));

        // 6. Verify the deployment
        console.log("\n=== Deployment Summary ===");
        console.log("CreditOracle:", address(creditOracle));
        console.log("NFT Implementation:", address(implementation));
        console.log("NFT Proxy (use this):", address(proxy));
        console.log("Owner:", nft.owner());
        console.log("Version:", nft.version());

        // 7. Set NFT as authorized updater in CreditOracle
        console.log("\nAuthorizing NFT contract in CreditOracle...");
        creditOracle.setAuthorizedUpdater(address(proxy), true);
        console.log("Authorization complete!");

        vm.stopBroadcast();

        // Log instructions for upgrade
        console.log("\n=== Upgrade Instructions ===");
        console.log("To upgrade the implementation:");
        console.log("1. Deploy new implementation contract");
        console.log("2. Call upgradeToAndCall on proxy:");
        console.log("   SoulboundCreditNFT(proxy).upgradeToAndCall(newImplementation, data)");
    }
}
