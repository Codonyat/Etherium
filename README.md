# Strategy

An ERC20 token backed by MEGA with daily lotteries and auctions.

## Overview

Strategy (GIGA) is a collectible ERC20 token where:

- 1000 MEGA mints 1 GIGA (minus 1% fee)
- All operations have a 1% fee that funds daily lotteries and auctions
- Random holders win lottery prizes proportional to their holdings
- After the minting period, supply becomes fixed at the total minted

## Key Mechanics

### Minting & Redemption

- **Minting Period (3 days)**: Unlimited minting at 1000:1 ratio (1000 MEGA = 1 GIGA)
- **Post-Minting**: Can only mint if someone redeems (burns) tokens first
- Redeem GIGA for MEGA anytime at proportional share of contract's MEGA reserve (1% fee applies)
- Redemption value increases as auctions bring in MEGA at market prices
- Requires ERC20 approval before minting: `mega.approve(strategyAddress, amount)`

### Daily Distribution

- Fees collected each day are distributed the next day
- After minting period: 50% of fees go to lottery, 50% to auction (both run daily)
- Smart contracts cannot win lotteries (excluded from holder tracking)

### Auctions

- Use MEGA for bidding (requires approval)
- 10% minimum bid increment
- Winners receive GIGA tokens
- Previous bidders are refunded automatically

## Technical Details

- **GIGA Decimals**: 21
- **MEGA Decimals**: 18
- Built on OpenZeppelin ERC20 with SafeERC20
- Uses Fenwick tree for efficient weighted random selection
- 25-hour days ensure events rotate through different times globally
- Fully immutable - no admin functions

## Development

```bash
# Install dependencies
forge install

# Run tests
forge test

# Deploy (replace with actual MEGA token address)
forge create src/Strategy.sol:Strategy \
  --constructor-args <MEGA_TOKEN_ADDRESS> \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY>
```

## License

MIT
