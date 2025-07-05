//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AaveStrategy} from "../../src/strategies/AaveStrategy.sol";

/**
 * @title UpgradeAaveStrategy
 * @notice Script to upgrade AaveStrategy to a new implementation
 * @dev This script safely upgrades the strategy while preserving all state
 */
contract UpgradeAaveStrategy is Script {
    // ERC1967 implementation storage slot
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    function run() external {
        // Get environment variables
        address proxyAddress = vm.envAddress("STRATEGY_PROXY_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console2.log("=== UPGRADING AAVE STRATEGY ===");
        console2.log("Proxy address:", proxyAddress);
        console2.log("Deployer:", deployerAddress);
        console2.log("");

        // Load the existing proxy
        AaveStrategy proxy = AaveStrategy(payable(proxyAddress));
        
        // Get current implementation address from proxy storage
        address currentImplementation = address(uint160(uint256(vm.load(proxyAddress, IMPLEMENTATION_SLOT))));
        console2.log("Current implementation:", currentImplementation);
        
        // Safety checks
        require(proxy.owner() == deployerAddress, "Only the owner can upgrade the strategy");
        require(currentImplementation != address(0), "Invalid proxy address");
        
        // Get current state to verify preservation
        address currentAsset = address(proxy.asset());
        address currentAdapter = address(proxy.adapter());
        address currentVault = proxy.vault();
        string memory currentName = proxy.name();
        
        console2.log("Current asset:", currentAsset);
        console2.log("Current adapter:", currentAdapter);
        console2.log("Current vault:", currentVault);
        console2.log("Current name:", currentName);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        console2.log("Deploying new implementation...");
        AaveStrategy newImplementation = new AaveStrategy();
        address newImplementationAddress = address(newImplementation);
        console2.log("New implementation deployed at:", newImplementationAddress);
        
        // Verify it's actually different
        require(newImplementationAddress != currentImplementation, "Same implementation address");
        
        // Perform the upgrade (no initialization data needed for simple upgrades)
        console2.log("Performing upgrade...");
        proxy.upgradeToAndCall(newImplementationAddress, "");
        
        console2.log("Upgrade completed!");

        vm.stopBroadcast();

        // Verify the upgrade worked
        console2.log("");
        console2.log("=== VERIFYING UPGRADE ===");
        address newCurrentImplementation = address(uint160(uint256(vm.load(proxyAddress, IMPLEMENTATION_SLOT))));
        console2.log("New implementation address:", newCurrentImplementation);
        
        require(newCurrentImplementation == newImplementationAddress, "Upgrade failed - implementation not updated");
        
        // Verify state is preserved
        require(address(proxy.asset()) == currentAsset, "Asset address changed unexpectedly");
        require(address(proxy.adapter()) == currentAdapter, "Adapter address changed unexpectedly");
        require(proxy.vault() == currentVault, "Vault address changed unexpectedly");
        require(keccak256(bytes(proxy.name())) == keccak256(bytes(currentName)), "Name changed unexpectedly");
        
        console2.log("State verification passed!");
        console2.log("");
        console2.log("=== UPGRADE SUCCESSFUL ===");
        console2.log("Old implementation:", currentImplementation);
        console2.log("New implementation:", newCurrentImplementation);
        console2.log("All state preserved successfully!");
    }
}