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
    event AuctionWon(address indexed winner, uint256 etheriumAmount, uint256 ethPaid, uint256 day);
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
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether); // Transfer 1000 tokens, 10 token fee
        
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
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether); // Transfer 1000 tokens, 10 token fee
        
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
        uint256 contractETHAfter = address(etherium).balance;
        uint256 contractWETHAfter = weth.balanceOf(address(etherium));
        
        assertEq(contractWETHAfter, 0, "Contract should have no WETH");
        // The contract received ETH from WETH but may have sent some to public good
        // so we just verify WETH was withdrawn
        assertGe(contractETHAfter + minBid, contractETHBefore, "ETH accounting should be consistent");
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
        
        uint256 day8Fees = etherium.dailyFeesCollected(8);
        
        // Day 9 - Previous auction ends without bids, new lottery/auction starts
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        
        // Get current day's fees before executing
        uint256 currentDay = etherium.getCurrentDay();
        uint256 dayFeesBefore = etherium.dailyFeesCollected(currentDay);
        
        etherium.executeLottery();
        
        // After auction rollover, current day should have previous auction amount
        uint256 dayFeesAfter = etherium.dailyFeesCollected(currentDay);
        
        // The rolled over amount is the auction from day 8 execution
        // Day 7 had 10 tokens in fees (from the transfer)
        // Day 8 execution splits day 7's fees 50/50: 5 to lottery, 5 to auction
        // The auction (with 5 tokens) had no bids, so it rolls over
        assertEq(dayFeesAfter - dayFeesBefore, 5 ether, "Auction fees should roll over");
    }

    function test50_50FeeSplitAfterMintingPeriod() public {
        // Generate tokens during minting
        // 100 ETH = 100,000 ETHERIUM tokens before fee
        vm.prank(alice);
        etherium.mint{value: 100 ether}(); // Alice gets 99,000 tokens after 1% fee
        
        // After minting period (day 8 = 8 * 25 hours from start)
        vm.warp(block.timestamp + 8 * 25 hours);
        
        // Alice has 99,000 tokens
        // Transfer 10,000 tokens (generates 100 token fee)
        vm.prank(alice);
        etherium.transfer(bob, 10_000 ether);
        // Bob got 9,900 tokens (10,000 - 100 fee), transfers some back
        vm.prank(bob);
        etherium.transfer(alice, 9_000 ether); // generates 90 token fee
        
        uint256 currentDay = etherium.getCurrentDay();
        uint256 totalFees = etherium.dailyFeesCollected(currentDay);
        assertEq(totalFees, 190 ether, "Should have 190 tokens in fees");
        
        // Execute lottery/auction for the day's fees
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        
        // We generated fees on day 8, so we execute on day 9 to distribute day 8's fees
        etherium.executeLottery();
        
        // Verify auction has half the fees (95 tokens)
        (, , , uint112 auctionAmount, ) = etherium.currentAuction();
        assertEq(auctionAmount, 95 ether, "Auction should have 95 tokens");
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
    address public maliciousBidder;

    function setUp() public {
        setupWETH();
        etherium = new Etherium();
        
        vm.deal(alice, 100 ether);
        
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
        assertEq(weth.balanceOf(maliciousBidder), 1 ether, "Should receive WETH refund");
        
        (address currentBidder, , , , ) = etherium.currentAuction();
        assertEq(currentBidder, alice, "Alice should be current bidder");
    }
}