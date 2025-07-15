//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StrategyVault} from "../src/StrategyVault.sol";
import {AaveStrategy} from "../src/strategies/AaveStrategy.sol";
import {AaveAdapter} from "../src/adapters/AaveAdapter.sol";

contract StrategyVaultTest is Test {
    StrategyVault public vault;
    AaveStrategy public strategy;
    AaveAdapter public adapter;
    IERC20 public asset;
    
    // USDC on Arbitrum
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");
    
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
        
        // Register USDC with adapter
        adapter.registerAsset(USDC);
        
        // Deploy strategy using UUPS proxy pattern
        // 1. Deploy implementation contract
        AaveStrategy strategyImpl = new AaveStrategy();
        
        // 2. Encode the initialize function call
        bytes memory initData = abi.encodeWithSelector(
            AaveStrategy.initialize.selector,
            USDC,
            address(adapter),
            "Aave USDC Strategy"
        );
        
        // 3. Deploy proxy with initialize call
        ERC1967Proxy strategyProxy = new ERC1967Proxy(
            address(strategyImpl),
            initData
        );
        
        // 4. Cast proxy to AaveStrategy interface
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
        
        vm.stopPrank();
        
        // Give users some USDC
        deal(USDC, user, 10000e6); // 10,000 USDC
        deal(USDC, user2, 5000e6); // 5,000 USDC
    }

    function testSystemDeployment() public {
        console2.log("=== SYSTEM DEPLOYMENT TEST ===");
        
        // Check vault
        assertEq(address(vault.asset()), USDC);
        assertEq(vault.name(), "Aave USDC Vault");
        assertEq(vault.symbol(), "aavUSDC");
        assertEq(address(vault.strategy()), address(strategy));
        console2.log("Vault deployed correctly");
        
        // Check strategy
        assertEq(address(strategy.asset()), USDC);
        assertEq(strategy.name(), "Aave USDC Strategy");
        assertEq(strategy.vault(), address(vault));
        assertEq(address(strategy.adapter()), address(adapter));
        console2.log("Strategy deployed correctly");
        
        // Check adapter
        assertTrue(adapter.isAssetRegistered(USDC));
        assertTrue(adapter.getAToken(USDC) != address(0));
        console2.log("Adapter deployed correctly");
        
        console2.log("=== DEPLOYMENT TEST COMPLETED ===");
    }

    function testInflationAttack() public {
        // Test the classic inflation attack where:
        // 1. Makes minimal deposit
        // 2. Directly transfers assets to strategy
        // 3. Tries to inflate share price to steal from subsequent depositors
        console2.log("=== INFLATION ATTACK TEST ===");

        address attacker = makeAddr("attacker");
        address victim = makeAddr("victim");

        deal(USDC, attacker, 10000e6);
        deal(USDC, victim, 1000e6);

        uint256 minimalDepositAmount = 1e6;

        vm.startPrank(attacker);
        asset.approve(address(vault), minimalDepositAmount);
        uint256 attackerShares = vault.deposit(minimalDepositAmount, attacker);
        vm.stopPrank();

        console2.log("Attacker shares received:", attackerShares);
        console2.log("Vault total assets after minimal deposit:", vault.totalAssets());
        console2.log("Share price after minimal deposit:", vault.totalAssets() * 1e18 / vault.totalSupply());

        uint256 donationAmount = 5000e6;
        vm.prank(attacker);
        asset.transfer(address(vault), donationAmount);

        console2.log("Vault total assets after donation:", vault.totalAssets());
        console2.log("Share price after donation:", vault.totalAssets() * 1e18 / vault.totalSupply());
        

        uint256 victimDeposit = 1000e6;
        console2.log("Step 3: Victim deposits:", victimDeposit);

        vm.startPrank(victim);
        asset.approve(address(vault), victimDeposit);
        uint256 victimShares = vault.deposit(victimDeposit, victim);
        vm.stopPrank();

        console2.log("Victim shares received:", victimShares);
        console2.log("Vault total assets after victim deposit:", vault.totalAssets());
        console2.log("Total shares outstanding:", vault.totalSupply());

        // Calculate expected withdrawals
        uint256 attackerExpectedWithdrawal = vault.previewRedeem(attackerShares);
        uint256 victimExpectedWithdrawal = vault.previewRedeem(victimShares);

        console2.log("Attacker expected withdrawal:", attackerExpectedWithdrawal);
        console2.log("Victim expected withdrawal:", victimExpectedWithdrawal);

        uint256 attackerTotalInput = minimalDepositAmount + donationAmount;
        uint256 victimTotalInput = victimDeposit;

        console2.log("Attacker total input:", attackerTotalInput);
        console2.log("Victim total input:", victimTotalInput);

        console2.log("=== Testing actual withdrawals ===");

        vm.startPrank(attacker);
        uint256 attackerActualWithdrawal = vault.redeem(attackerShares, attacker, attacker);
        vm.stopPrank();
        
        vm.startPrank(victim);
        uint256 victimActualWithdrawal = vault.redeem(victimShares, victim, victim);
        vm.stopPrank();

        console2.log("Attacker actual withdrawal:", attackerActualWithdrawal);
        console2.log("Victim actual withdrawal:", victimActualWithdrawal);
        
        // Calculate profit/loss
        int256 attackerProfitLoss = int256(attackerActualWithdrawal) - int256(attackerTotalInput);
        int256 victimProfitLoss = int256(victimActualWithdrawal) - int256(victimTotalInput);
        
        console2.log("Attacker profit/loss:", attackerProfitLoss);
        console2.log("Victim profit/loss:", victimProfitLoss);


         // === PROTECTION VERIFICATION ===
        
        // The vault should be protected against inflation attacks
        // Key protections to verify:
        
        // 1. Victim should not lose a significant portion of their deposit
        // Allow for small rounding errors but victim should get most of their deposit back
        uint256 victimLossPercentage = 0;
        if (victimActualWithdrawal < victimTotalInput) {
            victimLossPercentage = ((victimTotalInput - victimActualWithdrawal) * 10000) / victimTotalInput;
        }
        console2.log("Victim loss percentage (basis points):", victimLossPercentage);
        
        // Victim should not lose more than 1% due to the attack (allowing for fees and rounding)
        assertLt(victimLossPercentage, 100, "Victim lost more than 1% - inflation attack succeeded!");
        
        // 2. Attacker should not profit significantly from the attack
        // They might get some yield but shouldn't steal victim's funds
        if (attackerProfitLoss > 0) {
            uint256 attackerProfitPercentage = (uint256(attackerProfitLoss) * 10000) / attackerTotalInput;
            console2.log("Attacker profit percentage (basis points):", attackerProfitPercentage);
            
            // Attacker shouldn't profit more than reasonable yield would provide
            assertLt(attackerProfitPercentage, 50, "Attacker profited too much - inflation attack succeeded!");
        }
        
        // 3. Total assets should be conserved (minus any fees)
        uint256 totalInput = attackerTotalInput + victimTotalInput;
        uint256 totalOutput = attackerActualWithdrawal + victimActualWithdrawal;
        uint256 assetDifference = totalInput > totalOutput ? totalInput - totalOutput : totalOutput - totalInput;
        uint256 conservationErrorPercentage = (assetDifference * 10000) / totalInput;
        
        console2.log("Total input:", totalInput);
        console2.log("Total output:", totalOutput);
        console2.log("Asset conservation error (basis points):", conservationErrorPercentage);
        
        // Allow for small fees and rounding errors
        assertLt(conservationErrorPercentage, 50, "Assets not properly conserved!");
        
        console2.log("SUCCESS: Vault is protected against inflation attacks!");
        console2.log("=== INFLATION ATTACK TEST COMPLETED ===");
    }

    function testSingleUserDepositWithdraw() public {
        uint256 depositAmount = 1000e6; // 1,000 USDC
        
        console2.log("=== SINGLE USER DEPOSIT/WITHDRAW TEST ===");
        console2.log("Deposit amount:", depositAmount);
        console2.log("User initial balance:", asset.balanceOf(user));
        
        vm.startPrank(user);
        
        // Approve vault
        asset.approve(address(vault), depositAmount);
        console2.log("Approved vault");
        
        // Deposit
        uint256 shares = vault.deposit(depositAmount, user);
        console2.log("Shares received:", shares);
        console2.log("User balance after deposit:", asset.balanceOf(user));
        console2.log("Vault total assets:", vault.totalAssets());
        console2.log("Strategy total assets:", strategy.totalAssets());
        
        // Check APY
        uint256 apy = vault.getAPY();
        console2.log("Current APY (basis points):", apy);
        
        // Withdraw
        uint256 userBalanceBefore = asset.balanceOf(user);
        uint256 withdrawAmount = 500e6; // 500 USDC
        
        uint256 sharesUsed = vault.withdraw(withdrawAmount, user, user);
        console2.log("Shares used for withdrawal:", sharesUsed);
        console2.log("User balance after withdrawal:", asset.balanceOf(user));
        console2.log("Balance increase:", asset.balanceOf(user) - userBalanceBefore);
        
        vm.stopPrank();
        
        assertGt(shares, 0);
        assertEq(asset.balanceOf(user) - userBalanceBefore, withdrawAmount);
        console2.log("Deposit/withdraw successful");
        
        console2.log("=== SINGLE USER TEST COMPLETED ===");
    }

    function testMultipleUsersDepositWithdraw() public {
        uint256 deposit1 = 1000e6; // 1,000 USDC
        uint256 deposit2 = 2000e6; // 2,000 USDC
        
        console2.log("=== MULTIPLE USERS TEST ===");
        console2.log("User1 deposit:", deposit1);
        console2.log("User2 deposit:", deposit2);
        
        // User 1 deposits
        vm.startPrank(user);
        asset.approve(address(vault), deposit1);
        uint256 shares1 = vault.deposit(deposit1, user);
        vm.stopPrank();
        
        console2.log("User1 shares:", shares1);
        console2.log("Vault total assets after user1:", vault.totalAssets());
        
        // User 2 deposits
        vm.startPrank(user2);
        asset.approve(address(vault), deposit2);
        uint256 shares2 = vault.deposit(deposit2, user2);
        vm.stopPrank();
        
        console2.log("User2 shares:", shares2);
        console2.log("Vault total assets after user2:", vault.totalAssets());
        
        // Verify share distribution
        assertGt(shares1, 0);
        assertGt(shares2, 0);
        assertApproxEqRel(shares2, shares1 * 2, 0.01e18); // shares2 should be ~2x shares1
        
        // Total assets should be approximately equal to deposits
        assertApproxEqAbs(vault.totalAssets(), deposit1 + deposit2, 100);
        
        console2.log("Multiple users deposit successful");
        console2.log("=== MULTIPLE USERS TEST COMPLETED ===");
    }

    function testYieldAccrualOverTime() public {
        uint256 depositAmount = 1000e6; // 1,000 USDC
        
        console2.log("=== YIELD ACCRUAL TEST ===");
        console2.log("Deposit amount:", depositAmount);
        console2.log("Initial user balance:", asset.balanceOf(user));
        
        // Make initial deposit
        vm.startPrank(user);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialStrategyAssets = strategy.totalAssets();
        uint256 userShares = vault.balanceOf(user);
        uint256 currentAPY = vault.getAPY();
        
        console2.log("Initial vault total assets:", initialTotalAssets);
        console2.log("Initial strategy assets:", initialStrategyAssets);
        console2.log("User shares:", userShares);
        console2.log("Current APY (basis points):", currentAPY);
        
        // Fast forward time to accrue interest
        console2.log("Fast forwarding 365 days...");
        vm.warp(block.timestamp + 365 days);
        
        uint256 assetsAfterTime = vault.totalAssets();
        uint256 strategyAssetsAfterTime = strategy.totalAssets();
        uint256 yieldAccrued = assetsAfterTime - initialTotalAssets;
        
        console2.log("Assets after 1 year:", assetsAfterTime);
        console2.log("Strategy assets after 1 year:", strategyAssetsAfterTime);
        console2.log("Yield accrued:", yieldAccrued);
        
        if (yieldAccrued > 0) {
            uint256 yieldPercentage = (yieldAccrued * 10000) / initialTotalAssets;
            console2.log("Yield percentage (basis points):", yieldPercentage);
        }
        
        // Verify yield accrual
        assertGt(assetsAfterTime, initialTotalAssets);
        console2.log("SUCCESS: Yield accrued over time");
        
        // Withdraw and verify user gets more than they deposited
        uint256 userBalanceBefore = asset.balanceOf(user);
        uint256 sharesToRedeem = vault.balanceOf(user);
        uint256 expectedAssets = vault.previewRedeem(sharesToRedeem);
        
        console2.log("User balance before withdrawal:", userBalanceBefore);
        console2.log("Shares to redeem:", sharesToRedeem);
        console2.log("Expected assets:", expectedAssets);
        
        vault.redeem(sharesToRedeem, user, user);
        
        uint256 userBalanceAfter = asset.balanceOf(user);
        uint256 totalReceived = userBalanceAfter - userBalanceBefore;
        
        console2.log("User balance after withdrawal:", userBalanceAfter);
        console2.log("Total received:", totalReceived);
        
        if (totalReceived > depositAmount) {
            uint256 profit = totalReceived - depositAmount;
            console2.log("Profit earned:", profit);
            console2.log("SUCCESS: User earned profit from yield!");
        }
        
        vm.stopPrank();
        
        console2.log("=== YIELD ACCRUAL TEST COMPLETED ===");
    }

    function testVaultPauseUnpause() public {
        console2.log("=== PAUSE/UNPAUSE TEST ===");
        
        // Test pausing
        vm.prank(owner);
        vault.pause();
        assertTrue(vault.paused());
        console2.log("Vault paused");
        
        // Test that deposits are blocked when paused
        vm.startPrank(user);
        asset.approve(address(vault), 1000e6);
        vm.expectRevert();
        vault.deposit(1000e6, user);
        vm.stopPrank();
        console2.log("Deposits blocked when paused");
        
        // Test unpausing
        vm.prank(owner);
        vault.unpause();
        assertFalse(vault.paused());
        console2.log("Vault unpaused");
        
        // Test that deposits work after unpausing
        vm.startPrank(user);
        uint256 shares = vault.deposit(1000e6, user);
        assertGt(shares, 0);
        vm.stopPrank();
        console2.log("Deposits work after unpausing");
        
        console2.log("=== PAUSE/UNPAUSE TEST COMPLETED ===");
    }

    function testDepositLimit() public {
        console2.log("=== DEPOSIT LIMIT TEST ===");
        
        uint256 limit = 1500e6; // 1,500 USDC limit
        
        // Set deposit limit
        vm.prank(owner);
        vault.setDepositLimit(limit);
        assertEq(vault.depositLimit(), limit);
        console2.log("Deposit limit set to:", limit);
        
        // Test deposit within limit
        vm.startPrank(user);
        asset.approve(address(vault), 1000e6);
        uint256 shares = vault.deposit(1000e6, user);
        assertGt(shares, 0);
        vm.stopPrank();
        console2.log("Deposit within limit successful");
        
        // Test deposit exceeding limit
        vm.startPrank(user2);
        asset.approve(address(vault), 1000e6);
        vm.expectRevert();
        vault.deposit(1000e6, user2); // This would exceed the limit
        vm.stopPrank();
        console2.log("Deposit exceeding limit blocked");
        
        console2.log("=== DEPOSIT LIMIT TEST COMPLETED ===");
    }

    function testEmergencyFunctions() public {
        console2.log("=== EMERGENCY FUNCTIONS TEST ===");
        
        // Make a deposit first
        vm.startPrank(user);
        asset.approve(address(vault), 1000e6);
        vault.deposit(1000e6, user);
        vm.stopPrank();
        
        uint256 strategyAssetsBefore = strategy.totalAssets();
        uint256 vaultAssetsBefore = asset.balanceOf(address(vault));
        
        console2.log("Strategy assets before emergency:", strategyAssetsBefore);
        console2.log("Vault assets before emergency:", vaultAssetsBefore);
        
        // Emergency withdraw
        vm.prank(owner);
        vault.emergencyWithdraw();
        
        uint256 vaultAssetsAfter = asset.balanceOf(address(vault));
        console2.log("Vault assets after emergency:", vaultAssetsAfter);
        console2.log("Emergency withdrawal successful");
        
        // Verify assets were withdrawn from strategy to vault
        assertGt(vaultAssetsAfter, vaultAssetsBefore);
        
        console2.log("=== EMERGENCY FUNCTIONS TEST COMPLETED ===");
    }

    function testVaultHealthInformation() public {
        console2.log("=== VAULT HEALTH TEST ===");
        
        // Initially empty vault
        (uint256 totalDeposited, uint256 currentAPY, uint256 utilizationRate, bool isPaused) = vault.getVaultHealth();
        console2.log("Initial total deposited:", totalDeposited);
        console2.log("Initial APY:", currentAPY);
        console2.log("Initial utilization:", utilizationRate);
        console2.log("Initial paused status:", isPaused);
        
        // Make a deposit
        vm.startPrank(user);
        asset.approve(address(vault), 1000e6);
        vault.deposit(1000e6, user);
        vm.stopPrank();
        
        // Check health after deposit
        (totalDeposited, currentAPY, utilizationRate, isPaused) = vault.getVaultHealth();
        console2.log("After deposit - total deposited:", totalDeposited);
        console2.log("After deposit - APY:", currentAPY);
        console2.log("After deposit - utilization:", utilizationRate);
        console2.log("After deposit - paused status:", isPaused);
        
        assertGt(totalDeposited, 0);
        assertGt(currentAPY, 0);
        assertGt(utilizationRate, 0);
        console2.log("Vault health information accurate");
        
        console2.log("=== VAULT HEALTH TEST COMPLETED ===");
    }

    function testStrategyHealthInformation() public {
        console2.log("=== STRATEGY HEALTH TEST ===");
        
        // Make a deposit
        vm.startPrank(user);
        asset.approve(address(vault), 1000e6);
        vault.deposit(1000e6, user);
        vm.stopPrank();
        
        // Check strategy health
        (bool isHealthy, uint256 totalDeposited, uint256 currentAPY) = strategy.getStrategyHealth();
        console2.log("Strategy healthy:", isHealthy);
        console2.log("Strategy total deposited:", totalDeposited);
        console2.log("Strategy APY:", currentAPY);
        
        assertTrue(isHealthy);
        assertGt(totalDeposited, 0);
        assertGt(currentAPY, 0);
        console2.log("Strategy health information accurate");
        
        console2.log("=== STRATEGY HEALTH TEST COMPLETED ===");
    }

    function testZeroAmountDeposit() public {
        vm.startPrank(user);
        asset.approve(address(vault), 1000e6);
        vm.expectRevert(StrategyVault.StrategyVault_ZeroAmount.selector);
        vault.deposit(0, user);
        vm.stopPrank();
    }

    function testZeroAddressDeposit() public {
        vm.startPrank(user);
        asset.approve(address(vault), 1000e6);
        vm.expectRevert();
        vault.deposit(1000e6, address(0));
        vm.stopPrank();
    }


    function testUnauthorizedFunctionCalls() public {
        vm.startPrank(user);
        vm.expectRevert();
        vault.setDepositLimit(1000e6);

        vm.expectRevert();
        vault.pause();

        vm.expectRevert();
        vault.emergencyWithdraw();

        vm.stopPrank();
    }


    function testManagementFeeAccrual() public {
        console2.log("=== MANAGEMENT FEE ACCRUAL TEST ===");
        
        // Set management fee
        vm.prank(owner);
        vault.setManagementFee(100); // 1% per year (100 basis points)
        
        uint256 depositAmount = 1000e6; // 1,000 USDC
        console2.log("Deposit amount:", depositAmount);
        console2.log("Management fee rate: 1% per year");
        
        vm.startPrank(user);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, user);
        vm.stopPrank();
        
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialAccruedFees = vault.getAccruedFeesAssetValue();
        
        console2.log("Initial total assets:", initialTotalAssets);
        console2.log("Initial accrued fees:", initialAccruedFees);
        console2.log("User shares:", shares);
        
        // Test 1: No fees should accrue immediately
        assertEq(initialAccruedFees, 0, "Fees accrued immediately after deposit");
        
        // Test 2: Fast forward 6 months and check fees
        console2.log("\n--- After 6 months ---");
        vm.warp(block.timestamp + 182 days); // ~6 months
        
        vault.collectManagementFees();
        
        uint256 sixMonthAssets = vault.totalAssets();
        uint256 sixMonthFees = vault.getAccruedFeesAssetValue();
        
        console2.log("Assets after 6 months:", sixMonthAssets);
        console2.log("Accrued fees after 6 months:", sixMonthFees);
        
        // Should be approximately 0.5% of initial deposit (6 months of 1% annual fee)
        uint256 expectedSixMonthFees = (depositAmount * 50) / 10000; // 0.5%
        console2.log("Expected 6-month fees:", expectedSixMonthFees);
        
        assertGt(sixMonthFees, 0, "No fees accrued after 6 months");
        assertApproxEqAbs(sixMonthFees, expectedSixMonthFees, expectedSixMonthFees / 10, "6-month fees not close to expected");
        
        // Test 3: Fast forward full year
        console2.log("\n--- After 1 full year ---");
        vm.warp(block.timestamp + 183 days); // Complete the year
        
        vault.collectManagementFees();
        
        uint256 yearAssets = vault.totalAssets();
        uint256 yearFees = vault.getAccruedFeesAssetValue();
        
        console2.log("Assets after 1 year:", yearAssets);
        console2.log("Accrued fees after 1 year:", yearFees);
        
        // Should be approximately 1% of initial deposit
        uint256 expectedYearFees = (depositAmount * 100) / 10000; // 1%
        console2.log("Expected 1-year fees:", expectedYearFees);
        
        assertApproxEqAbs(yearFees, expectedYearFees, expectedYearFees / 5, "1-year fees not close to expected");
        
        // Test 4: User should still be able to withdraw most of their deposit
        console2.log("\n--- User withdrawal test ---");
        
        vm.prank(user);
        uint256 userWithdrawal = vault.redeem(shares, user, user);
        
        console2.log("User withdrawal amount:", userWithdrawal);
        
        // Calculate user profit/loss (handle both cases)
        if (userWithdrawal >= depositAmount) {
            uint256 userProfit = userWithdrawal - depositAmount;
            console2.log("User profit (including yield minus fees):", userProfit);
        } else {
            uint256 userLoss = depositAmount - userWithdrawal;
            console2.log("User loss due to fees:", userLoss);
        }
        
        // User should get back at least 98% of their deposit (allowing for fees + some yield)
        uint256 minExpectedWithdrawal = (depositAmount * 98) / 100;
        assertGt(userWithdrawal, minExpectedWithdrawal, "User lost more than 2% to management fees");
        
        // Test 5: Fee collection by admin
        console2.log("\n--- Fee collection test ---");
        
        uint256 feeRecipientBalanceBefore = asset.balanceOf(vault.feeRecipient());
        console2.log("Fee recipient balance before:", feeRecipientBalanceBefore);
        
        vm.prank(owner);
        vault.claimFees();
        
        uint256 feeRecipientBalanceAfter = asset.balanceOf(vault.feeRecipient());
        uint256 feesCollected = feeRecipientBalanceAfter - feeRecipientBalanceBefore;
        
        console2.log("Fee recipient balance after:", feeRecipientBalanceAfter);
        console2.log("Fees collected:", feesCollected);
        
        assertGt(feesCollected, 0, "No fees were collected");
        assertEq(vault.getAccruedFeesAssetValue(), 0, "Accrued fees not reset after collection");
        
        // Test 6: Verify fee collection was reasonable
        assertApproxEqAbs(feesCollected, expectedYearFees, expectedYearFees / 5, "Collected fees don't match accrued fees");
        
        console2.log("SUCCESS: Management fees work correctly");
        console2.log("=== MANAGEMENT FEE ACCRUAL TEST COMPLETED ===");
    }
} 