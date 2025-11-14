# Strategy

An ERC20 token backed by MON with daily lotteries and auctions.

## Overview

Strategy is a collectible ERC20 token where:

- 1 MON mints 1000 MONSTR (minus 1% fee)
- All operations have a 1% fee that funds daily lotteries and auctions
- Random holders win lottery prizes proportional to their holdings
- After day 7, supply becomes fixed at the total minted

## Key Mechanics

### Minting & Redemption

- **Days 0-6**: Unlimited minting at 1:1000 ratio
- **Day 7+**: Can only mint if someone redeems (burns) tokens first
- Redeem MONSTR for MON anytime at contract's MON balance / total supply ratio (1% fee applies)
- Redemption value increases as auctions bring in MON at market prices

### Daily Distribution

- Fees collected each day are distributed the next day
- After minting period: 50% of fees go to lottery, 50% to auction (both run daily)
- Smart contracts cannot win lotteries (excluded from holder tracking)

### Auctions

- Use WMON for bidding (prevents DoS attacks)
- 10% minimum bid increment
- Winners receive MONSTR tokens

## Technical Details

- Built on OpenZeppelin ERC20
- Uses Fenwick tree for efficient weighted random selection
- 25-hour days ensure events rotate through different times
- Fully immutable - no admin functions

## Development

```bash
# Install dependencies
forge install

# Run tests
forge test

# Deploy
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast
```

## License

MIT
