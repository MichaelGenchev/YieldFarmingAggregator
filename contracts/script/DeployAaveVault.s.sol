//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {StrategyVault} from "../src/StrategyVault.sol";
import {AaveStrategy} from "../src/strategies/AaveStrategy.sol";
import {AaveAdapter} from "../src/adapters/AaveAdapter.sol";

/**
 * @title DeployAaveVault
 * @notice Deployment script for the modular Aave vault system
 * @dev This script deploys the complete system: Adapter -> Strategy -> Vault
 */
contract DeployAaveVault is Script {
    // USDC on Arbitrum
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== DEPLOYING AAVE VAULT SYSTEM ===");
        console.log("Deployer:", deployer);
        console.log("Asset (USDC):", USDC);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy AaveAdapter
        console.log("1. Deploying AaveAdapter...");
        AaveAdapter adapter = new AaveAdapter();
        console.log("AaveAdapter deployed at:", address(adapter));
        
        // 2. Register USDC with the adapter
        console.log("2. Registering USDC with adapter...");
        adapter.registerAsset(USDC);
        console.log("USDC registered successfully");
        
        // 3. Deploy AaveStrategy
        console.log("3. Deploying AaveStrategy...");
        AaveStrategy strategy = new AaveStrategy(
            USDC,
            address(adapter),
            "Aave USDC Strategy"
        );
        console.log("AaveStrategy deployed at:", address(strategy));
        
        // 4. Deploy StrategyVault
        console.log("4. Deploying StrategyVault...");
        StrategyVault vault = new StrategyVault(
            USDC,
            "Aave USDC Vault",
            "aavUSDC",
            address(strategy)
        );
        console.log("StrategyVault deployed at:", address(vault));
        
        // 5. Set vault address on strategy
        console.log("5. Setting vault address on strategy...");
        strategy.setVault(address(vault));
        console.log("Vault address set on strategy");
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== DEPLOYMENT COMPLETED ===");
        console.log("AaveAdapter:", address(adapter));
        console.log("AaveStrategy:", address(strategy));
        console.log("StrategyVault:", address(vault));
        console.log("");
        
        // Verify deployment
        console.log("=== VERIFYING DEPLOYMENT ===");
        console.log("Vault asset:", address(vault.asset()));
        console.log("Vault strategy:", address(vault.strategy()));
        console.log("Strategy vault:", strategy.vault());
        console.log("Strategy adapter:", address(strategy.adapter()));
        console.log("USDC registered:", adapter.isAssetRegistered(USDC));
        console.log("aToken address:", adapter.getAToken(USDC));
        console.log("System ready for deposits!");
        
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Approve vault to spend your USDC:");
        console.log("   USDC.approve(", address(vault), ", amount)");
        console.log("2. Deposit USDC to start earning yield:");
        console.log("   vault.deposit(amount, your_address)");
        console.log("3. Monitor vault health:");
        console.log("   vault.getVaultHealth()");
        console.log("4. Check current APY:");
        console.log("   vault.getAPY()");
    }
} 