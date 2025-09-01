// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "./interfaces/IExternalTokens.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

/**
 * @title Etherium
 * @dev ERC20 token backed by ETH with daily lottery and auction mechanics
 * - During 7-day minting period: 1 ETH = 1000 ETHERIUM (both 18 decimals)
 * - Redemption: Proportional share of contract's ETH (ETHERIUM * ETH balance / total supply)
 * - 1% fee on mint/burn/transfer (split between lottery and auction pools)
 * - Daily lottery for random holder using prevrandao
 * - Daily auctions using WETH to prevent DoS attacks
 * - Users can lock 100 PepeUSD during minting period to mint without fees
 * - Efficient winner selection using Fenwick tree (Binary Indexed Tree)
 * - Uses transient storage for reentrancy guard (EIP-1153) for gas efficiency
 */
contract Etherium is ERC20, ReentrancyGuardTransient {
    // Conversion: 1 ETH = 1000 ETHERIUM during minting period (both 18 decimals)
    uint256 public constant DECIMALS = 18;
    uint256 public constant FEE_PERCENT = 100; // 1% = 100 basis points
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MINTING_PERIOD = 7 days;
    uint256 public constant PEPEUSD_LOCK_AMOUNT = 100 ether; // 100 PepeUSD (18 decimals)
    uint256 public constant PEPEUSD_UNLOCK_TIME = 30 days; // 1 month from deployment

    // Synthetic addresses for fee management
    address public constant FEES_POOL =
        0x00000000000fee50000000AdD2E5500000000000; // Where fees are collected
    address public constant LOT_POOL =
        0x0000000000010700000000aDD2E5500000000000; // Where lottery/auction prizes are held

    uint256 public immutable deploymentTime;
    uint256 public immutable mintingEndTime;

    // Packed storage slot: 112 + 32 + 8 = 152 bits (fits in one 256-bit slot)
    uint112 public maxSupplyEver; // Set after minting period (max ~5.2 quadrillion ETHERIUM with 18 decimals)
    uint32 public lastLotteryDay; // Day counter (sufficient for ~11.7 million years)
    uint8 public currentPublicGoodIndex; // Index in PUBLIC_GOODS array (max 255 addresses)

    uint256 public constant TIME_GAP = 1 minutes; // Must be 1 minute into new day before lottery can execute
    uint256 public constant MIN_FEES_FOR_DISTRIBUTION = 1e12; // Minimum fees (0.000001 ETHERIUM) to run lottery/auction

    // Cyclical array for unclaimed prizes (14 slots)
    // We need 14 slots because after minting period we alternate lottery/auction daily
    // This ensures a full week of unclaimed prizes for both types
    // Packed struct: 160 + 112 = 272 bits (exceeds 256, uses 2 slots per prize)
    struct UnclaimedPrize {
        address winner; // 160 bits
        uint112 amount; // 112 bits (ETHERIUM amount for prizes)
    }

    UnclaimedPrize[14] public unclaimedPrizes;

    // Public goods recipients (hardcoded)
    address[5] public PUBLIC_GOODS = [
        0x25941dC771bB64514Fc8abBce970307Fb9d477e9, // Protocol Guild
        0x15322B546e31F5Bfe144C4ae133A9Db6F0059fe3, // Coin Center
        0x1C95930Dfc1139381265ce45B5f480F1EFae09A1, // DeFi Education Fund
        0x25f5D96B50a3f7c704E76C38A3F10617e83D9491, // European Crypto Initiative
        0x8D3AcA27963D5BAD978d3e953D3F3680cEa3FAeC // Ethereum Cat Herders
    ];

    // Struct to maintain rolling 2-day history for each value
    // Stores current and previous value with the day of last update
    // Optimized to fit in one 256-bit storage slot
    struct DualState {
        uint112 olderValue; // Previous value before last update (112 bits)
        uint112 latestValue; // Most recent value (112 bits)
        uint32 lastUpdatedDay; // Day when latestValue was set (32 bits)
        // Total: 256 bits (fits exactly in 1 storage slot)
    }

    // For addresses, we need a separate struct since addresses are 160 bits
    struct DualAddress {
        address olderValue;
        address latestValue;
        uint32 lastUpdatedDay;
    }

    // Holder tracking with rolling 2-day history
    mapping(uint256 index => DualAddress) public holderByIndex;
    mapping(address holder => DualState) public indexByHolder;
    mapping(uint256 index => DualState) public fenwickTree;
    DualState public holderCount;
    DualState public totalHolderBalance;

    // PepeUSD integration
    IERC20 public constant PEPEUSD =
        IERC20(0xed7fd16423Bc19b9143313ac5E4B7F731D714e97);

    // WETH integration for auctions (mainnet address)
    IWETH public constant WETH =
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // Track PepeUSD locked per user during minting period
    mapping(address user => uint256 amount) public pepeUSDLocked;

    event Minted(
        address indexed to,
        uint256 ethAmount,
        uint256 etheriumAmount,
        uint256 fee
    );
    event Redeemed(
        address indexed from,
        uint256 etheriumAmount,
        uint256 ethAmount,
        uint256 fee
    );
    event LotteryWon(address indexed winner, uint256 amount, uint256 day);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event PublicGoodsFunded(
        address indexed publicGood,
        uint256 amount,
        address previousWinner
    );
    event PepeUSDLocked(
        address indexed user,
        uint256 pepeAmount,
        uint256 etheriumMinted,
        uint256 unlockTime
    );
    event PepeUSDUnlocked(address indexed user, uint256 amount);

    // Auction events
    event AuctionStarted(uint256 day, uint256 etheriumAmount, uint256 minBid);
    event BidPlaced(address indexed bidder, uint256 amount, uint256 day);
    event BidRefunded(address indexed bidder, uint256 amount);
    event AuctionWon(
        address indexed winner,
        uint256 etheriumAmount,
        uint256 ethPaid,
        uint256 day
    );

    // Auction state
    // Packed struct: 160 + 96 + 96 + 112 + 32 = 496 bits (uses 2 slots)
    struct Auction {
        address currentBidder; // 160 bits
        uint96 currentBid; // 96 bits - WETH amount bid
        uint96 minBid; // 96 bits - Minimum bid required (in WETH)
        uint112 etheriumAmount; // 112 bits - ETHERIUM amount being auctioned
        uint32 auctionDay; // 32 bits - Day of the auction
    }

    Auction public currentAuction;

    // Track fees collected per day for next day's lottery/auction
    mapping(uint256 day => uint256 fees) public dailyFeesCollected;

    constructor() ERC20("Etherium", "ETHERIUM") {
        deploymentTime = block.timestamp;
        mintingEndTime = deploymentTime + MINTING_PERIOD;
    }

    function decimals() public pure override returns (uint8) {
        return uint8(DECIMALS);
    }

    /**
     * @dev Check and set max supply after minting period ends
     */
    function _checkAndSetMaxSupply() internal {
        if (block.timestamp > mintingEndTime && maxSupplyEver == 0) {
            // Set max supply based on total supply at end of minting period
            // 1:1 conversion - max supply equals total ETHERIUM minted
            maxSupplyEver = uint112(totalSupply());
        }
    }

    /**
     * @dev Accept ETH from anyone - donations benefit all token holders proportionally
     */
    receive() external payable {
        // Accept all ETH transfers with no data
        // This allows:
        // 1. WETH withdrawals for auctions
        // 2. Community donations that increase backing value
        // 3. Failed public goods transfers to not revert
    }

    /**
     * @dev Mint ETHERIUM by depositing ETH (standard minting with fees)
     * During minting period: 1 ETH = 1000 ETHERIUM
     * After minting period: Can only mint up to available capacity
     */
    function mint() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");

        // Try to execute pending lottery/auction before changing state
        _tryExecuteLotteryAndAuction();

        _checkAndSetMaxSupply();

        uint256 etheriumToMint;
        uint256 fee;
        uint256 netEtherium;

        // Get balance before minting

        if (block.timestamp <= mintingEndTime) {
            // During minting period: 1 ETH = 1000 ETHERIUM
            // Overflow safety: msg.value < 2^96, 1000 < 2^10, so product < 2^106 (fits in uint256)
            etheriumToMint = msg.value * 1000;
        } else {
            // After minting period: proportional to ETH/supply ratio
            uint256 ethBalance = address(this).balance - msg.value; // Exclude sent ETH
            if (totalSupply() > 0 && ethBalance > 0) {
                // Mint proportionally to maintain ETH backing ratio
                // Overflow safety: msg.value < 2^96, totalSupply() <= maxSupplyEver < 2^112
                // Product < 2^208, which fits in uint256 (no overflow possible)
                etheriumToMint = (msg.value * totalSupply()) / ethBalance;
            } else {
                // Fallback to 1000:1 if no supply or ETH
                // Overflow safety: msg.value < 2^96, 1000 < 2^10, so product < 2^106 (fits in uint256)
                etheriumToMint = msg.value * 1000;
            }

            require(
                totalSupply() + etheriumToMint <= maxSupplyEver,
                "Max supply reached"
            );
        }

        // Calculate and apply fees (common to both minting periods)
        // Overflow safety: etheriumToMint <= maxSupplyEver < 2^112, FEE_PERCENT = 100 < 2^7
        // Product < 2^119, which fits in uint256 (no overflow possible)
        fee = (etheriumToMint * FEE_PERCENT) / BASIS_POINTS;
        netEtherium = etheriumToMint - fee;

        // Mint uses _atomicUpdate internally, so Fenwick tree is updated atomically
        _mint(msg.sender, netEtherium);
        if (fee > 0) {
            _mint(FEES_POOL, fee);
            dailyFeesCollected[getCurrentDay()] += fee;
        }

        // No need for manual Fenwick update - handled atomically in _update

        emit Minted(msg.sender, msg.value, netEtherium, fee);
    }

    /**
     * @dev Mint ETHERIUM fee-free by locking 100 PepeUSD
     * Each lock of 100 PepeUSD allows one fee-free mint
     * 1 ETH = 1000 ETHERIUM (no fees deducted)
     */
    function mintFeeFree() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");
        require(
            block.timestamp <= mintingEndTime,
            "Fee-free minting only during minting period"
        );

        // Try to execute pending lottery/auction before changing state
        _tryExecuteLotteryAndAuction();

        // Transfer 100 PepeUSD from user to lock
        require(
            PEPEUSD.transferFrom(
                msg.sender,
                address(this),
                PEPEUSD_LOCK_AMOUNT
            ),
            "PepeUSD transfer failed"
        );

        // Track locked amount
        pepeUSDLocked[msg.sender] += PEPEUSD_LOCK_AMOUNT;

        _checkAndSetMaxSupply();

        // Mint without fees, 1 ETH = 1000 ETHERIUM during minting period
        // Overflow safety: msg.value < 2^96, 1000 < 2^10, product < 2^106 (no overflow)
        uint256 etheriumToMint = msg.value * 1000;

        // After minting period: enforce max supply limit
        if (block.timestamp > mintingEndTime) {
            require(
                totalSupply() + etheriumToMint <= maxSupplyEver,
                "Max supply reached"
            );
        }

        // Mint full amount to user (no fees)
        // _mint uses _atomicUpdate internally, so Fenwick tree is updated atomically
        _mint(msg.sender, etheriumToMint);

        emit PepeUSDLocked(
            msg.sender,
            PEPEUSD_LOCK_AMOUNT,
            etheriumToMint,
            deploymentTime + PEPEUSD_UNLOCK_TIME
        );

        emit Minted(msg.sender, msg.value, etheriumToMint, 0);
    }

    /**
     * @dev Unlock all PepeUSD after 1 month from deployment
     */
    function unlockPepeUSD() external nonReentrant {
        uint256 lockedAmount = pepeUSDLocked[msg.sender];
        require(lockedAmount > 0, "No locked PepeUSD");
        require(
            block.timestamp >= deploymentTime + PEPEUSD_UNLOCK_TIME,
            "Still in lock period (1 month from deployment)"
        );

        // Try to execute pending lottery/auction before changing state
        _tryExecuteLotteryAndAuction();

        // Clear user's locked amount
        pepeUSDLocked[msg.sender] = 0;

        // Return all locked PepeUSD
        require(
            PEPEUSD.transfer(msg.sender, lockedAmount),
            "PepeUSD transfer failed"
        );

        emit PepeUSDUnlocked(msg.sender, lockedAmount);
    }

    /**
     * @dev Redeem ETHERIUM for ETH
     * Returns proportional share of contract's ETH balance (minus 1% fee)
     */
    function redeem(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Try to execute pending lottery/auction before changing state
        _tryExecuteLotteryAndAuction();

        _checkAndSetMaxSupply();

        // Overflow safety: amount <= user balance <= totalSupply < 2^112, FEE_PERCENT = 100 < 2^7
        // Product < 2^119, which fits in uint256 (no overflow possible)
        uint256 fee = (amount * FEE_PERCENT) / BASIS_POINTS;
        uint256 netEtherium = amount - fee;

        // Calculate proportional ETH to return before state changes
        // Overflow safety: netEtherium < 2^112, address(this).balance < 2^96 (ETH supply limit)
        // Product < 2^208, which fits in uint256 (no overflow possible)
        uint256 ethToReturn = (netEtherium * address(this).balance) /
            totalSupply();

        // Transfer fees atomically (Fenwick tree updated automatically)
        if (fee > 0) {
            _atomicUpdate(msg.sender, FEES_POOL, fee);
            dailyFeesCollected[getCurrentDay()] += fee;
        }

        // Burn the remainder from user atomically (Fenwick tree updated automatically)
        _burn(msg.sender, netEtherium);

        // Transfer proportional ETH back to user
        (bool success, ) = msg.sender.call{value: ethToReturn}("");
        require(success, "ETH transfer failed");

        emit Redeemed(msg.sender, amount, ethToReturn, fee);
    }

    /**
     * @dev Atomic balance update that ensures Fenwick tree consistency
     * This function should be used for ALL internal balance changes to maintain atomicity
     */
    function _atomicUpdate(address from, address to, uint256 value) internal {
        // Get balances BEFORE the update
        uint256 fromBalanceBefore = from != address(0) ? balanceOf(from) : 0;
        uint256 toBalanceBefore = to != address(0) ? balanceOf(to) : 0;

        // Perform the actual balance update
        super._update(from, to, value);

        // Get balances AFTER the update
        uint256 fromBalanceAfter = from != address(0) ? balanceOf(from) : 0;
        uint256 toBalanceAfter = to != address(0) ? balanceOf(to) : 0;

        // Update Fenwick tree atomically with balance changes
        // All filtering (address(0), contracts, synthetic addresses) handled internally
        _updateCumulativeBalancesWithExplicitBalances(
            from,
            fromBalanceBefore,
            fromBalanceAfter
        );

        _updateCumulativeBalancesWithExplicitBalances(
            to,
            toBalanceBefore,
            toBalanceAfter
        );
    }

    /**
     * @dev Override update to apply fees on transfers
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // Redirect external transfers to this contract to FEES_POOL
        if (to == address(this)) {
            _atomicUpdate(from, FEES_POOL, value);
            return;
        }

        // For minting and burning, use atomic update directly
        if (from == address(0) || to == address(0)) {
            _atomicUpdate(from, to, value);
            return;
        }

        // Try to execute pending lottery/auction before transfers
        _tryExecuteLotteryAndAuction();

        // Apply fees for transfers
        // Overflow safety: value <= totalSupply < 2^112, FEE_PERCENT = 100 < 2^7
        // Product < 2^119, which fits in uint256 (no overflow possible)
        uint256 fee = (value * FEE_PERCENT) / BASIS_POINTS;
        uint256 netAmount = value - fee;

        // Use atomic updates for both the transfer and fee
        // This ensures Fenwick tree consistency
        // For self-transfers, we still need to emit the Transfer event
        if (from == to) {
            // Self-transfer: emit event but skip the no-op balance update
            emit Transfer(from, to, netAmount);
        } else {
            // Normal transfer: update balances and emit event via _atomicUpdate
            _atomicUpdate(from, to, netAmount);
        }

        // Transfer fees to fees pool atomically
        if (fee > 0) {
            _atomicUpdate(from, FEES_POOL, fee);
            dailyFeesCollected[getCurrentDay()] += fee;
        }
    }

    /**
     * @dev Update a DualState with a new value, preserving history
     */
    function _updateDualState(
        DualState storage state,
        uint112 newValue,
        uint32 currentDay
    ) internal {
        if (state.lastUpdatedDay < currentDay) {
            // New day - shift current to older and set new value
            state.olderValue = state.latestValue;
            state.latestValue = newValue;
            state.lastUpdatedDay = currentDay;
        } else {
            // Same day - just update latest value
            state.latestValue = newValue;
        }
    }

    /**
     * @dev Update a DualAddress with a new value, preserving history
     */
    function _updateDualAddress(
        DualAddress storage state,
        address newValue,
        uint32 currentDay
    ) internal {
        if (state.lastUpdatedDay < currentDay) {
            // New day - shift current to older and set new value
            state.olderValue = state.latestValue;
            state.latestValue = newValue;
            state.lastUpdatedDay = currentDay;
        } else {
            // Same day - just update latest value
            state.latestValue = newValue;
        }
    }

    /**
     * @dev Get value from a DualState for a specific day
     */
    function _getDualStateValue(
        DualState memory state,
        uint32 targetDay
    ) internal pure returns (uint112) {
        if (state.lastUpdatedDay <= targetDay) {
            return state.latestValue;
        }
        return state.olderValue;
    }

    /**
     * @dev Get value from a DualAddress for a specific day
     */
    function _getDualAddressValue(
        DualAddress memory state,
        uint32 targetDay
    ) internal pure returns (address) {
        if (state.lastUpdatedDay <= targetDay) {
            return state.latestValue;
        }
        return state.olderValue;
    }

    /**
     * @dev Update Fenwick tree at index with delta (suffix sum version)
     * For suffix sums, we update positions whose range includes the index
     */
    function _fenwickUpdate(uint256 index, int256 delta) internal {
        uint32 currentDay = uint32(getCurrentDay());

        // Update all nodes whose suffix range includes this index
        // Start from index and move backward
        uint256 i = index;
        while (i > 0) {
            DualState storage treeNode = fenwickTree[i];
            uint112 currentSum = treeNode.latestValue;
            uint112 newSum;

            if (delta > 0) {
                newSum = currentSum + uint112(uint256(delta));
            } else {
                uint112 decrease = uint112(uint256(-delta));
                newSum = currentSum - decrease;
            }

            _updateDualState(treeNode, newSum, currentDay);

            // Move to previous node whose range includes our index
            // For suffix tree: move to i - lowbit(i)
            i -= i & uint256(-int256(i));
        }
    }

    /**
     * @dev Query suffix sum from index to end for a specific day
     * Goes upward using the current holder count as max
     */
    function _fenwickQuery(
        uint256 index,
        uint32 targetDay
    ) internal view returns (uint256) {
        uint256 sum = 0;
        uint112 maxIndex = _getDualStateValue(holderCount, targetDay);

        while (index <= maxIndex) {
            sum += _getDualStateValue(fenwickTree[index], targetDay);
            index += index & uint256(-int256(index)); // Move up the tree
        }
        return sum;
    }

    /**
     * @dev Update holder balance with explicit before/after balances
     */
    function _updateCumulativeBalancesWithExplicitBalances(
        address account,
        uint256 balanceBefore,
        uint256 balanceAfter
    ) internal {
        if (account == address(0)) return; // Skip zero address (minting/burning)
        if (account.code.length > 0) return; // Skip contracts
        if (account == LOT_POOL || account == FEES_POOL) return; // Skip synthetic addresses

        uint32 currentDay = uint32(getCurrentDay());
        uint256 currentIndex = indexByHolder[account].latestValue;

        int256 balanceChange = int256(balanceAfter) - int256(balanceBefore);

        if (balanceAfter > 0 && currentIndex == 0) {
            // Add new holder
            uint112 newCount = holderCount.latestValue + 1;
            uint112 newTotalBalance = totalHolderBalance.latestValue +
                uint112(balanceAfter);

            _updateDualState(holderCount, newCount, currentDay);
            _updateDualAddress(holderByIndex[newCount], account, currentDay);
            _updateDualState(
                indexByHolder[account],
                uint112(newCount),
                currentDay
            );

            // Update Fenwick tree
            _fenwickUpdate(newCount, int256(balanceAfter));

            _updateDualState(totalHolderBalance, newTotalBalance, currentDay);
        } else if (balanceAfter == 0 && currentIndex > 0) {
            // Remove holder - use the balance before removal
            uint112 currentTotalBalance = totalHolderBalance.latestValue;

            // Update Fenwick tree before removal
            _fenwickUpdate(currentIndex, -int256(balanceBefore));

            uint112 newTotalBalance = currentTotalBalance -
                uint112(balanceBefore);

            _updateDualState(totalHolderBalance, newTotalBalance, currentDay);

            // Compact holders by moving the last holder to the removed position
            uint112 currentCount = holderCount.latestValue;

            if (currentIndex < currentCount) {
                address lastHolder = holderByIndex[currentCount].latestValue;

                // Get the last holder's balance from the Fenwick tree at their position
                // This is their balance BEFORE any concurrent updates
                uint112 lastHolderFenwickBalance = fenwickTree[currentCount]
                    .latestValue;

                // Remove last holder's balance from old position
                _fenwickUpdate(
                    currentCount,
                    -int256(uint256(lastHolderFenwickBalance))
                );

                // Move last holder to current position
                _updateDualAddress(
                    holderByIndex[currentIndex],
                    lastHolder,
                    currentDay
                );
                _updateDualState(
                    indexByHolder[lastHolder],
                    uint112(currentIndex),
                    currentDay
                );

                // Add last holder's balance to new position
                _fenwickUpdate(
                    currentIndex,
                    int256(uint256(lastHolderFenwickBalance))
                );
            }

            // Clear the removed holder's index and last position
            _updateDualState(indexByHolder[account], 0, currentDay);
            _updateDualAddress(
                holderByIndex[currentCount],
                address(0),
                currentDay
            );

            // Decrement holder count
            _updateDualState(holderCount, currentCount - 1, currentDay);
        } else if (currentIndex > 0) {
            // Update existing holder
            // Update Fenwick tree with the difference
            _fenwickUpdate(currentIndex, balanceChange);

            uint112 currentTotalBalance = totalHolderBalance.latestValue;
            uint112 newTotalBalance;

            if (balanceChange > 0) {
                newTotalBalance =
                    currentTotalBalance +
                    uint112(uint256(balanceChange));
            } else {
                uint112 decrease = uint112(uint256(-balanceChange));
                newTotalBalance = currentTotalBalance > decrease
                    ? currentTotalBalance - decrease
                    : 0;
            }

            _updateDualState(totalHolderBalance, newTotalBalance, currentDay);
        }
    }

    /**
     * @dev Internal function to try executing pending lottery and auction
     * Called before state-changing operations to ensure winners are determined first
     */
    function _tryExecuteLotteryAndAuction() internal {
        uint256 currentDay = getCurrentDay();

        // No lottery/auction until day 2 (need previous day's fees)
        if (currentDay < 2) return;

        // If day changed since last lottery, we have a pending lottery/auction
        if (currentDay <= lastLotteryDay) return;

        // Ensure we're at least 1 minute into the new day to prevent manipulation
        uint256 timeIntoDay = (block.timestamp - deploymentTime) % 25 hours;
        if (timeIntoDay < TIME_GAP) return;

        // Get fees from previous day (day before current)
        uint256 feesToDistribute = dailyFeesCollected[currentDay - 1];

        // Skip lottery/auction for dust amounts
        // This ensures both lottery and auction get meaningful amounts when split
        if (feesToDistribute < MIN_FEES_FOR_DISTRIBUTION) return;

        // Run both lottery and auction every day after minting period
        // During minting period, only run lottery with full fees
        if (block.timestamp > mintingEndTime) {
            // Split fees 50/50 between lottery and auction
            uint256 lotteryShare = feesToDistribute / 2;
            uint256 auctionShare = feesToDistribute - lotteryShare; // Handle odd amounts
            _executeLotteryInternal(lotteryShare);
            _startAuction(auctionShare);
        } else {
            _executeLotteryInternal(feesToDistribute);
        }
    }

    /**
     * @dev Internal lottery execution logic
     */
    function _executeLotteryInternal(uint256 feesToDistribute) internal {
        uint256 randomSeed = block.prevrandao;
        uint256 currentDay = getCurrentDay();

        // Use snapshot from previous day (when fees were collected)
        uint32 snapshotDay = uint32(currentDay - 1);

        // Get holder count and total balance from the snapshot day
        uint112 snapshotHolderCount = _getDualStateValue(
            holderCount,
            snapshotDay
        );
        uint112 snapshotTotalBalance = _getDualStateValue(
            totalHolderBalance,
            snapshotDay
        );

        // Select winner if there are holders
        if (snapshotHolderCount > 0 && snapshotTotalBalance > 0) {
            address winner = _selectWinnerEfficient(snapshotDay, randomSeed);

            uint256 lotteryDay = currentDay - 1; // The day whose fees we're distributing
            uint256 slot = lotteryDay % 14; // Use 14 slots to handle lottery/auction alternation

            // Transfer prize from fees pool to lottery pool for holding
            _atomicUpdate(FEES_POOL, LOT_POOL, feesToDistribute);

            // Check if this slot has an unclaimed prize
            UnclaimedPrize storage prize = unclaimedPrizes[slot];
            if (prize.amount > 0) {
                // Try to redeem ETHERIUM for ETH and send to public good
                address publicGood = PUBLIC_GOODS[currentPublicGoodIndex];
                currentPublicGoodIndex = uint8(
                    (currentPublicGoodIndex + 1) % PUBLIC_GOODS.length
                );

                // Attempt to send ETH to public good first (1:1 conversion)
                (bool success, ) = publicGood.call{value: prize.amount}("");

                if (success) {
                    // ETH transfer successful, now burn the ETHERIUM tokens from lottery pool
                    _burn(LOT_POOL, prize.amount);
                    emit PublicGoodsFunded(
                        publicGood,
                        prize.amount,
                        prize.winner
                    );
                } else {
                    // ETH transfer failed, add unclaimed prize to current winner's prize
                    // The current winner will get both prizes when they claim
                    feesToDistribute += prize.amount;
                    // Note: We still cycle to the next public good for fairness
                }
            }

            // Store new prize in the slot (overwriting any previous data)
            prize.winner = winner;
            prize.amount = uint112(feesToDistribute); // Store ETHERIUM amount as prize

            emit LotteryWon(winner, feesToDistribute, lotteryDay);
        }

        // Update last lottery day
        lastLotteryDay = uint32(currentDay);
    }

    /**
     * @dev Public function to execute daily lottery
     */
    function executeLottery() external nonReentrant {
        uint256 currentDay = getCurrentDay();
        require(
            currentDay >= 2,
            "Must wait until day 2 for first lottery/auction"
        );

        require(
            currentDay > lastLotteryDay,
            "No pending lottery/auction (same day)"
        );

        // Ensure we're at least 1 minute into the new day
        uint256 timeIntoDay = (block.timestamp - deploymentTime) % 25 hours;
        require(
            timeIntoDay >= TIME_GAP,
            "Must wait 1 minute into new day before executing"
        );

        // Get fees from previous day
        uint256 feesToDistribute = dailyFeesCollected[currentDay - 1];
        require(
            feesToDistribute >= MIN_FEES_FOR_DISTRIBUTION,
            "Insufficient fees to distribute"
        );

        // Split fees 50/50 between lottery and auction
        uint256 lotteryShare = feesToDistribute / 2;
        uint256 auctionShare = feesToDistribute - lotteryShare; // Handle odd amounts

        // Run both lottery and auction every day after minting period
        // During minting period, only run lottery with full fees
        if (block.timestamp > mintingEndTime) {
            _executeLotteryInternal(lotteryShare);
            _startAuction(auctionShare);
        } else {
            _executeLotteryInternal(feesToDistribute);
        }
    }

    /**
     * @dev Claim unclaimed prizes for the caller
     */
    function claim() external nonReentrant {
        uint256 totalClaimed = 0;

        // Check all 7 slots for prizes belonging to caller
        for (uint256 i = 0; i < 14; i++) {
            if (
                unclaimedPrizes[i].winner == msg.sender &&
                unclaimedPrizes[i].amount > 0
            ) {
                uint256 prizeAmount = unclaimedPrizes[i].amount;
                totalClaimed += prizeAmount;

                // Clear the slot
                unclaimedPrizes[i].winner = address(0);
                unclaimedPrizes[i].amount = 0;

                emit PrizeClaimed(msg.sender, prizeAmount);
            }
        }

        require(totalClaimed > 0, "No prizes to claim");

        // Transfer all claimed prizes at once from lottery pool
        // _atomicUpdate handles Fenwick tree updates automatically
        _atomicUpdate(LOT_POOL, msg.sender, totalClaimed);
    }

    /**
     * @dev Efficient winner selection using binary search on Fenwick tree (suffix sum version)
     */
    function _selectWinnerEfficient(
        uint32 lotteryDay,
        uint256 randomSeed
    ) internal view returns (address) {
        uint112 snapshotTotalBalance = _getDualStateValue(
            totalHolderBalance,
            lotteryDay
        );
        uint112 snapshotHolderCount = _getDualStateValue(
            holderCount,
            lotteryDay
        );

        // Random number from 1 to total balance
        // No overflow risk: modulo operation always produces result < snapshotTotalBalance
        uint256 winningNumber = (randomSeed % snapshotTotalBalance) + 1;

        // With suffix sums, we want to find the largest index where suffix sum >= winningNumber
        // Since suffix sum decreases as index increases, we search for the transition point
        uint256 left = 1;
        uint256 right = snapshotHolderCount;

        while (left < right) {
            uint256 mid = (left + right + 1) / 2; // Round up to avoid infinite loop
            uint256 suffixSum = _fenwickQuery(mid, lotteryDay);

            if (suffixSum >= winningNumber) {
                // This holder or later could be the winner, try higher index
                left = mid;
            } else {
                // Suffix sum too small, need earlier holder
                right = mid - 1;
            }
        }

        return _getDualAddressValue(holderByIndex[left], lotteryDay);
    }

    /**
     * @dev Get current day number
     * We use 25-hour "pseudo-days" instead of 24-hour days so that over time,
     * the daily lottery/auction transitions happen at different hours of the day.
     * This gives participants from all time zones equal opportunities to participate
     * in the beginning and end of each cycle, preventing any geographic advantage.
     */
    function getCurrentDay() public view returns (uint256) {
        return (block.timestamp - deploymentTime) / 25 hours;
    }

    /**
     * @dev Get holder count (latest value)
     */
    function getHolderCount() external view returns (uint256) {
        return holderCount.latestValue;
    }

    /**
     * @dev Get holder info by index (1-indexed for Fenwick tree)
     */
    function getHolderByIndex(
        uint256 index
    ) external view returns (address holder, uint256 balance) {
        require(
            index > 0 && index <= holderCount.latestValue,
            "Index out of bounds"
        );
        address holderAddress = holderByIndex[index].latestValue;
        return (holderAddress, balanceOf(holderAddress));
    }

    /**
     * @dev Get current lottery pool balance
     */
    function currentLotteryPool() external view returns (uint256) {
        return balanceOf(LOT_POOL);
    }

    /**
     * @dev Check if an address is a holder
     */
    function isHolder(address account) external view returns (bool) {
        return indexByHolder[account].latestValue > 0;
    }

    /**
     * @dev Debug function to get Fenwick tree value at index (for testing)
     */
    function getFenwickValue(uint256 index) external view returns (uint256) {
        return fenwickTree[index].latestValue;
    }

    /**
     * @dev Debug function to get suffix sum from index to end (for testing)
     */
    function getSuffixSum(uint256 index) external view returns (uint256) {
        return _fenwickQuery(index, uint32(getCurrentDay()));
    }

    /**
     * @dev Get claimable amount for the caller
     */
    function getMyClaimableAmount() external view returns (uint256 total) {
        for (uint256 i = 0; i < 14; i++) {
            if (unclaimedPrizes[i].winner == msg.sender) {
                total += unclaimedPrizes[i].amount;
            }
        }
    }

    /**
     * @dev Get all unclaimed prizes
     */
    function getAllUnclaimedPrizes()
        external
        view
        returns (address[14] memory winners, uint112[14] memory amounts)
    {
        for (uint256 i = 0; i < 14; i++) {
            winners[i] = unclaimedPrizes[i].winner;
            amounts[i] = unclaimedPrizes[i].amount;
        }
    }

    /**
     * @dev Start an auction for the previous day's fees
     */
    function _startAuction(uint256 feesToDistribute) internal {
        uint256 currentDay = getCurrentDay();

        // Finalize previous auction if it exists
        if (currentAuction.auctionDay != 0) {
            _finalizeAuction();
        }

        // Calculate minimum bid for the ETHERIUM amount being auctioned
        // MinBid = (ETH balance * feesToDistribute) / totalSupply
        // Round up to ensure we never sell below backing value
        // Overflow safety: balance < 2^96, feesToDistribute < 2^112, product < 2^208
        uint256 minBid = (address(this).balance *
            feesToDistribute +
            totalSupply() -
            1) / totalSupply();

        // Transfer fees from fees pool to lottery pool for auction
        _atomicUpdate(FEES_POOL, LOT_POOL, feesToDistribute);

        // Start new auction
        currentAuction = Auction({
            currentBidder: address(0),
            currentBid: 0,
            minBid: uint96(minBid),
            etheriumAmount: uint112(feesToDistribute),
            auctionDay: uint32(currentDay - 1) // Day whose fees we're auctioning
        });

        emit AuctionStarted(currentDay - 1, feesToDistribute, minBid);

        // Update last lottery day (even though it's an auction, we use same tracking)
        lastLotteryDay = uint32(currentDay);
    }

    /**
     * @dev Finalize the current auction
     */
    function _finalizeAuction() internal {
        // If no bids, roll over the fees to the next day
        if (currentAuction.currentBidder == address(0)) {
            if (currentAuction.etheriumAmount > 0) {
                // Add unclaimed auction amount back to fees pool for next day
                _atomicUpdate(
                    LOT_POOL,
                    FEES_POOL,
                    currentAuction.etheriumAmount
                );
                // Track it for the next day's distribution
                dailyFeesCollected[getCurrentDay()] += currentAuction
                    .etheriumAmount;
            }
            return;
        }

        // Convert WETH to ETH for the winning bid
        // This is safe because we control when this happens (no external call that could revert)
        WETH.withdraw(currentAuction.currentBid);

        uint256 slot = currentAuction.auctionDay % 14;

        // Check if this slot has an unclaimed prize
        UnclaimedPrize storage prize = unclaimedPrizes[slot];
        if (prize.amount > 0) {
            // Try to send to public good
            address publicGood = PUBLIC_GOODS[currentPublicGoodIndex];
            currentPublicGoodIndex = uint8(
                (currentPublicGoodIndex + 1) % PUBLIC_GOODS.length
            );

            (bool success, ) = publicGood.call{value: prize.amount}("");

            if (success) {
                _burn(LOT_POOL, prize.amount);
                emit PublicGoodsFunded(publicGood, prize.amount, prize.winner);
            } else {
                // Add to current winner's prize
                currentAuction.etheriumAmount += uint112(prize.amount);
            }
        }

        // Store new prize
        prize.winner = currentAuction.currentBidder;
        prize.amount = currentAuction.etheriumAmount;

        emit AuctionWon(
            currentAuction.currentBidder,
            currentAuction.etheriumAmount,
            currentAuction.currentBid,
            currentAuction.auctionDay
        );
    }

    /**
     * @dev Place a bid in the current auction
     * The bidder must have approved WETH that is at least 10% higher than the current bid
     * Winning bid gets the auctioned ETHERIUM tokens
     * Previous bidder gets their WETH refunded immediately
     *
     * We enforce a 10% minimum increment to make auctions more accessible to non-bot participants.
     * Since token prices rarely change by 10% in a single day, this creates a window where
     * early bidders can speculate on the value without being immediately outbid by bots
     * that might otherwise place marginally higher bids repeatedly.
     *
     * Using WETH prevents griefing attacks where malicious bidders could block refunds
     * by reverting in their receive() function.
     */
    function bid(uint256 bidAmount) external nonReentrant {
        require(currentAuction.auctionDay != 0, "No active auction");

        uint256 currentDay = getCurrentDay();

        // Check if auction is still active (same day)
        require(currentDay == lastLotteryDay, "Auction has ended");

        // Determine minimum bid required
        // Overflow safety: currentBid < 2^96, 110 < 2^7, product < 2^103 (no overflow)
        uint256 minBid = currentAuction.currentBid == 0
            ? currentAuction.minBid // Use stored minimum for first bid
            : (currentAuction.currentBid * 110) / 100; // 10% increase for subsequent bids

        require(bidAmount >= minBid, "Bid too low");

        // Transfer WETH from bidder to contract
        require(
            WETH.transferFrom(msg.sender, address(this), bidAmount),
            "WETH transfer failed"
        );

        // Store previous bidder info
        address previousBidder = currentAuction.currentBidder;
        uint256 previousBid = currentAuction.currentBid;

        // Update auction state
        currentAuction.currentBidder = msg.sender;
        currentAuction.currentBid = uint96(bidAmount);

        emit BidPlaced(msg.sender, bidAmount, currentAuction.auctionDay);

        // Refund previous bidder if exists (in WETH)
        if (previousBidder != address(0)) {
            require(
                WETH.transfer(previousBidder, previousBid),
                "WETH refund failed"
            );
            emit BidRefunded(previousBidder, previousBid);
        }
    }
}
