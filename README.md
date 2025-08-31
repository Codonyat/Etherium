# Etherium

A collectible ERC20 token backed by ETH with daily lottery and auction mechanics powered by prevrandao.

## Overview

Etherium is an ERC20 token with the following features:

- **ETH-backed**: During minting period: 1 ETH = 1000 ETHERIUM (both 18 decimals)
- **1% transfer fee**: Split 50/50 between lottery and auction pools after minting period
- **Daily lottery**: Random holder wins accumulated fees using prevrandao
- **Daily auctions**: WETH-based auctions for fee distribution (prevents DoS attacks)
- **Claimable prizes**: Winners have 1 week to claim, unclaimed prizes go to public goods
- **Fixed max supply**: Set by total supply at end of 7-day minting period
- **PepeUSD integration**: Lock 100 PepeUSD per mint for fee-free minting

## Key Features

### Minting & Redemption
- **7-day minting period**: Unlimited minting at 1 ETH = 1000 ETHERIUM (1% fee)
- **After minting period**: Fixed max supply based on total minted during initial week
- **Redemption creates capacity**: Burning ETHERIUM frees up space for new mints up to max supply
- Redeem ETHERIUM for ETH anytime at 1000:1 ratio (1% fee applied)

### Daily Lottery & Auctions
- After minting period: Fees split 50/50 between lottery and auction
- **Lottery**: Random holder selected proportionally to holdings using prevrandao
- **Auctions**: WETH-based bidding system (prevents griefing attacks)
- Smart contracts excluded from lottery participation
- Efficient O(log n) winner selection using Fenwick tree
- 25-hour "pseudo-days" ensure lottery/auction times rotate through different hours

### Auction System
- **WETH Integration**: Bidders use WETH tokens instead of ETH
- **DoS Prevention**: WETH refunds cannot be blocked by malicious contracts
- **10% Minimum Increment**: Each bid must be at least 10% higher than previous
- **Automatic Finalization**: When new auction starts, previous one finalizes
- **WETH to ETH Conversion**: Only happens on finalization, maintaining ETH backing

### Prize Claiming System
- Winners have 1 week to claim their prizes (lottery or auction)
- Unclaimed prizes automatically sent to public goods organizations as ETH
- If ETH transfer to public good fails, prize is added to current winner
- Winners can claim all their prizes in a single transaction
- 14 prize slots handle alternating lottery/auction daily schedule

### PepeUSD Integration
- Lock 100 PepeUSD during minting period to mint without fees (via `mintFeeFree()`)
- Multiple locks allowed (e.g., lock 300 PepeUSD for 3 fee-free mints)
- All PepeUSD unlockable after 30 days from deployment
- Simple mechanism: each lock enables one fee-free mint

## Technical Details

### Contract Architecture
- Built on OpenZeppelin ERC20 and ReentrancyGuardTransient (EIP-1153)
- Efficient holder tracking with Fenwick tree (Binary Indexed Tree) for O(log n) operations
- Packed storage optimization for gas efficiency
- DualState pattern for maintaining 2-day history snapshots
- No admin functions - fully decentralized and immutable

### Fee Structure
- 1% on all transfers, mints, and burns
- During minting period: 100% of fees to lottery pool
- After minting period: 50% lottery, 50% auction
- Fees tracked daily for next day's distribution

### Storage Optimizations
- Uses transient storage for reentrancy guard (gas efficient)
- Packed storage variables into single slots where possible
- UnclaimedPrize struct packed efficiently (address + uint112)
- DualState structs optimized to fit in single storage slots

### Public Goods Recipients
Hardcoded addresses for automatic distribution of unclaimed prizes:
- Protocol Guild (0x25941dC771bB64514Fc8abBce970307Fb9d477e9)
- Coin Center (0x15322B546e31F5Bfe144C4ae133A9Db6F0059fe3)
- DeFi Education Fund (0x1C95930Dfc1139381265ce45B5f480F1EFae09A1)
- European Crypto Initiative (0x25f5D96B50a3f7c704E76C38A3F10617e83D9491)
- Ethereum Cat Herders (0x8D3AcA27963D5BAD978d3e953D3F3680cEa3FAeC)

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

- **No upgradability**: Fully immutable contract with no admin controls
- **Reentrancy protection**: Using transient storage (ReentrancyGuardTransient)
- **DoS prevention**: WETH-based auctions prevent refund blocking attacks
- **Smart contract exclusion**: Contracts cannot participate in lottery
- **Secure randomness**: Prevrandao provides on-chain randomness
- **Direct ETH rejection**: Must use mint() function, no accidental sends
- **Time gap protection**: 1-minute delay after day change prevents manipulation
- **Sustainable rewards**: Fee mechanism ensures continuous lottery/auction prizes

## WETH Integration

The auction system uses Wrapped ETH (WETH) to prevent denial-of-service attacks:
- Bidders approve and transfer WETH instead of sending ETH
- Previous bidders receive WETH refunds (cannot be blocked)
- WETH is only converted to ETH when auction finalizes
- Maintains full ETH backing while preventing griefing attacks

## License

MIT