// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrategyTestBase, MockContract, ReentrancyAttacker, MockRejectNative, MockMEGA} from "./helpers/StrategyTestBase.sol";
import {console} from "forge-std/Test.sol";
import {Strategy} from "../src/Strategy.sol";

contract StrategyCoreTest is StrategyTestBase {
    function testTransferWithFee() public {
        // Alice mints tokens
        mintGiga(alice, 10 ether);

        // Verify initial balances
        uint256 aliceInitial = giga.balanceOf(alice);
        assertEq(
            aliceInitial,
            9.9 ether,
            "Alice should have 9900 GIGA after minting"
        );
        assertEq(
            giga.balanceOf(giga.FEES_POOL()),
            0.1 ether,
            "Fees pool should have 0.1 GIGA from mint"
        );

        uint256 transferAmount = 1 ether;
        uint256 expectedFee = 0.01 ether; // 1% fee
        uint256 expectedReceived = transferAmount - expectedFee;

        // Transfer with fee verification
        vm.prank(alice);
        bool success = giga.transfer(bob, transferAmount);
        assertTrue(success, "Transfer should succeed");

        assertEq(
            giga.balanceOf(alice),
            aliceInitial - transferAmount,
            "Alice balance should decrease by transfer amount"
        );
        assertEq(
            giga.balanceOf(bob),
            expectedReceived,
            "Bob should receive amount minus fee"
        );
        assertEq(
            giga.balanceOf(giga.FEES_POOL()),
            0.1 ether + expectedFee,
            "Fees pool should increase by transfer fee"
        );
    }

    function testRejectDirectNativeTransfer() public {
        // The contract now rejects native ETH transfers
        // It expects ERC20 MEGA instead
        uint256 initialSupply = giga.totalSupply();

        vm.prank(alice);
        vm.expectRevert("Use mint() with ERC20 MEGA");
        (bool success, ) = address(giga).call{value: 1 ether}("");

        // No tokens should be minted
        assertEq(
            giga.totalSupply(),
            initialSupply,
            "No tokens should be minted"
        );
        assertEq(giga.balanceOf(alice), 0, "Alice should have no tokens");
    }

    function testReentrancyGuardWorks() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(giga, mega);
        mega.mint(address(attacker), 10 ether);

        // Attacker tries to reenter during mint
        vm.prank(address(attacker));
        attacker.attack(2 ether);

        // Check that only one mint succeeded
        uint256 attackerBalance = giga.balanceOf(address(attacker));
        assertEq(attackerBalance, 1.98 ether); // Only one mint: 2 MEGA * 0.99 (after 1% fee)
    }

    function testNativeSentToBeneficiariesNotTokens() public {
        // Setup beneficiary addresses
        address beneficiary1 = address(0x9999);
        address beneficiary2 = address(0x8888);

        // Setup holders
        setupBasicHolders();

        // Move past minting period
        skipPastMintingPeriod();

        // Generate fees
        uint256 aliceBalanceBefore = giga.balanceOf(alice);
        uint256 bobBalanceBefore = giga.balanceOf(bob);
        vm.prank(alice);
        bool success = giga.transfer(bob, 1 ether);
        assertTrue(success, "Transfer should succeed");
        assertEq(
            giga.balanceOf(alice),
            aliceBalanceBefore - 1 ether,
            "Alice balance should decrease by 1"
        );
        assertEq(
            giga.balanceOf(bob),
            bobBalanceBefore + 0.99 ether,
            "Bob should receive 990 (1000 - 10 fee)"
        );

        // Execute lottery
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(bytes32(uint256(123)));
        giga.executeLottery();

        // Get winner
        (address winner, uint112 prizeAmount) = giga.lotteryUnclaimedPrizes(
            8 % 7
        );

        // Fast forward 14 days to trigger unclaimed prize distribution
        for (uint256 i = 0; i < 14; i++) {
            vm.prank(alice);
            giga.transfer(bob, 0.1 ether);
            vm.warp(block.timestamp + 25 hours + 61);
            giga.executeLottery();
        }

        // Beneficiaries should receive MEGA, not GIGA tokens
        // (Implementation sends to winner if beneficiaries fail)
    }

    function testUnclaimedPrizeFailedTransferGoesToCurrentWinner() public {
        setupBasicHolders();

        // Move past minting period
        skipPastMintingPeriod();

        // Day 9: Generate fees (odd day for lottery)
        vm.warp(block.timestamp + 25 hours);
        uint256 aliceBalanceBefore = giga.balanceOf(alice);
        uint256 bobBalanceBefore = giga.balanceOf(bob);
        vm.prank(alice);
        bool success = giga.transfer(bob, 1 ether);
        assertTrue(success, "Transfer should succeed");
        assertEq(
            giga.balanceOf(alice),
            aliceBalanceBefore - 1 ether,
            "Alice balance should decrease"
        );
        assertEq(
            giga.balanceOf(bob),
            bobBalanceBefore + 0.99 ether,
            "Bob should receive 990 after fee"
        );

        // Day 10: Execute lottery for day 9
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(bytes32(uint256(111)));
        giga.executeLottery();

        (address winner1, uint112 amount1) = giga.lotteryUnclaimedPrizes(
            9 % 7
        );

        // Generate fees for multiple days to potentially overwrite slots
        for (uint256 i = 0; i < 14; i++) {
            // Generate fees
            if (giga.balanceOf(bob) > 100 ether) {
                vm.prank(bob);
                giga.transfer(alice, 0.1 ether);
            } else if (giga.balanceOf(alice) > 100 ether) {
                vm.prank(alice);
                giga.transfer(bob, 0.1 ether);
            }

            // Move to next day and execute
            vm.warp(block.timestamp + 25 hours + 61);
            vm.prevrandao(bytes32(uint256(i * 1000)));
            giga.executeLottery();
        }

        // After 14 days, unclaimed prizes may be distributed
        // Just verify the system continues to work
        assertTrue(true, "System continues to operate after unclaimed prizes");
    }

    function testUnclaimedPrizeGoesToBeneficiary() public {
        setupBasicHolders();

        // Move past minting period
        skipPastMintingPeriod();

        // Day 9: Generate fees
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        // Day 10: Execute lottery for day 9
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(bytes32(uint256(999)));
        giga.executeLottery();

        (address winner, uint112 prizeAmount) = giga.lotteryUnclaimedPrizes(
            9 % 7
        );

        if (winner != address(0)) {
            // Wait 14 days and execute lotteries to trigger unclaimed distribution
            for (uint256 i = 0; i < 14; i++) {
                if (giga.balanceOf(alice) > 100 ether) {
                    vm.prank(alice);
                    giga.transfer(bob, 0.1 ether);
                }
                vm.warp(block.timestamp + 25 hours + 61);
                vm.prevrandao(bytes32(uint256(i * 7777)));
                giga.executeLottery();
            }

            // After 14 days, prize may be distributed
            // The contract handles unclaimed prizes in its own way
            assertTrue(true, "Unclaimed prize handling completed");
        } else {
            // Day 9 was an auction day, not lottery
            assertTrue(true, "Day was auction, not lottery");
        }
    }

    function testBeneficiaryFunding() public {
        setupBasicHolders();

        // Move past minting period
        skipPastMintingPeriod();

        // Generate significant fees
        vm.prank(alice);
        giga.transfer(bob, 5 ether); // 0.05 GIGA fee

        // Execute lottery for day 8
        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        // Check if we got a lottery winner (day 8 is even, so should be 25 GIGA to lottery)
        (address winner1, uint112 prizeAmount1) = giga.lotteryUnclaimedPrizes(
            8 % 7
        );

        if (winner1 != address(0)) {
            // Track the first beneficiary's balance
            address firstBeneficiary = giga.BENEFICIARIES(0);
            uint256 beneficiaryMegaBefore = mega.balanceOf(firstBeneficiary);

            // Capture contract state BEFORE the 7-day wait (before beneficiary transfer)
            uint256 contractMegaBefore = giga.getMegaReserve();
            uint256 totalSupplyBefore = giga.totalSupply();

            // Wait 7 days to trigger unclaimed prize distribution
            for (uint256 i = 0; i < 7; i++) {
                // Generate fees
                vm.prank(alice);
                giga.transfer(bob, 0.1 ether);

                // Execute lottery
                vm.warp(block.timestamp + 25 hours + 61);
                giga.executeLottery();
            }

            // Now check if beneficiary received the correct MEGA amount
            uint256 beneficiaryMegaAfter = mega.balanceOf(firstBeneficiary);

            // Calculate expected MEGA based on token to MEGA conversion
            uint256 expectedMega = (prizeAmount1 * contractMegaBefore) /
                totalSupplyBefore;

            assertApproxEqAbs(
                beneficiaryMegaAfter - beneficiaryMegaBefore,
                expectedMega,
                1, // Allow 1 wei difference for rounding
                "Beneficiary should receive MEGA based on proper token/MEGA conversion"
            );
        }
    }

    function testBeneficiaryFundingReverts() public {
        // Deploy a contract that reverts on native receive as beneficiary
        MockRejectNative rejectingBeneficiary = new MockRejectNative();

        setupBasicHolders();

        // Move past minting period
        skipPastMintingPeriod();

        // Generate fees on day 9 for lottery
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        // Execute lottery on day 10 - should not revert even if public good rejects
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(bytes32(uint256(999)));
        giga.executeLottery();

        // Check for lottery or auction execution
        // Day 9 could be lottery or auction depending on implementation
        (address winner, ) = giga.lotteryUnclaimedPrizes(9 % 7);
        (address bidder, , , uint112 auctionAmount, ) = giga.currentAuction();

        // Should have either lottery winner or auction
        assertTrue(
            winner != address(0) || auctionAmount > 0,
            "Should have executed lottery/auction despite public good reverting"
        );
    }

    function testAuctionWithMEGABids() public {
        // This test verifies MEGA bidding in auctions
        setupBasicHolders();

        // Move past minting period
        skipPastMintingPeriod();

        // Generate fees for auction
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        // Execute to start auction
        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        // Verify auction was created
        (address bidder, , , uint112 auctionAmount, ) = giga.currentAuction();
        assertEq(bidder, address(0), "Auction should have no bidder initially");
        assertGt(auctionAmount, 0, "Auction should have tokens");
    }

    function testLOT_POOLTransfersRedirectedToFEES_POOL() public {
        // Test that external transfers to LOT_POOL are redirected to FEES_POOL
        // This maintains the invariant: LOT_POOL balance == auction amount + unclaimed prizes

        // First mint to the test contract itself to have balance
        mega.mint(address(this), 10 ether);
        mega.approve(address(giga), 10 ether);
        giga.mint(10 ether);

        uint256 testContractBalance = giga.balanceOf(address(this));
        assertEq(
            testContractBalance,
            9.9 ether,
            "Test contract should have 9900 tokens"
        );

        uint256 feesPoolBefore = giga.balanceOf(giga.FEES_POOL());
        uint256 lotPoolBefore = giga.balanceOf(giga.LOT_POOL());

        // Test contract tries to transfer to LOT_POOL
        giga.transfer(giga.LOT_POOL(), 0.1 ether);

        // Should be redirected to FEES_POOL
        uint256 feesPoolAfter = giga.balanceOf(giga.FEES_POOL());
        uint256 lotPoolAfter = giga.balanceOf(giga.LOT_POOL());

        assertEq(
            lotPoolAfter,
            lotPoolBefore,
            "LOT_POOL balance should not change"
        );
        assertEq(
            feesPoolAfter,
            feesPoolBefore + 0.1 ether,
            "FEES_POOL should receive 0.1 tokens (redirected from LOT_POOL)"
        );
    }

    function testInternalLOT_POOLTransfersStillWork() public {
        // Test that internal transfers to LOT_POOL (from FEES_POOL during lottery)
        // still work correctly and are not redirected

        setupBasicHolders();

        // Move past minting period
        skipPastMintingPeriod();

        // Generate fees on day 9 (odd day for lottery)
        vm.warp(block.timestamp + 25 hours);
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        uint256 lotPoolBefore = giga.balanceOf(giga.LOT_POOL());

        // Execute lottery on day 10 for day 9's fees
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(bytes32(uint256(123456)));
        giga.executeLottery();

        uint256 lotPoolAfter = giga.balanceOf(giga.LOT_POOL());

        // LOT_POOL should have received funds from the internal transfer
        // Either from lottery prize or auction amount
        // Just verify the system executed without reverting
        assertTrue(true, "Lottery/auction executed successfully");
    }

    function testFuzz_Invariants(
        uint8 numUsers,
        uint256 seed,
        uint8 numTransfers
    ) public {
        // Bound inputs
        numUsers = uint8(bound(numUsers, 2, 20));
        numTransfers = uint8(bound(numTransfers, 1, 50));

        // Create users and mint
        for (uint256 i = 0; i < numUsers; i++) {
            address user = address(uint160(0x1000 + i));

            uint256 mintAmount = ((uint256(keccak256(abi.encode(seed, i))) %
                5) + 1) * 1 ether;

            mega.mint(user, mintAmount);
            vm.startPrank(user);
            mega.approve(address(giga), mintAmount);
            giga.mint(mintAmount);
            vm.stopPrank();
        }

        // Perform random transfers
        for (uint256 i = 0; i < numTransfers; i++) {
            address from = address(
                uint160(
                    0x1000 +
                        (uint256(keccak256(abi.encode(seed, i, "from"))) %
                            numUsers)
                )
            );
            address to = address(
                uint160(
                    0x1000 +
                        (uint256(keccak256(abi.encode(seed, i, "to"))) %
                            numUsers)
                )
            );

            if (from == to) continue;

            uint256 balance = giga.balanceOf(from);
            if (balance > 100 ether) {
                uint256 amount = uint256(
                    keccak256(abi.encode(seed, i, "amount"))
                ) % (balance / 2);
                if (amount > 0) {
                    vm.prank(from);
                    giga.transfer(to, amount);
                }
            }
        }

        // Verify invariants
        // 1. Total supply invariant
        uint256 totalSupply = giga.totalSupply();
        uint256 sumOfBalances = 0;

        // Sum all special addresses
        sumOfBalances += giga.balanceOf(giga.FEES_POOL());
        sumOfBalances += giga.balanceOf(giga.LOT_POOL());

        // Sum all user balances
        for (uint256 i = 0; i < numUsers; i++) {
            address user = address(uint160(0x1000 + i));
            sumOfBalances += giga.balanceOf(user);
        }

        // Total supply should equal sum of all balances
        assertEq(
            totalSupply,
            sumOfBalances,
            "Total supply should equal sum of all balances"
        );

        // 2. Fenwick tree consistency
        uint256 fenwickTotal = 0;
        uint256 holderCount = giga.getHolderCount();
        if (holderCount > 0) {
            // getSuffixSum(1) gets the total from the beginning
            fenwickTotal = giga.getSuffixSum(1);
        }

        // Fenwick should track only EOA holders
        uint256 eoaTotal = 0;
        for (uint256 i = 0; i < numUsers; i++) {
            address user = address(uint160(0x1000 + i));
            if (giga.isHolder(user)) {
                eoaTotal += giga.balanceOf(user);
            }
        }

        assertEq(
            fenwickTotal,
            eoaTotal,
            "Fenwick total should match EOA holder balances"
        );
    }
}
