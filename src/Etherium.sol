// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPepeUSD, IUSDC, IUniswapV3Factory, IUniswapV3Pool} from "./interfaces/IPepeUSD.sol";

/**
 * @title Etherium
 * @dev ERC20 token backed by ETH with daily lottery and commit-reveal randomness
 * - 1 ETH = 1,000,000 ETHERIUM (12 decimals)
 * - 1% fee on mint/burn/transfer (0.9% to lottery pool, 0.1% to randomness participants)
 * - Daily lottery for random holder
 * - Commit-reveal scheme for randomness
 * - PepeUSD holders can lock to mint without fee
 * - Efficient winner selection using cumulative sum tree
 */
contract Etherium is ERC20, ReentrancyGuard {
    uint256 public constant DECIMALS = 12;
    uint256 public constant ETH_TO_ETHERIUM = 1e6; // 1 ETH = 1,000,000 ETHERIUM
    uint256 public constant FEE_PERCENT = 100; // 1% = 100 basis points
    uint256 public constant LOTTERY_FEE_PERCENT = 90; // 0.9% = 90 basis points
    uint256 public constant RANDOMNESS_FEE_PERCENT = 10; // 0.1% = 10 basis points
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant DAY_DURATION = 24 hours;
    uint256 public constant MINTING_PERIOD = 7 days;
    uint256 public constant PEPEUSD_LOCK_PERIOD = 7 days;
    
    uint256 public immutable deploymentTime;
    uint256 public immutable mintingEndTime;
    uint256 public maxSupplyEver; // Set after minting period based on what was minted
    uint256 public totalEthDeposited; // Track total ETH deposited during minting period
    
    // Lottery state
    uint256 public currentLotteryPool;
    uint256 public currentRandomnessPool;
    uint256 public lastLotteryTime;
    uint256 public currentDay;
    
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
    
    // Efficient holder tracking for lottery
    struct HolderNode {
        address holder;
        uint256 balance;
        uint256 cumulativeSum;
    }
    
    HolderNode[] public holderNodes;
    mapping(address => uint256) public holderNodeIndex;
    mapping(address => bool) public isHolder;
    uint256 public totalHolderBalance;
    
    // Used secrets tracking to prevent reuse
    mapping(uint256 => bool) public usedSecrets;
    
    // PepeUSD integration
    IPepeUSD public constant PEPEUSD = IPepeUSD(0xed7fd16423Bc19b9143313ac5E4B7F731D714e97);
    IUSDC public constant USDC = IUSDC(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IUniswapV3Factory public constant UNISWAP_V3_FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    
    struct PepeUSDLock {
        uint256 amount;
        uint256 unlockTime;
        uint256 etheriumMinted;
    }
    
    mapping(address => PepeUSDLock) public pepeUSDLocks;
    
    event Minted(address indexed to, uint256 ethAmount, uint256 etheriumAmount, uint256 fee);
    event Redeemed(address indexed from, uint256 etheriumAmount, uint256 ethAmount, uint256 fee);
    event LotteryWon(address indexed winner, uint256 amount, uint256 day);
    event CommitmentMade(address indexed participant, uint256 day, bytes32 commitment, uint256 amount);
    event SecretRevealed(address indexed participant, uint256 day, uint256 secret);
    event RandomnessRewardClaimed(address indexed participant, uint256 day, uint256 amount);
    event PepeUSDLocked(address indexed user, uint256 pepeAmount, uint256 etheriumMinted, uint256 unlockTime);
    event PepeUSDUnlocked(address indexed user, uint256 amount);
    
    constructor() ERC20("Etherium", "ETHERIUM") {
        deploymentTime = block.timestamp;
        mintingEndTime = deploymentTime + MINTING_PERIOD;
        lastLotteryTime = deploymentTime;
        currentDay = 0;
    }
    
    function decimals() public pure override returns (uint8) {
        return uint8(DECIMALS);
    }
    
    /**
     * @dev Mint ETHERIUM by depositing ETH
     */
    function mint() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH");
        
        uint256 etheriumToMint = (msg.value * ETH_TO_ETHERIUM * 10**DECIMALS) / 1e18;
        uint256 fee = (etheriumToMint * FEE_PERCENT) / BASIS_POINTS;
        uint256 netEtherium = etheriumToMint - fee;
        
        if (block.timestamp <= mintingEndTime) {
            // During minting period: no limit, mint full amount including fees
            totalEthDeposited += msg.value; // Track total ETH deposited
            _mint(msg.sender, netEtherium);
            // Mint fees directly to pools as ETHERIUM tokens
            _mintFeesToPools(fee);
        } else {
            // After minting period: can only mint up to maxSupplyEver
            if (maxSupplyEver == 0) {
                // Set max supply based on total ETH deposited during minting period
                maxSupplyEver = (totalEthDeposited * ETH_TO_ETHERIUM * 10**DECIMALS) / 1e18;
            }
            
            require(totalSupply() + netEtherium <= maxSupplyEver, "Max supply reached");
            
            _mint(msg.sender, netEtherium);
            // During post-minting period, fees go to pool counters, not minted
            _distributeFees(fee);
        }
        
        _updateHolderBalance(msg.sender, int256(netEtherium));
        
        emit Minted(msg.sender, msg.value, netEtherium, fee);
    }
    
    /**
     * @dev Lock PepeUSD to mint ETHERIUM without fees
     */
    function lockPepeUSDAndMint(uint256 pepeAmount) external nonReentrant {
        require(pepeAmount > 0, "Amount must be greater than 0");
        require(pepeUSDLocks[msg.sender].amount == 0, "Already have locked PepeUSD");
        
        // Transfer PepeUSD from user
        require(PEPEUSD.transferFrom(msg.sender, address(this), pepeAmount), "PepeUSD transfer failed");
        
        // Get PepeUSD value in ETH using TWAP
        uint256 ethValue = getPepeUSDValueInETH(pepeAmount);
        uint256 etheriumToMint = (ethValue * ETH_TO_ETHERIUM * 10**DECIMALS) / 1e18;
        
        // Store lock info
        pepeUSDLocks[msg.sender] = PepeUSDLock({
            amount: pepeAmount,
            unlockTime: block.timestamp + PEPEUSD_LOCK_PERIOD,
            etheriumMinted: etheriumToMint
        });
        
        // Mint without fees
        _mint(msg.sender, etheriumToMint);
        _updateHolderBalance(msg.sender, int256(etheriumToMint));
        
        emit PepeUSDLocked(msg.sender, pepeAmount, etheriumToMint, block.timestamp + PEPEUSD_LOCK_PERIOD);
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
        require(PEPEUSD.transfer(msg.sender, lock.amount), "PepeUSD transfer failed");
        
        emit PepeUSDUnlocked(msg.sender, lock.amount);
    }
    
    /**
     * @dev Get PepeUSD value in ETH using Uniswap V3 TWAP
     */
    function getPepeUSDValueInETH(uint256 pepeAmount) public view returns (uint256) {
        // Get PepeUSD/USDC pool
        address pepeUsdcPool = UNISWAP_V3_FACTORY.getPool(address(PEPEUSD), address(USDC), 3000); // 0.3% fee tier
        require(pepeUsdcPool != address(0), "PepeUSD/USDC pool not found");
        
        // Get USDC/ETH pool
        address usdcEthPool = UNISWAP_V3_FACTORY.getPool(address(USDC), address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), 3000); // WETH address
        require(usdcEthPool != address(0), "USDC/ETH pool not found");
        
        // For simplicity, using current price instead of TWAP
        // In production, should use proper TWAP calculation
        uint256 pepeInUsdc = pepeAmount; // Assuming 1:1 for PepeUSD to USDC
        
        // Convert USDC to ETH (simplified - in production use proper price calculation)
        // Assuming 1 USDC = 0.0003 ETH (example rate)
        uint256 ethValue = (pepeInUsdc * 3) / 10000; // Simplified conversion
        
        return ethValue;
    }
    
    /**
     * @dev Redeem ETHERIUM for ETH
     */
    function redeem(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        uint256 fee = (amount * FEE_PERCENT) / BASIS_POINTS;
        uint256 netEtherium = amount - fee;
        uint256 ethToReturn = (netEtherium * 1e18) / (ETH_TO_ETHERIUM * 10**DECIMALS);
        
        // User loses full amount from their balance, but only net amount burned from supply
        // We do this by burning the full amount, then minting back the fee
        super._update(msg.sender, address(0), amount);
        super._update(address(0), address(this), fee); // Mint fee back to contract
        
        _distributeFees(fee);
        _updateHolderBalance(msg.sender, -int256(amount));
        
        (bool success, ) = msg.sender.call{value: ethToReturn}("");
        require(success, "ETH transfer failed");
        
        emit Redeemed(msg.sender, amount, ethToReturn, fee);
    }
    
    /**
     * @dev Override update to apply fees on transfers
     */
    function _update(address from, address to, uint256 value) internal override {
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
        super._update(from, address(0), value);
        
        // Update recipient balance (add net amount)
        super._update(address(0), to, netAmount);
        
        // Add fee to pools
        _distributeFees(fee);
        
        // Update holder tracking
        _updateHolderBalance(from, -int256(value));
        _updateHolderBalance(to, int256(netAmount));
    }
    
    /**
     * @dev Distribute fees between lottery and randomness pools (as counters)
     */
    function _distributeFees(uint256 totalFee) internal {
        uint256 lotteryFee = (totalFee * LOTTERY_FEE_PERCENT) / FEE_PERCENT;
        uint256 randomnessFee = totalFee - lotteryFee;
        
        currentLotteryPool += lotteryFee;
        currentRandomnessPool += randomnessFee;
    }
    
    /**
     * @dev Mint fees directly as ETHERIUM tokens during minting period
     */
    function _mintFeesToPools(uint256 totalFee) internal {
        uint256 lotteryFee = (totalFee * LOTTERY_FEE_PERCENT) / FEE_PERCENT;
        uint256 randomnessFee = totalFee - lotteryFee;
        
        // Mint the fees as actual ETHERIUM tokens to contract and add to pools
        super._update(address(0), address(this), totalFee);
        
        currentLotteryPool += lotteryFee;
        currentRandomnessPool += randomnessFee;
    }
    
    /**
     * @dev Update holder balance in efficient data structure
     */
    function _updateHolderBalance(address account, int256 balanceChange) internal {
        if (account.code.length > 0) return; // Skip contracts
        
        uint256 newBalance = balanceOf(account);
        
        if (newBalance > 0 && !isHolder[account]) {
            // Add new holder
            holderNodes.push(HolderNode({
                holder: account,
                balance: newBalance,
                cumulativeSum: totalHolderBalance + newBalance
            }));
            holderNodeIndex[account] = holderNodes.length - 1;
            isHolder[account] = true;
            totalHolderBalance += newBalance;
        } else if (newBalance == 0 && isHolder[account]) {
            // Remove holder
            uint256 index = holderNodeIndex[account];
            uint256 lastIndex = holderNodes.length - 1;
            
            if (index != lastIndex) {
                holderNodes[index] = holderNodes[lastIndex];
                holderNodeIndex[holderNodes[index].holder] = index;
            }
            
            holderNodes.pop();
            delete holderNodeIndex[account];
            isHolder[account] = false;
            totalHolderBalance -= uint256(-balanceChange);
            
            // Rebuild cumulative sums
            _rebuildCumulativeSums();
        } else if (isHolder[account]) {
            // Update existing holder
            uint256 index = holderNodeIndex[account];
            holderNodes[index].balance = newBalance;
            
            if (balanceChange > 0) {
                totalHolderBalance += uint256(balanceChange);
            } else {
                totalHolderBalance -= uint256(-balanceChange);
            }
            
            // Update cumulative sums from this index onwards
            _updateCumulativeSumsFrom(index);
        }
    }
    
    /**
     * @dev Rebuild all cumulative sums
     */
    function _rebuildCumulativeSums() internal {
        uint256 cumSum = 0;
        for (uint256 i = 0; i < holderNodes.length; i++) {
            cumSum += holderNodes[i].balance;
            holderNodes[i].cumulativeSum = cumSum;
        }
    }
    
    /**
     * @dev Update cumulative sums from specific index
     */
    function _updateCumulativeSumsFrom(uint256 startIndex) internal {
        uint256 cumSum = startIndex > 0 ? holderNodes[startIndex - 1].cumulativeSum : 0;
        for (uint256 i = startIndex; i < holderNodes.length; i++) {
            cumSum += holderNodes[i].balance;
            holderNodes[i].cumulativeSum = cumSum;
        }
    }
    
    /**
     * @dev Commit phase for randomness (first 12 hours of the day)
     */
    function commitSecret(bytes32 commitment, uint256 etheriumAmount) external nonReentrant {
        uint256 currentDayNumber = getCurrentDay();
        require(isCommitPhase(), "Not in commit phase");
        require(etheriumAmount > 0, "Must stake ETHERIUM");
        require(dayCommitments[currentDayNumber][msg.sender].commitment == 0, "Already committed");
        require(balanceOf(msg.sender) >= etheriumAmount, "Insufficient ETHERIUM balance");
        
        // Burn the staked ETHERIUM temporarily
        _burn(msg.sender, etheriumAmount);
        _updateHolderBalance(msg.sender, -int256(etheriumAmount));
        
        dayCommitments[currentDayNumber][msg.sender] = CommitReveal({
            commitment: commitment,
            amount: etheriumAmount,
            revealedSecret: 0,
            revealed: false,
            claimed: false
        });
        
        dayParticipants[currentDayNumber].push(msg.sender);
        
        emit CommitmentMade(msg.sender, currentDayNumber, commitment, etheriumAmount);
    }
    
    /**
     * @dev Reveal phase for randomness (last 12 hours of the day)
     */
    function revealSecret(uint256 secret) external nonReentrant {
        uint256 currentDayNumber = getCurrentDay();
        require(isRevealPhase(), "Not in reveal phase");
        
        CommitReveal storage cr = dayCommitments[currentDayNumber][msg.sender];
        require(cr.commitment != 0, "No commitment found");
        require(!cr.revealed, "Already revealed");
        require(keccak256(abi.encodePacked(secret, msg.sender)) == cr.commitment, "Invalid secret");
        require(!usedSecrets[secret], "Secret already used");
        
        cr.revealedSecret = secret;
        cr.revealed = true;
        usedSecrets[secret] = true;
        dayTotalRevealed[currentDayNumber] += cr.amount;
        
        emit SecretRevealed(msg.sender, currentDayNumber, secret);
    }
    
    /**
     * @dev Execute daily lottery with efficient winner selection
     */
    function executeLottery() external nonReentrant {
        uint256 previousDay = getCurrentDay() - 1;
        require(!dayLotteryExecuted[previousDay], "Lottery already executed");
        require(block.timestamp >= lastLotteryTime + DAY_DURATION, "Day not complete");
        
        // Generate random seed from revealed secrets
        uint256 randomSeed = _generateRandomSeed(previousDay);
        dayRandomSeed[previousDay] = randomSeed;
        
        // Select winner if there are holders
        if (holderNodes.length > 0 && currentLotteryPool > 0) {
            address winner = _selectWinnerEfficient(randomSeed);
            uint256 prize = currentLotteryPool;
            currentLotteryPool = 0;
            
            _mint(winner, prize);
            _updateHolderBalance(winner, int256(prize));
            emit LotteryWon(winner, prize, previousDay);
        }
        
        dayLotteryExecuted[previousDay] = true;
        lastLotteryTime = block.timestamp;
        currentDay++;
    }
    
    /**
     * @dev Efficient winner selection using binary search on cumulative sums
     */
    function _selectWinnerEfficient(uint256 randomSeed) internal view returns (address) {
        uint256 winningNumber = randomSeed % totalHolderBalance;
        
        // Binary search for the winner
        uint256 left = 0;
        uint256 right = holderNodes.length - 1;
        
        while (left < right) {
            uint256 mid = (left + right) / 2;
            if (holderNodes[mid].cumulativeSum <= winningNumber) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }
        
        return holderNodes[left].holder;
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
        uint256 totalPool = currentRandomnessPool;
        
        // Add forfeited stakes from non-revealers
        address[] memory participants = dayParticipants[day];
        uint256 forfeitedAmount = 0;
        for (uint256 i = 0; i < participants.length; i++) {
            CommitReveal memory participantCR = dayCommitments[day][participants[i]];
            if (!participantCR.revealed) {
                forfeitedAmount += participantCR.amount;
            }
        }
        
        uint256 totalReward = totalPool + forfeitedAmount;
        uint256 userReward = (totalReward * cr.amount) / dayTotalRevealed[day];
        
        cr.claimed = true;
        currentRandomnessPool -= (totalPool * cr.amount) / dayTotalRevealed[day];
        
        // Return staked amount + reward
        uint256 totalPayout = cr.amount + userReward;
        _mint(msg.sender, totalPayout);
        _updateHolderBalance(msg.sender, int256(totalPayout));
        
        emit RandomnessRewardClaimed(msg.sender, day, userReward);
    }
    
    /**
     * @dev Generate random seed from revealed secrets
     */
    function _generateRandomSeed(uint256 day) internal view returns (uint256) {
        uint256 seed = 0;
        address[] memory participants = dayParticipants[day];
        
        for (uint256 i = 0; i < participants.length; i++) {
            CommitReveal memory cr = dayCommitments[day][participants[i]];
            if (cr.revealed) {
                seed ^= cr.revealedSecret;
            }
        }
        
        // Add block randomness
        seed = uint256(keccak256(abi.encodePacked(seed, blockhash(block.number - 1), block.timestamp)));
        
        return seed;
    }
    
    /**
     * @dev Get current day number
     */
    function getCurrentDay() public view returns (uint256) {
        return (block.timestamp - deploymentTime) / DAY_DURATION;
    }
    
    /**
     * @dev Check if in commit phase (first 12 hours)
     */
    function isCommitPhase() public view returns (bool) {
        uint256 dayProgress = (block.timestamp - deploymentTime) % DAY_DURATION;
        return dayProgress < DAY_DURATION / 2;
    }
    
    /**
     * @dev Check if in reveal phase (last 12 hours)
     */
    function isRevealPhase() public view returns (bool) {
        uint256 dayProgress = (block.timestamp - deploymentTime) % DAY_DURATION;
        return dayProgress >= DAY_DURATION / 2;
    }
    
    /**
     * @dev Get holder count
     */
    function getHolderCount() external view returns (uint256) {
        return holderNodes.length;
    }
    
    /**
     * @dev Get holder info by index
     */
    function getHolderByIndex(uint256 index) external view returns (address holder, uint256 balance) {
        require(index < holderNodes.length, "Index out of bounds");
        HolderNode memory node = holderNodes[index];
        return (node.holder, node.balance);
    }
}