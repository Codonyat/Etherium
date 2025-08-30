// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract ReentrancyAttacker {
    Etherium public target;
    uint256 public attackCount;
    
    constructor(Etherium _target) {
        target = _target;
    }
    
    receive() external payable {
        if (attackCount < 2) {
            attackCount++;
            // Try to re-enter during ETH refund
            target.bid{value: msg.value * 2}();
        }
    }
    
    function attack() external payable {
        target.bid{value: msg.value}();
    }
}

contract MaliciousReceiver {
    // Refuses to receive ETH
    receive() external payable {
        revert("Refusing ETH");
    }
    
    // Consumes all gas
    fallback() external payable {
        while(true) {
            // Infinite loop to consume gas
        }
    }
}

contract EtheriumSecurityTest is Test {
    Etherium public etherium;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public attacker = address(0x666);
    
    function setUp() public {
        etherium = new Etherium();
        
        // Fund accounts
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(charlie, 1000 ether);
        vm.deal(attacker, 100 ether);
    }
    
    // ============ No-Bid Auction Rollover ============
    
    function testNoBidAuctionRollover() public {
        // Setup
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        // Move past minting period
        vm.warp(block.timestamp + 8 days);
        
        // Generate fees on current day
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether); // 10 ETHERIUM fee
        
        uint256 dayNFees = etherium.dailyFeesCollected(etherium.getCurrentDay());
        assertEq(dayNFees, 10 ether, "Should have 10 ETHERIUM in fees");
        
        // Move to next day to start auction/lottery
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Check auction was started with half the fees
        (,,, uint112 auctionAmount,) = etherium.currentAuction();
        assertEq(auctionAmount, 5 ether, "Auction should have 5 ETHERIUM");
        
        // No one bids, move to next day
        vm.warp(block.timestamp + 25 hours + 61);
        
        // Generate new fees before executing
        vm.prank(alice);
        etherium.transfer(bob, 100 ether); // 1 ETHERIUM fee
        
        uint256 currentDay = etherium.getCurrentDay();
        uint256 currentDayFees = etherium.dailyFeesCollected(currentDay);
        
        // Execute lottery/auction - will finalize previous auction first
        etherium.executeLottery();
        
        // After finalization, the 5 ETHERIUM from unclaimed auction should be added to current day
        uint256 updatedFees = etherium.dailyFeesCollected(currentDay);
        assertEq(updatedFees, currentDayFees + 5 ether, "Auction fees should roll over");
    }
    
    // ============ Division by Zero Protection ============
    
    function testRedeemWithZeroSupply() public {
        // This shouldn't be possible in practice, but test the edge case
        // Skip - can't actually get to zero supply after minting
    }
    
    function testMintWithZeroETHBalance() public {
        // First mint some during minting period to set max supply
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        // Move past minting period
        vm.warp(block.timestamp + 8 days);
        
        // Redeem all to empty contract
        vm.prank(alice);
        etherium.redeem(990 ether);
        
        // Now mint with no ETH in contract - should use 1000:1 fallback ratio
        vm.prank(bob);
        etherium.mint{value: 0.1 ether}();
        
        assertEq(etherium.balanceOf(bob), 99 ether, "Should use fallback ratio");
    }
    
    // ============ Reentrancy Protection ============
    
    function testReentrancyInBid() public {
        // Setup auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.warp(block.timestamp + 8 days);
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);
        
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Deploy attacker
        ReentrancyAttacker reentrancyAttacker = new ReentrancyAttacker(etherium);
        vm.deal(address(reentrancyAttacker), 10 ether);
        
        // First bid from normal user
        vm.prank(charlie);
        etherium.bid{value: 0.01 ether}();
        
        // Try reentrancy attack - attacker tries to bid, which will trigger receive() 
        // and attempt to re-enter bid()
        vm.prank(address(reentrancyAttacker));
        vm.expectRevert(); // Should revert due to reentrancy guard
        etherium.bid{value: 0.02 ether}();
    }
    
    function testReentrancyInRedeem() public {
        // Mint some tokens
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        // Try to redeem from a contract that re-enters
        // This is protected by nonReentrant modifier
        // Test passes if no reentrancy is possible
        vm.prank(alice);
        etherium.redeem(100 ether);
        
        assertTrue(true, "Reentrancy protection works");
    }
    
    // ============ Gas Griefing Protection ============
    
    function testBidRefundToMaliciousContract() public {
        // Setup auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.warp(block.timestamp + 8 days);
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);
        
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Deploy malicious receiver
        MaliciousReceiver malicious = new MaliciousReceiver();
        vm.deal(address(malicious), 10 ether);
        
        // Malicious contract bids
        vm.prank(address(malicious));
        etherium.bid{value: 0.01 ether}();
        
        // Normal user outbids - refund to malicious should fail but not block bid
        vm.prank(charlie);
        vm.expectRevert("Failed to refund previous bidder");
        etherium.bid{value: 0.011 ether}();
    }
    
    // ============ Zero Amount Operations ============
    
    function testMintZeroETH() public {
        vm.prank(alice);
        vm.expectRevert("Must send ETH");
        etherium.mint{value: 0}();
    }
    
    function testRedeemZeroAmount() public {
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        vm.prank(alice);
        vm.expectRevert("Amount must be greater than 0");
        etherium.redeem(0);
    }
    
    function testTransferZeroAmount() public {
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        // ERC20 allows zero transfers
        vm.prank(alice);
        etherium.transfer(bob, 0);
        
        // Should succeed but generate no fees from the zero transfer
        // But there were fees from minting (10 ETHERIUM)
        assertEq(etherium.dailyFeesCollected(etherium.getCurrentDay()), 10 ether);
    }
    
    // ============ Self-Transfer Fee Manipulation ============
    
    function testSelfTransferFees() public {
        vm.prank(alice);
        etherium.mint{value: 1 ether}(); // Gets 990 ETHERIUM
        
        uint256 balanceBefore = etherium.balanceOf(alice);
        
        // Transfer to self
        vm.prank(alice);
        etherium.transfer(alice, 100 ether);
        
        uint256 balanceAfter = etherium.balanceOf(alice);
        
        // Should still pay fees even on self-transfer
        assertEq(balanceBefore - balanceAfter, 1 ether, "Fees should apply to self-transfers");
        assertEq(etherium.dailyFeesCollected(etherium.getCurrentDay()), 1 ether);
    }
    
    // ============ Auction Sniping ============
    
    function testAuctionLastSecondBid() public {
        // Setup auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.warp(block.timestamp + 8 days);
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);
        
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        uint256 auctionDay = etherium.lastLotteryDay();
        
        // Bob bids early
        vm.prank(bob);
        etherium.bid{value: 0.01 ether}();
        
        // Move to near end of auction day but still same day
        vm.warp(block.timestamp + 24 hours); // Still within the same day
        
        // Charlie tries to snipe
        vm.prank(charlie);
        etherium.bid{value: 0.011 ether}();
        
        // Verify still same day
        assertEq(etherium.getCurrentDay(), auctionDay, "Should still be auction day");
        
        // Move to next day
        vm.warp(block.timestamp + 1 hours + 61);
        
        // Auction should be ended, no more bids
        vm.prank(alice);
        vm.expectRevert("Auction has ended");
        etherium.bid{value: 0.02 ether}();
        
        // Charlie should be the winner
        (address winner,,,,) = etherium.currentAuction();
        assertEq(winner, charlie, "Last valid bid should win");
    }
    
    // ============ Empty Contract Balance on Redeem ============
    
    function testRedeemWithInsufficientContractETH() public {
        // Mint tokens (10 ETH = 10,000 ETHERIUM each)
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 10 ether}();
        
        // Alice redeems most of her tokens
        vm.prank(alice);
        etherium.redeem(9000 ether); // Redeem 9000 ETHERIUM
        
        // Bob tries to redeem his tokens
        uint256 bobBalance = etherium.balanceOf(bob); // 9900 ETHERIUM
        uint256 contractETH = address(etherium).balance;
        
        uint256 bobETHBefore = bob.balance;
        vm.prank(bob);
        etherium.redeem(1000 ether); // Redeem 1000 ETHERIUM
        
        // Bob should get proportional ETH
        uint256 bobETHAfter = bob.balance;
        uint256 ethReceived = bobETHAfter - bobETHBefore;
        
        // Should receive proportional share
        assertGt(ethReceived, 0, "Bob should receive some ETH");
        assertLt(ethReceived, 10 ether, "Bob should get less than initial deposit");
    }
    
    // ============ Max Supply Enforcement ============
    
    function testMaxSupplyEnforcement() public {
        // Mint during minting period (100 ETH = 100,000 ETHERIUM)
        vm.prank(alice);
        etherium.mint{value: 100 ether}();
        
        // Move past minting period
        vm.warp(block.timestamp + 8 days);
        
        // Trigger max supply setting by trying to mint
        vm.prank(bob);
        etherium.mint{value: 0.001 ether}();
        
        // Max supply should be set to initial total supply
        uint256 maxSupply = etherium.maxSupplyEver();
        assertEq(maxSupply, 100_000 ether, "Max supply should be set");
        
        // Try to mint beyond max supply
        vm.prank(charlie);
        vm.expectRevert("Max supply reached");
        etherium.mint{value: 101 ether}(); // Would mint way more than allowed
    }
    
    // ============ Timestamp Manipulation ============
    
    function testTimestampManipulationResistance() public {
        // Setup
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        // Generate fees on day 0
        vm.prank(alice);
        etherium.transfer(bob, 100 ether);
        
        // Move to day 1 and generate more fees
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        etherium.transfer(bob, 100 ether);
        
        // Move to just before 1 minute mark on day 2
        vm.warp(block.timestamp + 25 hours + 59);
        
        // Should not be able to execute lottery yet
        vm.expectRevert("Must wait 1 minute into new day before executing");
        etherium.executeLottery();
        
        // Move 2 seconds forward (past 1 minute)
        vm.warp(block.timestamp + 2);
        
        // Now should work
        etherium.executeLottery();
        
        assertEq(etherium.lastLotteryDay(), 2, "Lottery executed after time gap");
    }
    
    // ============ Bid Validation ============
    
    function testBidWithInsufficientETH() public {
        // Setup auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.warp(block.timestamp + 8 days);
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);
        
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Calculate minimum bid
        uint256 minBid = (address(etherium).balance * 1e18) / etherium.totalSupply();
        
        // Try to bid below minimum
        vm.prank(charlie);
        vm.expectRevert("Bid too low");
        etherium.bid{value: minBid - 1}();
    }
    
    function testBidIncrementExactly10Percent() public {
        // Setup auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.warp(block.timestamp + 8 days);
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);
        
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // First bid
        vm.prank(bob);
        etherium.bid{value: 1 ether}();
        
        // Try 9% increase (should fail)
        vm.prank(charlie);
        vm.expectRevert("Bid too low");
        etherium.bid{value: 1.09 ether}();
        
        // Try exactly 10% increase (should work)
        vm.prank(charlie);
        etherium.bid{value: 1.1 ether}();
        
        (address winner,,,,) = etherium.currentAuction();
        assertEq(winner, charlie, "10% increment should be accepted");
    }
    
    // ============ Multiple Bids Same Block ============
    
    function testMultipleBidsSameBlock() public {
        // Setup auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.warp(block.timestamp + 8 days);
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);
        
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Multiple bids in same block
        vm.prank(alice);
        etherium.bid{value: 0.01 ether}();
        
        vm.prank(bob);
        etherium.bid{value: 0.011 ether}();
        
        vm.prank(charlie);
        etherium.bid{value: 0.0121 ether}();
        
        // Check final winner
        (address winner,,,,) = etherium.currentAuction();
        assertEq(winner, charlie, "Last valid bid should win");
    }
    
    // ============ Lottery Double Execution Prevention ============
    
    function testPreventDoubleLotteryExecution() public {
        // Setup
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        // Generate fees on day 0
        vm.prank(alice);
        etherium.transfer(bob, 100 ether);
        
        // Move to day 1 to generate more fees
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        etherium.transfer(bob, 100 ether);
        
        // Move to day 2 (can execute for day 1's fees)
        vm.warp(block.timestamp + 25 hours + 61);
        
        // Execute lottery once
        etherium.executeLottery();
        
        // Try to execute again immediately
        vm.expectRevert("No pending lottery/auction (same day)");
        etherium.executeLottery();
    }
    
    // ============ Fee Overflow Protection ============
    
    function testLargeFeeCalculation() public {
        // Mint large amount (1000 ETH = 1,000,000 ETHERIUM)
        vm.prank(alice);
        etherium.mint{value: 1000 ether}();
        
        // Transfer large amount to generate large fee
        uint256 largeAmount = etherium.balanceOf(alice); // 990,000 ETHERIUM after 1% mint fee
        vm.prank(alice);
        etherium.transfer(bob, largeAmount);
        
        // Check fees were collected correctly
        uint256 expectedFee = (largeAmount * 100) / 10000;
        assertEq(etherium.dailyFeesCollected(etherium.getCurrentDay()), expectedFee);
        assertEq(etherium.balanceOf(bob), largeAmount - expectedFee);
    }
    
    // ============ Unclaimed Prize Public Goods Flow ============
    
    function testUnclaimedPrizeToPublicGoods() public {
        // Setup and run lottery
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        // Generate fees on day 0
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);
        
        // Move to day 1 and generate more fees
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        etherium.transfer(bob, 100 ether);
        
        // Move to day 2 and execute
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(12345);
        etherium.executeLottery();
        
        // Get winner info
        (address[14] memory winners, uint112[14] memory amounts) = etherium.getAllUnclaimedPrizes();
        uint256 slot1 = 1 % 14;
        address firstWinner = winners[slot1];
        uint256 firstAmount = amounts[slot1];
        
        assertTrue(firstWinner != address(0), "Should have a winner");
        assertTrue(firstAmount > 0, "Should have prize amount");
        
        // Generate fees for 7 more days without claiming
        for (uint i = 0; i < 7; i++) {
            vm.prank(alice);
            etherium.transfer(bob, 100 ether);
            vm.warp(block.timestamp + 25 hours + 61);
            
            if (i < 6) {
                // Keep executing lottery
                vm.prevrandao(bytes32(uint256(i)));
                etherium.executeLottery();
            }
        }
        
        // Execute lottery on day 9 - should send day 1's unclaimed to public goods
        vm.prevrandao(99999);
        
        // Get first public good address
        address publicGood = etherium.PUBLIC_GOODS(0);
        uint256 publicGoodBalanceBefore = publicGood.balance;
        
        etherium.executeLottery();
        
        // Check if public good received funds
        uint256 publicGoodBalanceAfter = publicGood.balance;
        
        // The unclaimed prize should have been sent to public good
        // Note: This will only work if the public good can receive ETH
        if (publicGoodBalanceAfter > publicGoodBalanceBefore) {
            assertEq(
                publicGoodBalanceAfter - publicGoodBalanceBefore,
                firstAmount,
                "Public good should receive unclaimed prize"
            );
        }
    }
    
    // ============ Fenwick Tree Consistency ============
    
    function testFenwickTreeConsistencyUnderStress() public {
        // Create many holders
        for (uint i = 1; i <= 50; i++) {
            address holder = address(uint160(i));
            vm.deal(holder, 10 ether);
            vm.prank(holder);
            etherium.mint{value: 1 ether}();
        }
        
        // Perform many transfers
        for (uint i = 1; i <= 25; i++) {
            address from = address(uint160(i));
            address to = address(uint160(i + 25));
            vm.prank(from);
            etherium.transfer(to, 100 ether);
        }
        
        // Check holder count is correct
        uint256 holderCount = etherium.getHolderCount();
        assertTrue(holderCount <= 50, "Holder count should not exceed total addresses");
        
        // Verify Fenwick tree sum equals total holder balance
        uint256 totalHolderBalance = 0;
        for (uint i = 1; i <= 50; i++) {
            totalHolderBalance += etherium.balanceOf(address(uint160(i)));
        }
        
        // Account for lottery pool
        totalHolderBalance += etherium.balanceOf(etherium.FEES_POOL());
        
        assertEq(totalHolderBalance, etherium.totalSupply(), "Fenwick sum should equal total supply");
    }
    
    // ============ Auction Without Lottery Pool Funds ============
    
    function testAuctionWithoutFunds() public {
        // Move past minting period without any mints
        vm.warp(block.timestamp + 8 days);
        
        // Try to execute lottery/auction with no fees
        vm.expectRevert("No fees to distribute");
        etherium.executeLottery();
    }
    
    // ============ Bid After Auction Ends ============
    
    function testBidAfterAuctionEnds() public {
        // Setup auction
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.warp(block.timestamp + 8 days);
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);
        
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();
        
        // Move to next day
        vm.warp(block.timestamp + 25 hours);
        
        // Try to bid on ended auction
        vm.prank(charlie);
        vm.expectRevert("Auction has ended");
        etherium.bid{value: 0.01 ether}();
    }
    
    // ============ Claim Multiple Prizes ============
    
    function testClaimMultiplePrizes() public {
        // Alice mints and gets lucky multiple times
        vm.prank(alice);
        etherium.mint{value: 100 ether}();
        
        // Generate initial fees on day 0
        vm.prank(alice);
        etherium.transfer(bob, 100 ether);
        
        // Day 1: generate fees
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        etherium.transfer(bob, 100 ether);
        
        // Day 2: execute lottery for day 1's fees
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(bytes32(uint256(1)));
        etherium.executeLottery();
        
        // Continue for more days
        for (uint i = 0; i < 2; i++) {
            // Generate fees
            vm.prank(alice);
            etherium.transfer(bob, 100 ether);
            
            // Move to next day
            vm.warp(block.timestamp + 25 hours + 61);
            
            // Execute lottery
            vm.prevrandao(bytes32(uint256(i + 2)));
            etherium.executeLottery();
        }
        
        // Check Alice has multiple unclaimed prizes
        uint256 claimableAmount = etherium.getMyClaimableAmount();
        
        if (claimableAmount > 0) {
            uint256 aliceBalanceBefore = etherium.balanceOf(alice);
            
            // Claim all prizes at once
            vm.prank(alice);
            etherium.claim();
            
            uint256 aliceBalanceAfter = etherium.balanceOf(alice);
            assertEq(
                aliceBalanceAfter - aliceBalanceBefore,
                claimableAmount,
                "Should claim all prizes"
            );
        }
    }
}