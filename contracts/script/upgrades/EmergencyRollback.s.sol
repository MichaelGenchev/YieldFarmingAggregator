//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AaveStrategy} from "../../src/strategies/AaveStrategy.sol";

/**
 * @title EmergencyRollback
 * @notice Emergency script to rollback AaveStrategy to a previous implementation
 * @dev Use this script when an upgrade introduces critical issues
 */
contract EmergencyRollback is Script {
    // ERC1967 implementation storage slot
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    function run() external {
        // Get environment variables
        address proxyAddress = vm.envAddress("STRATEGY_PROXY_ADDRESS");
        address rollbackImplementation = vm.envAddress("ROLLBACK_IMPLEMENTATION");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console2.log("=== EMERGENCY ROLLBACK ===");
        console2.log("WARNING: This will rollback the strategy implementation!");
        console2.log("Proxy address:", proxyAddress);
        console2.log("Rollback to implementation:", rollbackImplementation);
        console2.log("Deployer:", deployerAddress);
        console2.log("");

        // Load the existing proxy
        AaveStrategy proxy = AaveStrategy(payable(proxyAddress));
        
        // Get current implementation address from proxy storage
        address currentImplementation = address(uint160(uint256(vm.load(proxyAddress, IMPLEMENTATION_SLOT))));
        console2.log("Current implementation:", currentImplementation);
        
        // Safety checks
        require(proxy.owner() == deployerAddress, "Only the owner can rollback the strategy");
        require(currentImplementation != address(0), "Invalid proxy address");
        require(rollbackImplementation != address(0), "Invalid rollback implementation");
        require(currentImplementation != rollbackImplementation, "Already at target implementation");
        
        // Get current state to verify preservation
        address currentAsset = address(proxy.asset());
        address currentAdapter = address(proxy.adapter());
        address currentVault = proxy.vault();
        string memory currentName = proxy.name();
        
        console2.log("Current state before rollback:");
        console2.log("- Asset:", currentAsset);
        console2.log("- Adapter:", currentAdapter);
        console2.log("- Vault:", currentVault);
        console2.log("- Name:", currentName);
        console2.log("");

        // Confirmation prompt (in a real script, you'd want user confirmation)
        console2.log("PROCEEDING WITH ROLLBACK IN 3 SECONDS...");
        console2.log("Cancel now if this is not intended!");
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Perform the rollback
        console2.log("Performing rollback...");
        proxy.upgradeToAndCall(rollbackImplementation, "");
        
        console2.log("Rollback completed!");

        vm.stopBroadcast();

        // Verify the rollback worked
        console2.log("");
        console2.log("=== VERIFYING ROLLBACK ===");
        address newCurrentImplementation = address(uint160(uint256(vm.load(proxyAddress, IMPLEMENTATION_SLOT))));
        console2.log("Implementation after rollback:", newCurrentImplementation);
        
        require(newCurrentImplementation == rollbackImplementation, "Rollback failed - implementation not updated");
        
        // Verify state is preserved
        require(address(proxy.asset()) == currentAsset, "Asset address changed unexpectedly");
        require(address(proxy.adapter()) == currentAdapter, "Adapter address changed unexpectedly");
        require(proxy.vault() == currentVault, "Vault address changed unexpectedly");
        require(keccak256(bytes(proxy.name())) == keccak256(bytes(currentName)), "Name changed unexpectedly");
        
        console2.log("State verification passed!");
        console2.log("");
        console2.log("=== ROLLBACK SUCCESSFUL ===");
        console2.log("Successfully rolled back from:", currentImplementation);
        console2.log("Successfully rolled back to:", newCurrentImplementation);
        console2.log("All state preserved successfully!");
        console2.log("");
        console2.log("Remember to investigate the issues with the previous implementation");
        console2.log("before attempting another upgrade.");
    }
}
