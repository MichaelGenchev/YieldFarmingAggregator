//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IStrategy
 * @notice Standard interface that all yield strategies must implement
 * @dev This interface ensures all strategies can plug into vaults seamlessly
 */
interface IStrategy {
    /**
     * @notice Returns the underlying asset that this strategy accepts
     * @return The ERC20 token address
     */
    function asset() external view returns (IERC20);

    /**
     * @notice Returns the total amount of assets under management
     * @return Total assets in the strategy
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Deposits assets into the strategy
     * @param amount The amount of assets to deposit
     * @return actualAmount The actual amount deposited (may differ due to protocol fees)
     */
    function deposit(uint256 amount) external returns (uint256 actualAmount);

    /**
     * @notice Withdraws assets from the strategy
     * @param amount The amount of assets to withdraw
     * @param recipient The address to receive the withdrawn assets
     * @return actualAmount The actual amount withdrawn
     */
    function withdraw(uint256 amount, address recipient) external returns (uint256 actualAmount);

    /**
     * @notice Withdraws all assets from the strategy (emergency function)
     * @param recipient The address to receive all withdrawn assets
     * @return actualAmount The actual amount withdrawn
     */
    function withdrawAll(address recipient) external returns (uint256 actualAmount);

    /**
     * @notice Returns the current APY of the strategy
     * @return The APY in basis points (e.g., 500 = 5%)
     */
    function getAPY() external view returns (uint256);

    /**
     * @notice Returns the name of the strategy
     * @return Strategy name
     */
    function name() external view returns (string memory);

    /**
     * @notice Returns the vault address that owns this strategy
     * @return The vault address
     */
    function vault() external view returns (address);
}
