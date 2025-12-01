// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy} from "../.././src/Strategy.sol";

abstract contract StrategyTestBase is Test {
    Strategy public giga;
    MockMEGA public mega;
    MockERC20 public communityToken;

    // Common test addresses
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);
    address public eve = address(0x5);

    // Events for testing
    event Minted(
        address indexed user,
        uint256 megaAmount,
        uint256 userTokens,
        uint256 feeTokens
    );
    event Redeemed(
        address indexed user,
        uint256 tokenAmount,
        uint256 megaAmount,
        uint256 fee
    );
    event Transfer(address indexed from, address indexed to, uint256 value);
    event PrevrandaoCommitted(
        address indexed user,
        bytes32 commitment,
        uint256 day
    );
    event PrevrandaoRevealed(
        address indexed user,
        uint256 prevrandao,
        uint256 day
    );
    event LotteryWon(address indexed winner, uint256 amount, uint256 day);
    event AuctionWon(
        address indexed winner,
        uint256 gigaAmount,
        uint256 megaPaid,
        uint256 day
    );
    event BeneficiaryFunded(
        address indexed beneficiary,
        uint256 amount,
        address originalWinner
    );

    function setUp() public virtual {
        // Deploy mock MEGA token
        mega = new MockMEGA();

        // Deploy mock community token for tests that need it
        communityToken = new MockERC20();

        // Deploy Strategy with MEGA token address
        giga = new Strategy(address(mega));

        // Fund test accounts with ETH (for gas) and MEGA tokens
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);
        vm.deal(eve, 100 ether);

        // Give each test account MEGA tokens
        mega.mint(alice, 100 ether);
        mega.mint(bob, 100 ether);
        mega.mint(charlie, 100 ether);
        mega.mint(david, 100 ether);
        mega.mint(eve, 100 ether);
    }

    // Note: Community token is now hardcoded in the contract
    // To test with community token, you need to modify the contract source before deployment

    // Helper function to move time forward by days
    function skipDays(uint256 numDays) internal {
        vm.warp(block.timestamp + numDays * 25 hours);
    }

    // Helper function to move to next day and past the 1-minute mark
    function moveToNextDay() internal {
        vm.warp(block.timestamp + 25 hours + 61);
    }

    // Helper function to skip past the minting period
    function skipPastMintingPeriod() internal {
        uint256 mintingPeriod = giga.MINTING_PERIOD();
        vm.warp(block.timestamp + mintingPeriod + 1 days);
    }

    // Helper to approve MEGA and mint GIGA
    function mintGiga(address user, uint256 megaAmount) internal {
        vm.startPrank(user);
        mega.approve(address(giga), megaAmount);
        giga.mint(megaAmount);
        vm.stopPrank();
    }

    // Helper function to set up basic holders
    function setupBasicHolders() internal {
        mintGiga(alice, 10 ether);
        mintGiga(bob, 5 ether);
        mintGiga(charlie, 2 ether);
    }
}

// MockMEGA is a simple ERC20 token for testing
contract MockMEGA {
    string public name = "Mock MEGA";
    string public symbol = "MEGA";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    // Mint tokens to a specific address (for testing)
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(
            allowance[from][msg.sender] >= amount,
            "Insufficient allowance"
        );

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        emit Transfer(from, to, amount);
        return true;
    }
}

// Common mock contracts used across tests
contract MockContract {
    MockMEGA public mega;

    constructor(MockMEGA _mega) {
        mega = _mega;
    }

    function mintStrategy(Strategy _giga, uint256 amount) external {
        mega.approve(address(_giga), amount);
        _giga.mint(amount);
    }

    function transferStrategy(
        Strategy _giga,
        address to,
        uint256 amount
    ) external {
        _giga.transfer(to, amount);
    }

    function approveStrategy(
        Strategy _giga,
        address spender,
        uint256 amount
    ) external {
        _giga.approve(spender, amount);
    }

    function transferFromStrategy(
        Strategy _giga,
        address from,
        address to,
        uint256 amount
    ) external {
        _giga.transferFrom(from, to, amount);
    }

    receive() external payable {}
}

// Contract that rejects native transfers
contract MockRejectNative {
    // No receive or fallback function - will reject native transfers
}

// Attack contract for reentrancy tests
contract ReentrancyAttacker {
    Strategy public target;
    MockMEGA public mega;
    uint256 public attackCount;
    bool public attacking;

    constructor(Strategy _target, MockMEGA _mega) {
        target = _target;
        mega = _mega;
    }

    function attack(uint256 amount) external {
        attacking = true;
        mega.approve(address(target), amount);
        target.mint(amount);
    }

    receive() external payable {
        if (attacking && attackCount < 1) {
            attackCount++;
            // Try to mint again during the callback
            uint256 balance = mega.balanceOf(address(this));
            if (balance >= 1 ether) {
                mega.approve(address(target), 1 ether);
                target.mint(1 ether);
            }
        }
    }
}

// Mock ERC20 for testing (community tokens)
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(
            allowance[from][msg.sender] >= amount,
            "Insufficient allowance"
        );

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;

        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// Keep MockWMEGA as alias for backwards compatibility
contract MockWMEGA is MockMEGA {}
