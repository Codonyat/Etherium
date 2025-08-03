# Etherium

A collectible token backed by ETH with daily lottery and decentralized randomness.

## Overview

Etherium is an ERC20 token with the following features:

- **ETH-backed**: 1 ETH = 1,000,000 ETHERIUM (12 decimals)
- **1% transfer fee**: 0.9% goes to daily lottery, 0.1% to randomness participants
- **Daily lottery**: Random holder wins accumulated fees proportional to holdings
- **Commit-reveal randomness**: Decentralized random number generation
- **Fixed max supply**: Set by ETH deposited during 7-day minting week
- **PepeUSD integration**: Lock PepeUSD to mint ETHERIUM without fees

## Key Features

### Minting & Redemption
- **Minting week**: Unlimited minting by depositing ETH (1% fee, fees also minted as tokens)
- **After minting week**: Fixed max supply based on ETH deposited during week
- **Redemption creates capacity**: Burning ETHERIUM frees up space for new mints
- Redeem ETHERIUM for ETH anytime (1% fee, only 99% actually burned from supply)

### Daily Lottery
- Automatic daily lottery for all ETHERIUM holders
- Winners selected proportionally to holdings
- Smart contracts excluded from lottery
- Efficient O(log n) winner selection

### Commit-Reveal Randomness
- 24-hour cycles: 12h commit phase, 12h reveal phase
- Participants stake ETHERIUM and commit secret numbers
- Honest revealers share 0.1% fees + dishonest participants' stakes
- Prevents secret reuse for true randomness

### PepeUSD Integration
- Lock PepeUSD for 1 week to mint fee-free ETHERIUM
- Amount based on PepeUSD value via Uniswap TWAP
- Unlock PepeUSD after lock period

## Technical Details

### Contract Architecture
- Built on OpenZeppelin ERC20
- ReentrancyGuard for security
- Efficient holder tracking with cumulative sum tree
- No admin functions - fully decentralized

### Fee Structure
- 1% on all transfers, mints, and burns
- 0.9% to lottery pool
- 0.1% to randomness participants

### Randomness Generation
- Commit phase: Hash(secret + address)
- Reveal phase: XOR all revealed secrets + block randomness
- Slashing for non-revealers

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

- No upgradability or admin controls
- Reentrancy protection on all external functions
- Holder tracking excludes smart contracts from lottery
- Commit-reveal prevents randomness manipulation
- Fee mechanism ensures sustainable lottery rewards

## License

MIT