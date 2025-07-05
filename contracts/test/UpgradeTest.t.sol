//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StrategyVault} from "../src/StrategyVault.sol";
import {AaveStrategy} from "../src/strategies/AaveStrategy.sol";
import {AaveAdapter} from "../src/adapters/AaveAdapter.sol";
import {UpgradeAaveStrategy} from "../script/upgrades/UpgradeAaveStrategy.s.sol";
import {EmergencyRollback} from "../script/upgrades/EmergencyRollback.s.sol";

/**
 * @title UpgradeTest
 * @notice Test suite for strategy upgrade functionality
 */
contract UpgradeTest is Test {
    StrategyVault public vault;
    AaveStrategy public strategy;
    AaveAdapter public adapter;
    IERC20 public asset;
    
    UpgradeAaveStrategy public upgradeScript;
    EmergencyRollback public rollbackScript;
    
    // USDC on Arbitrum
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    
    uint256 arbitrumFork;
    
    function setUp() public {
        // Fork Arbitrum mainnet
        arbitrumFork = vm.createFork("arbitrum");
        vm.selectFork(arbitrumFork);
        
        // Use USDC as the test asset
        asset = IERC20(USDC);
        
        // Deploy system components
        vm.startPrank(owner);
        
        // Deploy adapter
        adapter = new AaveAdapter();
        adapter.registerAsset(USDC);
        
        // Deploy strategy using UUPS proxy pattern
        AaveStrategy strategyImpl = new AaveStrategy();
        bytes memory initData = abi.encodeWithSelector(
            AaveStrategy.initialize.selector,
            USDC,
            address(adapter),
            "Aave USDC Strategy"
        );
        
        ERC1967Proxy strategyProxy = new ERC1967Proxy(
            address(strategyImpl),
            initData
        );
        
        strategy = AaveStrategy(address(strategyProxy));
        
        // Deploy vault
        vault = new StrategyVault(
            USDC,
            "Aave USDC Vault",
            "aavUSDC",
            address(strategy)
        );
        
        // Set vault on strategy
        strategy.setVault(address(vault));
        
        // Deploy upgrade scripts
        upgradeScript = new UpgradeAaveStrategy();
        rollbackScript = new EmergencyRollback();
        
        vm.stopPrank();
        
        // Give user some USDC
        deal(USDC, user, 10000e6);
    }
    
    function testUpgradeScriptDeployment() public {
        console2.log("=== UPGRADE SCRIPT DEPLOYMENT TEST ===");
        
        // Test script deployment
        assertNotEq(address(upgradeScript), address(0));
        assertNotEq(address(rollbackScript), address(0));
        
        console2.log("Upgrade script deployed at:", address(upgradeScript));
        console2.log("Rollback script deployed at:", address(rollbackScript));
        
        console2.log("Upgrade scripts deployed successfully");
    }
    
    function testGetStrategyInfo() public {
        console2.log("=== GET STRATEGY INFO TEST ===");
        
        // Get strategy info
        upgradeScript.getStrategyInfo(address(strategy));
        
        // Verify we can get implementation
        address impl = rollbackScript.getCurrentImplementation(address(strategy));
        assertNotEq(impl, address(0));
        
        console2.log("Current implementation:", impl);
        console2.log("Strategy info retrieved successfully");
    }
    
    function testUpgradeSimulation() public {
        console2.log("=== UPGRADE SIMULATION TEST ===");
        
        // Deploy new implementation
        AaveStrategy newImpl = new AaveStrategy();
        
        // Simulate upgrade
        bool success = upgradeScript.simulateUpgrade(address(strategy), address(newImpl));
        assertTrue(success);
        
        console2.log("Upgrade simulation passed");
    }
    
    function testStrategyUpgrade() public {
        console2.log("=== STRATEGY UPGRADE TEST ===");
        
        // Make initial deposit
        vm.startPrank(user);
        asset.approve(address(vault), 1000e6);
        vault.deposit(1000e6, user);
        vm.stopPrank();
        
        // Capture pre-upgrade state
        uint256 totalAssetsBefore = strategy.totalAssets();
        uint256 apyBefore = strategy.getAPY();
        address ownerBefore = strategy.owner();
        
        console2.log("Pre-upgrade total assets:", totalAssetsBefore);
        console2.log("Pre-upgrade APY:", apyBefore);
        console2.log("Pre-upgrade owner:", ownerBefore);
        
        // Deploy new implementation
        AaveStrategy newImpl = new AaveStrategy();
        address previousImpl = rollbackScript.getCurrentImplementation(address(strategy));
        
        // Perform upgrade
        vm.prank(owner);
        upgradeScript.upgradeAaveStrategy(address(strategy), address(newImpl), "");
        
        // Verify upgrade
        address currentImpl = rollbackScript.getCurrentImplementation(address(strategy));
        assertEq(currentImpl, address(newImpl));
        assertNotEq(currentImpl, previousImpl);
        
        // Verify state preserved
        assertEq(strategy.totalAssets(), totalAssetsBefore);
        assertEq(strategy.owner(), ownerBefore);
        assertEq(address(strategy.asset()), USDC);
        assertEq(address(strategy.adapter()), address(adapter));
        
        console2.log("Post-upgrade total assets:", strategy.totalAssets());
        console2.log("Post-upgrade APY:", strategy.getAPY());
        console2.log("Post-upgrade owner:", strategy.owner());
        console2.log("Strategy upgrade completed successfully");
    }
    
    function testUpgradeWithNewDeployment() public {
        console2.log("=== UPGRADE WITH NEW DEPLOYMENT TEST ===");
        
        // Make initial deposit
        vm.startPrank(user);
        asset.approve(address(vault), 1000e6);
        vault.deposit(1000e6, user);
        vm.stopPrank();
        
        address previousImpl = rollbackScript.getCurrentImplementation(address(strategy));
        
        // Upgrade with new deployment
        vm.prank(owner);
        upgradeScript.upgradeWithNewImplementation(address(strategy), "");
        
        // Verify upgrade
        address currentImpl = rollbackScript.getCurrentImplementation(address(strategy));
        assertNotEq(currentImpl, previousImpl);
        
        // Verify functionality
        assertGt(strategy.totalAssets(), 0);
        assertEq(strategy.owner(), owner);
        
        console2.log("Upgrade with new deployment completed successfully");
    }
    
    function testEmergencyRollback() public {
        console2.log("=== EMERGENCY ROLLBACK TEST ===");
        
        // Make initial deposit
        vm.startPrank(user);
        asset.approve(address(vault), 1000e6);
        vault.deposit(1000e6, user);
        vm.stopPrank();
        
        // Capture initial state
        address initialImpl = rollbackScript.getCurrentImplementation(address(strategy));
        uint256 totalAssetsBefore = strategy.totalAssets();
        
        // Perform upgrade
        AaveStrategy newImpl = new AaveStrategy();
        vm.prank(owner);
        upgradeScript.upgradeAaveStrategy(address(strategy), address(newImpl), "");
        
        // Verify upgrade happened
        address upgradedImpl = rollbackScript.getCurrentImplementation(address(strategy));
        assertEq(upgradedImpl, address(newImpl));
        
        // Perform emergency rollback
        vm.prank(owner);
        rollbackScript.emergencyRollbackSingle(
            address(strategy),
            initialImpl,
            "Test rollback"
        );
        
        // Verify rollback
        address rolledBackImpl = rollbackScript.getCurrentImplementation(address(strategy));
        assertEq(rolledBackImpl, initialImpl);
        
        // Verify functionality after rollback
        assertEq(strategy.totalAssets(), totalAssetsBefore);
        assertEq(strategy.owner(), owner);
        
        console2.log("Emergency rollback completed successfully");
    }
    
    function testRollbackValidation() public {
        console2.log("=== ROLLBACK VALIDATION TEST ===");
        
        // Test rollback to same implementation (should fail)
        address currentImpl = rollbackScript.getCurrentImplementation(address(strategy));
        
        vm.prank(owner);
        vm.expectRevert();
        rollbackScript.emergencyRollbackSingle(
            address(strategy),
            currentImpl,
            "Test invalid rollback"
        );
        
        // Test rollback to zero address (should fail)
        vm.prank(owner);
        vm.expectRevert();
        rollbackScript.emergencyRollbackSingle(
            address(strategy),
            address(0),
            "Test invalid rollback"
        );
        
        console2.log("Rollback validation working correctly");
    }
    
    function testHealthChecks() public {
        console2.log("=== HEALTH CHECKS TEST ===");
        
        // Test health check
        bool isHealthy = rollbackScript.quickHealthCheck(address(strategy));
        assertTrue(isHealthy);
        
        // Test emergency info
        rollbackScript.emergencyInfo(address(strategy));
        
        console2.log("Health checks working correctly");
    }
    
    function testBatchUpgrade() public {
        console2.log("=== BATCH UPGRADE TEST ===");
        
        // Deploy second strategy
        vm.startPrank(owner);
        AaveStrategy strategyImpl2 = new AaveStrategy();
        bytes memory initData2 = abi.encodeWithSelector(
            AaveStrategy.initialize.selector,
            USDC,
            address(adapter),
            "Aave USDC Strategy 2"
        );
        
        ERC1967Proxy strategyProxy2 = new ERC1967Proxy(
            address(strategyImpl2),
            initData2
        );
        
        AaveStrategy strategy2 = AaveStrategy(address(strategyProxy2));
        vm.stopPrank();
        
        // Prepare batch upgrade
        address[] memory strategies = new address[](2);
        strategies[0] = address(strategy);
        strategies[1] = address(strategy2);
        
        AaveStrategy newImpl = new AaveStrategy();
        
        // Perform batch upgrade
        vm.prank(owner);
        upgradeScript.batchUpgradeStrategies(strategies, address(newImpl), "");
        
        // Verify both upgrades
        assertEq(rollbackScript.getCurrentImplementation(address(strategy)), address(newImpl));
        assertEq(rollbackScript.getCurrentImplementation(address(strategy2)), address(newImpl));
        
        console2.log("Batch upgrade completed successfully");
    }
    
    function testUpgradeWithFunctionality() public {
        console2.log("=== UPGRADE WITH FUNCTIONALITY TEST ===");
        
        // Make deposits before upgrade
        vm.startPrank(user);
        asset.approve(address(vault), 2000e6);
        vault.deposit(1000e6, user);
        vm.stopPrank();
        
        uint256 sharesBefore = vault.balanceOf(user);
        uint256 assetsBefore = strategy.totalAssets();
        
        // Perform upgrade
        AaveStrategy newImpl = new AaveStrategy();
        vm.prank(owner);
        upgradeScript.upgradeAaveStrategy(address(strategy), address(newImpl), "");
        
        // Test functionality after upgrade
        vm.startPrank(user);
        // Should be able to deposit more
        vault.deposit(1000e6, user);
        
        // Should be able to withdraw
        uint256 withdrawAmount = 500e6;
        vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();
        
        // Verify functionality
        assertGt(vault.balanceOf(user), sharesBefore);
        assertGt(strategy.totalAssets(), assetsBefore);
        
        console2.log("Upgrade with functionality test passed");
    }
    
    function testUpgradePermissions() public {
        console2.log("=== UPGRADE PERMISSIONS TEST ===");
        
        // Deploy new implementation
        AaveStrategy newImpl = new AaveStrategy();
        
        // Test that non-owner cannot upgrade
        vm.prank(user);
        vm.expectRevert();
        upgradeScript.upgradeAaveStrategy(address(strategy), address(newImpl), "");
        
        // Test that owner can upgrade
        vm.prank(owner);
        upgradeScript.upgradeAaveStrategy(address(strategy), address(newImpl), "");
        
        console2.log("Upgrade permissions working correctly");
    }
} 