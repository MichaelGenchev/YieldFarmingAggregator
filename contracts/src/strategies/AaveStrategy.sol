//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IStrategy} from "../interfaces/IStrategy.sol";
import {AaveAdapter} from "../adapters/AaveAdapter.sol";

/**
 * @title AaveStrategy
 * @notice Strategy that lends assets on Aave V3 to generate yield
 * @dev This strategy uses the AaveAdapter to interact with Aave protocol
 * @dev Uses namespaced storage for upgrade safety
 */
contract AaveStrategy is Initializable, IStrategy, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:aave.strategy.storage
    struct AaveStrategyStorage {
        IERC20 asset;
        AaveAdapter adapter;
        address vault;
        string name;
    }

    // keccak256(abi.encode(uint256(keccak256("aave.strategy.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AAVE_STRATEGY_STORAGE_LOCATION = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

    function _getAaveStrategyStorage() private pure returns (AaveStrategyStorage storage $) {
        assembly {
            $.slot := AAVE_STRATEGY_STORAGE_LOCATION
        }
    }

    uint256 private constant RAY = 1e27;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    error AaveStrategy_OnlyVault();
    error AaveStrategy_VaultAlreadySet();
    error AaveStrategy_ZeroAmount();
    error AaveStrategy_AssetNotRegistered();
    error AaveStrategy_ZeroAddress();
    error AaveStrategy_DepositFailed();

    event VaultSet(address indexed vault);
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount, address indexed recipient);

    modifier onlyVault() {
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        if (msg.sender != $.vault) revert AaveStrategy_OnlyVault();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _asset,
        address _adapter,
        string memory _name
    ) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        if (_asset == address(0)) revert AaveStrategy_ZeroAddress();
        if (_adapter == address(0)) revert AaveStrategy_ZeroAddress();

        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        $.asset = IERC20(_asset);
        $.adapter = AaveAdapter(_adapter);
        $.name = _name;

        // Approve adapter to spend our assets for deposits
        $.asset.forceApprove(address($.adapter), type(uint256).max);

        // Approve adapter to spend our aTokens for withdrawals
        // Note: We'll need to do this after the adapter registers the asset
        // This will be handled in setVault or we can add a separate function
    }

    function version() public pure virtual returns (string memory) {
        return "1.0.0";
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Sets the vault address (can only be called once)
     * @param _vault The vault address
     */
    function setVault(address _vault) external onlyOwner {
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        if ($.vault != address(0)) revert AaveStrategy_VaultAlreadySet();
        if (_vault == address(0)) revert AaveStrategy_ZeroAddress();
        
        $.vault = _vault;
        
        // Approve adapter to spend our aTokens for withdrawals
        address aToken = $.adapter.getAToken(address($.asset));
        if (aToken != address(0)) {
            IERC20(aToken).forceApprove(address($.adapter), type(uint256).max);
        }
        
        emit VaultSet(_vault);
    }

    /**
     * @notice Returns the total amount of assets under management
     * @return Total assets in the strategy (aToken balance)
     */
    function totalAssets() external view override returns (uint256) {
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        return $.adapter.getATokenBalance(address($.asset), address(this));
    }

    /**
     * @notice Deposits assets into Aave
     * @param amount The amount of assets to deposit
     * @return actualAmount The actual amount deposited
     */
    function deposit(uint256 amount) external override onlyVault returns (uint256 actualAmount) {
        if (amount == 0) revert AaveStrategy_ZeroAmount();
        
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        require($.adapter.isAssetRegistered(address($.asset)), AaveStrategy_AssetNotRegistered());
        uint256 aTokenBefore = $.adapter.getATokenBalance(address($.asset), address(this));
        // Transfer assets from vault to this contract
        $.asset.safeTransferFrom(msg.sender, address(this), amount);
        
        // Supply to Aave via adapter
        actualAmount = $.adapter.supply(address($.asset), amount, address(this));

        uint256 aTokenAfter = $.adapter.getATokenBalance(address($.asset), address(this));
        require(aTokenAfter > aTokenBefore, AaveStrategy_DepositFailed());
        
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
        
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        
        // Withdraw from Aave via adapter
        actualAmount = $.adapter.withdraw(address($.asset), amount, recipient);
        
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
        
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        
        // Withdraw all from Aave via adapter
        actualAmount = $.adapter.withdraw(address($.asset), type(uint256).max, recipient);
        
        emit Withdrawn(actualAmount, recipient);
    }

    /**
     * @notice Returns the current APY of the strategy
     * @return The APY in basis points (e.g., 500 = 5%)
     */
    function getAPY() external view override returns (uint256) {
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        uint256 liquidityRate = $.adapter.getSupplyAPY(address($.asset));
        
        // Convert from ray (27 decimals) to basis points (4 decimals)
        // APY = (liquidityRate / RAY) * 10000
        return (liquidityRate * 10000) / RAY;
    }

    /**
     * @notice Returns the current supply rate from Aave in ray format
     * @return The supply rate in ray (27 decimals)
     */
    function getSupplyRate() external view returns (uint256) {
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        return $.adapter.getSupplyAPY(address($.asset));
    }

    /**
     * @notice Returns the aToken balance
     * @return The aToken balance
     */
    function getATokenBalance() external view returns (uint256) {
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        return $.adapter.getATokenBalance(address($.asset), address(this));
    }

    /**
     * @notice Returns the aToken address
     * @return The aToken address
     */
    function getAToken() external view returns (address) {
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        return $.adapter.getAToken(address($.asset));
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
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        totalDeposited = $.adapter.getATokenBalance(address($.asset), address(this));
        currentAPY = this.getAPY();
        
        // Strategy is healthy if it has a positive APY and the adapter is working
        isHealthy = currentAPY > 0 && $.adapter.isAssetRegistered(address($.asset));
    }

    // Public getters for interface compatibility
    function asset() external view override returns (IERC20) {
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        return $.asset;
    }

    function vault() external view override returns (address) {
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        return $.vault;
    }

    function name() external view override returns (string memory) {
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        return $.name;
    }

    function adapter() external view returns (AaveAdapter) {
        AaveStrategyStorage storage $ = _getAaveStrategyStorage();
        return $.adapter;
    }
} 