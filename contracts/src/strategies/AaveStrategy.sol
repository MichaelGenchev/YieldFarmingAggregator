//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IStrategy} from "../interfaces/IStrategy.sol";
import {AaveAdapter} from "../adapters/AaveAdapter.sol";

/**
 * @title AaveStrategy
 * @notice Strategy that lends assets on Aave V3 to generate yield
 * @dev This strategy uses the AaveAdapter to interact with Aave protocol
 */
contract AaveStrategy is IStrategy, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable override asset;
    AaveAdapter public immutable adapter;
    address public override vault;
    string public override name;

    uint256 private constant RAY = 1e27;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    error AaveStrategy_OnlyVault();
    error AaveStrategy_VaultAlreadySet();
    error AaveStrategy_ZeroAmount();
    error AaveStrategy_ZeroAddress();

    event VaultSet(address indexed vault);
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount, address indexed recipient);

    modifier onlyVault() {
        if (msg.sender != vault) revert AaveStrategy_OnlyVault();
        _;
    }

    constructor(
        address _asset,
        address _adapter,
        string memory _name
    ) Ownable(msg.sender) {
        if (_asset == address(0)) revert AaveStrategy_ZeroAddress();
        if (_adapter == address(0)) revert AaveStrategy_ZeroAddress();
        
        asset = IERC20(_asset);
        adapter = AaveAdapter(_adapter);
        name = _name;
        
        // Approve adapter to spend our assets for deposits
        asset.forceApprove(address(adapter), type(uint256).max);
        
        // Approve adapter to spend our aTokens for withdrawals
        // Note: We'll need to do this after the adapter registers the asset
        // This will be handled in setVault or we can add a separate function
    }

    /**
     * @notice Sets the vault address (can only be called once)
     * @param _vault The vault address
     */
    function setVault(address _vault) external onlyOwner {
        if (vault != address(0)) revert AaveStrategy_VaultAlreadySet();
        if (_vault == address(0)) revert AaveStrategy_ZeroAddress();
        
        vault = _vault;
        
        // Approve adapter to spend our aTokens for withdrawals
        address aToken = adapter.getAToken(address(asset));
        if (aToken != address(0)) {
            IERC20(aToken).forceApprove(address(adapter), type(uint256).max);
        }
        
        emit VaultSet(_vault);
    }

    /**
     * @notice Returns the total amount of assets under management
     * @return Total assets in the strategy (aToken balance)
     */
    function totalAssets() external view override returns (uint256) {
        return adapter.getATokenBalance(address(asset), address(this));
    }

    /**
     * @notice Deposits assets into Aave
     * @param amount The amount of assets to deposit
     * @return actualAmount The actual amount deposited
     */
    function deposit(uint256 amount) external override onlyVault returns (uint256 actualAmount) {
        if (amount == 0) revert AaveStrategy_ZeroAmount();
        
        // Transfer assets from vault to this contract
        asset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Supply to Aave via adapter
        actualAmount = adapter.supply(address(asset), amount, address(this));
        
        emit Deposited(actualAmount);
    }

    /**
     * @notice Withdraws assets from Aave
     * @param amount The amount of assets to withdraw
     * @param recipient The address to receive the withdrawn assets
     * @return actualAmount The actual amount withdrawn
     */
    function withdraw(uint256 amount, address recipient) 
        external 
        override 
        onlyVault 
        returns (uint256 actualAmount) 
    {
        if (amount == 0) revert AaveStrategy_ZeroAmount();
        if (recipient == address(0)) revert AaveStrategy_ZeroAddress();
        
        // Withdraw from Aave via adapter
        actualAmount = adapter.withdraw(address(asset), amount, recipient);
        
        emit Withdrawn(actualAmount, recipient);
    }

    /**
     * @notice Withdraws all assets from Aave (emergency function)
     * @param recipient The address to receive all withdrawn assets
     * @return actualAmount The actual amount withdrawn
     */
    function withdrawAll(address recipient) 
        external 
        override 
        onlyVault 
        returns (uint256 actualAmount) 
    {
        if (recipient == address(0)) revert AaveStrategy_ZeroAddress();
        
        // Withdraw all from Aave via adapter
        actualAmount = adapter.withdraw(address(asset), type(uint256).max, recipient);
        
        emit Withdrawn(actualAmount, recipient);
    }

    /**
     * @notice Returns the current APY of the strategy
     * @return The APY in basis points (e.g., 500 = 5%)
     */
    function getAPY() external view override returns (uint256) {
        uint256 liquidityRate = adapter.getSupplyAPY(address(asset));
        
        // Convert from ray (27 decimals) to basis points (4 decimals)
        // APY = (liquidityRate / RAY) * 10000
        return (liquidityRate * 10000) / RAY;
    }

    /**
     * @notice Returns the current supply rate from Aave in ray format
     * @return The supply rate in ray (27 decimals)
     */
    function getSupplyRate() external view returns (uint256) {
        return adapter.getSupplyAPY(address(asset));
    }

    /**
     * @notice Returns the aToken balance
     * @return The aToken balance
     */
    function getATokenBalance() external view returns (uint256) {
        return adapter.getATokenBalance(address(asset), address(this));
    }

    /**
     * @notice Returns the aToken address
     * @return The aToken address
     */
    function getAToken() external view returns (address) {
        return adapter.getAToken(address(asset));
    }

    /**
     * @notice Emergency function to recover stuck tokens
     * @param token The token to recover
     * @param amount The amount to recover
     */
    function emergencyRecover(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @notice Returns strategy health status
     * @return isHealthy True if strategy is operating normally
     * @return totalDeposited Total assets deposited in the strategy
     * @return currentAPY Current APY in basis points
     */
    function getStrategyHealth() external view returns (
        bool isHealthy,
        uint256 totalDeposited,
        uint256 currentAPY
    ) {
        totalDeposited = adapter.getATokenBalance(address(asset), address(this));
        currentAPY = this.getAPY();
        
        // Strategy is healthy if it has a positive APY and the adapter is working
        isHealthy = currentAPY > 0 && adapter.isAssetRegistered(address(asset));
    }
} 