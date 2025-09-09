// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../../src/Etherium.sol";

abstract contract EtheriumTestBase is Test {
    Etherium public etherium;

    // Common test addresses
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);
    address public eve = address(0x5);

    // Events for testing
    event Minted(address indexed user, uint256 ethAmount, uint256 userTokens, uint256 feeTokens);
    event Redeemed(address indexed user, uint256 tokenAmount, uint256 ethAmount, uint256 fee);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event PrevrandaoCommitted(address indexed user, bytes32 commitment, uint256 day);
    event PrevrandaoRevealed(address indexed user, uint256 prevrandao, uint256 day);
    event LotteryWon(address indexed winner, uint256 amount, uint256 day);
    event AuctionWon(address indexed winner, uint256 etheriumAmount, uint256 ethPaid, uint256 day);
    event PublicGoodsFunded(address indexed publicGood, uint256 amount, address originalWinner);

    function setUp() public virtual {
        etherium = new Etherium();

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);
        vm.deal(eve, 100 ether);
    }

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
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 5 ether}();

        vm.prank(charlie);
        etherium.mint{value: 2 ether}();
    }
}

// Common mock contracts used across tests
contract MockContract {
    function mintEtherium(Etherium etherium) external {
        etherium.mint{value: 1 ether}();
    }

    function transferEtherium(Etherium etherium, address to, uint256 amount) external {
        etherium.transfer(to, amount);
    }

    function approveEtherium(Etherium etherium, address spender, uint256 amount) external {
        etherium.approve(spender, amount);
    }

    function transferFromEtherium(Etherium etherium, address from, address to, uint256 amount) external {
        etherium.transferFrom(from, to, amount);
    }

    receive() external payable {}
}

// Contract that rejects ETH transfers
contract MockRejectETH {
// No receive or fallback function - will reject ETH transfers
}

// Attack contract for reentrancy tests
contract ReentrancyAttacker {
    Etherium public target;
    uint256 public attackCount;
    bool public attacking;

    constructor(Etherium _target) {
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

// Mock ERC20 for testing
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

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
