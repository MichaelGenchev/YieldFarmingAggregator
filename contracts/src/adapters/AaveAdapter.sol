//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IPool} from "../interfaces/IPool.sol";
import {IAToken} from "../interfaces/IAToken.sol";
import {ReserveData} from "../interfaces/IPool.sol";

/**
 * @title AaveAdapter
 * @notice Adapter that wraps Aave V3 protocol interactions
 * @dev This adapter isolates the system from changes in Aave's contracts
 */
contract AaveAdapter is Ownable {
    using SafeERC20 for IERC20;

    // Arbitrum Aave V3 Pool address
    address public constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    
    IPool public immutable aavePool;
    
    // Mapping from underlying asset to aToken
    mapping(address => address) public aTokens;
    
    error AaveAdapter_InvalidAsset();
    error AaveAdapter_ZeroAmount();
    error AaveAdapter_UnauthorizedCaller();
    
    event AssetRegistered(address indexed asset, address indexed aToken);
    event Supplied(address indexed asset, uint256 amount, address indexed onBehalfOf);
    event Withdrawn(address indexed asset, uint256 amount, address indexed to);

    modifier onlyRegisteredAsset(address asset) {
        if (aTokens[asset] == address(0)) revert AaveAdapter_InvalidAsset();
        _;
    }

    constructor() Ownable(msg.sender) {
        aavePool = IPool(AAVE_POOL);
    }

    /**
     * @notice Registers an asset with its corresponding aToken
     * @param asset The underlying asset address
     */
    function registerAsset(address asset) external onlyOwner {
        if (asset == address(0)) revert AaveAdapter_InvalidAsset();
        
        ReserveData memory reserveData = aavePool.getReserveData(asset);
        if (reserveData.aTokenAddress == address(0)) revert AaveAdapter_InvalidAsset();
        
        aTokens[asset] = reserveData.aTokenAddress;
        
        // Approve max amount for efficiency
        IERC20(asset).forceApprove(AAVE_POOL, type(uint256).max);
        
        emit AssetRegistered(asset, reserveData.aTokenAddress);
    }

    /**
     * @notice Supplies assets to Aave on behalf of the caller
     * @param asset The asset to supply
     * @param amount The amount to supply
     * @param onBehalfOf The address to receive the aTokens
     * @return actualAmount The actual amount supplied
     */
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external onlyRegisteredAsset(asset) returns (uint256 actualAmount) {
        if (amount == 0) revert AaveAdapter_ZeroAmount();
        
        // Transfer assets from caller to this contract
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        
        // Supply to Aave
        aavePool.supply(asset, amount, onBehalfOf, 0);
        
        actualAmount = amount;
        emit Supplied(asset, amount, onBehalfOf);
    }

    /**
     * @notice Withdraws assets from Aave on behalf of the caller
     * @param asset The asset to withdraw
     * @param amount The amount to withdraw (use type(uint256).max for all)
     * @param to The address to receive the withdrawn assets
     * @return actualAmount The actual amount withdrawn
     * @dev The caller (strategy) must hold the aTokens and approve this contract to spend them
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external onlyRegisteredAsset(asset) returns (uint256 actualAmount) {
        if (amount == 0) revert AaveAdapter_ZeroAmount();
        
        address aToken = aTokens[asset];
        address caller = msg.sender;
        
        // Get caller's aToken balance before withdrawal
        uint256 callerBalanceBefore = IERC20(aToken).balanceOf(caller);
        
        if (amount == type(uint256).max) {
            // Transfer all aTokens from caller to this contract
            if (callerBalanceBefore > 0) {
                IERC20(aToken).safeTransferFrom(caller, address(this), callerBalanceBefore);
            }
            
            // Withdraw all from Aave
            actualAmount = aavePool.withdraw(asset, type(uint256).max, to);
            
            // Transfer any remaining aTokens back to caller
            uint256 remainingBalance = IERC20(aToken).balanceOf(address(this));
            if (remainingBalance > 0) {
                IERC20(aToken).safeTransfer(caller, remainingBalance);
            }
        } else {
            // Transfer all aTokens temporarily to ensure we have enough
            if (callerBalanceBefore > 0) {
                IERC20(aToken).safeTransferFrom(caller, address(this), callerBalanceBefore);
            }
            
            // Withdraw exact amount from Aave
            actualAmount = aavePool.withdraw(asset, amount, to);
            
            // Transfer remaining aTokens back to caller
            uint256 remainingBalance = IERC20(aToken).balanceOf(address(this));
            if (remainingBalance > 0) {
                IERC20(aToken).safeTransfer(caller, remainingBalance);
            }
        }
        
        emit Withdrawn(asset, actualAmount, to);
    }

    /**
     * @notice Gets the aToken balance for an account
     * @param asset The underlying asset
     * @param account The account to check
     * @return The aToken balance
     */
    function getATokenBalance(address asset, address account) 
        external 
        view 
        onlyRegisteredAsset(asset) 
        returns (uint256) 
    {
        return IAToken(aTokens[asset]).balanceOf(account);
    }

    /**
     * @notice Gets the current supply APY for an asset
     * @param asset The underlying asset
     * @return The current supply APY in ray (27 decimals)
     */
    function getSupplyAPY(address asset) 
        external 
        view 
        onlyRegisteredAsset(asset) 
        returns (uint256) 
    {
        ReserveData memory reserveData = aavePool.getReserveData(asset);
        return reserveData.currentLiquidityRate;
    }

    /**
     * @notice Gets the aToken address for an asset
     * @param asset The underlying asset
     * @return The aToken address
     */
    function getAToken(address asset) external view returns (address) {
        return aTokens[asset];
    }

    /**
     * @notice Checks if an asset is registered
     * @param asset The asset to check
     * @return True if registered, false otherwise
     */
    function isAssetRegistered(address asset) external view returns (bool) {
        return aTokens[asset] != address(0);
    }

    /**
     * @notice Emergency function to recover stuck tokens
     * @param token The token to recover
     * @param amount The amount to recover
     */
    function emergencyRecover(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
} 