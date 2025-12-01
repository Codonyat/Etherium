// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy, IWMEGA} from "../src/Strategy.sol";
import {MockWMEGA, WMEGATestBase} from "././helpers/WSTRATHelpers.sol";

contract StrategyAuctionTest is WMEGATestBase {
    Strategy public giga;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public david = address(0x4);

    // Event definitions for testing
    event AuctionStarted(uint256 day, uint256 gigaAmount, uint256 minBid);
    event BidPlaced(address indexed bidder, uint256 amount, uint256 day);
    event BidRefunded(address indexed bidder, uint256 amount);
    event AuctionWon(
        address indexed winner,
        uint256 gigaAmount,
        uint256 megaPaid,
        uint256 day
    );
    event LotteryWon(address indexed winner, uint256 amount, uint256 day);

    function setUp() public {
        setupWMEGA();
        giga = new Strategy(address(wmega));

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);
    }

    function testAuctionWithWrappedBidding() public {
        // Generate fees during minting period
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        // Fast forward past minting period
        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);

        // Generate fees via transfer (alice has 9.9 tokens from 10 MEGA mint with 1:1 ratio)
        uint256 aliceBalanceBefore = giga.balanceOf(alice);
        vm.prank(alice);
        bool success = giga.transfer(bob, 1 ether); // Transfer 1 token, 0.01 token fee
        assertTrue(success, "Transfer should succeed");
        assertEq(
            giga.balanceOf(alice),
            aliceBalanceBefore - 1 ether,
            "Alice balance should decrease by 1"
        );
        assertEq(
            giga.balanceOf(bob),
            0.99 ether,
            "Bob should receive 0.99 (1 - 0.01 fee)"
        );

        // Execute lottery/auction
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        // Get auction details
        (, , uint96 minBid, , ) = giga.currentAuction();

        // Alice bids with wrapped token
        getWMEGAAndApprove(alice, address(giga), 1 ether);
        vm.prank(alice);
        giga.bid(minBid);

        // Bob outbids
        uint256 newBid = (minBid * 110) / 100;
        getWMEGAAndApprove(bob, address(giga), 1 ether);
        vm.prank(bob);
        giga.bid(newBid);

        // Verify Alice got refunded in wrapped token
        assertEq(wmega.balanceOf(alice), 1 ether, "Alice should be refunded");

        // Verify Bob is current bidder
        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testAuctionFinalizationConvertsWrappedToNative() public {
        // Generate fees
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        // Fast forward past minting period
        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);

        // Generate fees via transfer (alice has 9.9 tokens from 10 MEGA mint with 1:1 ratio)
        uint256 aliceBalanceBefore = giga.balanceOf(alice);
        vm.prank(alice);
        bool success = giga.transfer(bob, 1 ether); // Transfer 1 token, 0.01 token fee
        assertTrue(success, "Transfer should succeed");
        assertEq(
            giga.balanceOf(alice),
            aliceBalanceBefore - 1 ether,
            "Alice balance should decrease by 1"
        );
        assertEq(
            giga.balanceOf(bob),
            0.99 ether,
            "Bob should receive 0.99 (1 - 0.01 fee)"
        );

        // Execute lottery/auction
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        // Place bid
        (, , uint96 minBid, , ) = giga.currentAuction();
        getWMEGAAndApprove(alice, address(giga), 1 ether);
        vm.prank(alice);
        giga.bid(minBid);

        uint256 contractNativeBefore = address(giga).balance;
        uint256 contractWrappedBefore = wmega.balanceOf(address(giga));
        assertEq(contractWrappedBefore, minBid, "Contract should hold wrapped token");

        // Generate fees on day 8 for day 9's lottery/auction
        vm.prank(bob);
        giga.transfer(alice, 0.5 ether); // Generate 0.005 token fee

        // Finalize auction
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        // Verify wrapped token was converted to native
        uint256 contractWrappedAfter = wmega.balanceOf(address(giga));

        assertEq(contractWrappedAfter, 0, "Contract should have no wrapped token");
        // The important thing is that wrapped token was successfully withdrawn and converted to native
        // The native balance may change due to beneficiary funding, but wrapped should be zero
    }

    function testBidIncrementRequirement() public {
        // Setup auction
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // First bid at minimum
        getWMEGAAndApprove(alice, address(giga), 1 ether);
        vm.prank(alice);
        giga.bid(minBid);

        // Try to bid with less than 10% increase
        uint256 lowBid = (minBid * 109) / 100; // 9% increase
        getWMEGAAndApprove(bob, address(giga), 1 ether);
        vm.prank(bob);
        vm.expectRevert("Bid too low");
        giga.bid(lowBid);

        // Bid with exactly 10% increase should work
        uint256 validBid = (minBid * 110) / 100;
        vm.prank(bob);
        giga.bid(validBid);

        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testNoBidAuctionRollover() public {
        // Generate fees
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        // Day 8 - Start auction but don't bid (distributes day 7's fees)
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        // Generate more fees on day 8 for day 9's lottery/auction
        vm.prank(bob);
        giga.transfer(alice, 0.5 ether); // Generate 0.005 token fee

        // Get FEES_POOL balance before rollover
        uint256 feesPoolBefore = giga.balanceOf(giga.FEES_POOL());

        // Day 9 - Previous auction ends without bids, new lottery/auction starts
        vm.warp(block.timestamp + 25 hours + 1 minutes);

        giga.executeLottery();

        // After auction rollover, funds should be back in FEES_POOL
        uint256 feesPoolAfter = giga.balanceOf(giga.FEES_POOL());

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
        // 100 MEGA = 100 GIGA tokens before fee
        vm.prank(alice);
        giga.mint{value: 100 ether}(); // Alice gets 99 tokens after 1% fee
        // During minting period, 1% fee is minted as tokens: 100 MEGA * 1:1 ratio * 1% = 1 token

        // After minting period (day 8 = 8 * 25 hours from start)
        vm.warp(block.timestamp + 8 * 25 hours);

        // Alice has 99 tokens
        // Transfer 10 tokens (generates 0.1 token fee)
        vm.prank(alice);
        giga.transfer(bob, 10 ether);
        // Bob got 9.9 tokens (10 - 0.1 fee), transfers some back
        vm.prank(bob);
        giga.transfer(alice, 9 ether); // generates 0.09 token fee

        // Check FEES_POOL balance for accumulated fees
        uint256 totalFees = giga.balanceOf(giga.FEES_POOL());
        // We expect accumulated fees: 1 (from minting) + 0.1 + 0.09 = 1.19 ether
        assertEq(
            totalFees,
            1.19 ether,
            "FEES_POOL should have 1.19 tokens in fees"
        );

        // Execute lottery/auction for the day's fees
        vm.warp(block.timestamp + 25 hours + 1 minutes);

        // We generated fees on day 8, so we execute on day 9 to distribute day 8's fees
        giga.executeLottery();

        // Verify auction has half the fees (0.595 tokens)
        (, , , uint112 auctionAmount, ) = giga.currentAuction();
        assertEq(auctionAmount, 0.595 ether, "Auction should have 0.595 tokens");
    }

    function testMinimumBidCalculation() public {
        // Test that minimum bid is calculated correctly
        // New Formula: MinBid = (native balance * feesToDistribute) / (2 * totalSupply)

        // Setup: Create known MEGA balance and total supply
        vm.prank(alice);
        giga.mint{value: 10 ether}(); // 9.9 GIGA to alice, 0.1 to fees
        vm.prank(bob);
        giga.mint{value: 5 ether}(); // 4.95 GIGA to bob, 0.05 to fees

        // Total supply: 9.9 + 0.1 + 4.95 + 0.05 = 15 GIGA
        // MEGA balance: 15 MEGA
        uint256 expectedTotalSupply = 15 ether;
        uint256 megaBalance = 15 ether;
        assertEq(
            giga.totalSupply(),
            expectedTotalSupply,
            "Total supply should be 15 GIGA"
        );
        assertEq(
            address(giga).balance,
            megaBalance,
            "Contract should have 15 MEGA"
        );

        // Move past minting period
        skipPastMintingPeriod(giga);

        // Generate specific amount of fees for auction
        vm.prank(alice);
        giga.transfer(bob, 1 ether); // 0.01 GIGA fee

        // Execute to start auction - fees will be split 50/50 between lottery and auction
        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        // Get auction details
        (, , uint96 minBid, uint112 auctionAmount, ) = giga.currentAuction();

        // After transfer: 0.01 GIGA fee generated
        // Split 50/50: 0.005 GIGA for lottery, 0.005 GIGA for auction
        assertEq(auctionAmount, 0.005 ether, "Auction should be for 0.005 GIGA");

        // Calculate expected minimum bid with new formula
        // MinBid = (megaBalance * auctionAmount) / (2 * totalSupply)
        // = (15 MEGA * 0.005 GIGA) / (2 * 15 GIGA)
        // = 0.075 / 30 MEGA
        // = 0.0025 MEGA

        uint256 expectedMinBid = (megaBalance * auctionAmount) /
            (2 * expectedTotalSupply);

        assertEq(
            minBid,
            expectedMinBid,
            "Minimum bid should match calculated value"
        );
        assertEq(minBid, 0.0025 ether, "Minimum bid should be 0.0025 MEGA");

        // Verify that bidding exactly the minimum bid works
        getWMEGAAndApprove(alice, address(giga), minBid);
        vm.prank(alice);
        giga.bid(minBid);

        (address currentBidder, uint96 currentBid, , , ) = giga
            .currentAuction();
        assertEq(currentBidder, alice, "Alice should be current bidder");
        assertEq(currentBid, minBid, "Current bid should equal minimum bid");

        // Verify bidding below minimum fails
        getWMEGAAndApprove(bob, address(giga), minBid);
        vm.prank(bob);
        vm.expectRevert("Bid too low");
        giga.bid(minBid - 1);
    }

    function testMinimumBidWithDifferentBalances() public {
        // Test minimum bid calculation with various MEGA balances and fee amounts

        // Scenario 1: Low MEGA balance, high supply (deflated token)
        vm.prank(alice);
        giga.mint{value: 100 ether}(); // 99 GIGA

        // Burn most tokens to simulate deflation
        skipPastMintingPeriod(giga);
        vm.prank(alice);
        giga.redeem(90 ether); // Burns 89.1 GIGA, returns ~89.1 MEGA

        uint256 remainingSupply = giga.totalSupply();
        uint256 remainingNative = address(giga).balance;

        // Generate fees
        vm.prank(alice);
        giga.transfer(bob, 1 ether); // 10 GIGA fee

        // Start auction
        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        (, , uint96 minBid1, uint112 auctionAmount1, ) = giga
            .currentAuction();

        // Verify minimum bid with new formula
        // MinBid = (native balance * auctionAmount) / (2 * totalSupply)
        uint256 expectedMin1 = (remainingNative * auctionAmount1) /
            (2 * remainingSupply);
        assertEq(
            minBid1,
            expectedMin1,
            "Min bid should match expected calculation"
        );

        // Scenario 2: High MEGA balance from donations
        // Reset with new deployment for clean state
        vm.warp(block.timestamp + 30 days); // Clear any time dependencies

        // Someone donates MEGA to increase backing
        vm.deal(address(this), 50 ether);
        (bool sent, ) = address(giga).call{value: 50 ether}("");
        assertTrue(sent, "Native donation should succeed");

        // Generate new fees
        vm.prank(alice);
        giga.transfer(bob, 0.5 ether);

        // Start new auction
        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        (, , uint96 minBid2, uint112 auctionAmount2, ) = giga
            .currentAuction();

        uint256 currentNative = address(giga).balance;
        uint256 currentSupply = giga.totalSupply();
        uint256 expectedMin2 = (currentNative * auctionAmount2) /
            (2 * currentSupply);

        assertEq(
            minBid2,
            expectedMin2,
            "Min bid should reflect increased MEGA backing"
        );

        // The minimum bid should be higher due to the donation increasing the backing value
        assertTrue(
            minBid2 > minBid1,
            "Higher MEGA backing should result in higher min bid"
        );
    }

    function testMinimumBidFormula() public {
        // Test that minimum bid uses the correct formula
        // Formula: MinBid = (native balance * auctionAmount) / (2 * totalSupply)

        // Using 3 MEGA to create 3 GIGA total supply
        vm.prank(alice);
        giga.mint{value: 3 ether}(); // 2.97 GIGA to alice, 0.03 to fees

        skipPastMintingPeriod(giga);

        // Generate an odd fee amount: 0.007 GIGA
        // After split: 0.0035 GIGA for auction
        vm.prank(alice);
        giga.transfer(bob, 0.7 ether); // 0.007 GIGA fee

        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        (, , uint96 minBid, uint112 auctionAmount, ) = giga.currentAuction();

        uint256 megaBalance = address(giga).balance;
        uint256 totalSupply = giga.totalSupply();

        // The auction should have 0.0035 GIGA (half of 0.007)
        assertEq(auctionAmount, 0.0035 ether, "Auction should have 0.0035 GIGA");

        // Calculate with new formula
        // MinBid = (megaBalance * auctionAmount) / (2 * totalSupply)
        // = (3 MEGA * 0.0035 GIGA) / (2 * 3 GIGA)
        // = 0.0105 / 6 = 0.00175 MEGA
        uint256 expectedMinBid = (megaBalance * auctionAmount) /
            (2 * totalSupply);

        assertEq(
            minBid,
            expectedMinBid,
            "Minimum bid should match contract calculation"
        );

        // The minimum bid is now half of the redemption value
        uint256 redemptionValue = (auctionAmount * megaBalance) / totalSupply;
        assertEq(
            minBid,
            redemptionValue / 2,
            "Min bid should be half of redemption value"
        );
    }

    // ============ Native MEGA Bidding Tests ============

    function testBidWithNative() public {
        // Setup: Generate fees and start auction
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // Alice bids with native MEGA
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        giga.bid{value: minBid}(0); // Pass 0 as bidAmount when using msg.value

        // Verify Alice's MEGA balance decreased
        assertEq(
            alice.balance,
            aliceBalanceBefore - minBid,
            "Alice should have spent MEGA"
        );

        // Verify contract received wrapped token (not native)
        assertEq(
            wmega.balanceOf(address(giga)),
            minBid,
            "Contract should hold wrapped token"
        );

        // Verify Alice is the current bidder
        (address currentBidder, uint96 currentBid, , , ) = giga
            .currentAuction();
        assertEq(currentBidder, alice, "Alice should be current bidder");
        assertEq(currentBid, minBid, "Bid amount should match minBid");
    }

    function testBidWithNativeOverridesBidAmount() public {
        // Test that msg.value takes precedence over bidAmount parameter
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // Alice sends native MEGA but passes different bidAmount parameter
        vm.prank(alice);
        giga.bid{value: minBid}(999999 ether); // This gets ignored

        // Verify the actual bid is msg.value, not the parameter
        (, uint96 currentBid, , , ) = giga.currentAuction();
        assertEq(currentBid, minBid, "Bid should be msg.value, not parameter");
    }

    function testNativeBidRefundsInWrapped() public {
        // Test that previous bidders get wrapped token refund even if current bidder uses native
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // Alice bids with wrapped token - get enough wrapped token for the bid
        getWMEGAAndApprove(alice, address(giga), minBid);
        vm.prank(alice);
        giga.bid(minBid);

        // Bob outbids with native MEGA
        uint256 newBid = (minBid * 110) / 100;
        vm.prank(bob);
        giga.bid{value: newBid}(0);

        // Verify Alice got refunded in wrapped token (not native MEGA)
        // She should get back exactly what she bid
        assertEq(
            wmega.balanceOf(alice),
            minBid,
            "Alice should receive wrapped token refund equal to her bid"
        );

        // Verify Bob is current bidder
        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testMixedNativeAndWrappedBids() public {
        // Test that native and wrapped token bids can be mixed in same auction
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // Alice bids with native MEGA
        vm.prank(alice);
        giga.bid{value: minBid}(0);

        // Bob outbids with wrapped token
        uint256 bid2 = (minBid * 110) / 100;
        getWMEGAAndApprove(bob, address(giga), bid2);
        vm.prank(bob);
        giga.bid(bid2);

        // Charlie outbids with native MEGA
        uint256 bid3 = (bid2 * 110) / 100;
        vm.prank(charlie);
        giga.bid{value: bid3}(0);

        // David outbids with wrapped token
        uint256 bid4 = (bid3 * 110) / 100;
        getWMEGAAndApprove(david, address(giga), bid4);
        vm.prank(david);
        giga.bid(bid4);

        // Verify all previous bidders got wrapped token refunds
        assertEq(
            wmega.balanceOf(alice),
            minBid,
            "Alice should have wrapped token refund"
        );
        assertEq(wmega.balanceOf(bob), bid2, "Bob should have wrapped token refund");
        assertEq(
            wmega.balanceOf(charlie),
            bid3,
            "Charlie should have wrapped token refund"
        );

        // Verify David is the winner
        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, david, "David should be current bidder");
    }

    function testNativeBidTooLow() public {
        // Test that bidding with native MEGA below minimum reverts
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // Alice tries to bid with native MEGA below minimum
        vm.prank(alice);
        vm.expectRevert("Bid too low");
        giga.bid{value: minBid - 1}(0);

        // Verify no bid was placed
        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, address(0), "Should have no bidder");
    }

    function testNativeBidRevertRollback() public {
        // Test that if native bid fails, the wrapping is rolled back
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        uint256 aliceBalanceBefore = alice.balance;
        uint256 wmegaBalanceBefore = wmega.balanceOf(address(giga));

        // Alice tries to bid too low with native MEGA
        vm.prank(alice);
        vm.expectRevert("Bid too low");
        giga.bid{value: minBid - 1}(0);

        // Verify Alice's MEGA was refunded (transaction reverted)
        assertEq(
            alice.balance,
            aliceBalanceBefore,
            "Alice should have same MEGA balance"
        );

        // Verify contract didn't receive any wrapped token
        assertEq(
            wmega.balanceOf(address(giga)),
            wmegaBalanceBefore,
            "Contract should have same wrapped token balance"
        );
    }

    function testAuctionFinalizationWithNativeWinner() public {
        // Test that auction finalization works correctly when winner used native MEGA
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, uint112 auctionAmount, ) = giga.currentAuction();

        // Alice bids with native MEGA
        vm.prank(alice);
        giga.bid{value: minBid}(0);

        uint256 contractWrappedBefore = wmega.balanceOf(address(giga));
        assertEq(
            contractWrappedBefore,
            minBid,
            "Contract should hold Alice's wrapped bid"
        );

        // Generate fees for next day
        vm.prank(bob);
        giga.transfer(alice, 0.5 ether);

        // Finalize auction by triggering next day's lottery
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        // Verify wrapped token was withdrawn to native
        assertEq(
            wmega.balanceOf(address(giga)),
            0,
            "Contract should have no wrapped token after finalization"
        );

        // Verify Alice won the auction and has claimable prize (at least the auction amount)
        vm.prank(alice);
        uint256 claimable = giga.getMyClaimableAmount();
        assertGe(
            claimable,
            auctionAmount,
            "Alice should have at least the auction prize claimable"
        );

        // Verify Alice can actually claim her prize
        uint256 aliceBalanceBefore = giga.balanceOf(alice);
        vm.prank(alice);
        giga.claim();
        uint256 aliceBalanceAfter = giga.balanceOf(alice);

        assertEq(
            aliceBalanceAfter - aliceBalanceBefore,
            claimable,
            "Alice should receive her claimable amount"
        );
    }

    function testNativeBidIncrementRequirement() public {
        // Test that 10% increment rule applies to native MEGA bids
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // Alice bids with native MEGA
        vm.prank(alice);
        giga.bid{value: minBid}(0);

        // Bob tries to bid with only 9% increase using native MEGA
        uint256 lowBid = (minBid * 109) / 100;
        vm.prank(bob);
        vm.expectRevert("Bid too low");
        giga.bid{value: lowBid}(0);

        // Bob bids with exactly 10% increase using native MEGA
        uint256 validBid = (minBid * 110) / 100;
        vm.prank(bob);
        giga.bid{value: validBid}(0);

        // Verify Bob is now the current bidder
        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testNativeWrappingCorrectness() public {
        // Test that native token is correctly wrapped
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        uint256 contractNativeBefore = address(giga).balance;
        uint256 contractWrappedBefore = wmega.balanceOf(address(giga));

        // Alice bids with native MEGA
        vm.prank(alice);
        giga.bid{value: minBid}(0);

        // Contract's native MEGA should not increase (it gets wrapped)
        // Actually, it will increase because wmega.deposit returns MEGA to contract via receive()
        // But wrapped token balance should definitely increase
        assertEq(
            wmega.balanceOf(address(giga)),
            contractWrappedBefore + minBid,
            "Contract should have received wrapped token"
        );

        // Verify the wrapped token amount matches the bid amount exactly
        (, uint96 currentBid, , , ) = giga.currentAuction();
        assertEq(
            wmega.balanceOf(address(giga)),
            currentBid,
            "Wrapped token balance should match bid amount"
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

contract StrategyAuctionSecurityTest is WMEGATestBase {
    Strategy public giga;
    address public alice = address(0x1);
    address public maliciousBidder;

    function setUp() public {
        setupWMEGA();
        giga = new Strategy(address(wmega));

        vm.deal(alice, 100 ether);

        MaliciousBidder malicious = new MaliciousBidder();
        maliciousBidder = address(malicious);
        vm.deal(maliciousBidder, 100 ether);
    }

    function testWrappedNativePreventsRefundDoS() public {
        // Setup auction
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        skipPastMintingPeriod(giga);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(address(0x99), 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // Malicious bidder places bid
        getWMEGAAndApprove(maliciousBidder, address(giga), 1 ether);
        vm.prank(maliciousBidder);
        giga.bid(minBid);

        // Alice can still outbid even though malicious bidder reverts on MEGA
        uint256 newBid = (minBid * 110) / 100;
        getWMEGAAndApprove(alice, address(giga), 1 ether);
        vm.prank(alice);
        giga.bid(newBid); // This would fail with native but succeeds with wrapped token

        // Verify malicious bidder got wrapped token refund
        assertEq(
            wmega.balanceOf(maliciousBidder),
            1 ether,
            "Should receive wrapped native refund"
        );

        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, alice, "Alice should be current bidder");
    }
}
