// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy, IWMON} from "../.././src/Strategy.sol";

abstract contract StrategyTestBase is Test {
    Strategy public monstr;
    IWMON public wmon;
    MockERC20 public communityToken;

    // Monad WMON addresses
    address public constant WMON_MAINNET =
        0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address public constant WMON_TESTNET =
        0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;

    // Common test addresses
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);
    address public eve = address(0x5);

    // Events for testing
    event Minted(
        address indexed user,
        uint256 monAmount,
        uint256 userTokens,
        uint256 feeTokens
    );
    event Redeemed(
        address indexed user,
        uint256 tokenAmount,
        uint256 monAmount,
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
        uint256 monstrAmount,
        uint256 monPaid,
        uint256 day
    );
    event BeneficiaryFunded(
        address indexed beneficiary,
        uint256 amount,
        address originalWinner
    );

    function setUp() public virtual {
        // Determine which WMON to use based on chain ID
        address wmonAddress = getWMONAddress();

        if (wmonAddress == address(0)) {
            // No real WMON available - deploy mock for local testing
            MockWMON mockWmon = new MockWMON();
            wmon = IWMON(address(mockWmon));
        } else {
            // Use real WMON from the network
            wmon = IWMON(wmonAddress);
        }

        // Deploy mock community token for tests that need it
        communityToken = new MockERC20();

        // Deploy Strategy with appropriate WMON
        monstr = new Strategy(address(wmon));

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);
        vm.deal(eve, 100 ether);
    }

    /// @dev Returns the appropriate WMON address for the current chain, or address(0) for local testing
    function getWMONAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        // Monad Mainnet chain ID (update when known)
        if (chainId == 143) {
            return WMON_MAINNET;
        }
        // Monad Testnet chain ID
        else if (chainId == 10143) {
            return WMON_TESTNET;
        }
        // Local testing (Foundry default is 31337)
        else {
            return address(0);
        }
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

    // Helper function to set up basic holders
    function setupBasicHolders() internal {
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        vm.prank(bob);
        monstr.mint{value: 5 ether}();

        vm.prank(charlie);
        monstr.mint{value: 2 ether}();
    }
}

// Common mock contracts used across tests
contract MockContract {
    function mintStrategy(Strategy _monstr) external {
        _monstr.mint{value: 1 ether}();
    }

    function transferStrategy(
        Strategy _monstr,
        address to,
        uint256 amount
    ) external {
        _monstr.transfer(to, amount);
    }

    function approveStrategy(
        Strategy _monstr,
        address spender,
        uint256 amount
    ) external {
        _monstr.approve(spender, amount);
    }

    function transferFromStrategy(
        Strategy _monstr,
        address from,
        address to,
        uint256 amount
    ) external {
        _monstr.transferFrom(from, to, amount);
    }

    receive() external payable {}
}

// Contract that rejects MON transfers
contract MockRejectETH {
    // No receive or fallback function - will reject MON transfers
}

// Attack contract for reentrancy tests
contract ReentrancyAttacker {
    Strategy public target;
    uint256 public attackCount;
    bool public attacking;

    constructor(Strategy _target) {
        target = _target;
    }

    function attack() external payable {
        attacking = true;
        target.mint{value: msg.value}();
    }

    receive() external payable {
        if (attacking && attackCount < 1) {
            attackCount++;
            // Try to mint again during the callback
            if (address(this).balance >= 1 ether) {
                target.mint{value: 1 ether}();
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

// Mock WMON for local testing
// This is only used when running tests without a fork (local testing)
// When testing on Monad forks, the real WMON contract is used instead
contract MockWMON {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "MON transfer failed");
        emit Transfer(msg.sender, address(0), amount);
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

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }
}
