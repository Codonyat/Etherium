// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy, IWMON} from "../src/Strategy.sol";

// Mock WMON for testing
contract MockWMON {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "MON transfer failed");
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
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

        return true;
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

contract StrategyMaxSupplyOrderTest is Test {
    Strategy public monstr;
    MockWMON public wmon;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    event LotteryWon(address indexed winner, uint256 amount, uint256 day);
    event BeneficiaryFunded(
        address indexed beneficiary,
        uint256 amount,
        address previousWinner
    );

    function setUp() public {
        wmon = new MockWMON();
        monstr = new Strategy(address(wmon));

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }

    function testMaxSupplySetBeforeBurns() public {
        // During minting period, create holders
        vm.prank(alice);
        monstr.mint{value: 50 ether}();

        vm.prank(bob);
        monstr.mint{value: 30 ether}();

        vm.prank(charlie);
        monstr.mint{value: 20 ether}();

        // Total supply after minting: 100 MON * 1:1 = 100 MONSTR (99 to users + 1 fees)
        uint256 totalSupplyAtEndOfMinting = monstr.totalSupply();
        assertEq(
            totalSupplyAtEndOfMinting,
            100 ether,
            "Total supply should be 100 MONSTR"
        );

        // Move past minting period
        vm.warp(monstr.mintingEndTime() + 1);

        // Verify max supply not yet set
        assertEq(monstr.maxSupplyEver(), 0, "Max supply not yet set");

        // The first transaction after minting period will set max supply
        // This happens BEFORE any lottery execution or potential burns
        uint256 totalSupplyBeforeFirstTx = monstr.totalSupply();

        // First transaction after minting period - a simple transfer
        vm.prank(alice);
        monstr.transfer(bob, 1 ether);

        // Max supply should now be set to the total supply BEFORE the transfer
        uint256 maxSupplyEver = monstr.maxSupplyEver();
        assertEq(
            maxSupplyEver,
            totalSupplyBeforeFirstTx,
            "Max supply should be set to initial total"
        );
        assertEq(
            maxSupplyEver,
            100 ether,
            "Max supply should be 100 MONSTR"
        );

        // Current supply is actually MORE than max due to transfer fee being added to FEES_POOL
        // After minting period, fees are taken from sender, not minted
        uint256 currentSupply = monstr.totalSupply();
        assertEq(
            currentSupply,
            maxSupplyEver,
            "Supply unchanged - fees just moved between accounts"
        );

        // Verify max supply never changes
        vm.prank(bob);
        monstr.transfer(charlie, 2 ether);

        assertEq(
            monstr.maxSupplyEver(),
            maxSupplyEver,
            "Max supply should never change once set"
        );
    }

    function testMaxSupplyWithImmediateBeneficiaryBurn() public {
        // Setup: Create holders and ensure we'll have an unclaimed prize
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        vm.prank(bob);
        monstr.mint{value: 10 ether}();

        // Day 0: Generate fees
        vm.prank(alice);
        monstr.transfer(bob, 1 ether);

        // Day 1: Execute lottery to create a winner
        vm.warp(block.timestamp + 25 hours + 61);
        monstr.executeLottery();

        // Don't let winner claim - let it sit for 7 days
        // Generate fees each day to keep lottery going
        for (uint256 i = 0; i < 7; i++) {
            vm.prank(bob);
            monstr.transfer(alice, 0.1 ether);

            vm.warp(block.timestamp + 25 hours + 61);

            // Skip executing lottery until we're past minting period
            if (block.timestamp <= monstr.mintingEndTime()) {
                monstr.executeLottery();
            }
        }

        // Now we're past minting period with an unclaimed prize
        assertTrue(
            block.timestamp > monstr.mintingEndTime(),
            "Should be past minting period"
        );

        // Generate one more fee
        vm.prank(alice);
        monstr.transfer(bob, 0.2 ether);

        uint256 totalSupplyBefore = monstr.totalSupply();
        // Max supply might already be set by the transfer above since we're past minting period
        uint256 maxSupplyBefore = monstr.maxSupplyEver();

        // The next lottery execution will:
        // 1. Check and set max supply (happens FIRST now)
        // 2. Try to send unclaimed prize to public goods (might burn tokens)
        vm.warp(block.timestamp + 25 hours + 61);
        monstr.executeLottery();

        uint256 maxSupply = monstr.maxSupplyEver();
        uint256 totalSupplyAfter = monstr.totalSupply();

        // Max supply should be set and not change
        assertTrue(maxSupply > 0, "Max supply should be set");
        if (maxSupplyBefore == 0) {
            // If it wasn't set before, it should equal the supply BEFORE any burns
            assertEq(
                maxSupply,
                totalSupplyBefore,
                "Max supply should be set before burns"
            );
        } else {
            // If already set, it shouldn't change
            assertEq(maxSupply, maxSupplyBefore, "Max supply shouldn't change");
        }

        // If burns happened, total supply would be less than max supply
        if (totalSupplyAfter < totalSupplyBefore) {
            console.log("Tokens were burned for public goods");
            assertTrue(
                totalSupplyAfter < maxSupply,
                "Current supply should be less than max after burns"
            );
        }
    }

    function testTransferTriggersMaxSupplyBeforeLottery() public {
        // Setup during minting period
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        // Move just past minting period
        vm.warp(monstr.mintingEndTime() + 1);

        assertEq(monstr.maxSupplyEver(), 0, "Max supply not yet set");

        // A simple transfer should set max supply before executing lottery
        uint256 totalSupplyBefore = monstr.totalSupply();

        vm.prank(alice);
        monstr.transfer(bob, 1 ether);

        // Max supply should now be set
        uint256 maxSupply = monstr.maxSupplyEver();
        assertEq(
            maxSupply,
            totalSupplyBefore,
            "Max supply should be set by transfer"
        );

        // And it should equal the total supply before the transfer's fee
        assertEq(maxSupply, 10 ether, "Max supply should be 10 MONSTR");
    }
}
