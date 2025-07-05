# Modular Yield Farming Vault System

## Architecture Overview

This project implements a **modular, extensible yield farming vault system** following the **One Vault Per Strategy** approach. The architecture prioritizes **separation of concerns**, **security**, and **upgradability**.

### 🏗️ System Components

#### 1. **StrategyVault.sol** - The Core Vault 🏦
- **ERC-4626 compliant** tokenized vault
- Handles all user interactions (deposits, withdrawals, shares)
- Manages accounting and fee collection
- Delegates yield generation to strategy contracts
- Features: Pause/unpause, deposit limits, withdrawal fees, management fees

#### 2. **IStrategy.sol** - Strategy Interface 🔌
- Standard interface that all strategies must implement
- Ensures seamless integration with vaults
- Defines core methods: `deposit()`, `withdraw()`, `totalAssets()`, `getAPY()`

#### 3. **AaveStrategy.sol** - Aave Lending Strategy 🧠
- Implements the IStrategy interface
- Lends assets on Aave V3 to generate yield
- Uses AaveAdapter for all Aave interactions
- Features: Health monitoring, emergency functions

#### 4. **AaveAdapter.sol** - Aave Protocol Wrapper 🔧
- Isolates the system from Aave protocol changes
- Handles asset registration and aToken management
- Provides clean interface for Aave interactions
- Owner-controlled for upgrades and maintenance

## 🔐 Security Features

- **Modular Design**: Each component can be upgraded independently
- **Access Control**: Owner-only functions for critical operations
- **Pause Mechanism**: Emergency pause for vault operations
- **Deposit Limits**: Configurable maximum deposit amounts
- **Fee Management**: Withdrawal and management fees with caps
- **Emergency Functions**: Quick asset recovery mechanisms

## 📈 Yield Generation

The system generates yield through:
1. **Aave Lending**: Deposits USDC into Aave V3 lending pool
2. **aToken Appreciation**: Earns interest through aToken balance growth
3. **Compound Interest**: Automatic compounding of earned interest
4. **Real-time APY**: Live APY rates from Aave protocol

## 🚀 Getting Started

### Prerequisites
- Foundry installed
- Arbitrum RPC endpoint
- USDC tokens for testing

### Environment Setup

The project uses environment variables for RPC endpoints. You have two options:

#### Option 1: Using .env file (Recommended)
Create a `.env` file in the contracts directory:
```bash
# .env file
ARBITRUM_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/YOUR_API_KEY
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
```

#### Option 2: Export environment variables
```bash
export ARBITRUM_RPC_URL="https://arb-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
export MAINNET_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
```

**RPC Provider Options:**
- **Alchemy**: `https://arb-mainnet.g.alchemy.com/v2/YOUR_API_KEY`
- **Infura**: `https://arbitrum-mainnet.infura.io/v3/YOUR_PROJECT_ID`
- **Public RPC**: `https://arb1.arbitrum.io/rpc` (may be rate limited)

### Deployment

```bash
# Deploy the complete system
forge script script/DeployAaveVault.s.sol --rpc-url arbitrum --broadcast

# Or using environment variable directly:
forge script script/DeployAaveVault.s.sol --rpc-url $ARBITRUM_RPC_URL --broadcast

# Or deploy step by step:
# 1. Deploy AaveAdapter
# 2. Register USDC asset
# 3. Deploy AaveStrategy
# 4. Deploy StrategyVault
# 5. Link vault to strategy
```

### Usage

```solidity
// 1. Approve vault to spend USDC
USDC.approve(vaultAddress, amount);

// 2. Deposit USDC to earn yield
vault.deposit(amount, userAddress);

// 3. Monitor vault performance
(uint256 totalDeposited, uint256 currentAPY, uint256 utilizationRate, bool isPaused) = vault.getVaultHealth();

// 4. Withdraw with accrued interest
vault.withdraw(amount, userAddress, userAddress);
```

## 🧪 Testing

### Run Complete Test Suite
```bash
# Run all tests with mainnet forking (using named RPC)
forge test --fork-url arbitrum -vv

# Or using environment variable directly:
forge test --fork-url $ARBITRUM_RPC_URL -vv

# Run specific test with detailed logs
forge test --match-test testYieldAccrualOverTime --fork-url arbitrum -vvv
```

### Test Coverage
- ✅ System deployment and integration
- ✅ Single user deposit/withdraw lifecycle
- ✅ Multiple users with fair share distribution
- ✅ **Yield accrual over time (proving deposit-yield-withdraw works)**
- ✅ Pause/unpause functionality
- ✅ Deposit limits and fee management
- ✅ Emergency functions
- ✅ Health monitoring and reporting

## 📊 Key Test Results

The comprehensive test suite **proves the deposit-yield-withdraw lifecycle works perfectly**:

1. **Deposits**: Users can deposit USDC and receive proportional vault shares
2. **Yield Generation**: Assets earn interest through Aave lending (aToken appreciation)
3. **Time-based Accrual**: Interest compounds over time automatically
4. **Withdrawals**: Users can withdraw their principal + accrued interest
5. **Profit Realization**: Tests confirm users earn more than they deposited

## 🏗️ Extending the System

### Adding New Strategies

To add a new strategy (e.g., Curve stablecoin pool):

1. **Create Adapter**: `CurveAdapter.sol`
```solidity
contract CurveAdapter {
    // Wrap Curve protocol interactions
}
```

2. **Create Strategy**: `CurveStrategy.sol`
```solidity
contract CurveStrategy is IStrategy {
    // Implement IStrategy interface
    // Use CurveAdapter for interactions
}
```

3. **Deploy New Vault**: Use existing `StrategyVault.sol`
```solidity
new StrategyVault(asset, name, symbol, curveStrategy);
```

### Benefits of This Architecture

- **Risk Isolation**: Each vault is completely independent
- **Easy Expansion**: Add new strategies without touching existing code
- **Protocol Upgrades**: Update adapters without changing strategies/vaults
- **Battle-tested Components**: Core vault logic is reused across strategies
- **User Choice**: Users can choose their preferred risk/reward profile

## 🔧 Configuration

### Vault Parameters
- `depositLimit`: Maximum total deposits allowed
- `withdrawalFee`: Fee charged on withdrawals (basis points)
- `managementFee`: Annual management fee (basis points)
- `paused`: Emergency pause state

### Strategy Parameters
- `asset`: Underlying asset (USDC)
- `adapter`: Protocol adapter address
- `name`: Strategy identification

## 📋 Contract Addresses (Example)

After deployment on Arbitrum:
- **AaveAdapter**: `0x...`
- **AaveStrategy**: `0x...`
- **StrategyVault**: `0x...`
- **USDC**: `0xaf88d065e77c8cC2239327C5EDb3A432268e5831`

## 🛠️ Development Commands

```bash
# Build contracts
forge build

# Run tests
forge test

# Deploy locally
forge script script/DeployAaveVault.s.sol

# Verify contracts
forge verify-contract <address> <contract> --etherscan-api-key <key>
```

## 🎯 Next Steps

1. **Add Second Strategy**: Implement Curve stablecoin pool strategy
2. **Vault Factory**: Create factory contract for easy vault deployment
3. **Frontend Integration**: Build user interface for vault interactions
4. **Multi-asset Support**: Extend to support other assets (DAI, USDT, etc.)
5. **Advanced Features**: Implement yield farming with protocol rewards

This architecture provides a solid foundation for a **production-ready yield farming system** that can scale to support multiple strategies while maintaining security and user experience.
