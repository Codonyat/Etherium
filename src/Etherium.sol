// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "./interfaces/IExternalTokens.sol";

/**
 * @title Etherium
 * @dev ERC20 token backed by ETH with daily lottery and commit-reveal randomness
 * - 1 ETH = 1 ETHERIUM (18 decimals)
 * - 1% fee on mint/burn/transfer (0.9% to lottery pool, 0.1% to randomness participants)
 * - Daily lottery for random holder
 * - Overlapping commit-reveal phases: commit for day N, reveal for day N-1
 * - Users can lock 100 PepeUSD during minting period to mint without fees
 * - Efficient winner selection using cumulative sum tree
 */
contract Etherium is ERC20, ReentrancyGuard {
    // Conversion: 1 ETH = 1 ETHERIUM (both 18 decimals)
    uint256 public constant DECIMALS = 18;
    uint256 public constant FEE_PERCENT = 100; // 1% = 100 basis points
    uint256 public constant LOTTERY_FEE_PERCENT = 90; // 0.9% = 90 basis points
    uint256 public constant RANDOMNESS_FEE_PERCENT = 10; // 0.1% = 10 basis points
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MINTING_PERIOD = 7 days;
    uint256 public constant PEPEUSD_LOCK_AMOUNT = 100 ether; // 100 PepeUSD (18 decimals)
    uint256 public constant PEPEUSD_UNLOCK_TIME = 30 days; // 1 month from deployment

    // Synthetic addresses for pools
    address public constant LOTTERY_POOL =
        0x0000000000000010770000900100000000000000;
    address public constant RANDOMNESS_POOL =
        0x00000000000000d1cE0009001000000000000000;

    uint256 public immutable deploymentTime;
    uint256 public immutable mintingEndTime;
    uint256 public maxSupplyEver; // Set after minting period based on what was minted

    // Lottery state
    uint256 public lastLotteryTime;

    // Commit-reveal state
    struct CommitReveal {
        bytes32 commitment;
        uint256 amount;
        uint256 revealedSecret;
        bool revealed;
        bool claimed;
    }

    mapping(uint256 day => mapping(address participant => CommitReveal)) public dayCommitments;
    mapping(uint256 day => uint256 seed) public dayRandomSeed;
    mapping(uint256 day => address[] participants) public dayParticipants;
    mapping(uint256 day => uint256 totalRevealed) public dayTotalRevealed;
    mapping(uint256 day => bool executed) public dayLotteryExecuted;

    // Efficient holder tracking using Fenwick tree
    mapping(uint256 index => address holder) public holderByIndex;
    mapping(address holder => uint256 index) public indexByHolder;
    mapping(uint256 index => uint256 sum) public fenwickTree;
    uint256 public holderCount;
    uint256 public totalHolderBalance;

    // Used secrets tracking to prevent reuse
    mapping(uint256 secret => bool used) public usedSecrets;

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
    event CommitmentMade(
        address indexed participant,
        uint256 day,
        bytes32 commitment,
        uint256 amount
    );
    event SecretRevealed(
        address indexed participant,
        uint256 day,
        uint256 secret
    );
    event RandomnessRewardClaimed(
        address indexed participant,
        uint256 day,
        uint256 amount
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
        lastLotteryTime = deploymentTime;
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
            maxSupplyEver = totalSupply();
        }
    }

    /**
     * @dev Mint ETHERIUM by depositing ETH (standard minting with fees)
     */
    function mint() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");

        _checkAndSetMaxSupply();

        // Apply fee for normal minting
        uint256 fee = (msg.value * FEE_PERCENT) / BASIS_POINTS;
        uint256 netEtherium = msg.value - fee;

        // After minting period: enforce max supply limit
        if (block.timestamp > mintingEndTime) {
            require(
                totalSupply() + netEtherium <= maxSupplyEver,
                "Max supply reached"
            );
        }
        // During minting period: no limit on minting

        // Mint net amount to user
        _mint(msg.sender, netEtherium);

        // Mint fees directly to pools as ETHERIUM tokens
        _distributeFees(fee);

        _updateCumulativeBalances(msg.sender, int256(netEtherium));

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

        // Mint full amount to user (no fees)
        _mint(msg.sender, netEtherium);
        _updateCumulativeBalances(msg.sender, int256(netEtherium));

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

        _checkAndSetMaxSupply();

        uint256 fee = (amount * FEE_PERCENT) / BASIS_POINTS;
        uint256 netEtherium = amount - fee;

        // User loses full amount from their balance, but only net amount burned from supply
        // We do this by burning the full amount, then minting back the fee to the pools
        _burn(msg.sender, amount);

        _distributeFees(fee);
        _updateCumulativeBalances(msg.sender, -int256(amount));

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
        // Handle minting and burning without fees (they have their own fee logic)
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Apply fees for transfers
        uint256 fee = (value * FEE_PERCENT) / BASIS_POINTS;
        uint256 netAmount = value - fee;

        // Update holder tracking BEFORE changing balances
        _updateCumulativeBalances(from, -int256(value));
        _updateCumulativeBalances(to, int256(netAmount));

        // Deduct full amount from sender
        // Update sender balance (deduct full amount)
        _burn(from, value);

        // Update recipient balance (add net amount)
        _mint(to, netAmount);

        // Add fee to pools
        _distributeFees(fee);
    }

    /**
     * @dev Distribute fees between lottery and randomness pools by minting to synthetic addresses
     */
    function _distributeFees(uint256 totalFee) internal {
        uint256 lotteryFee = (totalFee * LOTTERY_FEE_PERCENT) / FEE_PERCENT;
        uint256 randomnessFee = totalFee - lotteryFee;

        // Mint fees directly to synthetic addresses
        _mint(LOTTERY_POOL, lotteryFee);
        _mint(RANDOMNESS_POOL, randomnessFee);
    }

    /**
     * @dev Update Fenwick tree at index with delta
     */
    function _fenwickUpdate(uint256 index, int256 delta) internal {
        while (index <= holderCount) {
            if (delta > 0) {
                fenwickTree[index] += uint256(delta);
            } else {
                uint256 decrease = uint256(-delta);
                fenwickTree[index] = fenwickTree[index] > decrease
                    ? fenwickTree[index] - decrease
                    : 0;
            }
            index += index & uint256(-int256(index)); // index & -index gives lowest set bit
        }
    }

    /**
     * @dev Query sum from index 1 to index (inclusive)
     */
    function _fenwickQuery(uint256 index) internal view returns (uint256) {
        uint256 sum = 0;
        while (index > 0) {
            sum += fenwickTree[index];
            index -= index & uint256(-int256(index));
        }
        return sum;
    }

    /**
     * @dev Update holder balance in efficient data structure
     */
    function _updateCumulativeBalances(
        address account,
        int256 balanceChange
    ) internal {
        if (account.code.length > 0) return; // Skip contracts
        if (account == LOTTERY_POOL || account == RANDOMNESS_POOL) return; // Skip synthetic addresses

        uint256 currentBalance = balanceOf(account);
        uint256 currentIndex = indexByHolder[account];

        // Calculate what the new balance will be after the change
        uint256 newBalance;
        if (balanceChange > 0) {
            newBalance = currentBalance + uint256(balanceChange);
        } else {
            uint256 decrease = uint256(-balanceChange);
            newBalance = currentBalance > decrease
                ? currentBalance - decrease
                : 0;
        }

        if (newBalance > 0 && currentIndex == 0) {
            // Add new holder
            holderCount++;
            holderByIndex[holderCount] = account;
            indexByHolder[account] = holderCount;

            // Update Fenwick tree
            _fenwickUpdate(holderCount, int256(newBalance));
            totalHolderBalance += newBalance;
        } else if (newBalance == 0 && currentIndex > 0) {
            // Remove holder - use the current balance before removal

            // Update Fenwick tree before removal
            _fenwickUpdate(currentIndex, -int256(currentBalance));
            totalHolderBalance = totalHolderBalance > currentBalance
                ? totalHolderBalance - currentBalance
                : 0;

            // If not last holder, move last holder to this position
            if (currentIndex < holderCount) {
                address lastHolder = holderByIndex[holderCount];
                uint256 lastHolderBalance = balanceOf(lastHolder);

                // Update Fenwick tree: remove last holder's balance from old position
                _fenwickUpdate(holderCount, -int256(lastHolderBalance));

                // Move last holder to current position
                holderByIndex[currentIndex] = lastHolder;
                indexByHolder[lastHolder] = currentIndex;

                // Update Fenwick tree: add last holder's balance to new position
                _fenwickUpdate(currentIndex, int256(lastHolderBalance));
            }

            // Clean up removed holder
            delete holderByIndex[holderCount];
            delete indexByHolder[account];
            holderCount--;
        } else if (currentIndex > 0) {
            // Update existing holder
            // Update Fenwick tree with the difference
            _fenwickUpdate(currentIndex, balanceChange);

            if (balanceChange > 0) {
                totalHolderBalance += uint256(balanceChange);
            } else {
                uint256 decrease = uint256(-balanceChange);
                totalHolderBalance = totalHolderBalance > decrease
                    ? totalHolderBalance - decrease
                    : 0;
            }
        }
    }

    /**
     * @dev Commit phase for randomness (can commit for the current day)
     */
    function commitSecret(
        bytes32 commitment,
        uint256 etheriumAmount
    ) external nonReentrant {
        uint256 currentDayNumber = getCurrentDay();
        // Can always commit for the current day
        require(etheriumAmount > 0, "Must stake ETHERIUM");
        require(
            dayCommitments[currentDayNumber][msg.sender].commitment == 0,
            "Already committed"
        );
        require(
            balanceOf(msg.sender) >= etheriumAmount,
            "Insufficient ETHERIUM balance"
        );

        // Burn the staked ETHERIUM temporarily
        _burn(msg.sender, etheriumAmount);
        _updateCumulativeBalances(msg.sender, -int256(etheriumAmount));

        dayCommitments[currentDayNumber][msg.sender] = CommitReveal({
            commitment: commitment,
            amount: etheriumAmount,
            revealedSecret: 0,
            revealed: false,
            claimed: false
        });

        dayParticipants[currentDayNumber].push(msg.sender);

        emit CommitmentMade(
            msg.sender,
            currentDayNumber,
            commitment,
            etheriumAmount
        );
    }

    /**
     * @dev Reveal phase for randomness (can reveal for the previous day)
     */
    function revealSecret(
        uint256 secret,
        uint256 dayNumber
    ) external nonReentrant {
        uint256 currentDayNumber = getCurrentDay();
        require(
            dayNumber == currentDayNumber - 1,
            "Can only reveal for previous day"
        );
        require(currentDayNumber > 0, "Cannot reveal on first day");

        CommitReveal storage cr = dayCommitments[dayNumber][msg.sender];
        require(cr.commitment != 0, "No commitment found");
        require(!cr.revealed, "Already revealed");
        require(
            keccak256(abi.encodePacked(secret, msg.sender)) == cr.commitment,
            "Invalid secret"
        );
        require(!usedSecrets[secret], "Secret already used");

        cr.revealedSecret = secret;
        cr.revealed = true;
        usedSecrets[secret] = true;
        dayTotalRevealed[dayNumber] += cr.amount;

        // Incrementally update the random seed
        dayRandomSeed[dayNumber] ^= secret;

        emit SecretRevealed(msg.sender, dayNumber, secret);
    }

    /**
     * @dev Execute daily lottery with efficient winner selection
     */
    function executeLottery() external nonReentrant {
        uint256 currentDayNumber = getCurrentDay();
        require(
            currentDayNumber >= 2,
            "Must wait until day 2 to execute first lottery"
        );
        uint256 lotteryDay = currentDayNumber - 2; // Execute lottery for day that finished revealing
        require(!dayLotteryExecuted[lotteryDay], "Lottery already executed");

        // Get the random seed that was computed incrementally during reveals
        uint256 randomSeed = dayRandomSeed[lotteryDay];

        // Select winner if there are holders
        uint256 lotteryPoolBalance = balanceOf(LOTTERY_POOL);
        if (holderCount > 0 && lotteryPoolBalance > 0) {
            address winner = _selectWinnerEfficient(randomSeed);

            // Transfer prize from lottery pool to winner
            _burn(LOTTERY_POOL, lotteryPoolBalance);
            _mint(winner, lotteryPoolBalance);
            _updateCumulativeBalances(winner, int256(lotteryPoolBalance));
            emit LotteryWon(winner, lotteryPoolBalance, lotteryDay);
        }

        dayLotteryExecuted[lotteryDay] = true;
        lastLotteryTime = block.timestamp;
    }

    /**
     * @dev Efficient winner selection using binary search on Fenwick tree
     */
    function _selectWinnerEfficient(
        uint256 randomSeed
    ) internal view returns (address) {
        uint256 winningNumber = (randomSeed % totalHolderBalance) + 1; // 1-indexed for Fenwick tree

        // Binary search for the winner
        uint256 left = 1;
        uint256 right = holderCount;

        while (left < right) {
            uint256 mid = (left + right) / 2;
            if (_fenwickQuery(mid) < winningNumber) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        return holderByIndex[left];
    }

    /**
     * @dev Claim randomness rewards for honest participants
     */
    function claimRandomnessReward(uint256 day) external nonReentrant {
        require(dayLotteryExecuted[day], "Lottery not executed yet");

        CommitReveal storage cr = dayCommitments[day][msg.sender];
        require(cr.revealed, "Did not reveal secret");
        require(!cr.claimed, "Already claimed");

        // Calculate reward share
        uint256 randomnessPoolBalance = balanceOf(RANDOMNESS_POOL);

        // Add forfeited stakes from non-revealers
        address[] memory participants = dayParticipants[day];
        uint256 forfeitedAmount = 0;
        for (uint256 i = 0; i < participants.length; i++) {
            CommitReveal memory participantCR = dayCommitments[day][
                participants[i]
            ];
            if (!participantCR.revealed) {
                forfeitedAmount += participantCR.amount;
            }
        }

        uint256 totalReward = randomnessPoolBalance + forfeitedAmount;
        uint256 userReward = (totalReward * cr.amount) / dayTotalRevealed[day];

        cr.claimed = true;

        // Burn user's share from randomness pool
        uint256 poolShare = (randomnessPoolBalance * cr.amount) /
            dayTotalRevealed[day];
        _burn(RANDOMNESS_POOL, poolShare);

        // Return staked amount + reward
        uint256 totalPayout = cr.amount + userReward;
        _mint(msg.sender, totalPayout);
        _updateCumulativeBalances(msg.sender, int256(totalPayout));

        emit RandomnessRewardClaimed(msg.sender, day, userReward);
    }

    /**
     * @dev Get current day number
     */
    function getCurrentDay() public view returns (uint256) {
        return (block.timestamp - deploymentTime) / 24 hours;
    }

    /**
     * @dev Check if can commit for a specific day
     */
    function canCommitForDay(uint256 dayNumber) public view returns (bool) {
        uint256 currentDayNumber = getCurrentDay();
        return dayNumber == currentDayNumber;
    }

    /**
     * @dev Check if can reveal for a specific day
     */
    function canRevealForDay(uint256 dayNumber) public view returns (bool) {
        uint256 currentDayNumber = getCurrentDay();
        return currentDayNumber > 0 && dayNumber == currentDayNumber - 1;
    }

    /**
     * @dev Get holder count
     */
    function getHolderCount() external view returns (uint256) {
        return holderCount;
    }

    /**
     * @dev Get holder info by index (1-indexed for Fenwick tree)
     */
    function getHolderByIndex(
        uint256 index
    ) external view returns (address holder, uint256 balance) {
        require(index > 0 && index <= holderCount, "Index out of bounds");
        address holderAddress = holderByIndex[index];
        return (holderAddress, balanceOf(holderAddress));
    }

    /**
     * @dev Get current lottery pool balance
     */
    function currentLotteryPool() external view returns (uint256) {
        return balanceOf(LOTTERY_POOL);
    }

    /**
     * @dev Get current randomness pool balance
     */
    function currentRandomnessPool() external view returns (uint256) {
        return balanceOf(RANDOMNESS_POOL);
    }

    /**
     * @dev Check if an address is a holder
     */
    function isHolder(address account) external view returns (bool) {
        return indexByHolder[account] > 0;
    }
}
