// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy} from "../src/Strategy.sol";

// Mock ERC20 MEGA for testing
contract MockMEGA {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
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
}

contract StrategyAuctionTest is Test {
    Strategy public giga;
    MockMEGA public mega;

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
        mega = new MockMEGA();
        giga = new Strategy(address(mega));

        // Fund test accounts
        mega.mint(alice, 100 ether);
        mega.mint(bob, 100 ether);
        mega.mint(charlie, 100 ether);
        mega.mint(david, 100 ether);
    }

    // Helper functions
    function mintGiga(address user, uint256 megaAmount) internal {
        vm.startPrank(user);
        mega.approve(address(giga), megaAmount);
        giga.mint(megaAmount);
        vm.stopPrank();
    }

    function skipPastMintingPeriod() internal {
        vm.warp(block.timestamp + giga.MINTING_PERIOD() + 1 days);
    }

    function placeBid(address bidder, uint256 bidAmount) internal {
        vm.startPrank(bidder);
        mega.approve(address(giga), bidAmount);
        giga.bid(bidAmount);
        vm.stopPrank();
    }

    function testAuctionWithBidding() public {
        // Generate fees during minting period
        mintGiga(alice, 10 ether);

        // Fast forward past minting period
        skipPastMintingPeriod();
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

        // Alice bids
        uint256 aliceMegaBefore = mega.balanceOf(alice);
        placeBid(alice, minBid);
        assertEq(
            mega.balanceOf(alice),
            aliceMegaBefore - minBid,
            "Alice should have spent MEGA"
        );

        // Bob outbids
        uint256 newBid = (minBid * 110) / 100;
        placeBid(bob, newBid);

        // Verify Alice got refunded
        assertEq(
            mega.balanceOf(alice),
            aliceMegaBefore,
            "Alice should be refunded"
        );

        // Verify Bob is current bidder
        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testAuctionFinalization() public {
        // Generate fees
        mintGiga(alice, 10 ether);

        // Fast forward past minting period
        skipPastMintingPeriod();
        vm.warp(block.timestamp + 1 hours);

        // Generate fees via transfer
        uint256 aliceBalanceBefore = giga.balanceOf(alice);
        vm.prank(alice);
        bool success = giga.transfer(bob, 1 ether);
        assertTrue(success, "Transfer should succeed");

        // Execute lottery/auction
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        // Place bid
        (, , uint96 minBid, , ) = giga.currentAuction();
        placeBid(alice, minBid);

        uint256 contractMegaBefore = giga.getMegaReserve();
        uint256 escrowedBefore = giga.escrowedBidMega();
        assertEq(escrowedBefore, minBid, "Contract should have escrowed bid");

        // Generate fees on day 8 for day 9's lottery/auction
        vm.prank(bob);
        giga.transfer(alice, 0.5 ether); // Generate 0.005 token fee

        // Finalize auction
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        // Verify escrowed bid was added to reserve
        uint256 escrowedAfter = giga.escrowedBidMega();
        assertEq(escrowedAfter, 0, "Escrow should be empty after finalization");

        // Reserve should have increased by bid amount
        uint256 contractMegaAfter = giga.getMegaReserve();
        assertGt(
            contractMegaAfter,
            contractMegaBefore,
            "Reserve should have increased"
        );
    }

    function testBidIncrementRequirement() public {
        // Setup auction
        mintGiga(alice, 10 ether);

        skipPastMintingPeriod();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // First bid at minimum
        placeBid(alice, minBid);

        // Try to bid with less than 10% increase
        uint256 lowBid = (minBid * 109) / 100; // 9% increase
        vm.startPrank(bob);
        mega.approve(address(giga), lowBid);
        vm.expectRevert("Bid too low");
        giga.bid(lowBid);
        vm.stopPrank();

        // Bid with exactly 10% increase should work
        uint256 validBid = (minBid * 110) / 100;
        placeBid(bob, validBid);

        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testNoBidAuctionRollover() public {
        // Generate fees
        mintGiga(alice, 10 ether);

        skipPastMintingPeriod();
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
        assertTrue(
            feesPoolAfter > 0,
            "FEES_POOL should contain rolled over auction amount"
        );
    }

    function test50_50FeeSplitAfterMintingPeriod() public {
        // Generate tokens during minting
        mintGiga(alice, 100 ether); // Alice gets 99 tokens after 1% fee

        // After minting period (day 8 = 8 * 25 hours from start)
        vm.warp(block.timestamp + 8 * 25 hours);

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

        giga.executeLottery();

        // Verify auction has (100 - LOTTERY_PERCENT)% of fees
        (, , , uint112 auctionAmount, ) = giga.currentAuction();
        uint256 expectedAuctionAmount = (totalFees * (100 - giga.LOTTERY_PERCENT())) / 100;
        assertEq(auctionAmount, expectedAuctionAmount, "Auction should have correct percentage of fees");
    }

    function testMinimumBidCalculation() public {
        // Setup: Create known MEGA balance and total supply
        mintGiga(alice, 10 ether); // 9.9 GIGA to alice, 0.1 to fees
        mintGiga(bob, 5 ether); // 4.95 GIGA to bob, 0.05 to fees

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
            giga.getMegaReserve(),
            megaBalance,
            "Contract should have 15 MEGA"
        );

        // Move past minting period
        skipPastMintingPeriod();

        // Generate specific amount of fees for auction
        vm.prank(alice);
        giga.transfer(bob, 1 ether); // 0.01 GIGA fee

        // Execute to start auction - fees will be split 50/50 between lottery and auction
        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        // Get auction details
        (, , uint96 minBid, uint112 auctionAmount, ) = giga.currentAuction();

        // After transfer: 0.01 GIGA fee generated
        // Split based on LOTTERY_PERCENT: lottery gets LOTTERY_PERCENT%, auction gets rest
        uint256 expectedAuctionAmount = (0.01 ether * (100 - giga.LOTTERY_PERCENT())) / 100;
        assertEq(auctionAmount, expectedAuctionAmount, "Auction should have correct percentage of fees");

        // Calculate expected minimum bid with new formula
        // MinBid = (megaBalance * auctionAmount) / (2 * totalSupply)
        uint256 expectedMinBid = (megaBalance * auctionAmount) /
            (2 * expectedTotalSupply);

        assertEq(
            minBid,
            expectedMinBid,
            "Minimum bid should match calculated value"
        );

        // Verify that bidding exactly the minimum bid works
        placeBid(alice, minBid);

        (address currentBidder, uint96 currentBid, , , ) = giga
            .currentAuction();
        assertEq(currentBidder, alice, "Alice should be current bidder");
        assertEq(currentBid, minBid, "Current bid should equal minimum bid");

        // Verify bidding below minimum fails
        vm.startPrank(bob);
        mega.approve(address(giga), minBid);
        vm.expectRevert("Bid too low");
        giga.bid(minBid - 1);
        vm.stopPrank();
    }

    function testMinimumBidWithDifferentBalances() public {
        // Scenario 1: Low MEGA balance, high supply (deflated token)
        mintGiga(alice, 100 ether); // 99 GIGA

        // Burn most tokens to simulate deflation
        skipPastMintingPeriod();
        vm.prank(alice);
        giga.redeem(90 ether); // Burns 89.1 GIGA, returns ~89.1 MEGA

        uint256 remainingSupply = giga.totalSupply();
        uint256 remainingMega = giga.getMegaReserve();

        // Generate fees
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        // Start auction
        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        (, , uint96 minBid1, uint112 auctionAmount1, ) = giga.currentAuction();

        // Verify minimum bid with new formula
        uint256 expectedMin1 = (remainingMega * auctionAmount1) /
            (2 * remainingSupply);
        assertEq(
            minBid1,
            expectedMin1,
            "Min bid should match expected calculation"
        );

        // Scenario 2: High MEGA balance from donations
        // Someone donates MEGA to increase backing
        mega.mint(address(this), 50 ether);
        mega.transfer(address(giga), 50 ether);

        // Generate new fees
        vm.prank(alice);
        giga.transfer(bob, 0.5 ether);

        // Start new auction
        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        (, , uint96 minBid2, uint112 auctionAmount2, ) = giga.currentAuction();

        uint256 currentMega = giga.getMegaReserve();
        uint256 currentSupply = giga.totalSupply();
        uint256 expectedMin2 = (currentMega * auctionAmount2) /
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
        // Using 3 MEGA to create 3 GIGA total supply
        mintGiga(alice, 3 ether); // 2.97 GIGA to alice, 0.03 to fees

        skipPastMintingPeriod();

        // Generate an odd fee amount: 0.007 GIGA
        vm.prank(alice);
        giga.transfer(bob, 0.7 ether); // 0.007 GIGA fee

        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        (, , uint96 minBid, uint112 auctionAmount, ) = giga.currentAuction();

        uint256 megaBalance = giga.getMegaReserve();
        uint256 totalSupply = giga.totalSupply();

        // The auction should have (100 - LOTTERY_PERCENT)% of 0.007 GIGA
        uint256 expectedAuctionAmount = (0.007 ether * (100 - giga.LOTTERY_PERCENT())) / 100;
        assertEq(auctionAmount, expectedAuctionAmount, "Auction should have correct percentage of fees");

        // Calculate with new formula
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

    function testBidRefunds() public {
        // Setup auction
        mintGiga(alice, 10 ether);

        skipPastMintingPeriod();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // Alice bids
        uint256 aliceMegaBefore = mega.balanceOf(alice);
        placeBid(alice, minBid);
        assertEq(
            mega.balanceOf(alice),
            aliceMegaBefore - minBid,
            "Alice should have spent MEGA"
        );

        // Bob outbids
        uint256 newBid = (minBid * 110) / 100;
        placeBid(bob, newBid);

        // Verify Alice got refunded in MEGA
        assertEq(
            mega.balanceOf(alice),
            aliceMegaBefore,
            "Alice should receive MEGA refund"
        );

        // Verify Bob is current bidder
        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testMultipleBidsAndRefunds() public {
        // Setup auction
        mintGiga(alice, 10 ether);

        skipPastMintingPeriod();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        uint256 aliceMegaBefore = mega.balanceOf(alice);
        uint256 bobMegaBefore = mega.balanceOf(bob);
        uint256 charlieMegaBefore = mega.balanceOf(charlie);

        // Alice bids
        placeBid(alice, minBid);

        // Bob outbids
        uint256 bid2 = (minBid * 110) / 100;
        placeBid(bob, bid2);

        // Charlie outbids
        uint256 bid3 = (bid2 * 110) / 100;
        placeBid(charlie, bid3);

        // David outbids
        uint256 bid4 = (bid3 * 110) / 100;
        placeBid(david, bid4);

        // Verify all previous bidders got refunds
        assertEq(
            mega.balanceOf(alice),
            aliceMegaBefore,
            "Alice should have MEGA refund"
        );
        assertEq(mega.balanceOf(bob), bobMegaBefore, "Bob should have MEGA refund");
        assertEq(
            mega.balanceOf(charlie),
            charlieMegaBefore,
            "Charlie should have MEGA refund"
        );

        // Verify David is the winner
        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, david, "David should be current bidder");
    }

    function testBidTooLow() public {
        // Setup auction
        mintGiga(alice, 10 ether);

        skipPastMintingPeriod();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // Alice tries to bid below minimum
        vm.startPrank(alice);
        mega.approve(address(giga), minBid);
        vm.expectRevert("Bid too low");
        giga.bid(minBid - 1);
        vm.stopPrank();

        // Verify no bid was placed
        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, address(0), "Should have no bidder");
    }

    function testAuctionFinalizationWithWinner() public {
        // Setup auction
        mintGiga(alice, 10 ether);

        skipPastMintingPeriod();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, uint112 auctionAmount, ) = giga.currentAuction();

        // Alice bids
        placeBid(alice, minBid);

        uint256 escrowedBefore = giga.escrowedBidMega();
        assertEq(
            escrowedBefore,
            minBid,
            "Contract should have escrowed Alice's bid"
        );

        // Generate fees for next day
        vm.prank(bob);
        giga.transfer(alice, 0.5 ether);

        // Finalize auction by triggering next day's lottery
        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        // Verify escrowed was cleared
        assertEq(
            giga.escrowedBidMega(),
            0,
            "Contract should have no escrowed MEGA after finalization"
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

    function testBidIncrementAfterFirstBid() public {
        // Test that 10% increment rule applies after first bid
        mintGiga(alice, 10 ether);

        skipPastMintingPeriod();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // Alice bids at minimum
        placeBid(alice, minBid);

        // Bob tries to bid with only 9% increase
        uint256 lowBid = (minBid * 109) / 100;
        vm.startPrank(bob);
        mega.approve(address(giga), lowBid);
        vm.expectRevert("Bid too low");
        giga.bid(lowBid);
        vm.stopPrank();

        // Bob bids with exactly 10% increase
        uint256 validBid = (minBid * 110) / 100;
        placeBid(bob, validBid);

        // Verify Bob is now the current bidder
        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, bob, "Bob should be current bidder");
    }

    function testEscrowAccountingCorrectness() public {
        // Test that escrow accounting is correct
        mintGiga(alice, 10 ether);

        skipPastMintingPeriod();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        uint256 reserveBefore = giga.getMegaReserve();
        uint256 escrowBefore = giga.escrowedBidMega();

        // Alice bids
        placeBid(alice, minBid);

        // Reserve should not change (bid goes to escrow, not reserve)
        // Actually the total MEGA balance increases but escrow increases too
        uint256 reserveAfter = giga.getMegaReserve();
        uint256 escrowAfter = giga.escrowedBidMega();

        assertEq(
            escrowAfter,
            escrowBefore + minBid,
            "Escrow should increase by bid amount"
        );
        assertEq(
            reserveAfter,
            reserveBefore,
            "Reserve should remain unchanged"
        );

        // Verify the bid amount matches escrow
        (, uint96 currentBid, , , ) = giga.currentAuction();
        assertEq(
            escrowAfter,
            currentBid,
            "Escrow should match bid amount"
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

contract StrategyAuctionSecurityTest is Test {
    Strategy public giga;
    MockMEGA public mega;
    address public alice = address(0x1);
    address public maliciousBidder;

    function setUp() public {
        mega = new MockMEGA();
        giga = new Strategy(address(mega));

        mega.mint(alice, 100 ether);

        MaliciousBidder malicious = new MaliciousBidder();
        maliciousBidder = address(malicious);
        mega.mint(maliciousBidder, 100 ether);
    }

    function mintGiga(address user, uint256 megaAmount) internal {
        vm.startPrank(user);
        mega.approve(address(giga), megaAmount);
        giga.mint(megaAmount);
        vm.stopPrank();
    }

    function skipPastMintingPeriod() internal {
        vm.warp(block.timestamp + giga.MINTING_PERIOD() + 1 days);
    }

    function testRefundDoSPrevention() public {
        // Setup auction
        mintGiga(alice, 10 ether);

        skipPastMintingPeriod();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        giga.transfer(address(0x99), 1 ether);

        vm.warp(block.timestamp + 25 hours + 1 minutes);
        giga.executeLottery();

        (, , uint96 minBid, , ) = giga.currentAuction();

        // Malicious bidder places bid
        vm.startPrank(maliciousBidder);
        mega.approve(address(giga), minBid);
        giga.bid(minBid);
        vm.stopPrank();

        // Alice can still outbid - refund goes as ERC20 transfer which works fine
        uint256 newBid = (minBid * 110) / 100;
        vm.startPrank(alice);
        mega.approve(address(giga), newBid);
        giga.bid(newBid); // This should succeed
        vm.stopPrank();

        // Verify malicious bidder got MEGA refund (ERC20 transfer doesn't use receive())
        assertEq(
            mega.balanceOf(maliciousBidder),
            100 ether,
            "Should receive MEGA refund"
        );

        (address currentBidder, , , , ) = giga.currentAuction();
        assertEq(currentBidder, alice, "Alice should be current bidder");
    }
}
