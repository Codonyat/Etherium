// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EtheriumTestBase} from "./helpers/EtheriumTestBase.sol";
import {console} from "forge-std/Test.sol";
import {IWETH} from "../src/Etherium.sol";
import {MockWETH} from "./helpers/WETHHelpers.sol";

contract EtheriumUnclaimedPrizesBugTest is EtheriumTestBase {
    IWETH public constant WETH =
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    uint256 mainnetFork;
    
    // Additional events not in base class
    event BidPlaced(address indexed bidder, uint256 amount, uint256 day);
    event AuctionStarted(uint256 day, uint256 etheriumAmount, uint256 minBid);

    function setUp() public override {
        // Use mainnet fork
        mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);

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
        emit Minted(alice, 100 ether, 99000 ether, 1000 ether);
        vm.prank(alice);
        etherium.mint{value: 100 ether}();

        vm.expectEmit(true, false, false, true);
        emit Minted(bob, 100 ether, 99000 ether, 1000 ether);
        vm.prank(bob);
        etherium.mint{value: 100 ether}();

        vm.expectEmit(true, false, false, true);
        emit Minted(charlie, 100 ether, 99000 ether, 1000 ether);
        vm.prank(charlie);
        etherium.mint{value: 100 ether}();

        // Skip past minting period to enable alternating lottery/auction
        vm.warp(block.timestamp + 8 days);

        // Generate some fees through transfers
        // Transfer fee is 1%, so 10000 * 0.01 = 100 ETHERIUM fee
        vm.prank(alice);
        bool success1 = etherium.transfer(bob, 10000 ether);
        assertTrue(success1, "Transfer should succeed");
        // Alice should have 99000 - 10000 = 89000 ETHERIUM
        assertEq(etherium.balanceOf(alice), 89000 ether, "Alice balance after transfer");
        // Bob should have 99000 + 9900 = 108900 ETHERIUM (10000 - 100 fee)
        assertEq(etherium.balanceOf(bob), 108900 ether, "Bob balance after receiving");

        // Transfer 5000 ETHERIUM, fee = 50 ETHERIUM
        vm.prank(bob);
        bool success2 = etherium.transfer(charlie, 5000 ether);
        assertTrue(success2, "Transfer should succeed");
        // Bob should have 108900 - 5000 = 103900 ETHERIUM
        assertEq(etherium.balanceOf(bob), 103900 ether, "Bob balance after transfer");
        // Charlie should have 99000 + 4950 = 103950 ETHERIUM
        assertEq(etherium.balanceOf(charlie), 103950 ether, "Charlie balance after receiving");

        // Day 8: Execute lottery
        moveToNextDay();
        etherium.executeLottery();

        // Generate more fees for the auction
        // Transfer 3000 ETHERIUM, fee = 30 ETHERIUM
        vm.prank(charlie);
        bool success3 = etherium.transfer(alice, 3000 ether);
        assertTrue(success3, "Transfer should succeed");
        // Charlie should have 103950 - 3000 = 100950 ETHERIUM
        assertEq(etherium.balanceOf(charlie), 100950 ether, "Charlie balance after transfer");
        // Alice should have 89000 + 2970 = 91970 ETHERIUM
        assertEq(etherium.balanceOf(alice), 91970 ether, "Alice balance after receiving");

        // Day 9: Execute lottery which will also start an auction
        moveToNextDay();

        // Execute lottery - someone will win
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0); // We don't know who will win due to randomness
        etherium.executeLottery();

        // Determine who won the Day 9 lottery by checking claimable amounts
        address day9LotteryWinner;
        uint256 day9LotteryPrize;

        vm.prank(alice);
        uint256 aliceClaimable = etherium.getMyClaimableAmount();
        vm.prank(bob);
        uint256 bobClaimable = etherium.getMyClaimableAmount();
        vm.prank(charlie);
        uint256 charlieClaimable = etherium.getMyClaimableAmount();

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
        WETH.deposit{value: 10 ether}();
        WETH.approve(address(etherium), 10 ether);
        
        // Get auction details before bidding
        (,, , uint112 auctionAmount, uint112 auctionDay) = etherium.currentAuction();
        assertGt(auctionAmount, 0, "Auction should have tokens");
        
        // Expect bid event
        vm.expectEmit(true, false, false, true);
        emit BidPlaced(david, 1 ether, auctionDay);
        etherium.bid(1 ether);
        vm.stopPrank();

        // Generate fees for next day
        // Transfer 2000 ETHERIUM, fee = 20 ETHERIUM
        vm.prank(alice);
        bool success4 = etherium.transfer(bob, 2000 ether);
        assertTrue(success4, "Transfer should succeed");

        // Day 10: Execute lottery again, which will also finalize the auction
        moveToNextDay();

        // Execute lottery - this will finalize the auction
        etherium.executeLottery();

        // Check claimable amounts after auction finalization
        vm.prank(alice);
        uint256 aliceAfter = etherium.getMyClaimableAmount();
        vm.prank(bob);
        uint256 bobAfter = etherium.getMyClaimableAmount();
        vm.prank(charlie);
        uint256 charlieAfter = etherium.getMyClaimableAmount();
        vm.prank(david);
        uint256 davidClaimable = etherium.getMyClaimableAmount();

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
        emit Minted(alice, 100 ether, 99000 ether, 1000 ether);
        vm.prank(alice);
        etherium.mint{value: 100 ether}();

        vm.expectEmit(true, false, false, true);
        emit Minted(bob, 100 ether, 99000 ether, 1000 ether);
        vm.prank(bob);
        etherium.mint{value: 100 ether}();

        vm.expectEmit(true, false, false, true);
        emit Minted(charlie, 100 ether, 99000 ether, 1000 ether);
        vm.prank(charlie);
        etherium.mint{value: 100 ether}();

        // Skip past minting period
        vm.warp(block.timestamp + 8 days);

        // Generate fees
        vm.prank(alice);
        bool success1 = etherium.transfer(bob, 10000 ether);
        assertTrue(success1, "Transfer should succeed");
        // Verify balances: Alice had 99000, transferred 10000, has 89000
        assertEq(etherium.balanceOf(alice), 89000 ether, "Alice balance after transfer");
        // Bob had 99000, received 9900 (10000 - 100 fee), has 108900
        assertEq(etherium.balanceOf(bob), 108900 ether, "Bob balance after receiving");

        // Day 8: Execute lottery
        moveToNextDay();
        etherium.executeLottery();

        // Generate more fees
        vm.prank(bob);
        bool success2 = etherium.transfer(alice, 5000 ether);
        assertTrue(success2, "Transfer should succeed");
        // Bob had 108900, transferred 5000, has 103900
        assertEq(etherium.balanceOf(bob), 103900 ether, "Bob balance after transfer");
        // Alice had 89000, received 4950 (5000 - 50 fee), has 93950
        assertEq(etherium.balanceOf(alice), 93950 ether, "Alice balance after receiving");

        // Day 9: Execute lottery and start auction
        moveToNextDay();
        etherium.executeLottery();

        // Determine who won Day 9 lottery by checking claimable amounts
        vm.prank(alice);
        uint256 aliceClaimableBefore = etherium.getMyClaimableAmount();
        vm.prank(bob);
        uint256 bobClaimableBefore = etherium.getMyClaimableAmount();
        vm.prank(charlie);
        uint256 charlieClaimableBefore = etherium.getMyClaimableAmount();

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
        uint256 davidWethBefore = WETH.balanceOf(david);
        WETH.deposit{value: 10 ether}();
        uint256 davidWethAfterDeposit = WETH.balanceOf(david);
        assertEq(davidWethAfterDeposit - davidWethBefore, 10 ether, "David should have deposited 10 WETH");
        WETH.approve(address(etherium), 10 ether);
        
        // Get auction details before bidding
        (,, , uint112 auctionAmount, uint112 auctionDay) = etherium.currentAuction();
        assertGt(auctionAmount, 0, "Auction should have tokens");
        
        // Expect bid event
        vm.expectEmit(true, false, false, true);
        emit BidPlaced(david, 1 ether, auctionDay);
        etherium.bid(1 ether);
        
        // Verify WETH was transferred
        uint256 davidWethAfterBid = WETH.balanceOf(david);
        assertEq(davidWethAfterDeposit - davidWethAfterBid, 1 ether, "David should have spent 1 WETH on bid");
        vm.stopPrank();

        // Day 10: Finalize auction
        moveToNextDay();
        etherium.executeLottery();

        // Check claimable amounts after auction finalization
        vm.prank(alice);
        uint256 aliceClaimableAfter = etherium.getMyClaimableAmount();
        vm.prank(bob);
        uint256 bobClaimableAfter = etherium.getMyClaimableAmount();
        vm.prank(charlie);
        uint256 charlieClaimableAfter = etherium.getMyClaimableAmount();
        vm.prank(david);
        uint256 davidClaimable = etherium.getMyClaimableAmount();

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
            uint256 davidBalanceBefore = etherium.balanceOf(david);
            vm.prank(david);
            etherium.claim();
            uint256 davidBalanceAfter = etherium.balanceOf(david);

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
            assertEq(etherium.getMyClaimableAmount(), 0, "David should have no claimable after claiming");
        }
    }

    /**
     * @dev Test that verifies no auctions occur during the minting period
     * All fees should go to lottery during the first 7 days
     */
    function testNoAuctionsDuringMintingPeriod() public {
        // During minting period (first 7 days)
        // All fees should go to lottery, not auction

        // Day 0: Setup holders
        vm.expectEmit(true, false, false, true);
        emit Minted(alice, 100 ether, 99000 ether, 1000 ether);
        vm.prank(alice);
        etherium.mint{value: 100 ether}();
        assertEq(etherium.balanceOf(alice), 99000 ether, "Alice initial balance");

        vm.expectEmit(true, false, false, true);
        emit Minted(bob, 100 ether, 99000 ether, 1000 ether);
        vm.prank(bob);
        etherium.mint{value: 100 ether}();
        assertEq(etherium.balanceOf(bob), 99000 ether, "Bob initial balance");

        vm.expectEmit(true, false, false, true);
        emit Minted(charlie, 50 ether, 49500 ether, 500 ether);
        vm.prank(charlie);
        etherium.mint{value: 50 ether}();
        assertEq(etherium.balanceOf(charlie), 49500 ether, "Charlie initial balance");

        // Still in minting period (day 0)
        uint256 currentDay = etherium.getCurrentDay();
        assertEq(currentDay, 0, "Should be day 0");

        // Generate fees through transfers
        vm.prank(alice);
        bool success1 = etherium.transfer(bob, 5000 ether);
        assertTrue(success1, "Transfer should succeed");
        // Alice: 99000 - 5000 = 94000
        assertEq(etherium.balanceOf(alice), 94000 ether, "Alice balance after transfer");
        // Bob: 99000 + 4950 = 103950 (received 5000 - 50 fee)
        assertEq(etherium.balanceOf(bob), 103950 ether, "Bob balance after receiving");

        vm.prank(bob);
        bool success2 = etherium.transfer(charlie, 3000 ether);
        assertTrue(success2, "Transfer should succeed");
        // Bob: 103950 - 3000 = 100950
        assertEq(etherium.balanceOf(bob), 100950 ether, "Bob balance after transfer");
        // Charlie: 49500 + 2970 = 52470 (received 3000 - 30 fee)
        assertEq(etherium.balanceOf(charlie), 52470 ether, "Charlie balance after receiving");

        // Move to day 1 (still in minting period)
        moveToNextDay();
        currentDay = etherium.getCurrentDay();
        assertEq(currentDay, 1, "Should be day 1");

        // Execute lottery - should be lottery, not auction
        vm.prevrandao(bytes32(uint256(12345)));
        // During minting period, all fees go to lottery
        // Total fees so far: 1000 + 1000 + 500 (mint fees) + 50 + 30 (transfer fees) = 2580 ETHERIUM
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0); // We don't know exact winner/amount due to randomness
        etherium.executeLottery();

        // Check that there's no active auction
        (address bidder, , , uint112 auctionAmount, ) = etherium
            .currentAuction();
        assertEq(
            auctionAmount,
            0,
            "Should be no auction during minting period"
        );
        assertEq(
            bidder,
            address(0),
            "Should be no bidder during minting period"
        );

        // Check that lottery was executed (someone should have won)
        (address lotteryWinner, uint112 lotteryPrize) = etherium
            .lotteryUnclaimedPrizes(0 % 7);
        assertTrue(
            lotteryWinner == alice ||
                lotteryWinner == bob ||
                lotteryWinner == charlie,
            "Should have a lottery winner during minting period"
        );
        assertGt(lotteryPrize, 0, "Lottery prize should be greater than 0");
        // Verify the prize amount is the total fees collected
        assertEq(lotteryPrize, 2580 ether, "Lottery prize should be all collected fees");

        // Test multiple days during minting period
        for (uint256 day = 2; day <= 6; day++) {
            // Generate more fees
            if (etherium.balanceOf(alice) > 1000 ether) {
                vm.prank(alice);
                etherium.transfer(bob, 1000 ether);
            } else if (etherium.balanceOf(bob) > 1000 ether) {
                vm.prank(bob);
                etherium.transfer(alice, 1000 ether);
            }

            // Move to next day
            moveToNextDay();

            // Execute lottery
            vm.prevrandao(bytes32(uint256(day * 1000)));
            etherium.executeLottery();

            // Verify no auction was created
            (bidder, , , auctionAmount, ) = etherium.currentAuction();
            if (auctionAmount > 0) {
                // If there's an auction amount, it should be from a previous day
                // not from the current execution
                assertTrue(
                    day >= 7,
                    string.concat(
                        "No auction should be created on day ",
                        vm.toString(day)
                    )
                );
            }
        }

        // Now test the transition: day 7 is last day of minting period
        moveToNextDay();
        currentDay = etherium.getCurrentDay();
        assertEq(currentDay, 7, "Should be day 7 (last day of minting period)");

        // Generate fees on day 7
        vm.prank(charlie);
        bool success3 = etherium.transfer(alice, 2000 ether);
        assertTrue(success3, "Transfer should succeed");

        // Move to day 8 (first day after minting period)
        moveToNextDay();
        currentDay = etherium.getCurrentDay();
        assertEq(currentDay, 8, "Should be day 8 (after minting period)");

        // Execute lottery for day 7's fees
        vm.prevrandao(bytes32(uint256(99999)));
        etherium.executeLottery();

        // After minting period, we should start seeing auctions
        // Day 7 is odd, so it should be lottery
        // Day 8 (current) would get auction if there are fees

        // Generate fees on day 8
        vm.prank(alice);
        bool success4 = etherium.transfer(bob, 1000 ether);
        assertTrue(success4, "Transfer should succeed");

        // Move to day 9 and execute
        moveToNextDay();
        etherium.executeLottery();

        // Now check if auction was created (day 8 is even, so should be auction)
        (bidder, , , auctionAmount, ) = etherium.currentAuction();
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
        emit Minted(alice, 100 ether, 99000 ether, 1000 ether);
        vm.prank(alice);
        etherium.mint{value: 100 ether}();
        assertEq(etherium.balanceOf(alice), 99000 ether, "Alice initial balance");

        vm.expectEmit(true, false, false, true);
        emit Minted(bob, 100 ether, 99000 ether, 1000 ether);
        vm.prank(bob);
        etherium.mint{value: 100 ether}();
        assertEq(etherium.balanceOf(bob), 99000 ether, "Bob initial balance");

        vm.expectEmit(true, false, false, true);
        emit Minted(charlie, 50 ether, 49500 ether, 500 ether);
        vm.prank(charlie);
        etherium.mint{value: 50 ether}();
        assertEq(etherium.balanceOf(charlie), 49500 ether, "Charlie initial balance");

        // During minting period (days 0-6), all fees go to lottery
        // After day 7, it alternates: odd days = lottery, even days = auction

        // Test lottery prize during minting period first
        // Day 1: Generate fees
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        bool success1 = etherium.transfer(bob, 10000 ether); // 100 ETHERIUM fee
        assertTrue(success1, "Transfer should succeed");
        // Alice: 99000 - 10000 = 89000
        assertEq(etherium.balanceOf(alice), 89000 ether, "Alice balance after transfer");
        // Bob: 99000 + 9900 = 108900
        assertEq(etherium.balanceOf(bob), 108900 ether, "Bob balance after receiving");

        // Day 2: Execute lottery for day 1's fees
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(bytes32(uint256(111111)));
        // Total fees: 1000 + 1000 + 500 (mint fees) + 100 (transfer fee) = 2600 ETHERIUM
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0); // Don't know exact winner due to randomness
        etherium.executeLottery();

        // Check the lottery prize amount
        uint256 lotteryDay = 1;
        (address lotteryWinner, uint112 lotteryPrizeAmount) = etherium
            .lotteryUnclaimedPrizes(lotteryDay % 7);

        console.log("Lottery winner:", lotteryWinner);
        console.log("Lottery prize amount:", lotteryPrizeAmount);

        // The winner should have exactly this amount claimable
        vm.prank(lotteryWinner);
        uint256 claimableBeforeClaim = etherium.getMyClaimableAmount();
        assertEq(
            claimableBeforeClaim,
            lotteryPrizeAmount,
            "Claimable should match lottery prize"
        );

        // Claim the lottery prize
        uint256 balanceBeforeClaim = etherium.balanceOf(lotteryWinner);
        vm.prank(lotteryWinner);
        etherium.claim();
        uint256 balanceAfterClaim = etherium.balanceOf(lotteryWinner);

        // Verify exact amount was transferred
        uint256 actualClaimed = balanceAfterClaim - balanceBeforeClaim;
        assertEq(
            actualClaimed,
            lotteryPrizeAmount,
            "Should claim exact lottery prize amount"
        );
        // During minting period: All fees go to lottery
        // Total fees should be 2600 ETHERIUM (1000 + 1000 + 500 mint fees + 100 transfer fee)
        assertEq(actualClaimed, 2600 ether, "Should claim exactly 2600 ETHERIUM in fees");
        console.log("Actual claimed amount:", actualClaimed);

        // Verify claimable is now zero
        vm.prank(lotteryWinner);
        uint256 claimableAfterClaim = etherium.getMyClaimableAmount();
        assertEq(
            claimableAfterClaim,
            0,
            "Should have no claimable amount after claiming"
        );

        // Verify the prize slot is cleared
        (address winnerAfter, uint112 amountAfter) = etherium
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
        uint256 aliceBalanceNow = etherium.balanceOf(alice);
        uint256 bobBalanceNow = etherium.balanceOf(bob);
        uint256 charlieBalanceNow = etherium.balanceOf(charlie);
        
        // Transfer from whoever has balance
        uint256 transferAmount = 4000 ether;
        uint256 expectedFee = 40 ether; // 1% of 4000
        
        if (aliceBalanceNow > transferAmount) {
            uint256 bobBalanceBefore = etherium.balanceOf(bob);
            vm.prank(alice);
            bool success = etherium.transfer(bob, transferAmount);
            assertTrue(success, "Transfer should succeed");
            // Verify fee was deducted correctly
            assertEq(etherium.balanceOf(bob) - bobBalanceBefore, transferAmount - expectedFee, "Bob should receive amount minus fee");
        } else if (bobBalanceNow > transferAmount) {
            uint256 aliceBalanceBefore = etherium.balanceOf(alice);
            vm.prank(bob);
            bool success = etherium.transfer(alice, transferAmount);
            assertTrue(success, "Transfer should succeed");
            // Verify fee was deducted correctly
            assertEq(etherium.balanceOf(alice) - aliceBalanceBefore, transferAmount - expectedFee, "Alice should receive amount minus fee");
        } else if (charlieBalanceNow > transferAmount) {
            uint256 aliceBalanceBefore = etherium.balanceOf(alice);
            vm.prank(charlie);
            bool success = etherium.transfer(alice, transferAmount);
            assertTrue(success, "Transfer should succeed");
            // Verify fee was deducted correctly
            assertEq(etherium.balanceOf(alice) - aliceBalanceBefore, transferAmount - expectedFee, "Alice should receive amount minus fee");
        } else {
            // Skip auction test if no one has enough balance
            console.log("Skipping auction test - insufficient balances");
            return;
        }

        // Day 9: Execute to start auction
        moveToNextDay();
        // Day 8 was even, so half the fees (20 ETHERIUM) go to lottery, half to auction
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0);
        vm.expectEmit(false, false, false, false);
        emit AuctionStarted(0, 0, 0);
        etherium.executeLottery();

        // Check current auction (should have day 8's auction fees)
        (
            ,
            ,
            ,
            uint112 auctionTokenAmount,
            uint112 auctionDay
        ) = etherium.currentAuction();
        console.log("Auction token amount:", auctionTokenAmount);
        console.log("Auction day:", auctionDay);
        // Should be 20 ETHERIUM (half of 40 ETHERIUM fees from day 8)
        assertEq(auctionTokenAmount, 20 ether, "Auction should have 20 ETHERIUM");
        assertEq(auctionDay, 8, "Auction should be for day 8");

        // Place a bid
        vm.startPrank(david);
        uint256 wethBefore = WETH.balanceOf(david);
        WETH.deposit{value: 10 ether}();
        assertEq(WETH.balanceOf(david) - wethBefore, 10 ether, "David should have deposited 10 WETH");
        WETH.approve(address(etherium), 10 ether);
        
        vm.expectEmit(true, false, false, true);
        emit BidPlaced(david, 1 ether, auctionDay);
        etherium.bid(1 ether);
        vm.stopPrank();

        // Generate some fees for day 10 before executing
        // Transfer from whoever has balance
        if (etherium.balanceOf(bob) > 2000 ether) {
            vm.prank(bob);
            etherium.transfer(alice, 2000 ether);
        } else if (etherium.balanceOf(charlie) > 2000 ether) {
            vm.prank(charlie);
            etherium.transfer(alice, 2000 ether);
        } else if (etherium.balanceOf(alice) > 2000 ether) {
            vm.prank(alice);
            etherium.transfer(bob, 2000 ether);
        }

        // Move to day 10 to finalize auction
        moveToNextDay();
        etherium.executeLottery();

        // Check david's claimable (should be the auction tokens)
        vm.prank(david);
        uint256 davidClaimable = etherium.getMyClaimableAmount();

        // David should be able to claim the auction amount
        // The amount depends on the fees collected for the auction day
        assertGt(
            davidClaimable,
            0,
            "David should have some ETHERIUM claimable from auction"
        );
        console.log("David's claimable amount from auction:", davidClaimable);

        // Claim the auction prize
        uint256 davidBalanceBefore = etherium.balanceOf(david);
        vm.prank(david);
        etherium.claim();
        uint256 davidBalanceAfter = etherium.balanceOf(david);

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
        uint256 davidClaimableAfter = etherium.getMyClaimableAmount();
        assertEq(
            davidClaimableAfter,
            0,
            "David should have no claimable amount after claiming"
        );

        // Check the auction prize slot is cleared
        (address auctionWinner, uint112 auctionPrizeAmount) = etherium
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
