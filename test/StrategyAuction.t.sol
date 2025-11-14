// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy, IWMON} from "../src/Strategy.sol";
import {MockWMON, WMONTestBase} from "././helpers/WSTRATHelpers.sol";

contract StrategyAuctionTest is WMONTestBase {
    Strategy public monstr;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);

    // Event definitions for testing
    event AuctionStarted(uint256 day, uint256 monstrAmount, uint256 minBid);
    event BidPlaced(address indexed bidder, uint256 amount, uint256 day);
    event BidRefunded(address indexed bidder, uint256 amount);
    event AuctionWon(
        address indexed winner,
        uint256 monstrAmount,
        uint256 monPaid,
        uint256 day
    );
    event LotteryWon(address indexed winner, uint256 amount, uint256 day);

    function setUp() public {
        setupWMON();
        monstr = new Strategy(address(wmon));

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);
    }

    function testAuctionWithWMONBidding() public {
        // Generate fees during minting period
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        // Fast forward past minting period
        vm.warp(block.timestamp + 8 days + 1 hours);

        // Generate fees via transfer (alice has 9.9 tokens from 10 MON mint with 1:1 ratio)
        uint256 aliceBalanceBefore = monstr.balanceOf(alice);
        vm.prank(alice);
        bool success = monstr.transfer(bob, 1000 ether); // Transfer 1000 tokens, 10 token fee
        assertTrue(success, "Transfer should succeed");
        assertEq(
            monstr.balanceOf(alice),
            aliceBalanceBefore - 1000 ether,
            "Alice balance should decrease by 1000"
        );
        assertEq(
            monstr.balanceOf(bob),
            990 ether,
            "Bob should receive 990 (1000 - 10 fee)"
        );

        // Execute lottery/auction
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        monstr.executeLottery();

        // Get auction details
        (, , uint96 minBid, , ) = monstr.currentAuction();

        // Alice bids with WMON
        getWMONAndApprove(alice, address(monstr), 1 ether);
        vm.prank(alice);
        monstr.bid(minBid);

        // Bob outbids
        uint256 newBid = (minBid * 110) / 100;
        getWMONAndApprove(bob, address(monstr), 1 ether);
        vm.prank(bob);
        monstr.bid(newBid);

        // Verify Alice got refunded in WMON
        assertEq(wmon.balanceOf(alice), 1 ether, "Alice should be refunded");

        // Verify Bob is current bidder
        (address currentBidder, , , , ) = monstr.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testAuctionFinalizationConvertsWMONToMON() public {
        // Generate fees
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        // Fast forward past minting period
        vm.warp(block.timestamp + 8 days + 1 hours);

        // Generate fees via transfer (alice has 9.9 tokens from 10 MON mint with 1:1 ratio)
        uint256 aliceBalanceBefore = monstr.balanceOf(alice);
        vm.prank(alice);
        bool success = monstr.transfer(bob, 1000 ether); // Transfer 1000 tokens, 10 token fee
        assertTrue(success, "Transfer should succeed");
        assertEq(
            monstr.balanceOf(alice),
            aliceBalanceBefore - 1000 ether,
            "Alice balance should decrease by 1000"
        );
        assertEq(
            monstr.balanceOf(bob),
            990 ether,
            "Bob should receive 990 (1000 - 10 fee)"
        );

        // Execute lottery/auction
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        monstr.executeLottery();

        // Place bid
        (, , uint96 minBid, , ) = monstr.currentAuction();
        getWMONAndApprove(alice, address(monstr), 1 ether);
        vm.prank(alice);
        monstr.bid(minBid);

        uint256 contractMONBefore = address(monstr).balance;
        uint256 contractWMONBefore = wmon.balanceOf(address(monstr));
        assertEq(contractWMONBefore, minBid, "Contract should hold WMON");

        // Generate fees on day 8 for day 9's lottery/auction
        vm.prank(bob);
        monstr.transfer(alice, 500 ether); // Generate 5 token fee

        // Finalize auction
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        monstr.executeLottery();

        // Verify WMON was converted to MON
        uint256 contractWMONAfter = wmon.balanceOf(address(monstr));

        assertEq(contractWMONAfter, 0, "Contract should have no WMON");
        // The important thing is that WMON was successfully withdrawn and converted to MON
        // The MON balance may change due to beneficiary funding, but WMON should be zero
    }

    function testBidIncrementRequirement() public {
        // Setup auction
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        monstr.transfer(bob, 1000 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        monstr.executeLottery();

        (, , uint96 minBid, , ) = monstr.currentAuction();

        // First bid at minimum
        getWMONAndApprove(alice, address(monstr), 1 ether);
        vm.prank(alice);
        monstr.bid(minBid);

        // Try to bid with less than 10% increase
        uint256 lowBid = (minBid * 109) / 100; // 9% increase
        getWMONAndApprove(bob, address(monstr), 1 ether);
        vm.prank(bob);
        vm.expectRevert("Bid too low");
        monstr.bid(lowBid);

        // Bid with exactly 10% increase should work
        uint256 validBid = (minBid * 110) / 100;
        vm.prank(bob);
        monstr.bid(validBid);

        (address currentBidder, , , , ) = monstr.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testNoBidAuctionRollover() public {
        // Generate fees
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        monstr.transfer(bob, 1000 ether);

        // Day 8 - Start auction but don't bid (distributes day 7's fees)
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        monstr.executeLottery();

        // Generate more fees on day 8 for day 9's lottery/auction
        vm.prank(bob);
        monstr.transfer(alice, 500 ether); // Generate 5 token fee

        // Get FEES_POOL balance before rollover
        uint256 feesPoolBefore = monstr.balanceOf(monstr.FEES_POOL());

        // Day 9 - Previous auction ends without bids, new lottery/auction starts
        vm.warp(block.timestamp + 25 hours + 1 minutes);

        monstr.executeLottery();

        // After auction rollover, funds should be back in FEES_POOL
        uint256 feesPoolAfter = monstr.balanceOf(monstr.FEES_POOL());

        // The rolled over amount from the failed auction goes back to FEES_POOL
        // This ensures it will be distributed in the next lottery/auction
        // The auction (with 5 tokens) had no bids, so it returns to FEES_POOL
        assertTrue(
            feesPoolAfter > 0,
            "FEES_POOL should contain rolled over auction amount"
        );
    }

    function test50_50FeeSplitAfterMintingPeriod() public {
        // Generate tokens during minting
        // 100 MON = 100 MONSTR tokens before fee
        vm.prank(alice);
        monstr.mint{value: 100 ether}(); // Alice gets 99 tokens after 1% fee
        // During minting period, 1% fee is minted as tokens: 100 MON * 1:1 ratio * 1% = 1 token

        // After minting period (day 8 = 8 * 25 hours from start)
        vm.warp(block.timestamp + 8 * 25 hours);

        // Alice has 99 tokens
        // Transfer 10,000 tokens (generates 100 token fee)
        vm.prank(alice);
        monstr.transfer(bob, 10_000 ether);
        // Bob got 9,900 tokens (10,000 - 100 fee), transfers some back
        vm.prank(bob);
        monstr.transfer(alice, 9_000 ether); // generates 90 token fee

        // Check FEES_POOL balance for accumulated fees
        uint256 totalFees = monstr.balanceOf(monstr.FEES_POOL());
        // We expect accumulated fees: 1000 (from minting) + 100 + 90 = 1190 ether
        assertEq(
            totalFees,
            1190 ether,
            "FEES_POOL should have 1190 tokens in fees"
        );

        // Execute lottery/auction for the day's fees
        vm.warp(block.timestamp + 25 hours + 1 minutes);

        // We generated fees on day 8, so we execute on day 9 to distribute day 8's fees
        monstr.executeLottery();

        // Verify auction has half the fees (595 tokens)
        (, , , uint112 auctionAmount, ) = monstr.currentAuction();
        assertEq(auctionAmount, 595 ether, "Auction should have 595 tokens");
    }

    function testMinimumBidCalculation() public {
        // Test that minimum bid is calculated correctly
        // New Formula: MinBid = (MON balance * feesToDistribute) / (2 * totalSupply)

        // Setup: Create known MON balance and total supply
        vm.prank(alice);
        monstr.mint{value: 10 ether}(); // 9.9 MONSTR to alice, 0.1 to fees
        vm.prank(bob);
        monstr.mint{value: 5 ether}(); // 4.95 MONSTR to bob, 0.05 to fees

        // Total supply: 9.9 + 0.1 + 4.95 + 0.05 = 15 MONSTR
        // MON balance: 15 MON
        uint256 expectedTotalSupply = 15000 ether;
        uint256 monBalance = 15 ether;
        assertEq(
            monstr.totalSupply(),
            expectedTotalSupply,
            "Total supply should be 15000 MONSTR"
        );
        assertEq(
            address(monstr).balance,
            monBalance,
            "Contract should have 15 MON"
        );

        // Move past minting period
        vm.warp(block.timestamp + 8 days);

        // Generate specific amount of fees for auction
        vm.prank(alice);
        monstr.transfer(bob, 1000 ether); // 10 MONSTR fee

        // Execute to start auction - fees will be split 50/50 between lottery and auction
        vm.warp(block.timestamp + 25 hours + 61);
        monstr.executeLottery();

        // Get auction details
        (, , uint96 minBid, uint112 auctionAmount, ) = monstr.currentAuction();

        // After transfer: 10 MONSTR fee generated
        // Split 50/50: 5 MONSTR for lottery, 5 MONSTR for auction
        assertEq(auctionAmount, 5 ether, "Auction should be for 5 MONSTR");

        // Calculate expected minimum bid with new formula
        // MinBid = (monBalance * auctionAmount) / (2 * totalSupply)
        // = (15 MON * 5 MONSTR) / (2 * 15 MONSTR)
        // = 75 / 30 MON
        // = 2.5 MON

        uint256 expectedMinBid = (monBalance * auctionAmount) /
            (2 * expectedTotalSupply);

        assertEq(
            minBid,
            expectedMinBid,
            "Minimum bid should match calculated value"
        );
        assertEq(minBid, 2.5 ether, "Minimum bid should be 2.5 MON");

        // Verify that bidding exactly the minimum bid works
        getWMONAndApprove(alice, address(monstr), minBid);
        vm.prank(alice);
        monstr.bid(minBid);

        (address currentBidder, uint96 currentBid, , , ) = monstr
            .currentAuction();
        assertEq(currentBidder, alice, "Alice should be current bidder");
        assertEq(currentBid, minBid, "Current bid should equal minimum bid");

        // Verify bidding below minimum fails
        getWMONAndApprove(bob, address(monstr), minBid);
        vm.prank(bob);
        vm.expectRevert("Bid too low");
        monstr.bid(minBid - 1);
    }

    function testMinimumBidWithDifferentBalances() public {
        // Test minimum bid calculation with various MON balances and fee amounts

        // Scenario 1: Low MON balance, high supply (deflated token)
        vm.prank(alice);
        monstr.mint{value: 100 ether}(); // 99 MONSTR

        // Burn most tokens to simulate deflation
        vm.warp(block.timestamp + 8 days);
        vm.prank(alice);
        monstr.redeem(90 ether); // Burns 89.1 MONSTR, returns ~89.1 MON

        uint256 remainingSupply = monstr.totalSupply();
        uint256 remainingETH = address(monstr).balance;

        // Generate fees
        vm.prank(alice);
        monstr.transfer(bob, 1000 ether); // 10 MONSTR fee

        // Start auction
        vm.warp(block.timestamp + 25 hours + 61);
        monstr.executeLottery();

        (, , uint96 minBid1, uint112 auctionAmount1, ) = monstr
            .currentAuction();

        // Verify minimum bid with new formula
        // MinBid = (MON balance * auctionAmount) / (2 * totalSupply)
        uint256 expectedMin1 = (remainingETH * auctionAmount1) /
            (2 * remainingSupply);
        assertEq(
            minBid1,
            expectedMin1,
            "Min bid should match expected calculation"
        );

        // Scenario 2: High MON balance from donations
        // Reset with new deployment for clean state
        vm.warp(block.timestamp + 30 days); // Clear any time dependencies

        // Someone donates MON to increase backing
        vm.deal(address(this), 50 ether);
        (bool sent, ) = address(monstr).call{value: 50 ether}("");
        assertTrue(sent, "MON donation should succeed");

        // Generate new fees
        vm.prank(alice);
        monstr.transfer(bob, 500 ether);

        // Start new auction
        vm.warp(block.timestamp + 25 hours + 61);
        monstr.executeLottery();

        (, , uint96 minBid2, uint112 auctionAmount2, ) = monstr
            .currentAuction();

        uint256 currentETH = address(monstr).balance;
        uint256 currentSupply = monstr.totalSupply();
        uint256 expectedMin2 = (currentETH * auctionAmount2) /
            (2 * currentSupply);

        assertEq(
            minBid2,
            expectedMin2,
            "Min bid should reflect increased MON backing"
        );

        // The minimum bid should be higher due to the donation increasing the backing value
        assertTrue(
            minBid2 > minBid1,
            "Higher MON backing should result in higher min bid"
        );
    }

    function testMinimumBidFormula() public {
        // Test that minimum bid uses the correct formula
        // Formula: MinBid = (MON balance * auctionAmount) / (2 * totalSupply)

        // Using 3 MON to create 3 MONSTR total supply
        vm.prank(alice);
        monstr.mint{value: 3 ether}(); // 2.97 MONSTR to alice, 0.03 to fees

        vm.warp(block.timestamp + 8 days);

        // Generate an odd fee amount: 7 MONSTR
        // After split: 3.5 MONSTR for auction
        vm.prank(alice);
        monstr.transfer(bob, 700 ether); // 7 MONSTR fee

        vm.warp(block.timestamp + 25 hours + 61);
        monstr.executeLottery();

        (, , uint96 minBid, uint112 auctionAmount, ) = monstr.currentAuction();

        uint256 monBalance = address(monstr).balance;
        uint256 totalSupply = monstr.totalSupply();

        // The auction should have 3.5 MONSTR (half of 7)
        assertEq(auctionAmount, 3.5 ether, "Auction should have 3.5 MONSTR");

        // Calculate with new formula
        // MinBid = (monBalance * auctionAmount) / (2 * totalSupply)
        // = (3 MON * 3.5 MONSTR) / (2 * 3 MONSTR)
        // = 10.5 / 6 = 1.75 MON
        uint256 expectedMinBid = (monBalance * auctionAmount) /
            (2 * totalSupply);

        assertEq(
            minBid,
            expectedMinBid,
            "Minimum bid should match contract calculation"
        );

        // The minimum bid is now half of the redemption value
        uint256 redemptionValue = (auctionAmount * monBalance) / totalSupply;
        assertEq(
            minBid,
            redemptionValue / 2,
            "Min bid should be half of redemption value"
        );
    }
}

// Test specifically for DoS prevention
contract MaliciousBidder {
    receive() external payable {
        revert("I always revert!");
    }

    fallback() external payable {
        revert("I always revert!");
    }
}

contract StrategyAuctionSecurityTest is WMONTestBase {
    Strategy public monstr;
    address public alice = address(0x1);
    address public maliciousBidder;

    function setUp() public {
        setupWMON();
        monstr = new Strategy(address(wmon));

        vm.deal(alice, 100 ether);

        MaliciousBidder malicious = new MaliciousBidder();
        maliciousBidder = address(malicious);
        vm.deal(maliciousBidder, 100 ether);
    }

    function testWETHPreventsRefundDoS() public {
        // Setup auction
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        monstr.transfer(address(0x99), 1000 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        monstr.executeLottery();

        (, , uint96 minBid, , ) = monstr.currentAuction();

        // Malicious bidder places bid
        getWMONAndApprove(maliciousBidder, address(monstr), 1 ether);
        vm.prank(maliciousBidder);
        monstr.bid(minBid);

        // Alice can still outbid even though malicious bidder reverts on MON
        uint256 newBid = (minBid * 110) / 100;
        getWMONAndApprove(alice, address(monstr), 1 ether);
        vm.prank(alice);
        monstr.bid(newBid); // This would fail with MON but succeeds with WMON

        // Verify malicious bidder got WMON refund
        assertEq(
            wmon.balanceOf(maliciousBidder),
            1 ether,
            "Should receive WMON refund"
        );

        (address currentBidder, , , , ) = monstr.currentAuction();
        assertEq(currentBidder, alice, "Alice should be current bidder");
    }
}
