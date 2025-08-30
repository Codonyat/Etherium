// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract EtheriumAuctionMinBidTest is Test {
    Etherium public etherium;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);

    // Event definitions for testing
    event AuctionStarted(uint256 day, uint256 etheriumAmount, uint256 minBid);
    event BidPlaced(address indexed bidder, uint256 amount, uint256 day);
    event AuctionWon(address indexed winner, uint256 etheriumAmount, uint256 ethPaid, uint256 day);

    function setUp() public {
        etherium = new Etherium();

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);
    }

    function testMinBidCalculationForSmallAuction() public {
        // Setup: Create supply and generate small fees
        vm.prank(alice);
        etherium.mint{value: 10 ether}(); // 9900 ETHERIUM to alice, 100 to fees pool
        
        // Move past minting period
        vm.warp(block.timestamp + 8 days);
        
        // Generate exactly 2 ETHERIUM in fees (minimum for auction after split)
        // Transfer 200 ETHERIUM to generate 2 ETHERIUM fee
        vm.prank(alice);
        etherium.transfer(bob, 200 ether);
        
        // Move to next day to execute
        vm.warp(block.timestamp + 25 hours + 61);
        
        // Execute lottery/auction
        etherium.executeLottery();
        
        // Get auction details
        (,,, uint112 auctionAmount,) = etherium.currentAuction();
        
        // Auction should have 1 ETHERIUM (50% of 2 ETHERIUM fees)
        assertEq(auctionAmount, 1 ether, "Auction should have 1 ETHERIUM");
        
        // Calculate expected minimum bid
        // MinBid = (10 ETH * 1 ETHERIUM + totalSupply - 1) / totalSupply (rounded up)
        uint256 totalSupply = etherium.totalSupply();
        uint256 expectedMinBid = (10 ether * 1 ether + totalSupply - 1) / totalSupply;
        
        // Try to bid below minimum (should fail)
        vm.prank(charlie);
        vm.expectRevert("Bid too low");
        etherium.bid{value: expectedMinBid - 1}();
        
        // Bid exactly at minimum (should succeed)
        vm.prank(charlie);
        etherium.bid{value: expectedMinBid}();
        
        (address bidder, uint96 bid,,,) = etherium.currentAuction();
        assertEq(bidder, charlie, "Charlie should be current bidder");
        assertEq(bid, expectedMinBid, "Bid should match expected minimum");
    }

    function testMinBidCalculationForLargeAuction() public {
        // Setup: Create supply and generate large fees
        vm.prank(alice);
        etherium.mint{value: 10 ether}(); // 9900 ETHERIUM to alice
        
        // Move past minting period
        vm.warp(block.timestamp + 8 days);
        
        // Generate ~100 ETHERIUM in fees
        for (uint i = 0; i < 10; i++) {
            vm.prank(alice);
            etherium.transfer(bob, 990 ether); // 9.9 ETHERIUM fee each
            vm.prank(bob);
            etherium.transfer(alice, 980.1 ether); // Return most tokens
        }
        
        // Move to next day
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Get auction details
        (,,, uint112 auctionAmount,) = etherium.currentAuction();
        
        // Total fees should be ~99-100 ETHERIUM (10 transfers × 9.9 + 10 transfers × 9.801)
        // Auction gets 50% of fees
        assertTrue(auctionAmount >= 49 ether && auctionAmount <= 100 ether, "Auction should have 50% of fees");
        
        // Calculate expected minimum bid
        uint256 contractBalance = address(etherium).balance;
        uint256 totalSupply = etherium.totalSupply();
        uint256 expectedMinBid = (contractBalance * auctionAmount + totalSupply - 1) / totalSupply;
        
        // Bid exactly at minimum
        vm.prank(charlie);
        etherium.bid{value: expectedMinBid}();
        
        (address bidder, uint96 bid,,,) = etherium.currentAuction();
        assertEq(bidder, charlie, "Charlie should be current bidder");
        assertGe(bid, expectedMinBid, "Bid should be at least expected minimum");
    }

    function testMinBidRoundingPreventsUnderpricing() public {
        // Setup scenario where rounding matters
        vm.prank(alice);
        etherium.mint{value: 1 ether}(); // 990 ETHERIUM to alice
        
        vm.warp(block.timestamp + 8 days);
        
        // Generate small fee amount
        vm.prank(alice);
        etherium.transfer(bob, 100 ether); // 1 ETHERIUM fee
        
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Get auction amount (0.5 ETHERIUM after split)
        (,,, uint112 auctionAmount,) = etherium.currentAuction();
        
        // Calculate what minimum bid would be without rounding
        uint256 contractBalance = address(etherium).balance;
        uint256 totalSupply = etherium.totalSupply();
        uint256 minBidNoRounding = (contractBalance * auctionAmount) / totalSupply;
        uint256 minBidWithRounding = (contractBalance * auctionAmount + totalSupply - 1) / totalSupply;
        
        // Verify rounding increases the minimum bid when there's a remainder
        if ((contractBalance * auctionAmount) % totalSupply != 0) {
            assertGt(minBidWithRounding, minBidNoRounding, "Rounding should increase minimum bid");
        }
        
        // Verify can't bid at unrounded amount if it's lower
        if (minBidWithRounding > minBidNoRounding) {
            vm.prank(charlie);
            vm.expectRevert("Bid too low");
            etherium.bid{value: minBidNoRounding}();
        }
        
        // Can bid at rounded amount
        vm.prank(charlie);
        etherium.bid{value: minBidWithRounding}();
    }

    function testMinBidWithDifferentBackingRatios() public {
        // Setup initial state
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        // Move past minting period (after 7 days)
        vm.warp(block.timestamp + 8 days);
        
        // Generate fees for auction
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether); // 10 ETHERIUM fee
        
        // Move to next day to execute lottery/auction
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Get initial auction state  
        (,,, uint112 auctionAmount,) = etherium.currentAuction();
        
        // Auction should have 5 ETHERIUM (50% of 10 ETHERIUM fees)
        assertEq(auctionAmount, 5 ether, "Should auction 5 ETHERIUM");
        
        uint256 initialBalance = address(etherium).balance;
        uint256 totalSupply = etherium.totalSupply();
        uint256 initialMinBid = (initialBalance * auctionAmount + totalSupply - 1) / totalSupply;
        
        // Verify initial min bid is reasonable (should be around 0.005 ETH for 5 ETHERIUM)
        assertTrue(initialMinBid > 0, "Initial min bid should be positive");
        assertEq(initialMinBid, 0.005 ether, "Min bid should be 0.005 ETH for 5 ETHERIUM with 1:1000 backing");
        
        // Simulate a successful previous auction that increased ETH backing
        // (As if someone paid 5 ETH in a previous auction)
        vm.deal(address(etherium), address(etherium).balance + 5 ether);
        
        // Recalculate minimum bid with new backing
        uint256 newContractBalance = address(etherium).balance;
        uint256 expectedNewMinBid = (newContractBalance * auctionAmount + totalSupply - 1) / totalSupply;
        
        // New minimum should be 50% higher (15 ETH backing vs 10 ETH)
        assertGt(expectedNewMinBid, initialMinBid, "Min bid should increase after more ETH added");
        assertEq(expectedNewMinBid, 0.0075 ether, "Min bid should be 0.0075 ETH with 15 ETH backing");
        
        // Verify we can bid at this new minimum
        vm.prank(charlie);
        etherium.bid{value: expectedNewMinBid}();
        
        (address bidder, uint96 bid,,,) = etherium.currentAuction();
        assertEq(bidder, charlie, "Charlie should be bidder");
    }

    function testBidIncrementEnforcement() public {
        // Setup
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);
        
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Get minimum bid
        (,,, uint112 auctionAmount,) = etherium.currentAuction();
        uint256 minBid = (address(etherium).balance * auctionAmount + etherium.totalSupply() - 1) / etherium.totalSupply();
        
        // First bid at minimum
        vm.prank(charlie);
        etherium.bid{value: minBid}();
        
        // Try to outbid with only 9% increase (should fail)
        uint256 insufficientBid = (minBid * 109) / 100;
        vm.prank(david);
        vm.expectRevert("Bid too low");
        etherium.bid{value: insufficientBid}();
        
        // Outbid with exactly 10% increase (should succeed)
        uint256 validBid = (minBid * 110) / 100;
        vm.prank(david);
        etherium.bid{value: validBid}();
        
        (address bidder, uint96 bid,,,) = etherium.currentAuction();
        assertEq(bidder, david, "David should be current bidder");
        assertEq(bid, validBid, "Bid should be 10% higher");
    }

    function testAuctionForDustAmountSkipped() public {
        // Setup
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        vm.warp(block.timestamp + 8 days);
        
        // Generate tiny fee (less than MIN_FEES_FOR_DISTRIBUTION)
        // Need to generate less than 1e12 wei in fees
        // With 1% fee, transferring 1e11 wei generates 1e9 wei fee
        vm.prank(alice);
        etherium.transfer(bob, 1e11); // Fee will be 1e9 wei (below threshold)
        
        // Try to execute lottery/auction
        vm.warp(block.timestamp + 25 hours + 61);
        
        // Should revert because fees are below threshold
        vm.expectRevert("Insufficient fees to distribute");
        etherium.executeLottery();
    }

    function testCorrectMinBidAfterMultipleMints() public {
        // Initial mint
        vm.prank(alice);
        etherium.mint{value: 5 ether}(); // 4950 ETHERIUM to alice
        
        vm.prank(bob);
        etherium.mint{value: 5 ether}(); // 4950 ETHERIUM to bob
        
        // Total: 10 ETH, 10000 ETHERIUM (9900 + 100 fees)
        
        vm.warp(block.timestamp + 8 days);
        
        // Generate fees
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether); // 10 ETHERIUM fee
        
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Auction gets 5 ETHERIUM (50% of 10)
        (,,, uint112 auctionAmount,) = etherium.currentAuction();
        assertEq(auctionAmount, 5 ether, "Should auction 5 ETHERIUM");
        
        // With 10 ETH backing 10000 ETHERIUM, 5 ETHERIUM should cost:
        // (10 ETH * 5 ETHERIUM + 10000 - 1) / 10000 = 0.005 ETH (rounded up)
        uint256 expectedMinBid = (10 ether * 5 ether + etherium.totalSupply() - 1) / etherium.totalSupply();
        
        // Verify the calculation
        assertEq(expectedMinBid, 0.005 ether, "Min bid should be 0.005 ETH for 5 ETHERIUM");
        
        // Test bidding at this amount
        vm.prank(charlie);
        etherium.bid{value: expectedMinBid}();
        
        (address bidder, uint96 bid,,,) = etherium.currentAuction();
        assertEq(bidder, charlie, "Charlie should win with minimum bid");
        assertEq(bid, expectedMinBid, "Bid should match expected");
    }
}