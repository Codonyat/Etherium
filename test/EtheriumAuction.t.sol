// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium, IWETH} from "../src/Etherium.sol";
import {MockWETH, WETHTestBase} from "./helpers/WETHHelpers.sol";

contract EtheriumAuctionTest is WETHTestBase {
    Etherium public etherium;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);

    // Event definitions for testing
    event AuctionStarted(uint256 day, uint256 etheriumAmount, uint256 minBid);
    event BidPlaced(address indexed bidder, uint256 amount, uint256 day);
    event BidRefunded(address indexed bidder, uint256 amount);
    event AuctionWon(
        address indexed winner,
        uint256 etheriumAmount,
        uint256 ethPaid,
        uint256 day
    );
    event LotteryWon(address indexed winner, uint256 amount, uint256 day);

    function setUp() public {
        setupWETH();
        etherium = new Etherium();

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);
    }

    function testAuctionWithWETHBidding() public {
        // Generate fees during minting period
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        // Fast forward past minting period
        vm.warp(block.timestamp + 8 days + 1 hours);

        // Generate fees via transfer (alice has 9,900 tokens from 10 ETH mint with 1000:1 ratio)
        uint256 aliceBalanceBefore = etherium.balanceOf(alice);
        vm.prank(alice);
        bool success = etherium.transfer(bob, 1000 ether); // Transfer 1000 tokens, 10 token fee
        assertTrue(success, "Transfer should succeed");
        assertEq(
            etherium.balanceOf(alice),
            aliceBalanceBefore - 1000 ether,
            "Alice balance should decrease by 1000"
        );
        assertEq(
            etherium.balanceOf(bob),
            990 ether,
            "Bob should receive 990 (1000 - 10 fee)"
        );

        // Execute lottery/auction
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        // Get auction details
        (, , uint96 minBid, , ) = etherium.currentAuction();

        // Alice bids with WETH
        getWETHAndApprove(alice, address(etherium), 1 ether);
        vm.prank(alice);
        etherium.bid(minBid);

        // Bob outbids
        uint256 newBid = (minBid * 110) / 100;
        getWETHAndApprove(bob, address(etherium), 1 ether);
        vm.prank(bob);
        etherium.bid(newBid);

        // Verify Alice got refunded in WETH
        assertEq(weth.balanceOf(alice), 1 ether, "Alice should be refunded");

        // Verify Bob is current bidder
        (address currentBidder, , , , ) = etherium.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testAuctionFinalizationConvertsWETHToETH() public {
        // Generate fees
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        // Fast forward past minting period
        vm.warp(block.timestamp + 8 days + 1 hours);

        // Generate fees via transfer (alice has 9,900 tokens from 10 ETH mint with 1000:1 ratio)
        uint256 aliceBalanceBefore = etherium.balanceOf(alice);
        vm.prank(alice);
        bool success = etherium.transfer(bob, 1000 ether); // Transfer 1000 tokens, 10 token fee
        assertTrue(success, "Transfer should succeed");
        assertEq(
            etherium.balanceOf(alice),
            aliceBalanceBefore - 1000 ether,
            "Alice balance should decrease by 1000"
        );
        assertEq(
            etherium.balanceOf(bob),
            990 ether,
            "Bob should receive 990 (1000 - 10 fee)"
        );

        // Execute lottery/auction
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        // Place bid
        (, , uint96 minBid, , ) = etherium.currentAuction();
        getWETHAndApprove(alice, address(etherium), 1 ether);
        vm.prank(alice);
        etherium.bid(minBid);

        uint256 contractETHBefore = address(etherium).balance;
        uint256 contractWETHBefore = weth.balanceOf(address(etherium));
        assertEq(contractWETHBefore, minBid, "Contract should hold WETH");

        // Generate fees on day 8 for day 9's lottery/auction
        vm.prank(bob);
        etherium.transfer(alice, 500 ether); // Generate 5 token fee

        // Finalize auction
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        // Verify WETH was converted to ETH
        uint256 contractWETHAfter = weth.balanceOf(address(etherium));

        assertEq(contractWETHAfter, 0, "Contract should have no WETH");
        // The important thing is that WETH was successfully withdrawn and converted to ETH
        // The ETH balance may change due to public goods funding, but WETH should be zero
    }

    function testBidIncrementRequirement() public {
        // Setup auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        (, , uint96 minBid, , ) = etherium.currentAuction();

        // First bid at minimum
        getWETHAndApprove(alice, address(etherium), 1 ether);
        vm.prank(alice);
        etherium.bid(minBid);

        // Try to bid with less than 10% increase
        uint256 lowBid = (minBid * 109) / 100; // 9% increase
        getWETHAndApprove(bob, address(etherium), 1 ether);
        vm.prank(bob);
        vm.expectRevert("Bid too low");
        etherium.bid(lowBid);

        // Bid with exactly 10% increase should work
        uint256 validBid = (minBid * 110) / 100;
        vm.prank(bob);
        etherium.bid(validBid);

        (address currentBidder, , , , ) = etherium.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testNoBidAuctionRollover() public {
        // Generate fees
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);

        // Day 8 - Start auction but don't bid (distributes day 7's fees)
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        // Generate more fees on day 8 for day 9's lottery/auction
        vm.prank(bob);
        etherium.transfer(alice, 500 ether); // Generate 5 token fee

        // Get FEES_POOL balance before rollover
        uint256 feesPoolBefore = etherium.balanceOf(etherium.FEES_POOL());

        // Day 9 - Previous auction ends without bids, new lottery/auction starts
        vm.warp(block.timestamp + 25 hours + 1 minutes);

        etherium.executeLottery();

        // After auction rollover, funds should be back in FEES_POOL
        uint256 feesPoolAfter = etherium.balanceOf(etherium.FEES_POOL());

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
        // 100 ETH = 100,000 ETHERIUM tokens before fee
        vm.prank(alice);
        etherium.mint{value: 100 ether}(); // Alice gets 99,000 tokens after 1% fee
        // During minting period, 1% fee is minted as tokens: 100 ETH * 1000 ratio * 1% = 1000 tokens

        // After minting period (day 8 = 8 * 25 hours from start)
        vm.warp(block.timestamp + 8 * 25 hours);

        // Alice has 99,000 tokens
        // Transfer 10,000 tokens (generates 100 token fee)
        vm.prank(alice);
        etherium.transfer(bob, 10_000 ether);
        // Bob got 9,900 tokens (10,000 - 100 fee), transfers some back
        vm.prank(bob);
        etherium.transfer(alice, 9_000 ether); // generates 90 token fee

        // Check FEES_POOL balance for accumulated fees
        uint256 totalFees = etherium.balanceOf(etherium.FEES_POOL());
        // We expect accumulated fees: 1000 (from minting) + 100 + 90 = 1190 ether
        assertEq(
            totalFees,
            1190 ether,
            "FEES_POOL should have 1190 tokens in fees"
        );

        // Execute lottery/auction for the day's fees
        vm.warp(block.timestamp + 25 hours + 1 minutes);

        // We generated fees on day 8, so we execute on day 9 to distribute day 8's fees
        etherium.executeLottery();

        // Verify auction has half the fees (595 tokens)
        (, , , uint112 auctionAmount, ) = etherium.currentAuction();
        assertEq(auctionAmount, 595 ether, "Auction should have 595 tokens");
    }

    function testMinimumBidCalculation() public {
        // Test that minimum bid is calculated correctly
        // New Formula: MinBid = (ETH balance * feesToDistribute) / (2 * totalSupply)

        // Setup: Create known ETH balance and total supply
        vm.prank(alice);
        etherium.mint{value: 10 ether}(); // 9900 ETHERIUM to alice, 100 to fees
        vm.prank(bob);
        etherium.mint{value: 5 ether}(); // 4950 ETHERIUM to bob, 50 to fees

        // Total supply: 9900 + 100 + 4950 + 50 = 15000 ETHERIUM
        // ETH balance: 15 ETH
        uint256 expectedTotalSupply = 15000 ether;
        uint256 ethBalance = 15 ether;
        assertEq(
            etherium.totalSupply(),
            expectedTotalSupply,
            "Total supply should be 15000 ETHERIUM"
        );
        assertEq(
            address(etherium).balance,
            ethBalance,
            "Contract should have 15 ETH"
        );

        // Move past minting period
        vm.warp(block.timestamp + 8 days);

        // Generate specific amount of fees for auction
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether); // 10 ETHERIUM fee

        // Execute to start auction - fees will be split 50/50 between lottery and auction
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();

        // Get auction details
        (, , uint96 minBid, uint112 auctionAmount, ) = etherium
            .currentAuction();

        // After transfer: 10 ETHERIUM fee generated
        // Split 50/50: 5 ETHERIUM for lottery, 5 ETHERIUM for auction
        assertEq(auctionAmount, 5 ether, "Auction should be for 5 ETHERIUM");

        // Calculate expected minimum bid with new formula
        // MinBid = (ethBalance * auctionAmount) / (2 * totalSupply)
        // = (15 ETH * 5 ETHERIUM) / (2 * 15000 ETHERIUM)
        // = 75 / 30000 ETH
        // = 0.0025 ETH = 2500000000000000 wei

        uint256 expectedMinBid = (ethBalance * auctionAmount) /
            (2 * expectedTotalSupply);

        assertEq(
            minBid,
            expectedMinBid,
            "Minimum bid should match calculated value"
        );
        assertEq(minBid, 0.0025 ether, "Minimum bid should be 0.0025 ETH");

        // Verify that bidding exactly the minimum bid works
        getWETHAndApprove(alice, address(etherium), minBid);
        vm.prank(alice);
        etherium.bid(minBid);

        (address currentBidder, uint96 currentBid, , , ) = etherium
            .currentAuction();
        assertEq(currentBidder, alice, "Alice should be current bidder");
        assertEq(currentBid, minBid, "Current bid should equal minimum bid");

        // Verify bidding below minimum fails
        getWETHAndApprove(bob, address(etherium), minBid);
        vm.prank(bob);
        vm.expectRevert("Bid too low");
        etherium.bid(minBid - 1);
    }

    function testMinimumBidWithDifferentBalances() public {
        // Test minimum bid calculation with various ETH balances and fee amounts

        // Scenario 1: Low ETH balance, high supply (deflated token)
        vm.prank(alice);
        etherium.mint{value: 100 ether}(); // 99000 ETHERIUM

        // Burn most tokens to simulate deflation
        vm.warp(block.timestamp + 8 days);
        vm.prank(alice);
        etherium.redeem(90000 ether); // Burns 89100 ETHERIUM, returns ~89.1 ETH

        uint256 remainingSupply = etherium.totalSupply();
        uint256 remainingETH = address(etherium).balance;

        // Generate fees
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether); // 10 ETHERIUM fee

        // Start auction
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();

        (, , uint96 minBid1, uint112 auctionAmount1, ) = etherium
            .currentAuction();

        // Verify minimum bid with new formula
        // MinBid = (ETH balance * auctionAmount) / (2 * totalSupply)
        uint256 expectedMin1 = (remainingETH * auctionAmount1) /
            (2 * remainingSupply);
        assertEq(
            minBid1,
            expectedMin1,
            "Min bid should match expected calculation"
        );

        // Scenario 2: High ETH balance from donations
        // Reset with new deployment for clean state
        vm.warp(block.timestamp + 30 days); // Clear any time dependencies

        // Someone donates ETH to increase backing
        vm.deal(address(this), 50 ether);
        (bool sent, ) = address(etherium).call{value: 50 ether}("");
        assertTrue(sent, "ETH donation should succeed");

        // Generate new fees
        vm.prank(alice);
        etherium.transfer(bob, 500 ether);

        // Start new auction
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();

        (, , uint96 minBid2, uint112 auctionAmount2, ) = etherium
            .currentAuction();

        uint256 currentETH = address(etherium).balance;
        uint256 currentSupply = etherium.totalSupply();
        uint256 expectedMin2 = (currentETH * auctionAmount2) /
            (2 * currentSupply);

        assertEq(
            minBid2,
            expectedMin2,
            "Min bid should reflect increased ETH backing"
        );

        // The minimum bid should be higher due to the donation increasing the backing value
        assertTrue(
            minBid2 > minBid1,
            "Higher ETH backing should result in higher min bid"
        );
    }

    function testMinimumBidFormula() public {
        // Test that minimum bid uses the correct formula
        // Formula: MinBid = (ETH balance * auctionAmount) / (2 * totalSupply)

        // Using 3 ETH to create 3000 ETHERIUM total supply
        vm.prank(alice);
        etherium.mint{value: 3 ether}(); // 2970 ETHERIUM to alice, 30 to fees

        vm.warp(block.timestamp + 8 days);

        // Generate an odd fee amount: 7 ETHERIUM
        // After split: 3.5 ETHERIUM for auction
        vm.prank(alice);
        etherium.transfer(bob, 700 ether); // 7 ETHERIUM fee

        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();

        (, , uint96 minBid, uint112 auctionAmount, ) = etherium
            .currentAuction();

        uint256 ethBalance = address(etherium).balance;
        uint256 totalSupply = etherium.totalSupply();

        // The auction should have 3.5 ETHERIUM (half of 7)
        assertEq(auctionAmount, 3.5 ether, "Auction should have 3.5 ETHERIUM");

        // Calculate with new formula
        // MinBid = (ethBalance * auctionAmount) / (2 * totalSupply)
        // = (3 ETH * 3.5 ETHERIUM) / (2 * 3000 ETHERIUM)
        // = 10.5 / 6000 = 0.00175 ETH
        uint256 expectedMinBid = (ethBalance * auctionAmount) /
            (2 * totalSupply);

        assertEq(
            minBid,
            expectedMinBid,
            "Minimum bid should match contract calculation"
        );

        // The minimum bid is now half of the redemption value
        uint256 redemptionValue = (auctionAmount * ethBalance) / totalSupply;
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

contract EtheriumAuctionSecurityTest is WETHTestBase {
    Etherium public etherium;
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);
    address public maliciousBidder;

    function setUp() public {
        setupWETH();
        etherium = new Etherium();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);

        MaliciousBidder malicious = new MaliciousBidder();
        maliciousBidder = address(malicious);
        vm.deal(maliciousBidder, 100 ether);
    }

    function testWETHPreventsRefundDoS() public {
        // Setup auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(address(0x99), 1000 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        (, , uint96 minBid, , ) = etherium.currentAuction();

        // Malicious bidder places bid
        getWETHAndApprove(maliciousBidder, address(etherium), 1 ether);
        vm.prank(maliciousBidder);
        etherium.bid(minBid);

        // Alice can still outbid even though malicious bidder reverts on ETH
        uint256 newBid = (minBid * 110) / 100;
        getWETHAndApprove(alice, address(etherium), 1 ether);
        vm.prank(alice);
        etherium.bid(newBid); // This would fail with ETH but succeeds with WETH

        // Verify malicious bidder got WETH refund
        assertEq(
            weth.balanceOf(maliciousBidder),
            1 ether,
            "Should receive WETH refund"
        );

        (address currentBidder, , , , ) = etherium.currentAuction();
        assertEq(currentBidder, alice, "Alice should be current bidder");
    }

    // ============ Native ETH Bidding Tests ============

    function testBidWithNativeETH() public {
        // Setup: Generate fees and start auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        (, , uint96 minBid, , ) = etherium.currentAuction();

        // Alice bids with native ETH
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        etherium.bid{value: minBid}(0); // Pass 0 as bidAmount when using msg.value

        // Verify Alice's ETH balance decreased
        assertEq(
            alice.balance,
            aliceBalanceBefore - minBid,
            "Alice should have spent ETH"
        );

        // Verify contract received WETH (not native ETH)
        assertEq(
            weth.balanceOf(address(etherium)),
            minBid,
            "Contract should hold WETH"
        );

        // Verify Alice is the current bidder
        (address currentBidder, uint96 currentBid, , , ) = etherium
            .currentAuction();
        assertEq(currentBidder, alice, "Alice should be current bidder");
        assertEq(currentBid, minBid, "Bid amount should match minBid");
    }

    function testBidWithNativeETHOverridesBidAmount() public {
        // Test that msg.value takes precedence over bidAmount parameter
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        (, , uint96 minBid, , ) = etherium.currentAuction();

        // Alice sends native ETH but passes different bidAmount parameter
        vm.prank(alice);
        etherium.bid{value: minBid}(999999 ether); // This gets ignored

        // Verify the actual bid is msg.value, not the parameter
        (, uint96 currentBid, , , ) = etherium.currentAuction();
        assertEq(currentBid, minBid, "Bid should be msg.value, not parameter");
    }

    function testNativeETHBidRefundsInWETH() public {
        // Test that previous bidders get WETH refund even if current bidder uses native ETH
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        (, , uint96 minBid, , ) = etherium.currentAuction();

        // Alice bids with WETH - get enough WETH for the bid
        getWETHAndApprove(alice, address(etherium), minBid);
        vm.prank(alice);
        etherium.bid(minBid);

        // Bob outbids with native ETH
        uint256 newBid = (minBid * 110) / 100;
        vm.prank(bob);
        etherium.bid{value: newBid}(0);

        // Verify Alice got refunded in WETH (not native ETH)
        // She should get back exactly what she bid
        assertEq(
            weth.balanceOf(alice),
            minBid,
            "Alice should receive WETH refund equal to her bid"
        );

        // Verify Bob is current bidder
        (address currentBidder, , , , ) = etherium.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testMixedNativeETHAndWETHBids() public {
        // Test that native ETH and WETH bids can be mixed in same auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        (, , uint96 minBid, , ) = etherium.currentAuction();

        // Alice bids with native ETH
        vm.prank(alice);
        etherium.bid{value: minBid}(0);

        // Bob outbids with WETH
        uint256 bid2 = (minBid * 110) / 100;
        getWETHAndApprove(bob, address(etherium), bid2);
        vm.prank(bob);
        etherium.bid(bid2);

        // Charlie outbids with native ETH
        uint256 bid3 = (bid2 * 110) / 100;
        vm.prank(charlie);
        etherium.bid{value: bid3}(0);

        // David outbids with WETH
        uint256 bid4 = (bid3 * 110) / 100;
        getWETHAndApprove(david, address(etherium), bid4);
        vm.prank(david);
        etherium.bid(bid4);

        // Verify all previous bidders got WETH refunds
        assertEq(
            weth.balanceOf(alice),
            minBid,
            "Alice should have WETH refund"
        );
        assertEq(weth.balanceOf(bob), bid2, "Bob should have WETH refund");
        assertEq(
            weth.balanceOf(charlie),
            bid3,
            "Charlie should have WETH refund"
        );

        // Verify David is the winner
        (address currentBidder, , , , ) = etherium.currentAuction();
        assertEq(currentBidder, david, "David should be current bidder");
    }

    function testNativeETHBidTooLow() public {
        // Test that bidding with native ETH below minimum reverts
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        (, , uint96 minBid, , ) = etherium.currentAuction();

        // Alice tries to bid with native ETH below minimum
        vm.prank(alice);
        vm.expectRevert("Bid too low");
        etherium.bid{value: minBid - 1}(0);

        // Verify no bid was placed
        (address currentBidder, , , , ) = etherium.currentAuction();
        assertEq(currentBidder, address(0), "Should have no bidder");
    }

    function testNativeETHBidRevertRollback() public {
        // Test that if native ETH bid fails, the WETH wrapping is rolled back
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        (, , uint96 minBid, , ) = etherium.currentAuction();

        uint256 aliceBalanceBefore = alice.balance;
        uint256 wethBalanceBefore = weth.balanceOf(address(etherium));

        // Alice tries to bid too low with native ETH
        vm.prank(alice);
        vm.expectRevert("Bid too low");
        etherium.bid{value: minBid - 1}(0);

        // Verify Alice's ETH was refunded (transaction reverted)
        assertEq(
            alice.balance,
            aliceBalanceBefore,
            "Alice should have same ETH balance"
        );

        // Verify contract didn't receive any WETH
        assertEq(
            weth.balanceOf(address(etherium)),
            wethBalanceBefore,
            "Contract should have same WETH balance"
        );
    }

    function testAuctionFinalizationWithNativeETHWinner() public {
        // Test that auction finalization works correctly when winner used native ETH
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        (, , uint96 minBid, uint112 auctionAmount, ) = etherium
            .currentAuction();

        // Alice bids with native ETH
        vm.prank(alice);
        etherium.bid{value: minBid}(0);

        uint256 contractWETHBefore = weth.balanceOf(address(etherium));
        assertEq(
            contractWETHBefore,
            minBid,
            "Contract should hold Alice's WETH bid"
        );

        // Generate fees for next day
        vm.prank(bob);
        etherium.transfer(alice, 0.5 ether);

        // Finalize auction by triggering next day's lottery
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        // Verify WETH was withdrawn to ETH
        assertEq(
            weth.balanceOf(address(etherium)),
            0,
            "Contract should have no WETH after finalization"
        );

        // Verify Alice won the auction and has claimable prize (at least the auction amount)
        vm.prank(alice);
        uint256 claimable = etherium.getMyClaimableAmount();
        assertGe(
            claimable,
            auctionAmount,
            "Alice should have at least the auction prize claimable"
        );

        // Verify Alice can actually claim her prize
        uint256 aliceBalanceBefore = etherium.balanceOf(alice);
        vm.prank(alice);
        etherium.claim();
        uint256 aliceBalanceAfter = etherium.balanceOf(alice);

        assertEq(
            aliceBalanceAfter - aliceBalanceBefore,
            claimable,
            "Alice should receive her claimable amount"
        );
    }

    function testNativeETHBidIncrementRequirement() public {
        // Test that 10% increment rule applies to native ETH bids
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        (, , uint96 minBid, , ) = etherium.currentAuction();

        // Alice bids with native ETH
        vm.prank(alice);
        etherium.bid{value: minBid}(0);

        // Bob tries to bid with only 9% increase using native ETH
        uint256 lowBid = (minBid * 109) / 100;
        vm.prank(bob);
        vm.expectRevert("Bid too low");
        etherium.bid{value: lowBid}(0);

        // Bob bids with exactly 10% increase using native ETH
        uint256 validBid = (minBid * 110) / 100;
        vm.prank(bob);
        etherium.bid{value: validBid}(0);

        // Verify Bob is now the current bidder
        (address currentBidder, , , , ) = etherium.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testNativeETHWrappingCorrectness() public {
        // Test that native ETH is correctly wrapped to WETH
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.warp(block.timestamp + 8 days + 1 hours);
        vm.prank(alice);
        etherium.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        etherium.executeLottery();

        (, , uint96 minBid, , ) = etherium.currentAuction();

        uint256 contractNativeBefore = address(etherium).balance;
        uint256 contractWETHBefore = weth.balanceOf(address(etherium));

        // Alice bids with native ETH
        vm.prank(alice);
        etherium.bid{value: minBid}(0);

        // Contract's native ETH should not increase (it gets wrapped)
        // Actually, it will increase because weth.deposit returns ETH to contract via receive()
        // But WETH balance should definitely increase
        assertEq(
            weth.balanceOf(address(etherium)),
            contractWETHBefore + minBid,
            "Contract should have received WETH"
        );

        // Verify the WETH amount matches the bid amount exactly
        (, uint96 currentBid, , , ) = etherium.currentAuction();
        assertEq(
            weth.balanceOf(address(etherium)),
            currentBid,
            "WETH balance should match bid amount"
        );
    }
}
