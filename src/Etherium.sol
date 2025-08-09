// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20, IUniswapV3Factory, IUniswapV3Pool} from "./interfaces/IExternalTokens.sol";

/**
 * @title Etherium
 * @dev ERC20 token backed by ETH with daily lottery and commit-reveal randomness
 * - 1 ETH = 1,000,000 ETHERIUM (12 decimals)
 * - 1% fee on mint/burn/transfer (0.9% to lottery pool, 0.1% to randomness participants)
 * - Daily lottery for random holder
 * - Overlapping commit-reveal phases: commit for day N, reveal for day N-1
 * - PepeUSD holders can lock to mint without fee
 * - Efficient winner selection using cumulative sum tree
 */
contract Etherium is ERC20, ReentrancyGuard {
    uint256 public constant DECIMALS = 12; // Using 12 decimals ensures exact conversion between ETH (18 decimals) and ETHERIUM (12 decimals)
    uint256 public constant ETH_TO_ETHERIUM = 1e6; // 1 ETH = 1,000,000 ETHERIUM
    uint256 public constant FEE_PERCENT = 100; // 1% = 100 basis points
    uint256 public constant LOTTERY_FEE_PERCENT = 90; // 0.9% = 90 basis points
    uint256 public constant RANDOMNESS_FEE_PERCENT = 10; // 0.1% = 10 basis points
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MINTING_PERIOD = 7 days;
    uint256 public constant PEPEUSD_LOCK_PERIOD = 7 days;

    // Synthetic addresses for pools
    address public constant LOTTERY_POOL =
        0x0000000000000010770000900100000000000000;
    address public constant RANDOMNESS_POOL =
        0x00000000000000d1cE0009001000000000000000;

    uint256 public immutable deploymentTime;
    uint256 public immutable mintingEndTime;
    uint256 public maxSupplyEver; // Set after minting period based on what was minted
    uint256 public totalEthDeposited; // Track total ETH deposited during minting period

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

    mapping(uint256 => mapping(address => CommitReveal)) public dayCommitments;
    mapping(uint256 => uint256) public dayRandomSeed;
    mapping(uint256 => address[]) public dayParticipants;
    mapping(uint256 => uint256) public dayTotalRevealed;
    mapping(uint256 => bool) public dayLotteryExecuted;

    // Efficient holder tracking using Fenwick tree
    mapping(uint256 => address) public holderByIndex; // index -> holder address
    mapping(address => uint256) public indexByHolder; // holder address -> index
    mapping(uint256 => uint256) public fenwickTree; // Fenwick tree for balance sums
    uint256 public holderCount;
    uint256 public totalHolderBalance;

    // Used secrets tracking to prevent reuse
    mapping(uint256 => bool) public usedSecrets;

    // PepeUSD integration
    IERC20 public constant PEPEUSD =
        IERC20(0xed7fd16423Bc19b9143313ac5E4B7F731D714e97);
    IUniswapV3Factory public constant UNISWAP_V3_FACTORY =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    struct PepeUSDLock {
        uint256 amount;
        uint256 unlockTime;
        uint256 etheriumMinted;
    }

    mapping(address => PepeUSDLock) public pepeUSDLocks;

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
     * @dev Mint ETHERIUM by depositing ETH
     */
    function mint() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");

        uint256 etheriumToMint = (msg.value *
            ETH_TO_ETHERIUM *
            10 ** DECIMALS) / 1e18;
        uint256 fee = (etheriumToMint * FEE_PERCENT) / BASIS_POINTS;
        uint256 netEtherium = etheriumToMint - fee;

        if (block.timestamp <= mintingEndTime) {
            // During minting period: no limit, mint full amount including fees
            totalEthDeposited += msg.value; // Track total ETH deposited
        } else {
            // After minting period: can only mint up to maxSupplyEver
            if (maxSupplyEver == 0) {
                // Set max supply based on total ETH deposited during minting period
                maxSupplyEver =
                    (totalEthDeposited * ETH_TO_ETHERIUM * 10 ** DECIMALS) /
                    1e18;
            }

            require(
                totalSupply() + netEtherium <= maxSupplyEver,
                "Max supply reached"
            );
        }

        // Mint net amount to user
        _mint(msg.sender, netEtherium);

        // Mint fees directly to pools as ETHERIUM tokens
        _distributeFees(fee);

        _updateCumulativeBalances(msg.sender, int256(netEtherium));

        emit Minted(msg.sender, msg.value, netEtherium, fee);
    }

    /**
     * @dev Lock PepeUSD to mint ETHERIUM without fees
     */
    function lockPepeUSDAndMint(uint256 pepeAmount) external nonReentrant {
        require(pepeAmount > 0, "Amount must be greater than 0");
        require(
            pepeUSDLocks[msg.sender].amount == 0,
            "Already have locked PepeUSD"
        );

        // Transfer PepeUSD from user
        require(
            PEPEUSD.transferFrom(msg.sender, address(this), pepeAmount),
            "PepeUSD transfer failed"
        );

        // Get PepeUSD value in ETH using TWAP
        uint256 ethValue = getPepeUSDValueInETH(pepeAmount);
        uint256 etheriumToMint = (ethValue * ETH_TO_ETHERIUM * 10 ** DECIMALS) /
            1e18;

        // Store lock info
        pepeUSDLocks[msg.sender] = PepeUSDLock({
            amount: pepeAmount,
            unlockTime: block.timestamp + PEPEUSD_LOCK_PERIOD,
            etheriumMinted: etheriumToMint
        });

        // Mint without fees
        _mint(msg.sender, etheriumToMint);
        _updateCumulativeBalances(msg.sender, int256(etheriumToMint));

        emit PepeUSDLocked(
            msg.sender,
            pepeAmount,
            etheriumToMint,
            block.timestamp + PEPEUSD_LOCK_PERIOD
        );
    }

    /**
     * @dev Unlock PepeUSD after lock period
     */
    function unlockPepeUSD() external nonReentrant {
        PepeUSDLock memory lock = pepeUSDLocks[msg.sender];
        require(lock.amount > 0, "No locked PepeUSD");
        require(block.timestamp >= lock.unlockTime, "Still in lock period");

        // Clear lock
        delete pepeUSDLocks[msg.sender];

        // Return PepeUSD
        require(
            PEPEUSD.transfer(msg.sender, lock.amount),
            "PepeUSD transfer failed"
        );

        emit PepeUSDUnlocked(msg.sender, lock.amount);
    }

    /**
     * @dev Get PepeUSD value in ETH using 30-minute TWAP from Uniswap V3
     */
    function getPepeUSDValueInETH(
        uint256 pepeAmount
    ) public view returns (uint256) {
        // WETH address on mainnet
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        // Get PepeUSD/WETH pool with 1% fee tier
        address pepeWethPool = UNISWAP_V3_FACTORY.getPool(
            address(PEPEUSD),
            WETH,
            10_000
        ); // 1% fee tier
        require(pepeWethPool != address(0), "PepeUSD/WETH pool not found");

        // Get pool interface to read price
        IUniswapV3Pool pool = IUniswapV3Pool(pepeWethPool);

        // Get 30-minute TWAP
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 1800; // 30 minutes ago
        secondsAgos[1] = 0;    // current

        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
        
        // Calculate average tick over the period
        int56 tickCumulativeDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 arithmeticMeanTick = int24(tickCumulativeDelta / 1800);
        
        // Calculate sqrt price from tick
        // sqrtPriceX96 = sqrt(1.0001^tick) * 2^96
        uint160 sqrtPriceX96 = getSqrtPriceFromTick(arithmeticMeanTick);

        // Determine token ordering
        address token0 = pool.token0();
        uint256 ethValue;

        if (token0 == address(PEPEUSD)) {
            // Price is WETH per PEPEUSD
            // ethValue = pepeAmount * price
            ethValue =
                (pepeAmount * uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) /
                (1 << 192);
        } else {
            // Price is PEPEUSD per WETH (inverted)
            // ethValue = pepeAmount / price
            ethValue =
                (pepeAmount * (1 << 192)) /
                (uint256(sqrtPriceX96) * uint256(sqrtPriceX96));
        }

        return ethValue;
    }
    
    /**
     * @dev Convert tick to sqrt price
     * Formula: sqrtPriceX96 = sqrt(1.0001^tick) * 2^96
     */
    function getSqrtPriceFromTick(int24 tick) internal pure returns (uint160) {
        uint256 absTick = tick < 0 ? uint256(uint24(-tick)) : uint256(uint24(tick));
        
        // Calculate sqrt(1.0001^tick) using bit manipulation
        // Based on Uniswap V3 math
        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        // Shift to get the final result
        return uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    /**
     * @dev Redeem ETHERIUM for ETH
     */
    function redeem(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        uint256 fee = (amount * FEE_PERCENT) / BASIS_POINTS;
        uint256 netEtherium = amount - fee;
        uint256 ethToReturn = (netEtherium * 1e18) /
            (ETH_TO_ETHERIUM * 10 ** DECIMALS);

        // User loses full amount from their balance, but only net amount burned from supply
        // We do this by burning the full amount, then minting back the fee
        _burn(msg.sender, amount);
        _mint(address(this), fee); // Mint fee back to contract

        _distributeFees(fee);
        _updateCumulativeBalances(msg.sender, -int256(amount));

        (bool success, ) = msg.sender.call{value: ethToReturn}("");
        require(success, "ETH transfer failed");

        emit Redeemed(msg.sender, amount, ethToReturn, fee);
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

        // Deduct full amount from sender
        // Update sender balance (deduct full amount)
        _burn(from, value);

        // Update recipient balance (add net amount)
        _mint(to, netAmount);

        // Add fee to pools
        _distributeFees(fee);

        // Update holder tracking
        _updateCumulativeBalances(from, -int256(value));
        _updateCumulativeBalances(to, int256(netAmount));
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
                fenwickTree[index] -= uint256(-delta);
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

        uint256 newBalance = balanceOf(account);
        uint256 currentIndex = indexByHolder[account];

        if (newBalance > 0 && currentIndex == 0) {
            // Add new holder
            holderCount++;
            holderByIndex[holderCount] = account;
            indexByHolder[account] = holderCount;

            // Update Fenwick tree
            _fenwickUpdate(holderCount, int256(newBalance));
            totalHolderBalance += newBalance;
        } else if (newBalance == 0 && currentIndex > 0) {
            // Remove holder
            uint256 oldBalance = balanceOf(account);

            // Update Fenwick tree before removal
            _fenwickUpdate(currentIndex, -int256(oldBalance));
            totalHolderBalance -= oldBalance;

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
                totalHolderBalance -= uint256(-balanceChange);
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
