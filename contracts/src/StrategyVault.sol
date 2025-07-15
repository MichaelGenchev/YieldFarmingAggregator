//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IStrategy} from "./interfaces/IStrategy.sol";

/**
 * @title StrategyVault
 * @notice ERC-4626 compliant vault that delegates yield generation to strategy contracts
 * @dev This vault handles all accounting and can work with any strategy implementing IStrategy
 */
contract StrategyVault is ERC4626, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");


    IStrategy public strategy;
    bool public paused;
    uint256 public depositLimit;
    uint256 public withdrawalFee; // In basis points (100 = 1%)
    uint256 public managementFee; // In basis points (100 = 1% per year)
    uint256 public lastFeeCollection;
    address public feeRecipient;
    uint256 public accruedManagementFees;

    mapping(address => bool) public approvedStrategies;
    
    uint256 private constant MAX_BPS = 10000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    
    error StrategyVault_ZeroAmount();
    error StrategyVault_ZeroAddress();
    error StrategyVault_Paused();
    error StrategyVault_DepositLimitExceeded();
    error StrategyVault_InvalidFee();
    error StrategyVault_StrategyAlreadySet();
    error StrategyVault_NoStrategy();
    error StrategyVault_StrategyNotApproved();

    event StrategySet(address indexed strategy);
    event Paused();
    event Unpaused();
    event DepositLimitSet(uint256 limit);
    event WithdrawalFeeSet(uint256 fee);
    event ManagementFeeSet(uint256 fee);
    event FeesCollected(uint256 amount);
    event EmergencyWithdrawal(uint256 amount);
    event FeeRecipientSet(address indexed feeRecipient);

    modifier whenNotPaused() {
        if (paused) revert StrategyVault_Paused();
        _;
    }

    modifier hasStrategy() {
        if (address(strategy) == address(0)) revert StrategyVault_NoStrategy();
        _;
    }

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _strategy
    ) ERC4626(IERC20(_asset)) ERC20(_name, _symbol) {
        if (_asset == address(0)) revert StrategyVault_ZeroAddress();
        
        if (_strategy != address(0)) {
            strategy = IStrategy(_strategy);
            emit StrategySet(_strategy);
        }
        
        depositLimit = type(uint256).max;
        lastFeeCollection = block.timestamp;
        feeRecipient = msg.sender; // Default to deployer

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        
        // Approve strategy to spend our assets
        if (_strategy != address(0)) {
            IERC20(_asset).forceApprove(_strategy, type(uint256).max);
        }
    }

    /**
     * @notice Sets the strategy contract (can only be called once)
     * @param _strategy The strategy contract address
     */
    function setStrategy(address _strategy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!approvedStrategies[_strategy]) revert StrategyVault_StrategyNotApproved();
        if (address(strategy) != address(0)) revert StrategyVault_StrategyAlreadySet();
        if (_strategy == address(0)) revert StrategyVault_ZeroAddress();
        
        strategy = IStrategy(_strategy);
        IERC20(asset()).forceApprove(_strategy, type(uint256).max);
        
        emit StrategySet(_strategy);
    }

    /**
     * @notice Returns the total amount of assets under management
     * @return Total assets in the vault (from strategy + any idle assets)
     */
    function totalAssets() public view override hasStrategy returns (uint256) {
        return strategy.totalAssets();
    }

    /**
     * @notice Internal deposit function
     * @param caller The caller address
     * @param receiver The receiver address
     * @param assets The amount of assets to deposit
     * @param shares The amount of shares to mint
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override whenNotPaused hasStrategy nonReentrant {
        if (assets == 0) revert StrategyVault_ZeroAmount();
        if (totalAssets() + assets > depositLimit) revert StrategyVault_DepositLimitExceeded();
        
        // Collect management fees before deposit
        _collectManagementFees();
        
        // Transfer assets from caller to this contract
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);
        
        // Deposit assets into strategy
        strategy.deposit(assets);
        
        // Mint shares to receiver
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice Internal withdraw function
     * @param caller The caller address
     * @param receiver The receiver address
     * @param owner The owner address
     * @param assets The amount of assets to withdraw
     * @param shares The amount of shares to burn
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override whenNotPaused hasStrategy nonReentrant {
        if (assets == 0) revert StrategyVault_ZeroAmount();
        
        // Collect management fees before withdrawal
        _collectManagementFees();
        
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // Burn shares from owner
        _burn(owner, shares);

        // Calculate withdrawal fee
        uint256 fee = (assets * withdrawalFee) / MAX_BPS;
        uint256 assetsAfterFee = assets - fee;
        
        // Withdraw assets from strategy
        strategy.withdraw(assets, address(this));
        
        // Transfer assets to receiver (minus fee)
        IERC20(asset()).safeTransfer(receiver, assetsAfterFee);
        
        // Keep fee in vault (will be counted in totalAssets)
        emit Withdraw(caller, receiver, owner, assetsAfterFee, shares);
    }

    /**
     * @notice Collects management fees by minting shares to fee recipient
     */
    function _collectManagementFees() internal {
        if (managementFee == 0 || totalSupply() == 0) return;
        uint256 timePassed = block.timestamp - lastFeeCollection;
        if (timePassed == 0) return;
        
        // Calculate fee as a percentage of total supply per year
        // This mints new shares representing the fee percentage
        uint256 feeShares = (totalSupply() * managementFee * timePassed) / 
                           (MAX_BPS * SECONDS_PER_YEAR);
        
        if (feeShares > 0) {
            _mint(feeRecipient, feeShares);
            accruedManagementFees += feeShares; // Track total fee shares
            emit FeesCollected(feeShares);
        }
        
        lastFeeCollection = block.timestamp;
    }

    function claimFees() external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Calculate the asset value of fee shares and redeem them
        uint256 feeShares = accruedManagementFees;
        if (feeShares == 0) return;
        
        // Convert fee shares to assets by redeeming them
        uint256 feeAssets = previewRedeem(feeShares);
        
        // Transfer the shares from fee recipient to this contract temporarily
        // then redeem them to get the underlying assets
        _transfer(feeRecipient, address(this), feeShares);
        
        // Redeem the shares to get underlying assets
        _burn(address(this), feeShares);
        uint256 assetsToWithdraw = feeAssets;
        
        // Withdraw from strategy if needed
        uint256 idleAssets = IERC20(asset()).balanceOf(address(this));
        if (idleAssets < assetsToWithdraw) {
            strategy.withdraw(assetsToWithdraw - idleAssets, address(this));
        }
        
        // Transfer assets to fee recipient
        IERC20(asset()).safeTransfer(feeRecipient, assetsToWithdraw);
        
        // Reset accrued fees
        accruedManagementFees = 0;
        
        emit FeesCollected(assetsToWithdraw);
    }

    /**
     * @notice Manually collect management fees
     */
    function collectManagementFees() external {
        _collectManagementFees();
    }

    /**
     * @notice Pause the vault
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        paused = true;
        emit Paused();
    }

    /**
     * @notice Unpause the vault
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        paused = false;
        emit Unpaused();
    }

    /**
     * @notice Set deposit limit
     * @param _limit The new deposit limit
     */
    function setDepositLimit(uint256 _limit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        depositLimit = _limit;
        emit DepositLimitSet(_limit);
    }

    /**
     * @notice Set withdrawal fee
     * @param _fee The new withdrawal fee in basis points
     */
    function setWithdrawalFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_fee > 1000) revert StrategyVault_InvalidFee(); // Max 10%
        withdrawalFee = _fee;
        emit WithdrawalFeeSet(_fee);
    }

    /**
     * @notice Set management fee
     * @param _fee The new management fee in basis points per year
     */
    function setManagementFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_fee > 1000) revert StrategyVault_InvalidFee(); // Max 10% per year
        
        // Collect existing fees before changing the rate
        _collectManagementFees();
        
        managementFee = _fee;
        emit ManagementFeeSet(_fee);
    }

    /**
     * @notice Set fee recipient
     * @param _feeRecipient The new fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_feeRecipient == address(0)) revert StrategyVault_ZeroAddress();
        feeRecipient = _feeRecipient;
        emit FeeRecipientSet(_feeRecipient);
    }

    /**
     * @notice Emergency withdrawal of all funds from strategy
     */
    function emergencyWithdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 withdrawn = strategy.withdrawAll(address(this));
        emit EmergencyWithdrawal(withdrawn);
    }

    /**
     * @notice Get the current APY from the strategy
     * @return The APY in basis points
     */
    function getAPY() external view hasStrategy returns (uint256) {
        return strategy.getAPY();
    }

    /**
     * @notice Get vault health information
     * @return totalDeposited Total assets deposited
     * @return currentAPY Current APY from strategy
     * @return utilizationRate Percentage of assets deployed to strategy
     * @return isPaused Whether the vault is paused
     */
    function getVaultHealth() external view returns (
        uint256 totalDeposited,
        uint256 currentAPY,
        uint256 utilizationRate,
        bool isPaused
    ) {
        totalDeposited = totalAssets();
        currentAPY = address(strategy) != address(0) ? strategy.getAPY() : 0;
        
        if (totalDeposited > 0) {
            uint256 deployedAssets = address(strategy) != address(0) ? strategy.totalAssets() : 0;
            utilizationRate = (deployedAssets * MAX_BPS) / totalDeposited;
        }
        
        isPaused = paused;
    }

    /**
     * @notice Returns the maximum amount of assets that can be deposited
     */
    function maxDeposit(address) public view override returns (uint256) {
        if (paused) return 0;
        
        uint256 currentAssets = totalAssets();
        if (currentAssets >= depositLimit) return 0;
        
        return depositLimit - currentAssets;
    }

    /**
     * @notice Returns the maximum amount of shares that can be minted
     */
    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        return maxAssets == 0 ? 0 : _convertToShares(maxAssets, Math.Rounding.Floor);
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (paused) return 0;
        return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        if (paused) return 0;
        return balanceOf(owner);
    }

    /**
     * @notice Preview deposit accounting for fees
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /**
     * @notice Preview withdrawal accounting for fees
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        // Add withdrawal fee to the assets needed
        uint256 assetsWithFee = assets + ((assets * withdrawalFee) / MAX_BPS);
        return _convertToShares(assetsWithFee, Math.Rounding.Ceil);
    }

    /**
     * @notice Get the asset value of accrued management fees
     * @return The asset value of fee shares
     */
    function getAccruedFeesAssetValue() external view returns (uint256) {
        if (accruedManagementFees == 0) return 0;
        return previewRedeem(accruedManagementFees);
    }

    /**
     * @notice Emergency function to recover stuck tokens
     * @param token The token to recover
     * @param amount The amount to recover
     */
    function emergencyRecover(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(feeRecipient, amount);
    }
}
