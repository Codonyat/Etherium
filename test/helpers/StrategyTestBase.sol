// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy, IWMEGA} from "../.././src/Strategy.sol";
import {WMEGAAddresses} from "../.././script/WMEGAAddresses.sol";

abstract contract StrategyTestBase is Test {
    Strategy public giga;
    IWMEGA public wmega;
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
        // Determine which WMEGA to use based on chain ID
        address wmegaAddress = WMEGAAddresses.getWMEGAAddress();

        if (wmegaAddress == address(0)) {
            // No real WMEGA available - deploy mock for local testing
            MockWMEGA mockWmega = new MockWMEGA();
            wmega = IWMEGA(address(mockWmega));
        } else {
            // Use real WMEGA from the network
            wmega = IWMEGA(wmegaAddress);
        }

        // Deploy mock community token for tests that need it
        communityToken = new MockERC20();

        // Deploy Strategy with appropriate WMEGA
        giga = new Strategy(address(wmega));

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);
        vm.deal(eve, 100 ether);
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

    // Helper function to set up basic holders
    function setupBasicHolders() internal {
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        vm.prank(bob);
        giga.mint{value: 5 ether}();

        vm.prank(charlie);
        giga.mint{value: 2 ether}();
    }
}

// Common mock contracts used across tests
contract MockContract {
    function mintStrategy(Strategy _giga) external {
        _giga.mint{value: 1 ether}();
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

// Mock WMEGA for local testing
// This is only used when running tests without a fork (local testing)
// When testing on MegaETH forks, the real WMEGA contract is used instead
contract MockWMEGA {
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
        require(success, "MEGA transfer failed");
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
