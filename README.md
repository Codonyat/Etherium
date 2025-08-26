# Etherium

A collectible ERC20 token backed 1:1 by ETH with daily lottery mechanics powered by prevrandao.

## Overview

Etherium is an ERC20 token with the following features:

- **ETH-backed**: 1 ETH = 1 ETHERIUM (both 18 decimals, 1:1 ratio)
- **1% transfer fee**: 100% goes to daily lottery pool
- **Daily lottery**: Random holder wins accumulated fees using prevrandao
- **Claimable prizes**: Winners have 7 days to claim, unclaimed prizes go to public goods
- **Fixed max supply**: Set by total supply at end of 7-day minting period
- **PepeUSD integration**: Lock 100 PepeUSD per mint for fee-free minting

## Key Features

### Minting & Redemption
- **7-day minting period**: Unlimited minting by depositing ETH (1% fee, fees also minted as tokens)
- **After minting period**: Fixed max supply based on total minted during initial week
- **Redemption creates capacity**: Burning ETHERIUM frees up space for new mints up to max supply
- Redeem ETHERIUM for ETH anytime (1% fee, 99% of tokens burned, 1% to lottery)

### Daily Lottery
- Automatic daily lottery execution for all ETHERIUM holders (EOAs only)
- Winners selected proportionally to holdings using prevrandao
- Smart contracts excluded from lottery participation
- Efficient O(log n) winner selection using Fenwick tree
- Must wait 1 minute into new day before lottery can execute (prevents manipulation)

### Prize Claiming System
- Winners have 7 days to claim their prizes
- Unclaimed prizes automatically sent to public goods organizations as ETH
- If ETH transfer to public good fails, prize is added to current lottery winner
- Winners can claim all their prizes in a single transaction

### PepeUSD Integration
- Lock 100 PepeUSD during minting period to mint without fees (via `mintFeeFree()`)
- Multiple locks allowed (e.g., lock 300 PepeUSD for 3 fee-free mints)
- All PepeUSD unlockable after 30 days from deployment
- Simple mechanism: each lock enables one fee-free mint

## Technical Details

### Contract Architecture
- Built on OpenZeppelin ERC20 and ReentrancyGuardTransient (EIP-1153)
- Efficient holder tracking with Fenwick tree (Binary Indexed Tree) for O(log n) operations
- Packed storage optimization for gas efficiency (maxSupplyEver, lastLotteryDay, currentPublicGoodIndex)
- DualState pattern for maintaining 2-day history snapshots
- No admin functions - fully decentralized and immutable

### Fee Structure
- 1% on all transfers, mints, and burns
- 100% of fees go to lottery pool
- During minting period: fees are minted as new tokens
- After minting period: fees are transferred from existing supply

### Storage Optimizations
- Uses transient storage for reentrancy guard (gas efficient)
- Packed storage variables into single slots where possible
- UnclaimedPrize struct packed to 256 bits (address + uint96)
- DualState structs optimized to fit in single storage slots

### Public Goods Recipients
Hardcoded addresses for automatic distribution of unclaimed prizes:
- Protocol Guild
- Coin Center  
- DeFi Education Fund
- European Crypto Initiative
- Ethereum Cat Herders

## Development

### Prerequisites
- [Foundry](https://getfoundry.sh/)

### Installation
```bash
forge install
```

### Build
```bash
forge build
```

### Testing
```bash
forge test
```

### Deployment
```bash
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast
```

## Security Considerations

- No upgradability or admin controls - fully immutable
- Reentrancy protection using transient storage (ReentrancyGuardTransient)
- Smart contracts automatically excluded from lottery participation
- Prevrandao provides secure on-chain randomness
- Direct ETH transfers rejected (must use mint() function)
- 1-minute delay after day change prevents lottery manipulation
- Fee mechanism ensures sustainable lottery rewards
- Comprehensive test suite with 32 tests including fuzz testing

## License

MIT