// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract EtheriumAuctionTest is Test {
    Etherium public etherium;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);

    // Event definitions for testing
    event AuctionStarted(uint256 day, uint256 etheriumAmount, uint256 minBid);
    event BidPlaced(address indexed bidder, uint256 amount, uint256 day);
    event BidRefunded(address indexed bidder, uint256 amount);
    event AuctionWon(address indexed winner, uint256 etheriumAmount, uint256 ethPaid, uint256 day);
    event LotteryWon(address indexed winner, uint256 amount, uint256 day);

    function setUp() public {
        etherium = new Etherium();

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);
    }

    function testNewMintingRatio() public {
        // Test 1 ETH = 1000 ETHERIUM during minting period
        vm.prank(alice);
        etherium.mint{value: 1 ether}();

        // Alice should receive 990 ETHERIUM (1000 - 1% fee)  
        // Note: 1 ETH = 1000 ETHERIUM tokens, each with 18 decimals
        assertEq(etherium.balanceOf(alice), 990 ether, "Should receive 990 ETHERIUM for 1 ETH");
        
        // Fees pool should have 10 ETHERIUM (1% fee)
        assertEq(etherium.balanceOf(etherium.FEES_POOL()), 10 ether, "Fees pool should have 10 ETHERIUM");
        
        // Total supply should be 1000 ETHERIUM
        assertEq(etherium.totalSupply(), 1000 ether, "Total supply should be 1000 ETHERIUM");
    }

    function testProportionalRedeem() public {
        // Mint some tokens first
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 5 ether}();
        
        // Total ETH: 15, Total ETHERIUM: 15,000
        // Alice has 9,900 ETHERIUM, Bob has 4,950 ETHERIUM, Pool has 150 ETHERIUM
        
        // Alice redeems 1,000 ETHERIUM
        vm.prank(alice);
        etherium.redeem(1000 ether);
        
        // With 1% fee: 990 burned, 10 to pool
        // ETH to return: 990 * 15 / 15,000 = 0.99 ETH
        assertEq(alice.balance, 90.99 ether, "Alice should receive proportional ETH");
    }

    function testDailyAuctionAndLottery() public {
        // Setup: Create holders and generate fees during minting period
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 5 ether}();
        
        // Generate some transfer fees on day 1
        vm.prank(alice);
        etherium.transfer(charlie, 100 ether); // 1 ETHERIUM fee
        
        // Move to day 2 and execute (during minting period - only lottery)
        vm.warp(block.timestamp + 50 hours + 61); // Day 2 + 1 minute
        vm.prevrandao(12345);
        
        // Should only emit lottery event during minting period
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 1);
        
        etherium.executeLottery();
        
        // Move past minting period
        vm.warp(block.timestamp + 7 days);
        
        // Generate fees on the new day
        vm.prank(alice);
        etherium.transfer(bob, 100 ether); // 1 ETHERIUM fee
        
        // Move to next day to execute both lottery and auction
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(67890);
        
        // Should start an auction with half the fees
        uint256 currentDay = etherium.getCurrentDay();
        uint256 prevDayFees = etherium.dailyFeesCollected(currentDay - 1);
        
        etherium.executeLottery();
        
        // Check auction was started
        (address bidder, uint96 bid, uint96 minBid, uint112 amount, uint32 auctionDay) = etherium.currentAuction();
        assertEq(amount, prevDayFees / 2, "Auction should have half the fees");
        assertEq(bidder, address(0), "No bidder yet");
    }

    function testAuctionBidding() public {
        // Setup auction scenario
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        // Generate fees and move past minting period
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether); // 10 ETHERIUM fee
        
        // Move to next day to start auction
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Get the auction details to find the minimum bid
        (,,uint96 minBid, uint112 auctionAmount,) = etherium.currentAuction();
        assertTrue(minBid > 0, "Minimum bid should be set");
        assertTrue(auctionAmount > 0, "Auction amount should be set");
        
        // Charlie places first bid at minimum
        vm.prank(charlie);
        etherium.bid{value: minBid}();
        
        (address currentBidder, uint96 currentBid,,,) = etherium.currentAuction();
        assertEq(currentBidder, charlie, "Charlie should be current bidder");
        assertEq(currentBid, minBid, "Bid should match");
        
        // David outbids with 10% more
        uint256 newBid = (minBid * 110) / 100;
        uint256 charlieBalanceBefore = charlie.balance;
        
        vm.prank(david);
        etherium.bid{value: newBid}();
        
        // Charlie should be refunded
        assertEq(charlie.balance, charlieBalanceBefore + minBid, "Charlie should be refunded");
        
        (currentBidder, currentBid,,,) = etherium.currentAuction();
        assertEq(currentBidder, david, "David should be current bidder");
        assertEq(currentBid, newBid, "New bid should match");
    }

    function testAuctionFinalization() public {
        // Setup auction with winner
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 10 ether}();
        
        // Generate significant fees
        for (uint i = 0; i < 10; i++) {
            vm.prank(alice);
            etherium.transfer(bob, 100 ether); // 1 ETHERIUM fee each
            vm.prank(bob);
            etherium.transfer(alice, 100 ether); // 1 ETHERIUM fee each
        }
        
        vm.warp(block.timestamp + 8 days);
        
        // Generate more fees after minting period for auction
        for (uint i = 0; i < 10; i++) {
            vm.prank(alice);
            etherium.transfer(bob, 1000 ether); // 10 ETHERIUM fee each
            vm.prank(bob);
            etherium.transfer(alice, 1000 ether); // 10 ETHERIUM fee each
        }
        
        // Start auction
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Get auction minimum bid and place winning bid
        (,,uint96 minBid,,) = etherium.currentAuction();
        vm.prank(charlie);
        etherium.bid{value: minBid}();
        
        (,,, uint112 auctionAmount,) = etherium.currentAuction();
        
        // Move to next day to finalize
        vm.warp(block.timestamp + 25 hours + 61);
        
        // Generate new fees
        vm.prank(alice);
        etherium.transfer(bob, 100 ether);
        
        // Execute next day's lottery/auction (will finalize previous)
        etherium.executeLottery();
        
        // Check Charlie can claim the auction winnings
        uint256 charlieBalanceBefore = etherium.balanceOf(charlie);
        vm.prank(charlie);
        etherium.claim();
        
        assertEq(
            etherium.balanceOf(charlie) - charlieBalanceBefore,
            auctionAmount,
            "Charlie should receive auctioned ETHERIUM"
        );
    }

    function testProportionalMintingAfterPeriod() public {
        // First mint during minting period to establish some supply
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        // Move past minting period
        vm.warp(block.timestamp + 8 days);
        
        // Bob mints after minting period - should get proportional amount
        vm.prank(bob);
        etherium.mint{value: 1 ether}();
        
        // Bob should get proportional amount based on ETH/supply ratio
        // Contract has 2 ETH and ~2000 ETHERIUM, so ratio is maintained
        assertEq(etherium.balanceOf(bob), 990 ether, "Proportional minting maintains ratio");
        
        // Now contract has 1 ETH and 1000 ETHERIUM supply
        // Bob mints 1 ETH, should get proportional amount
        vm.prank(bob);
        etherium.mint{value: 1 ether}();
        
        // Bob should get: 1 ETH * 1,000 ETHERIUM / 1 ETH = 1,000 ETHERIUM before fees
        // After 1% fee: 990 ETHERIUM
        assertEq(etherium.balanceOf(bob), 990 ether, "Proportional minting maintains ratio");
        
        // If auction increases ETH backing...
        // Simulate someone winning auction and adding ETH
        vm.deal(address(etherium), 3 ether); // Artificially add ETH as if from auction
        
        // Now Charlie mints 1 ETH
        // Contract has 3 ETH and 2,000 ETHERIUM
        // Charlie should get: 1 ETH * 2,000 / 3 = 666.67 ETHERIUM before fees
        vm.prank(charlie);
        etherium.mint{value: 1 ether}();
        
        uint256 expectedAmount = (uint256(1 ether) * uint256(2000 ether)) / uint256(3 ether);
        uint256 expectedAfterFee = (expectedAmount * 99) / 100;
        
        // Allow small rounding difference
        assertApproxEqAbs(
            etherium.balanceOf(charlie),
            expectedAfterFee,
            1e18, // 1 ETHERIUM tolerance
            "Minting adjusts to maintain ETH backing ratio"
        );
    }

    function test50_50FeeSplit() public {
        // Setup
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        // Bob also needs tokens to participate in transfers
        vm.prank(bob);
        etherium.mint{value: 10 ether}();
        
        // Move past minting period
        vm.warp(block.timestamp + 8 days);
        
        // Generate 200 ETHERIUM in fees (20 transfers * 10 ETHERIUM fee each)
        for (uint i = 0; i < 10; i++) {
            vm.prank(alice);
            etherium.transfer(bob, 1000 ether); // 10 ETHERIUM fee
            vm.prank(bob);
            etherium.transfer(alice, 1000 ether); // 10 ETHERIUM fee
        }
        
        uint256 totalFees = etherium.dailyFeesCollected(etherium.getCurrentDay());
        assertEq(totalFees, 200 ether, "Should have 200 ETHERIUM in fees");
        
        // Move to next day to execute
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(99999);
        
        etherium.executeLottery();
        
        // Check lottery winner gets 100 ETHERIUM (50% of 200)
        (address[14] memory winners, uint112[14] memory amounts) = etherium.getAllUnclaimedPrizes();
        uint256 lotteryDay = etherium.getCurrentDay() - 1;
        uint256 slot = lotteryDay % 14;
        
        assertEq(amounts[slot], 100 ether, "Lottery winner should get 100 ETHERIUM");
        
        // Check auction has 100 ETHERIUM (50% of 200)
        (,,, uint112 auctionAmount,) = etherium.currentAuction();
        assertEq(auctionAmount, 100 ether, "Auction should have 100 ETHERIUM");
    }

    function testNoLotteryOrAuctionBeforeDay2() public {
        // Setup with enough fees
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 10 ether}();
        
        // Generate significant fees
        for (uint i = 0; i < 10; i++) {
            vm.prank(alice);
            etherium.transfer(bob, 100 ether); // 1 ETHERIUM fee each
            vm.prank(bob);
            etherium.transfer(alice, 100 ether); // 1 ETHERIUM fee each
        }
        
        // Try to execute on day 0
        vm.expectRevert("Must wait until day 2 for first lottery/auction");
        etherium.executeLottery();
        
        // Move to day 1
        vm.warp(block.timestamp + 25 hours + 61);
        
        // Still should revert
        vm.expectRevert("Must wait until day 2 for first lottery/auction");
        etherium.executeLottery();
        
        // Move to day 2
        vm.warp(block.timestamp + 25 hours + 61);
        
        // Now should work (will execute for day 1's fees)
        etherium.executeLottery();
        
        assertEq(etherium.lastLotteryDay(), 2, "Lottery executed on day 2");
    }

    function testBidIncrementRequirement() public {
        // Setup auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.warp(block.timestamp + 8 days);
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);
        
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Get minimum bid and place initial bid
        (,,uint96 minBid,,) = etherium.currentAuction();
        vm.prank(charlie);
        etherium.bid{value: minBid}();
        
        // Try to bid with only 5% increase (should fail)
        uint256 lowBid = (minBid * 105) / 100;
        vm.prank(david);
        vm.expectRevert("Bid too low");
        etherium.bid{value: lowBid}();
        
        // Bid with exactly 10% increase (should work)
        uint256 validBid = (minBid * 110) / 100;
        vm.prank(david);
        etherium.bid{value: validBid}();
        
        (address bidder,,,,) = etherium.currentAuction();
        assertEq(bidder, david, "10% increment should be accepted");
    }
}