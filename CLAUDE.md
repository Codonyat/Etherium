# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Etherium is a Solidity smart contract project implementing an ERC20 token backed by ETH with daily lottery mechanics and decentralized randomness generation. The token uses a 1:1,000,000 ratio (1 ETH = 1M ETHERIUM with 12 decimals) and implements a 1% fee structure on all operations.

## Development Commands

### Build
```bash
forge build
```

### Run Tests
```bash
forge test
# Run specific test
forge test --match-test testMintingWithFee
# Run with verbosity for debugging
forge test -vvv
```

### Deploy
```bash
# Requires PRIVATE_KEY environment variable
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast
```

### Clean Build
```bash
forge clean && forge build
```

## Architecture Overview

### Core Contract Structure
- **Main Contract**: `src/Etherium.sol` - Inherits from OpenZeppelin's ERC20 and ReentrancyGuard
- **Fee System**: 1% total fee split into 0.9% lottery pool and 0.1% randomness participant rewards
- **Holder Tracking**: Uses Fenwick tree (Binary Indexed Tree) for O(log n) cumulative balance queries, enabling efficient lottery winner selection
- **Randomness**: Commit-reveal scheme with 24-hour cycles (12h commit, 12h reveal phases)

### Key Design Patterns
1. **Synthetic Addresses**: Uses hardcoded addresses for LOTTERY_POOL and RANDOMNESS_POOL to track fee distributions
2. **Fenwick Tree Implementation**: Maintains cumulative holder balances for efficient random selection from total supply
3. **Time-based Phases**: 
   - 7-day initial minting period with unlimited supply
   - After minting period: fixed max supply based on initial deposits
   - Daily lottery cycles with commit-reveal randomness

### External Dependencies
- **OpenZeppelin Contracts**: ERC20 base implementation and ReentrancyGuard
- **Uniswap V3**: For PepeUSD/USDC TWAP price calculations
- **Forge-std**: Testing framework and utilities

## Testing Strategy

Tests are located in `test/Etherium.t.sol` and use Foundry's testing framework. Key test areas:
- Minting and redemption with fee calculations
- Lottery winner selection using Fenwick tree
- Commit-reveal randomness generation
- PepeUSD locking mechanism
- Edge cases around time transitions and phase changes

## Important Implementation Details

1. **Fenwick Tree Updates**: When balances change, the contract updates the Fenwick tree to maintain cumulative sums for lottery selection
2. **Smart Contract Exclusion**: Smart contracts are excluded from lottery participation (only EOAs can win)
3. **Fee Minting During Initial Period**: During the 7-day minting period, fees are also minted as new tokens rather than redistributed
4. **Redemption Creates Capacity**: After minting period ends, burning tokens creates capacity for new mints up to the original max supply