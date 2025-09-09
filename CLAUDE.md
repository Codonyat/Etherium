# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Etherium is a Solidity smart contract project implementing an ERC20 token backed by ETH with daily lottery mechanics and decentralized randomness generation. The token uses a 1:1 ratio (1 ETH = 1 ETHERIUM, both with 18 decimals) and implements a 1% fee structure on all operations.

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
- **PepeUSD Lock Mechanism**:
  - Users can lock 100 PepeUSD during minting period (each lock enables one fee-free mint)
  - Multiple locks allowed per user (e.g., lock 300 PepeUSD for 3 fee-free mints)
  - Call `mintFeeFree()` to use a lock and mint without fees
  - All locks unlockable after 1 month from deployment
- **Holder Tracking**: Uses Fenwick tree (Binary Indexed Tree) for O(log n) cumulative balance queries, enabling efficient lottery winner selection
- **Randomness**: Commit-reveal scheme with 24-hour cycles (12h commit, 12h reveal phases)

### Key Design Patterns

1. **Synthetic Addresses**: Uses hardcoded addresses for LOTTERY_POOL and RANDOMNESS_POOL to track fee distributions
2. **Fenwick Tree Implementation**: Maintains cumulative holder balances for efficient random selection from total supply
3. **Time-based Phases**:
   - 7-day initial minting period with unlimited supply
   - After minting period: fixed max supply based on initial deposits
   - Daily lottery cycles with commit-reveal randomness
4. **Fail-Fast Philosophy**: Avoid defensive coding patterns that hide errors. Unexpected behaviors should cause explicit failures during testing, not silent handling in production
5. **Code Simplicity**: Prioritize clarity and efficiency. Write straightforward, readable code over complex abstractions
6. **Storage Optimization**: Apply variable packing when it reduces storage reads (SLOADs) without compromising safety. Group related variables of smaller types together to fit in single storage slots

### External Dependencies

- **OpenZeppelin Contracts**: ERC20 base implementation and ReentrancyGuard
- **PepeUSD Token**: ERC20 token at 0xed7fd16423Bc19b9143313ac5E4B7F731D714e97 for fee exemption mechanism
- **Forge-std**: Testing framework and utilities

## Testing Strategy

Tests are located in `test/` directory and use Foundry's testing framework. Key test areas:

- Minting and redemption with fee calculations
- Lottery winner selection using Fenwick tree
- Commit-reveal randomness generation
- PepeUSD locking mechanism
- Edge cases around time transitions and phase changes
- **Test Debugging Priority**: When tests fail, first verify the test logic is correct before assuming contract bugs. Test implementation errors are more common than contract issues

## Important Implementation Details

1. **Fenwick Tree Updates**: When balances change, the contract updates the Fenwick tree to maintain cumulative sums for lottery selection
2. **Smart Contract Exclusion**: Smart contracts are excluded from lottery participation (only EOAs can win)
3. **Fee Minting During Initial Period**: During the 7-day minting period, fees are also minted as new tokens rather than redistributed
4. **Redemption Creates Capacity**: After minting period ends, burning tokens creates capacity for new mints up to the original max supply
