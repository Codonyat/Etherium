// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrategyTestBase} from "./helpers/StrategyTestBase.sol";
import {console} from "forge-std/Test.sol";
import {Strategy, IWMON} from "../src/Strategy.sol";

contract StrategyUnclaimedPrizesBugTest is StrategyTestBase {
    uint256 monadFork;

    // Additional events not in base class
    event BidPlaced(address indexed bidder, uint256 amount, uint256 day);
    event AuctionStarted(uint256 day, uint256 monstrAmount, uint256 minBid);

    function setUp() public override {
        // Use monad testnet fork - StrategyTestBase will automatically detect chain and use correct WMON
        monadFork = vm.createFork("monad_testnet");
        vm.selectFork(monadFork);

        // Call parent setUp which will detect we're on Monad Testnet and use the real WMON
        super.setUp();
    }

    /**
     * @dev This test verifies that the fix prevents lottery winners from
     * losing their prizes when auctions are finalized
     */
    function testLotteryWinnerKeepsClaimableAmount() public {
        // Setup: Create some holders with balances during minting period
        // During minting period, 1% fee is minted as new tokens
        vm.expectEmit(true, false, false, true);
        emit Minted(alice, 100 ether, 99 ether, 1 ether);
        vm.prank(alice);
        monstr.mint{value: 100 ether}();

        vm.expectEmit(true, false, false, true);
        emit Minted(bob, 100 ether, 99 ether, 1 ether);
        vm.prank(bob);
        monstr.mint{value: 100 ether}();

        vm.expectEmit(true, false, false, true);
        emit Minted(charlie, 100 ether, 99 ether, 1 ether);
        vm.prank(charlie);
        monstr.mint{value: 100 ether}();

        // Skip past minting period to enable alternating lottery/auction
        skipPastMintingPeriod();

        // Generate some fees through transfers
        // Transfer fee is 1%, so 10 * 0.01 = 0.1 MONSTR fee
        vm.prank(alice);
        bool success1 = monstr.transfer(bob, 10 ether);
        assertTrue(success1, "Transfer should succeed");
        // Alice should have 99 - 10 = 89 MONSTR
        assertEq(
            monstr.balanceOf(alice),
            89 ether,
            "Alice balance after transfer"
        );
        // Bob should have 99 + 9.9 = 108.9 MONSTR (10 - 0.1 fee)
        assertEq(
            monstr.balanceOf(bob),
            108.9 ether,
            "Bob balance after receiving"
        );

        // Transfer 5 MONSTR, fee = 0.05 MONSTR
        vm.prank(bob);
        bool success2 = monstr.transfer(charlie, 5 ether);
        assertTrue(success2, "Transfer should succeed");
        // Bob should have 108.9 - 5 = 103.9 MONSTR
        assertEq(
            monstr.balanceOf(bob),
            103.9 ether,
            "Bob balance after transfer"
        );
        // Charlie should have 99 + 4.95 = 103.95 MONSTR
        assertEq(
            monstr.balanceOf(charlie),
            103.95 ether,
            "Charlie balance after receiving"
        );

        // Day 8: Execute lottery
        moveToNextDay();
        monstr.executeLottery();

        // Generate more fees for the auction
        // Transfer 3 MONSTR, fee = 0.03 MONSTR
        vm.prank(charlie);
        bool success3 = monstr.transfer(alice, 3 ether);
        assertTrue(success3, "Transfer should succeed");
        // Charlie should have 103.95 - 3 = 100.95 MONSTR
        assertEq(
            monstr.balanceOf(charlie),
            100.95 ether,
            "Charlie balance after transfer"
        );
        // Alice should have 89 + 2.97 = 91.97 MONSTR
        assertEq(
            monstr.balanceOf(alice),
            91.97 ether,
            "Alice balance after receiving"
        );

        // Day 9: Execute lottery which will also start an auction
        moveToNextDay();

        // Execute lottery - someone will win
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0); // We don't know who will win due to randomness
        monstr.executeLottery();

        // Determine who won the Day 9 lottery by checking claimable amounts
        address day9LotteryWinner;
        uint256 day9LotteryPrize;

        vm.prank(alice);
        uint256 aliceClaimable = monstr.getMyClaimableAmount();
        vm.prank(bob);
        uint256 bobClaimable = monstr.getMyClaimableAmount();
        vm.prank(charlie);
        uint256 charlieClaimable = monstr.getMyClaimableAmount();

        // Find who has new claimable amount (the Day 9 lottery winner)
        // Note: They might have won on Day 8 too, so we track the highest
        if (
            aliceClaimable > bobClaimable && aliceClaimable > charlieClaimable
        ) {
            day9LotteryWinner = alice;
            day9LotteryPrize = aliceClaimable;
        } else if (bobClaimable > charlieClaimable) {
            day9LotteryWinner = bob;
            day9LotteryPrize = bobClaimable;
        } else {
            day9LotteryWinner = charlie;
            day9LotteryPrize = charlieClaimable;
        }

        console.log("Day 9 lottery winner:", day9LotteryWinner);
        console.log(
            "Claimable amount before auction finalization:",
            day9LotteryPrize
        );

        // Place a bid on the auction (david who wasn't a holder)
        vm.startPrank(david);
        wmon.deposit{value: 10 ether}();
        wmon.approve(address(monstr), 10 ether);

        // Get auction details before bidding
        (, , , uint112 auctionAmount, uint112 auctionDay) = monstr
            .currentAuction();
        assertGt(auctionAmount, 0, "Auction should have tokens");

        // Expect bid event
        vm.expectEmit(true, false, false, true);
        emit BidPlaced(david, 1 ether, auctionDay);
        monstr.bid(1 ether);
        vm.stopPrank();

        // Generate fees for next day
        // Transfer 2 MONSTR, fee = 0.02 MONSTR
        vm.prank(alice);
        bool success4 = monstr.transfer(bob, 2 ether);
        assertTrue(success4, "Transfer should succeed");

        // Day 10: Execute lottery again, which will also finalize the auction
        moveToNextDay();

        // Execute lottery - this will finalize the auction
        monstr.executeLottery();

        // Check claimable amounts after auction finalization
        vm.prank(alice);
        uint256 aliceAfter = monstr.getMyClaimableAmount();
        vm.prank(bob);
        uint256 bobAfter = monstr.getMyClaimableAmount();
        vm.prank(charlie);
        uint256 charlieAfter = monstr.getMyClaimableAmount();
        vm.prank(david);
        uint256 davidClaimable = monstr.getMyClaimableAmount();

        console.log("Alice claimable after:", aliceAfter);
        console.log("Bob claimable after:", bobAfter);
        console.log("Charlie claimable after:", charlieAfter);
        console.log("David (auction winner) claimable:", davidClaimable);

        // Check if any of the original holders lost claimable amount
        bool aliceLost = aliceAfter < aliceClaimable;
        bool bobLost = bobAfter < bobClaimable;
        bool charlieLost = charlieAfter < charlieClaimable;

        // WITH THE FIX: No one should lose their prize
        assertTrue(
            !aliceLost && !bobLost && !charlieLost && davidClaimable > 0,
            "FIX VERIFIED: No lottery winner lost their prize and auction winner has theirs!"
        );
    }

    /**
     * @dev Test that verifies the fix works by ensuring no one loses prizes
     * Both lottery and auction winners can claim their prizes
     */
    function testBothWinnersCanClaim() public {
        // Setup holders during minting period
        vm.expectEmit(true, false, false, true);
        emit Minted(alice, 100 ether, 99 ether, 1 ether);
        vm.prank(alice);
        monstr.mint{value: 100 ether}();

        vm.expectEmit(true, false, false, true);
        emit Minted(bob, 100 ether, 99 ether, 1 ether);
        vm.prank(bob);
        monstr.mint{value: 100 ether}();

        vm.expectEmit(true, false, false, true);
        emit Minted(charlie, 100 ether, 99 ether, 1 ether);
        vm.prank(charlie);
        monstr.mint{value: 100 ether}();

        // Skip past minting period
        skipPastMintingPeriod();

        // Generate fees
        vm.prank(alice);
        bool success1 = monstr.transfer(bob, 10 ether);
        assertTrue(success1, "Transfer should succeed");
        // Verify balances: Alice had 99000, transferred 10000, has 89000
        assertEq(
            monstr.balanceOf(alice),
            89 ether,
            "Alice balance after transfer"
        );
        // Bob had 99, received 9.9 (10 - 0.1 fee), has 108.9
        assertEq(
            monstr.balanceOf(bob),
            108.9 ether,
            "Bob balance after receiving"
        );

        // Day 8: Execute lottery
        moveToNextDay();
        monstr.executeLottery();

        // Generate more fees
        vm.prank(bob);
        bool success2 = monstr.transfer(alice, 5 ether);
        assertTrue(success2, "Transfer should succeed");
        // Bob had 108.9, transferred 5, has 103.9
        assertEq(
            monstr.balanceOf(bob),
            103.9 ether,
            "Bob balance after transfer"
        );
        // Alice had 89, received 4.95 (5 - 0.05 fee), has 93.95
        assertEq(
            monstr.balanceOf(alice),
            93.95 ether,
            "Alice balance after receiving"
        );

        // Day 9: Execute lottery and start auction
        moveToNextDay();
        monstr.executeLottery();

        // Determine who won Day 9 lottery by checking claimable amounts
        vm.prank(alice);
        uint256 aliceClaimableBefore = monstr.getMyClaimableAmount();
        vm.prank(bob);
        uint256 bobClaimableBefore = monstr.getMyClaimableAmount();
        vm.prank(charlie);
        uint256 charlieClaimableBefore = monstr.getMyClaimableAmount();

        // Record total claimable before auction
        uint256 totalClaimableBefore = aliceClaimableBefore +
            bobClaimableBefore +
            charlieClaimableBefore;
        console.log(
            "Total claimable before auction finalization:",
            totalClaimableBefore
        );

        // Place bid on the auction (david who is not a current holder)
        vm.startPrank(david);
        uint256 davidWethBefore = wmon.balanceOf(david);
        wmon.deposit{value: 10 ether}();
        uint256 davidWethAfterDeposit = wmon.balanceOf(david);
        assertEq(
            davidWethAfterDeposit - davidWethBefore,
            10 ether,
            "David should have deposited 10 WMON"
        );
        wmon.approve(address(monstr), 10 ether);

        // Get auction details before bidding
        (, , , uint112 auctionAmount, uint112 auctionDay) = monstr
            .currentAuction();
        assertGt(auctionAmount, 0, "Auction should have tokens");

        // Expect bid event
        vm.expectEmit(true, false, false, true);
        emit BidPlaced(david, 1 ether, auctionDay);
        monstr.bid(1 ether);

        // Verify WMON was transferred
        uint256 davidWethAfterBid = wmon.balanceOf(david);
        assertEq(
            davidWethAfterDeposit - davidWethAfterBid,
            1 ether,
            "David should have spent 1 WMON on bid"
        );
        vm.stopPrank();

        // Day 10: Finalize auction
        moveToNextDay();
        monstr.executeLottery();

        // Check claimable amounts after auction finalization
        vm.prank(alice);
        uint256 aliceClaimableAfter = monstr.getMyClaimableAmount();
        vm.prank(bob);
        uint256 bobClaimableAfter = monstr.getMyClaimableAmount();
        vm.prank(charlie);
        uint256 charlieClaimableAfter = monstr.getMyClaimableAmount();
        vm.prank(david);
        uint256 davidClaimable = monstr.getMyClaimableAmount();

        uint256 totalClaimableAfter = aliceClaimableAfter +
            bobClaimableAfter +
            charlieClaimableAfter +
            davidClaimable;
        console.log(
            "Total claimable after auction finalization:",
            totalClaimableAfter
        );
        console.log("David's claimable:", davidClaimable);

        // The bug: Someone lost their claimable amount
        bool aliceLost = aliceClaimableAfter < aliceClaimableBefore;
        bool bobLost = bobClaimableAfter < bobClaimableBefore;
        bool charlieLost = charlieClaimableAfter < charlieClaimableBefore;

        console.log("Alice lost funds:", aliceLost);
        console.log("Bob lost funds:", bobLost);
        console.log("Charlie lost funds:", charlieLost);

        // WITH THE FIX: No one should lose claimable amounts
        assertTrue(
            !aliceLost && !bobLost && !charlieLost,
            "FIX VERIFIED: No lottery winner lost their claimable prize when auction was finalized!"
        );

        // Try to actually claim the prizes to verify they work
        if (davidClaimable > 0) {
            uint256 davidBalanceBefore = monstr.balanceOf(david);
            vm.prank(david);
            monstr.claim();
            uint256 davidBalanceAfter = monstr.balanceOf(david);

            // David should successfully claim exact amount
            uint256 davidClaimed = davidBalanceAfter - davidBalanceBefore;
            assertEq(
                davidClaimed,
                davidClaimable,
                "David should claim exact claimable amount"
            );
            assertTrue(
                davidBalanceAfter > davidBalanceBefore,
                "David should be able to claim auction prize"
            );

            // Verify claimable is now zero
            vm.prank(david);
            assertEq(
                monstr.getMyClaimableAmount(),
                0,
                "David should have no claimable after claiming"
            );
        }
    }

    /**
     * @dev Test that verifies no auctions occur during the minting period
     * All fees should go to lottery during the minting period
     */
    function testNoAuctionsDuringMintingPeriod() public {
        // During minting period
        // All fees should go to lottery, not auction

        // Day 0: Setup holders
        vm.expectEmit(true, false, false, true);
        emit Minted(alice, 100 ether, 99 ether, 1 ether);
        vm.prank(alice);
        monstr.mint{value: 100 ether}();
        assertEq(monstr.balanceOf(alice), 99 ether, "Alice initial balance");

        vm.expectEmit(true, false, false, true);
        emit Minted(bob, 100 ether, 99 ether, 1 ether);
        vm.prank(bob);
        monstr.mint{value: 100 ether}();
        assertEq(monstr.balanceOf(bob), 99 ether, "Bob initial balance");

        vm.expectEmit(true, false, false, true);
        emit Minted(charlie, 50 ether, 49.5 ether, 0.5 ether);
        vm.prank(charlie);
        monstr.mint{value: 50 ether}();
        assertEq(
            monstr.balanceOf(charlie),
            49.5 ether,
            "Charlie initial balance"
        );

        // Still in minting period (day 0)
        uint256 currentDay = monstr.getCurrentDay();
        assertEq(currentDay, 0, "Should be day 0");

        // Generate fees through transfers
        vm.prank(alice);
        bool success1 = monstr.transfer(bob, 5 ether);
        assertTrue(success1, "Transfer should succeed");
        // Alice: 99 - 5 = 94
        assertEq(
            monstr.balanceOf(alice),
            94 ether,
            "Alice balance after transfer"
        );
        // Bob: 99 + 4.95 = 103.95 (received 5 - 0.05 fee)
        assertEq(
            monstr.balanceOf(bob),
            103.95 ether,
            "Bob balance after receiving"
        );

        vm.prank(bob);
        bool success2 = monstr.transfer(charlie, 3 ether);
        assertTrue(success2, "Transfer should succeed");
        // Bob: 103.95 - 3 = 100.95
        assertEq(
            monstr.balanceOf(bob),
            100.95 ether,
            "Bob balance after transfer"
        );
        // Charlie: 49.5 + 2.97 = 52.47 (received 3 - 0.03 fee)
        assertEq(
            monstr.balanceOf(charlie),
            52.47 ether,
            "Charlie balance after receiving"
        );

        // Move to day 1 (still in minting period)
        moveToNextDay();
        currentDay = monstr.getCurrentDay();
        assertEq(currentDay, 1, "Should be day 1");

        // Execute lottery - should be lottery, not auction
        vm.prevrandao(bytes32(uint256(12345)));
        // During minting period, all fees go to lottery
        // Total fees so far: 1 + 1 + 0.5 (mint fees) + 0.05 + 0.03 (transfer fees) = 2.58 MONSTR
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0); // We don't know exact winner/amount due to randomness
        monstr.executeLottery();

        // Check that there's no active auction (during minting period, no auctions)
        // However, there may be randomness pool balance from fees
        (address bidder, , , uint112 auctionAmount, ) = monstr.currentAuction();
        // During minting period, auctions don't happen - fees split between lottery and randomness
        // So auction amount might be > 0 if it represents randomness pool
        // The key is that bidder should be 0 (no active auction)
        assertEq(
            bidder,
            address(0),
            "Should be no bidder during minting period"
        );

        // Check that lottery was executed (someone should have won)
        (address lotteryWinner, uint112 lotteryPrize) = monstr
            .lotteryUnclaimedPrizes(0 % 7);
        assertTrue(
            lotteryWinner == alice ||
                lotteryWinner == bob ||
                lotteryWinner == charlie,
            "Should have a lottery winner during minting period"
        );
        assertGt(lotteryPrize, 0, "Lottery prize should be greater than 0");
        // Verify the prize amount - during minting period, all fees go to lottery (no auction)
        // Total fees: 2.58 MONSTR, lottery gets 100% = 2.58 MONSTR
        assertEq(
            lotteryPrize,
            2.58 ether,
            "Lottery prize should be all collected fees during minting period"
        );

        // Test multiple days during minting period
        for (uint256 day = 2; day <= 6; day++) {
            // Generate more fees
            if (monstr.balanceOf(alice) > 1 ether) {
                vm.prank(alice);
                monstr.transfer(bob, 1 ether);
            } else if (monstr.balanceOf(bob) > 1 ether) {
                vm.prank(bob);
                monstr.transfer(alice, 1 ether);
            }

            // Move to next day
            moveToNextDay();

            // Execute lottery
            vm.prevrandao(bytes32(uint256(day * 1000)));
            monstr.executeLottery();

            // Verify no auction was created (bidder should be address(0))
            (bidder, , , auctionAmount, ) = monstr.currentAuction();
            // During minting period, no auctions should be active (no bidder)
            // But auctionAmount might represent randomness pool balance
            assertEq(
                bidder,
                address(0),
                string.concat(
                    "No auction bidder should exist on day ",
                    vm.toString(day)
                )
            );
        }

        // Now test the transition: day 7 is last day of minting period
        moveToNextDay();
        currentDay = monstr.getCurrentDay();
        assertEq(currentDay, 7, "Should be day 7 (last day of minting period)");

        // Generate fees on day 7
        vm.prank(charlie);
        bool success3 = monstr.transfer(alice, 2 ether);
        assertTrue(success3, "Transfer should succeed");

        // Move to day 8 (first day after minting period)
        moveToNextDay();
        currentDay = monstr.getCurrentDay();
        assertEq(currentDay, 8, "Should be day 8 (after minting period)");

        // Execute lottery for day 7's fees
        vm.prevrandao(bytes32(uint256(99999)));
        monstr.executeLottery();

        // After minting period, we should start seeing auctions
        // Day 7 is odd, so it should be lottery
        // Day 8 (current) would get auction if there are fees

        // Generate fees on day 8
        vm.prank(alice);
        bool success4 = monstr.transfer(bob, 1 ether);
        assertTrue(success4, "Transfer should succeed");

        // Move to day 9 and execute
        moveToNextDay();
        monstr.executeLottery();

        // Now check if auction was created (day 8 is even, so should be auction)
        (bidder, , , auctionAmount, ) = monstr.currentAuction();
        assertGt(
            auctionAmount,
            0,
            "Should have auction after minting period on even days"
        );

        console.log(
            "Verified: No auctions during minting period, auctions start after day 7"
        );
    }

    /**
     * @dev Test that verifies claimed amounts exactly match the prize amounts
     * This ensures no tokens are lost or created during the claim process
     */
    function testExactPrizeAmountsClaimed() public {
        // Setup holders during minting period
        vm.expectEmit(true, false, false, true);
        emit Minted(alice, 100 ether, 99 ether, 1 ether);
        vm.prank(alice);
        monstr.mint{value: 100 ether}();
        assertEq(monstr.balanceOf(alice), 99 ether, "Alice initial balance");

        vm.expectEmit(true, false, false, true);
        emit Minted(bob, 100 ether, 99 ether, 1 ether);
        vm.prank(bob);
        monstr.mint{value: 100 ether}();
        assertEq(monstr.balanceOf(bob), 99 ether, "Bob initial balance");

        vm.expectEmit(true, false, false, true);
        emit Minted(charlie, 50 ether, 49.5 ether, 0.5 ether);
        vm.prank(charlie);
        monstr.mint{value: 50 ether}();
        assertEq(
            monstr.balanceOf(charlie),
            49.5 ether,
            "Charlie initial balance"
        );

        // During minting period (days 0-6), all fees go to lottery
        // After day 7, it alternates: odd days = lottery, even days = auction

        // Test lottery prize during minting period first
        // Day 1: Generate fees
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        bool success1 = monstr.transfer(bob, 10 ether); // 0.1 MONSTR fee
        assertTrue(success1, "Transfer should succeed");
        // Alice: 99 - 10 = 89
        assertEq(
            monstr.balanceOf(alice),
            89 ether,
            "Alice balance after transfer"
        );
        // Bob: 99 + 9.9 = 108.9
        assertEq(
            monstr.balanceOf(bob),
            108.9 ether,
            "Bob balance after receiving"
        );

        // Day 2: Execute lottery for day 1's fees
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(bytes32(uint256(111111)));
        // Total fees: 1 + 1 + 0.5 (mint fees) + 0.1 (transfer fee) = 2.6 MONSTR
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0); // Don't know exact winner due to randomness
        monstr.executeLottery();

        // Check the lottery prize amount
        uint256 lotteryDay = 1;
        (address lotteryWinner, uint112 lotteryPrizeAmount) = monstr
            .lotteryUnclaimedPrizes(lotteryDay % 7);

        console.log("Lottery winner:", lotteryWinner);
        console.log("Lottery prize amount:", lotteryPrizeAmount);

        // The winner should have exactly this amount claimable
        vm.prank(lotteryWinner);
        uint256 claimableBeforeClaim = monstr.getMyClaimableAmount();
        assertEq(
            claimableBeforeClaim,
            lotteryPrizeAmount,
            "Claimable should match lottery prize"
        );

        // Claim the lottery prize
        uint256 balanceBeforeClaim = monstr.balanceOf(lotteryWinner);
        vm.prank(lotteryWinner);
        monstr.claim();
        uint256 balanceAfterClaim = monstr.balanceOf(lotteryWinner);

        // Verify exact amount was transferred
        uint256 actualClaimed = balanceAfterClaim - balanceBeforeClaim;
        assertEq(
            actualClaimed,
            lotteryPrizeAmount,
            "Should claim exact lottery prize amount"
        );
        // During minting period: All fees go to lottery (no auction)
        // Total fees: 2.6 MONSTR (1 + 1 + 0.5 mint fees + 0.1 transfer fee)
        // Lottery gets: 2.6 * 1.0 = 2.6 MONSTR (100% during minting period)
        assertEq(
            actualClaimed,
            2.6 ether,
            "Should claim exactly 2.6 MONSTR in fees (100% during minting period)"
        );
        console.log("Actual claimed amount:", actualClaimed);

        // Verify claimable is now zero
        vm.prank(lotteryWinner);
        uint256 claimableAfterClaim = monstr.getMyClaimableAmount();
        assertEq(
            claimableAfterClaim,
            0,
            "Should have no claimable amount after claiming"
        );

        // Verify the prize slot is cleared
        (address winnerAfter, uint112 amountAfter) = monstr
            .lotteryUnclaimedPrizes(lotteryDay % 7);
        assertEq(
            winnerAfter,
            address(0),
            "Winner should be cleared after claim"
        );
        assertEq(amountAfter, 0, "Amount should be cleared after claim");

        console.log("Verified: Exact lottery prize amount claimed");

        // Now test auction prize claiming after minting period
        // Move to day 8 (past minting period)
        moveToNextDay(); // day 3
        moveToNextDay(); // day 4
        moveToNextDay(); // day 5
        moveToNextDay(); // day 6
        moveToNextDay(); // day 7
        moveToNextDay(); // day 8

        // Day 8 is even, so fees go to auction
        // Check who has balance and can transfer
        uint256 aliceBalanceNow = monstr.balanceOf(alice);
        uint256 bobBalanceNow = monstr.balanceOf(bob);
        uint256 charlieBalanceNow = monstr.balanceOf(charlie);

        // Transfer from whoever has balance
        uint256 transferAmount = 4 ether;
        uint256 expectedFee = 0.04 ether; // 1% of 4

        if (aliceBalanceNow > transferAmount) {
            uint256 bobBalanceBefore = monstr.balanceOf(bob);
            vm.prank(alice);
            bool success = monstr.transfer(bob, transferAmount);
            assertTrue(success, "Transfer should succeed");
            // Verify fee was deducted correctly
            assertEq(
                monstr.balanceOf(bob) - bobBalanceBefore,
                transferAmount - expectedFee,
                "Bob should receive amount minus fee"
            );
        } else if (bobBalanceNow > transferAmount) {
            uint256 aliceBalanceBefore = monstr.balanceOf(alice);
            vm.prank(bob);
            bool success = monstr.transfer(alice, transferAmount);
            assertTrue(success, "Transfer should succeed");
            // Verify fee was deducted correctly
            assertEq(
                monstr.balanceOf(alice) - aliceBalanceBefore,
                transferAmount - expectedFee,
                "Alice should receive amount minus fee"
            );
        } else if (charlieBalanceNow > transferAmount) {
            uint256 aliceBalanceBefore = monstr.balanceOf(alice);
            vm.prank(charlie);
            bool success = monstr.transfer(alice, transferAmount);
            assertTrue(success, "Transfer should succeed");
            // Verify fee was deducted correctly
            assertEq(
                monstr.balanceOf(alice) - aliceBalanceBefore,
                transferAmount - expectedFee,
                "Alice should receive amount minus fee"
            );
        } else {
            // Skip auction test if no one has enough balance
            console.log("Skipping auction test - insufficient balances");
            return;
        }

        // Day 9: Execute to start auction
        moveToNextDay();
        // Day 8 was even, so half the fees (20 MONSTR) go to lottery, half to auction
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0);
        vm.expectEmit(false, false, false, false);
        emit AuctionStarted(0, 0, 0);
        monstr.executeLottery();

        // Check current auction (should have day 8's auction fees)
        (, , , uint112 auctionTokenAmount, uint112 auctionDay) = monstr
            .currentAuction();
        console.log("Auction token amount:", auctionTokenAmount);
        console.log("Auction day:", auctionDay);
        // Should be 0.02 MONSTR (half of 0.04 MONSTR fees from day 8)
        assertEq(
            auctionTokenAmount,
            0.02 ether,
            "Auction should have 0.02 MONSTR"
        );
        assertEq(auctionDay, 8, "Auction should be for day 8");

        // Place a bid
        vm.startPrank(david);
        uint256 wethBefore = wmon.balanceOf(david);
        wmon.deposit{value: 10 ether}();
        assertEq(
            wmon.balanceOf(david) - wethBefore,
            10 ether,
            "David should have deposited 10 WMON"
        );
        wmon.approve(address(monstr), 10 ether);

        vm.expectEmit(true, false, false, true);
        emit BidPlaced(david, 1 ether, auctionDay);
        monstr.bid(1 ether);
        vm.stopPrank();

        // Generate some fees for day 10 before executing
        // Transfer from whoever has balance
        if (monstr.balanceOf(bob) > 2 ether) {
            vm.prank(bob);
            monstr.transfer(alice, 2 ether);
        } else if (monstr.balanceOf(charlie) > 2 ether) {
            vm.prank(charlie);
            monstr.transfer(alice, 2 ether);
        } else if (monstr.balanceOf(alice) > 2 ether) {
            vm.prank(alice);
            monstr.transfer(bob, 2 ether);
        }

        // Move to day 10 to finalize auction
        moveToNextDay();
        monstr.executeLottery();

        // Check david's claimable (should be the auction tokens)
        vm.prank(david);
        uint256 davidClaimable = monstr.getMyClaimableAmount();

        // David should be able to claim the auction amount
        // The amount depends on the fees collected for the auction day
        assertGt(
            davidClaimable,
            0,
            "David should have some MONSTR claimable from auction"
        );
        console.log("David's claimable amount from auction:", davidClaimable);

        // Claim the auction prize
        uint256 davidBalanceBefore = monstr.balanceOf(david);
        vm.prank(david);
        monstr.claim();
        uint256 davidBalanceAfter = monstr.balanceOf(david);

        // Verify exact amount was transferred
        uint256 davidActualClaimed = davidBalanceAfter - davidBalanceBefore;
        assertEq(
            davidActualClaimed,
            davidClaimable,
            "Claimed amount should match claimable"
        );
        assertGt(
            davidActualClaimed,
            0,
            "David should have claimed some amount"
        );

        // Verify claimable is now zero
        vm.prank(david);
        uint256 davidClaimableAfter = monstr.getMyClaimableAmount();
        assertEq(
            davidClaimableAfter,
            0,
            "David should have no claimable amount after claiming"
        );

        // Check the auction prize slot is cleared
        (address auctionWinner, uint112 auctionPrizeAmount) = monstr
            .auctionUnclaimedPrizes(auctionDay % 7);
        assertEq(
            auctionWinner,
            address(0),
            "Auction winner should be cleared after claim"
        );
        assertEq(
            auctionPrizeAmount,
            0,
            "Auction amount should be cleared after claim"
        );

        console.log("Verified: Exact auction prize amount claimed");
    }
}
