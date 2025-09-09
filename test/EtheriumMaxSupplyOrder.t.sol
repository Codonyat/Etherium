// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract EtheriumMaxSupplyOrderTest is Test {
    Etherium public etherium;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    event LotteryWon(address indexed winner, uint256 amount, uint256 day);
    event PublicGoodsFunded(address indexed publicGood, uint256 amount, address previousWinner);

    function setUp() public {
        etherium = new Etherium();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }

    function testMaxSupplySetBeforeBurns() public {
        // During minting period, create holders
        vm.prank(alice);
        etherium.mint{value: 50 ether}();

        vm.prank(bob);
        etherium.mint{value: 30 ether}();

        vm.prank(charlie);
        etherium.mint{value: 20 ether}();

        // Total supply after minting: 100 ETH * 1000 = 100,000 ETHERIUM
        uint256 totalSupplyAtEndOfMinting = etherium.totalSupply();
        assertEq(totalSupplyAtEndOfMinting, 100_000 ether, "Total supply should be 100,000 ETHERIUM");

        // Move past minting period
        vm.warp(etherium.mintingEndTime() + 1);

        // Verify max supply not yet set
        assertEq(etherium.maxSupplyEver(), 0, "Max supply not yet set");

        // The first transaction after minting period will set max supply
        // This happens BEFORE any lottery execution or potential burns
        uint256 totalSupplyBeforeFirstTx = etherium.totalSupply();
        
        // First transaction after minting period - a simple transfer
        vm.prank(alice);
        etherium.transfer(bob, 100 ether);
        
        // Max supply should now be set to the total supply BEFORE the transfer
        uint256 maxSupplyEver = etherium.maxSupplyEver();
        assertEq(maxSupplyEver, totalSupplyBeforeFirstTx, "Max supply should be set to initial total");
        assertEq(maxSupplyEver, 100_000 ether, "Max supply should be 100,000 ETHERIUM");
        
        // Current supply is actually MORE than max due to transfer fee being added to FEES_POOL
        // After minting period, fees are taken from sender, not minted
        uint256 currentSupply = etherium.totalSupply();
        assertEq(currentSupply, maxSupplyEver, "Supply unchanged - fees just moved between accounts");
        
        // Verify max supply never changes
        vm.prank(bob);
        etherium.transfer(charlie, 200 ether);
        
        assertEq(etherium.maxSupplyEver(), maxSupplyEver, "Max supply should never change once set");
    }

    function testMaxSupplyWithImmediatePublicGoodsBurn() public {
        // Setup: Create holders and ensure we'll have an unclaimed prize
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 10 ether}();

        // Day 0: Generate fees
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);

        // Day 1: Execute lottery to create a winner
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();

        // Don't let winner claim - let it sit for 7 days
        // Generate fees each day to keep lottery going
        for (uint256 i = 0; i < 7; i++) {
            vm.prank(bob);
            etherium.transfer(alice, 100 ether);
            
            vm.warp(block.timestamp + 25 hours + 61);
            
            // Skip executing lottery until we're past minting period
            if (block.timestamp <= etherium.mintingEndTime()) {
                etherium.executeLottery();
            }
        }

        // Now we're past minting period with an unclaimed prize
        assertTrue(block.timestamp > etherium.mintingEndTime(), "Should be past minting period");
        
        // Generate one more fee
        vm.prank(alice);
        etherium.transfer(bob, 200 ether);

        uint256 totalSupplyBefore = etherium.totalSupply();
        // Max supply might already be set by the transfer above since we're past minting period
        uint256 maxSupplyBefore = etherium.maxSupplyEver();

        // The next lottery execution will:
        // 1. Check and set max supply (happens FIRST now)
        // 2. Try to send unclaimed prize to public goods (might burn tokens)
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();

        uint256 maxSupply = etherium.maxSupplyEver();
        uint256 totalSupplyAfter = etherium.totalSupply();

        // Max supply should be set and not change
        assertTrue(maxSupply > 0, "Max supply should be set");
        if (maxSupplyBefore == 0) {
            // If it wasn't set before, it should equal the supply BEFORE any burns
            assertEq(maxSupply, totalSupplyBefore, "Max supply should be set before burns");
        } else {
            // If already set, it shouldn't change
            assertEq(maxSupply, maxSupplyBefore, "Max supply shouldn't change");
        }
        
        // If burns happened, total supply would be less than max supply
        if (totalSupplyAfter < totalSupplyBefore) {
            console.log("Tokens were burned for public goods");
            assertTrue(totalSupplyAfter < maxSupply, "Current supply should be less than max after burns");
        }
    }

    function testTransferTriggersMaxSupplyBeforeLottery() public {
        // Setup during minting period
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        // Move just past minting period
        vm.warp(etherium.mintingEndTime() + 1);

        assertEq(etherium.maxSupplyEver(), 0, "Max supply not yet set");

        // A simple transfer should set max supply before executing lottery
        uint256 totalSupplyBefore = etherium.totalSupply();
        
        vm.prank(alice);
        etherium.transfer(bob, 100 ether);

        // Max supply should now be set
        uint256 maxSupply = etherium.maxSupplyEver();
        assertEq(maxSupply, totalSupplyBefore, "Max supply should be set by transfer");
        
        // And it should equal the total supply before the transfer's fee
        assertEq(maxSupply, 10000 ether, "Max supply should be 10,000 ETHERIUM");
    }
}