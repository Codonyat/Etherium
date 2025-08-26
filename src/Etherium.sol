// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "./interfaces/IExternalTokens.sol";

/**
 * @title Etherium
 * @dev ERC20 token backed by ETH with daily lottery using prevrandao
 * - 1 ETH = 1 ETHERIUM (18 decimals)
 * - 1% fee on mint/burn/transfer (100% to lottery pool)
 * - Daily lottery for random holder using prevrandao
 * - Users can lock 100 PepeUSD during minting period to mint without fees
 * - Efficient winner selection using cumulative sum tree
 * - Uses transient storage for reentrancy guard (EIP-1153) for gas efficiency
 */
contract Etherium is ERC20, ReentrancyGuardTransient {
    // Conversion: 1 ETH = 1 ETHERIUM (both 18 decimals)
    uint256 public constant DECIMALS = 18;
    uint256 public constant FEE_PERCENT = 100; // 1% = 100 basis points
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MINTING_PERIOD = 7 days;
    uint256 public constant PEPEUSD_LOCK_AMOUNT = 100 ether; // 100 PepeUSD (18 decimals)
    uint256 public constant PEPEUSD_UNLOCK_TIME = 30 days; // 1 month from deployment

    // Synthetic address for lottery pool
    address public constant LOTTERY_POOL =
        0x000000000000107700000Add2E55000000000000;

    uint256 public immutable deploymentTime;
    uint256 public immutable mintingEndTime;

    // Packed storage slot: 96 + 32 + 8 = 136 bits (fits in one 256-bit slot)
    uint96 public maxSupplyEver; // Set after minting period (max ~79 billion ETH with 18 decimals)
    uint32 public lastLotteryDay; // Day counter (sufficient for ~11.7 million years)
    uint8 public currentPublicGoodIndex; // Index in PUBLIC_GOODS array (max 255 addresses)

    uint256 public constant TIME_GAP = 1 minutes; // Must be 1 minute into new day before lottery can execute

    // Cyclical array for unclaimed prizes (7 slots)
    // Packed into single storage slot: 160 + 96 = 256 bits
    struct UnclaimedPrize {
        address winner; // 160 bits
        uint96 amount; // 96 bits (max ~79 million ETH)
    }
    UnclaimedPrize[7] public unclaimedPrizes;

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
        uint96 olderValue; // Previous value before last update (96 bits)
        uint96 latestValue; // Most recent value (96 bits)
        uint32 lastUpdatedDay; // Day when latestValue was set (32 bits)
        // Total: 224 bits (fits in 1 storage slot)
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
            maxSupplyEver = uint96(totalSupply());
        }
    }

    /**
     * @dev Reject direct ETH transfers
     */
    receive() external payable {
        revert("Direct ETH transfers not allowed. Use mint() instead");
    }

    /**
     * @dev Mint ETHERIUM by depositing ETH (standard minting with fees)
     */
    function mint() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");

        // Try to execute pending lottery before changing state
        _tryExecuteLottery();

        _checkAndSetMaxSupply();

        // Apply fee for normal minting
        uint256 fee = (msg.value * FEE_PERCENT) / BASIS_POINTS;
        uint256 netEtherium = msg.value - fee;

        // Get balance before minting
        uint256 balanceBefore = balanceOf(msg.sender);

        if (block.timestamp <= mintingEndTime) {
            // During minting period: mint net amount to user, mint fees to pool
            _mint(msg.sender, netEtherium);
            if (fee > 0) {
                _mint(LOTTERY_POOL, fee);
            }
        } else {
            // After minting period: enforce max supply and transfer fees
            require(
                totalSupply() + msg.value <= maxSupplyEver,
                "Max supply reached"
            );
            // Mint full amount to user, then transfer fees
            _mint(msg.sender, msg.value);
            if (fee > 0) {
                super._update(msg.sender, LOTTERY_POOL, fee);
            }
        }

        // Get balance after minting and fee transfer
        uint256 balanceAfter = balanceOf(msg.sender);

        _updateCumulativeBalancesWithExplicitBalances(
            msg.sender,
            balanceBefore,
            balanceAfter
        );

        emit Minted(msg.sender, msg.value, netEtherium, fee);
    }

    /**
     * @dev Mint ETHERIUM fee-free by locking 100 PepeUSD
     */
    function mintFeeFree() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");
        require(
            block.timestamp <= mintingEndTime,
            "Fee-free minting only during minting period"
        );

        // Try to execute pending lottery before changing state
        _tryExecuteLottery();

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

        // Mint without fees
        uint256 netEtherium = msg.value;

        // After minting period: enforce max supply limit
        if (block.timestamp > mintingEndTime) {
            require(
                totalSupply() + netEtherium <= maxSupplyEver,
                "Max supply reached"
            );
        }

        // Get balance before minting
        uint256 balanceBefore = balanceOf(msg.sender);

        // Mint full amount to user (no fees)
        _mint(msg.sender, netEtherium);

        // Get balance after minting
        uint256 balanceAfter = balanceOf(msg.sender);

        _updateCumulativeBalancesWithExplicitBalances(
            msg.sender,
            balanceBefore,
            balanceAfter
        );

        emit PepeUSDLocked(
            msg.sender,
            PEPEUSD_LOCK_AMOUNT,
            netEtherium,
            deploymentTime + PEPEUSD_UNLOCK_TIME
        );

        emit Minted(msg.sender, msg.value, netEtherium, 0);
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

        // Try to execute pending lottery before changing state
        _tryExecuteLottery();

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
     */
    function redeem(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Try to execute pending lottery before changing state
        _tryExecuteLottery();

        _checkAndSetMaxSupply();

        uint256 fee = (amount * FEE_PERCENT) / BASIS_POINTS;
        uint256 netEtherium = amount - fee;

        // Get balance before redeeming
        uint256 balanceBefore = balanceOf(msg.sender);

        // First transfer fees to lottery pool
        if (fee > 0) {
            super._update(msg.sender, LOTTERY_POOL, fee);
        }

        // Then burn the remainder from user
        _burn(msg.sender, netEtherium);

        // Get balance after burning
        uint256 balanceAfter = balanceOf(msg.sender);

        _updateCumulativeBalancesWithExplicitBalances(
            msg.sender,
            balanceBefore,
            balanceAfter
        );

        // Transfer ETH back to user (1:1 conversion)
        (bool success, ) = msg.sender.call{value: netEtherium}("");
        require(success, "ETH transfer failed");

        emit Redeemed(msg.sender, amount, netEtherium, fee);
    }

    /**
     * @dev Override update to apply fees on transfers
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // Redirect external transfers to this contract to LOTTERY_POOL
        if (to == address(this)) {
            super._update(from, LOTTERY_POOL, value);
            return;
        }

        // Skip fee logic for minting and burning (they handle fees separately)
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Try to execute pending lottery before transfers
        _tryExecuteLottery();

        // Apply fees for transfers
        uint256 fee = (value * FEE_PERCENT) / BASIS_POINTS;
        uint256 netAmount = value - fee;

        // Get balances BEFORE the transfer
        uint256 fromBalanceBefore = balanceOf(from);
        uint256 toBalanceBefore = balanceOf(to);

        // Transfer net amount to recipient
        super._update(from, to, netAmount);

        // Transfer fees to lottery pool
        if (fee > 0) {
            super._update(from, LOTTERY_POOL, fee);
        }

        // Get balances AFTER the transfer
        uint256 fromBalanceAfter = balanceOf(from);
        uint256 toBalanceAfter = balanceOf(to);

        // Update holder tracking with actual balance changes
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
     * @dev Update a DualState with a new value, preserving history
     */
    function _updateDualState(
        DualState storage state,
        uint96 newValue,
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
    ) internal pure returns (uint96) {
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
            uint96 currentSum = treeNode.latestValue;
            uint96 newSum;

            if (delta > 0) {
                newSum = currentSum + uint96(uint256(delta));
            } else {
                uint96 decrease = uint96(uint256(-delta));
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
        uint96 maxIndex = _getDualStateValue(holderCount, targetDay);

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
        if (account.code.length > 0) return; // Skip contracts
        if (account == LOTTERY_POOL) return; // Skip synthetic address

        uint32 currentDay = uint32(getCurrentDay());
        uint256 currentIndex = indexByHolder[account].latestValue;

        int256 balanceChange = int256(balanceAfter) - int256(balanceBefore);

        if (balanceAfter > 0 && currentIndex == 0) {
            // Add new holder
            uint96 newCount = holderCount.latestValue + 1;
            uint96 newTotalBalance = totalHolderBalance.latestValue +
                uint96(balanceAfter);

            _updateDualState(holderCount, newCount, currentDay);
            _updateDualAddress(holderByIndex[newCount], account, currentDay);
            _updateDualState(
                indexByHolder[account],
                uint96(newCount),
                currentDay
            );

            // Update Fenwick tree
            _fenwickUpdate(newCount, int256(balanceAfter));

            _updateDualState(totalHolderBalance, newTotalBalance, currentDay);
        } else if (balanceAfter == 0 && currentIndex > 0) {
            // Remove holder - use the balance before removal
            uint96 currentTotalBalance = totalHolderBalance.latestValue;

            // Update Fenwick tree before removal
            _fenwickUpdate(currentIndex, -int256(balanceBefore));

            uint96 newTotalBalance = currentTotalBalance -
                uint96(balanceBefore);

            _updateDualState(totalHolderBalance, newTotalBalance, currentDay);

            // Compact holders by moving the last holder to the removed position
            uint96 currentCount = holderCount.latestValue;

            if (currentIndex < currentCount) {
                address lastHolder = holderByIndex[currentCount].latestValue;

                // Get the last holder's balance from the Fenwick tree at their position
                // This is their balance BEFORE any concurrent updates
                uint96 lastHolderFenwickBalance = fenwickTree[currentCount]
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
                    uint96(currentIndex),
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

            uint96 currentTotalBalance = totalHolderBalance.latestValue;
            uint96 newTotalBalance;

            if (balanceChange > 0) {
                newTotalBalance =
                    currentTotalBalance +
                    uint96(uint256(balanceChange));
            } else {
                uint96 decrease = uint96(uint256(-balanceChange));
                newTotalBalance = currentTotalBalance > decrease
                    ? currentTotalBalance - decrease
                    : 0;
            }

            _updateDualState(totalHolderBalance, newTotalBalance, currentDay);
        }
    }

    /**
     * @dev Internal function to try executing pending lottery
     * Called before state-changing operations to ensure winners are determined first
     */
    function _tryExecuteLottery() internal {
        uint256 currentDay = getCurrentDay();

        // No lottery on day 0
        if (currentDay == 0) return;

        // Check if there's a pending lottery (pool has funds and day changed)
        uint256 poolBalance = balanceOf(LOTTERY_POOL);
        if (poolBalance == 0) return;

        // If day changed since last lottery, we have a pending lottery
        if (currentDay <= lastLotteryDay) return;

        // Ensure we're at least 1 minute into the new day to prevent manipulation
        uint256 timeIntoDay = (block.timestamp - deploymentTime) % 24 hours;
        if (timeIntoDay < TIME_GAP) return;

        _executeLotteryInternal();
    }

    /**
     * @dev Internal lottery execution logic
     */
    function _executeLotteryInternal() internal {
        uint256 randomSeed = block.prevrandao;
        uint256 currentDay = getCurrentDay();

        // Use snapshot from when the lottery became pending (lastLotteryDay)
        uint32 snapshotDay = uint32(lastLotteryDay);

        // Get holder count and total balance from the snapshot day
        uint96 snapshotHolderCount = _getDualStateValue(
            holderCount,
            snapshotDay
        );
        uint96 snapshotTotalBalance = _getDualStateValue(
            totalHolderBalance,
            snapshotDay
        );

        // Select winner if there are holders
        uint256 lotteryPoolBalance = balanceOf(LOTTERY_POOL);
        if (
            snapshotHolderCount > 0 &&
            snapshotTotalBalance > 0 &&
            lotteryPoolBalance > 0
        ) {
            address winner = _selectWinnerEfficient(snapshotDay, randomSeed);

            uint256 lotteryDay = currentDay - 1;
            uint256 slot = lotteryDay % 7; // Determine which slot to use

            // Transfer prize from lottery pool to contract for holding
            super._update(LOTTERY_POOL, address(this), lotteryPoolBalance);

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
                    // ETH transfer successful, now burn the ETHERIUM tokens
                    _burn(address(this), prize.amount);
                    emit PublicGoodsFunded(
                        publicGood,
                        prize.amount,
                        prize.winner
                    );
                } else {
                    // ETH transfer failed, add unclaimed prize to current winner's prize
                    // The current winner will get both prizes when they claim
                    lotteryPoolBalance += prize.amount;
                    // Note: We still cycle to the next public good for fairness
                }
            }

            // Store new prize in the slot (overwriting any previous data)
            prize.winner = winner;
            prize.amount = uint96(lotteryPoolBalance); // Safe cast, lottery pool won't exceed 79B ETH

            emit LotteryWon(winner, lotteryPoolBalance, lotteryDay);
        }

        // Update last lottery day
        lastLotteryDay = uint32(currentDay);
    }

    /**
     * @dev Public function to execute daily lottery
     */
    function executeLottery() external nonReentrant {
        uint256 currentDay = getCurrentDay();
        require(currentDay > 0, "Must wait until day 1 for first lottery");

        uint256 poolBalance = balanceOf(LOTTERY_POOL);
        require(poolBalance > 0, "No pending lottery (empty pool)");

        require(currentDay > lastLotteryDay, "No pending lottery (same day)");

        // Ensure we're at least 1 minute into the new day
        uint256 timeIntoDay = (block.timestamp - deploymentTime) % 24 hours;
        require(
            timeIntoDay >= TIME_GAP,
            "Must wait 1 minute into new day before executing lottery"
        );

        _executeLotteryInternal();
    }

    /**
     * @dev Claim unclaimed prizes for the caller
     */
    function claim() external nonReentrant {
        uint256 totalClaimed = 0;

        // Check all 7 slots for prizes belonging to caller
        for (uint256 i = 0; i < 7; i++) {
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

        // Transfer all claimed prizes at once
        uint256 balanceBefore = balanceOf(msg.sender);
        super._update(address(this), msg.sender, totalClaimed);
        uint256 balanceAfter = balanceOf(msg.sender);

        _updateCumulativeBalancesWithExplicitBalances(
            msg.sender,
            balanceBefore,
            balanceAfter
        );
    }

    /**
     * @dev Efficient winner selection using binary search on Fenwick tree (suffix sum version)
     */
    function _selectWinnerEfficient(
        uint32 lotteryDay,
        uint256 randomSeed
    ) internal view returns (address) {
        uint96 snapshotTotalBalance = _getDualStateValue(
            totalHolderBalance,
            lotteryDay
        );
        uint96 snapshotHolderCount = _getDualStateValue(
            holderCount,
            lotteryDay
        );

        // Random number from 1 to total balance
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
     */
    function getCurrentDay() public view returns (uint256) {
        return (block.timestamp - deploymentTime) / 24 hours;
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
        return balanceOf(LOTTERY_POOL);
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
        for (uint256 i = 0; i < 7; i++) {
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
        returns (address[7] memory winners, uint96[7] memory amounts)
    {
        for (uint256 i = 0; i < 7; i++) {
            winners[i] = unclaimedPrizes[i].winner;
            amounts[i] = unclaimedPrizes[i].amount;
        }
    }
}
