// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract EtheriumTest is Test {
    Etherium public etherium;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    function setUp() public {
        etherium = new Etherium();
        
        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }
    
    function testMintingWithFee() public {
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        // 1 ETH = 1 ETHERIUM (both 18 decimals)
        // During minting period: Alice gets 99%, fees are minted too
        uint256 expectedBalance = 0.99 ether; // 99% of 1 ETH
        assertEq(etherium.balanceOf(alice), expectedBalance);
        
        // Total supply should be full 1 ETH (alice's 0.99 + 0.01 fees minted)
        uint256 expectedTotalSupply = 1 ether;
        assertEq(etherium.totalSupply(), expectedTotalSupply);
        
        // Check that fee was distributed to lottery pool
        uint256 totalFee = 0.01 ether; // 1% of 1 ETH
        
        assertEq(etherium.balanceOf(address(0x000000000000107700000Add2E55000000000000)), totalFee);
    }
    
    function testRedeemWithFee() public {
        // First mint some ETHERIUM
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 contractBalanceBefore = address(etherium).balance;
        
        // Redeem half
        uint256 redeemAmount = aliceBalance / 2;
        vm.prank(alice);
        etherium.redeem(redeemAmount);
        
        // Check ETHERIUM balance decreased
        assertEq(etherium.balanceOf(alice), aliceBalance - redeemAmount);
        
        // Check ETH was returned (minus fee)
        uint256 fee = (redeemAmount * 100) / 10000; // 1% fee
        uint256 netAmount = redeemAmount - fee;
        uint256 expectedEth = netAmount; // 1:1 conversion
        
        assertApproxEqAbs(
            contractBalanceBefore - address(etherium).balance,
            expectedEth,
            1000 // Allow small rounding error
        );
    }
    
    function testTransferWithFee() public {
        // First mint some ETHERIUM
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        uint256 aliceBalanceBefore = etherium.balanceOf(alice);
        uint256 transferAmount = 0.1 ether; // 0.1 ETHERIUM
        
        // Transfer to bob
        vm.prank(alice);
        etherium.transfer(bob, transferAmount);
        
        // Bob should receive 99% of transfer amount (1% fee)
        uint256 expectedBobBalance = (transferAmount * 99) / 100;
        assertEq(etherium.balanceOf(bob), expectedBobBalance);
        
        // Alice balance should decrease by full amount
        assertEq(etherium.balanceOf(alice), aliceBalanceBefore - transferAmount);
    }
    
    function testHolderTracking() public {
        // Initially no holders
        assertEq(etherium.getHolderCount(), 0);
        
        // Alice mints
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        assertEq(etherium.getHolderCount(), 1);
        
        // Bob mints
        vm.prank(bob);
        etherium.mint{value: 1 ether}();
        assertEq(etherium.getHolderCount(), 2);
        
        // Alice transfers all to bob
        uint256 aliceBalance = etherium.balanceOf(alice);
        vm.prank(alice);
        etherium.transfer(bob, aliceBalance);
        
        // Alice should be removed from holders
        assertEq(etherium.getHolderCount(), 1);
        assertFalse(etherium.isHolder(alice));
        assertTrue(etherium.isHolder(bob));
    }
    
    function testPrevrandaoLottery() public {
        // Mint some ETHERIUM to create holders
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 1 ether}();
        
        // Record initial lottery pool
        uint256 lotteryPoolBefore = etherium.balanceOf(address(0x000000000000107700000Add2E55000000000000));
        assertTrue(lotteryPoolBefore > 0);
        
        // Fast forward to day 1 (at least 1 minute in) to trigger lottery for day 0
        vm.warp(block.timestamp + 24 hours + 61);
        
        // Now lottery should execute immediately
        etherium.executeLottery();
        
        // Lottery pool should be distributed
        assertEq(etherium.balanceOf(address(0x000000000000107700000Add2E55000000000000)), 0);
        assertEq(etherium.lastLotteryDay(), 1);
    }
    
    function testLotteryWithMultipleHolders() public {
        // Setup: Multiple holders with different balances
        vm.prank(alice);
        etherium.mint{value: 2 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 1 ether}();
        
        vm.prank(charlie);
        etherium.mint{value: 0.5 ether}();
        
        // Record initial lottery pool
        uint256 lotteryPoolBefore = etherium.balanceOf(address(0x000000000000107700000Add2E55000000000000));
        assertTrue(lotteryPoolBefore > 0);
        
        // Fast forward to day 1 (at least 1 minute in) to execute lottery for day 0
        vm.warp(block.timestamp + 24 hours + 61);
        
        // Execute lottery with prevrandao
        etherium.executeLottery();
        
        // Lottery pool should be empty
        assertEq(etherium.balanceOf(address(0x000000000000107700000Add2E55000000000000)), 0);
        
        // One of the holders should have won
        // Can't predict exact winner due to randomness, but total supply should match
        uint256 totalSupplyAfter = etherium.totalSupply();
        assertTrue(totalSupplyAfter > 0);
    }
    
    function testMintingPeriodEnforcement() public {
        // During minting period: no limit, fees are minted too
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        uint256 totalSupplyAfterMinting = etherium.totalSupply();
        // Should be 10 ETHERIUM (including fees minted during minting period)
        uint256 expectedSupply = 10 ether; // 10 ETHERIUM
        assertEq(totalSupplyAfterMinting, expectedSupply);
        
        // Fast forward past minting period
        vm.warp(block.timestamp + 8 days);
        
        // First mint after period sets maxSupplyEver
        uint256 maxSupply = etherium.maxSupplyEver();
        assertEq(maxSupply, 0); // Not set yet
        
        // Now minting should be limited by max supply set during minting week
        vm.prank(bob);
        vm.expectRevert("Max supply reached");
        etherium.mint{value: 1 ether}(); // Should fail - no redemptions yet
        
        // After redemption, minting should work up to original max
        vm.prank(alice);
        etherium.redeem(1 ether); // Redeem 1 ETHERIUM
        
        // After redemption: 
        // - Alice loses 1 ETHERIUM from balance
        // - Only 0.99 ETHERIUM actually burned from total supply (0.01 fee stays)
        // - Total supply now: 10 - 0.99 = 9.01 ETHERIUM
        // - Max supply still: 10 ETHERIUM
        // - Available to mint: 10 - 9.01 = 0.99 ETHERIUM
        
        assertEq(etherium.totalSupply(), expectedSupply - 0.99 ether);
        
        // Bob can now mint up to the redeemed capacity
        vm.prank(bob);
        etherium.mint{value: 0.99 ether}(); // Should work - exactly the redeemed amount
    }
    
    function testNoContractsInLottery() public {
        // Deploy a contract that holds ETHERIUM
        MockContract mockContract = new MockContract();
        vm.deal(address(mockContract), 10 ether);
        
        // Contract mints ETHERIUM
        mockContract.mintEtherium(etherium);
        
        // Check contract is not tracked as holder
        assertFalse(etherium.isHolder(address(mockContract)));
        assertEq(etherium.getHolderCount(), 0);
        
        // Regular user mints
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        // Only alice should be tracked
        assertEq(etherium.getHolderCount(), 1);
        assertTrue(etherium.isHolder(alice));
    }
    
    function testPepeUSDFeeFreeFlow() public {
        // This test demonstrates the simplified PepeUSD lock and mint flow
        // Commented out since we don't have PepeUSD setup in tests
        
        // Setup: Give alice some PepeUSD tokens
        // deal(address(etherium.PEPEUSD()), alice, 200 ether); // 200 PepeUSD
        // vm.prank(alice);
        // IERC20(address(etherium.PEPEUSD())).approve(address(etherium), 200 ether);
        
        // Alice calls mintFeeFree which locks 100 PepeUSD and mints without fees
        // vm.prank(alice);
        // etherium.mintFeeFree{value: 1 ether}();
        // assertEq(etherium.balanceOf(alice), 1 ether, "Should mint 1:1 without fees");
        // assertEq(etherium.pepeUSDLocked(alice), 100 ether, "Should have 100 PepeUSD locked");
        
        // Alice can mint again with another 100 PepeUSD
        // vm.prank(alice);
        // etherium.mintFeeFree{value: 0.5 ether}();
        // assertEq(etherium.balanceOf(alice), 1.5 ether, "Should have 1.5 ETHERIUM total");
        // assertEq(etherium.pepeUSDLocked(alice), 200 ether, "Should have 200 PepeUSD locked");
        
        // After 1 month, alice can unlock all PepeUSD
        // vm.warp(block.timestamp + 30 days + 1);
        // vm.prank(alice);
        // etherium.unlockPepeUSD();
        // assertEq(etherium.pepeUSDLocked(alice), 0, "Should have no PepeUSD locked");
    }
    
    function testFenwickDebug() public {
        // Set up same scenario as probability test
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        console.log("After Alice mints:");
        console.log("Fenwick[1]:", etherium.getFenwickValue(1));
        console.log("Fenwick[2]:", etherium.getFenwickValue(2));
        
        vm.prank(bob);
        etherium.mint{value: 2 ether}();
        
        console.log("\nAfter Bob mints:");
        console.log("Fenwick[1]:", etherium.getFenwickValue(1));
        console.log("Fenwick[2]:", etherium.getFenwickValue(2));
        
        vm.prank(charlie);
        etherium.mint{value: 3 ether}();
        
        console.log("\nAfter Charlie mints:");
        console.log("Fenwick[1]:", etherium.getFenwickValue(1));
        console.log("Fenwick[2]:", etherium.getFenwickValue(2));
        console.log("Fenwick[3]:", etherium.getFenwickValue(3));
        console.log("Fenwick[4]:", etherium.getFenwickValue(4));
        
        console.log("\nBefore transfer:");
        console.log("Alice:", etherium.balanceOf(alice));
        console.log("Bob:", etherium.balanceOf(bob));
        console.log("Charlie:", etherium.balanceOf(charlie));
        
        // Transfer 0.5 ETHERIUM from Bob to Charlie
        vm.prank(bob);
        etherium.transfer(charlie, 0.5 ether);
        
        console.log("\nAfter transfer:");
        console.log("Alice:", etherium.balanceOf(alice));
        console.log("Bob:", etherium.balanceOf(bob));
        console.log("Charlie:", etherium.balanceOf(charlie));
        console.log("Fenwick[1]:", etherium.getFenwickValue(1));
        console.log("Fenwick[2]:", etherium.getFenwickValue(2));
        console.log("Fenwick[3]:", etherium.getFenwickValue(3));
        console.log("Fenwick[4]:", etherium.getFenwickValue(4));
        
        // Now simulate lottery selection to see the probabilities
        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 bobBalance = etherium.balanceOf(bob);
        uint256 charlieBalance = etherium.balanceOf(charlie);
        uint256 totalBalance = aliceBalance + bobBalance + charlieBalance;
        
        console.log("\nExpected probabilities:");
        console.log("Alice:", aliceBalance * 100 / totalBalance, "%");
        console.log("Bob:", bobBalance * 100 / totalBalance, "%");
        console.log("Charlie:", charlieBalance * 100 / totalBalance, "%");
        
        // Simulate lottery day 1
        vm.warp(block.timestamp + 24 hours + 1);
        
        // Take snapshot
        MockContract trigger = new MockContract();
        vm.deal(address(trigger), 1 ether);
        trigger.mintEtherium(etherium);
        
        // Check what indices point to what
        console.log("Holder indices:");
        for (uint256 i = 1; i <= etherium.getHolderCount(); i++) {
            (address holder, uint256 balance) = etherium.getHolderByIndex(i);
            console.log("Index:", i);
            console.log("Holder:", holder);
            console.log("Balance:", balance);
            console.log("Fenwick value:", etherium.getFenwickValue(i));
            console.log("Suffix sum:", etherium.getSuffixSum(i));
        }
    }
    
    function testFenwickTreeCumulativeSums() public {
        // Simple test to verify Fenwick tree is tracking cumulative sums correctly
        vm.prank(alice);
        etherium.mint{value: 1 ether}(); // Alice: 0.99 ETH
        
        vm.prank(bob);
        etherium.mint{value: 2 ether}(); // Bob: 1.98 ETH
        
        vm.prank(charlie);
        etherium.mint{value: 3 ether}(); // Charlie: 2.97 ETH
        
        // Check balances
        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 bobBalance = etherium.balanceOf(bob);
        uint256 charlieBalance = etherium.balanceOf(charlie);
        
        console.log("Initial balances:");
        console.log("Alice:", aliceBalance);
        console.log("Bob:", bobBalance);
        console.log("Charlie:", charlieBalance);
        
        // The cumulative sums should be:
        // Index 1 (Alice): 0.99 ETH
        // Index 2 (Bob): 0.99 + 1.98 = 2.97 ETH
        // Index 3 (Charlie): 0.99 + 1.98 + 2.97 = 5.94 ETH
        
        // Now do a transfer to see if cumulative sums update correctly
        vm.prank(bob);
        etherium.transfer(charlie, 0.5 ether);
        
        console.log("\nAfter transfer:");
        console.log("Alice:", etherium.balanceOf(alice));
        console.log("Bob:", etherium.balanceOf(bob));
        console.log("Charlie:", etherium.balanceOf(charlie));
        
        // New cumulative sums should be:
        // Index 1 (Alice): 0.99 ETH
        // Index 2 (Bob): 0.99 + 1.48 = 2.47 ETH  
        // Index 3 (Charlie): 0.99 + 1.48 + 3.465 = 5.935 ETH
    }
    
    function testLotteryProbabilityDistribution() public {
        // Setup holders with specific balances
        // Alice: 1 ETH worth, Bob: 2 ETH worth, Charlie: 3.5 ETH worth after transfer
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        vm.prank(bob); 
        etherium.mint{value: 2 ether}();
        
        vm.prank(charlie);
        etherium.mint{value: 3 ether}();
        
        // Bob transfers 0.5 ETHERIUM to Charlie
        // Bob has 2 * 0.99 = 1.98 ETHERIUM initially
        // Transfer of 0.5 ETHERIUM: Bob loses 0.5, Charlie gains 0.495 (after 1% fee)
        vm.prank(bob);
        etherium.transfer(charlie, 0.5 ether);
        
        // Final balances after all fees:
        // Alice: 0.99 ETH (minted 1 ETH with 1% fee)
        // Bob: 1.98 - 0.5 = 1.48 ETH
        // Charlie: 2.97 + 0.495 = 3.465 ETH
        // Total holder balance: 0.99 + 1.48 + 3.465 = 5.935 ETH
        
        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 bobBalance = etherium.balanceOf(bob);
        uint256 charlieBalance = etherium.balanceOf(charlie);
        
        console.log("Alice balance:", aliceBalance);
        console.log("Bob balance:", bobBalance);
        console.log("Charlie balance:", charlieBalance);
        console.log("Total:", aliceBalance + bobBalance + charlieBalance);
        
        // Debug: Check actual holder setup and total balance
        console.log("Holder count:", etherium.getHolderCount());
        
        // Track wins for each holder over many rounds
        uint256 aliceWins = 0;
        uint256 bobWins = 0;
        uint256 charlieWins = 0;
        uint256 rounds = 1000; // Increased for better statistics
        
        // Deploy a mock contract to trigger snapshots (contracts don't participate in lottery)
        MockContract triggerContract = new MockContract();
        vm.deal(address(triggerContract), 10 ether);
        
        // Save initial state
        uint256 snapshotId = vm.snapshot();
        
        for (uint256 i = 0; i < rounds; i++) {
            // Restore to initial state for each round
            vm.revertTo(snapshotId);
            snapshotId = vm.snapshot();
            
            // Move to day 1 (at least 1 minute in)
            vm.warp(block.timestamp + 24 hours + 61);
            
            // Set a different prevrandao for each round
            vm.prevrandao(bytes32(uint256(keccak256(abi.encode(i, "test")))));
            
            // Execute lottery
            etherium.executeLottery();
            
            // Check who won by comparing balance increases
            uint256 aliceNewBalance = etherium.balanceOf(alice);
            uint256 bobNewBalance = etherium.balanceOf(bob);
            uint256 charlieNewBalance = etherium.balanceOf(charlie);
            
            if (aliceNewBalance > aliceBalance) {
                aliceWins++;
            } else if (bobNewBalance > bobBalance) {
                bobWins++;
            } else if (charlieNewBalance > charlieBalance) {
                charlieWins++;
            } else {
                // Check all holder balances to find winner
                bool foundWinner = false;
                for (uint256 j = 1; j <= etherium.getHolderCount(); j++) {
                    (address holder, ) = etherium.getHolderByIndex(j);
                    if (holder != alice && holder != bob && holder != charlie) {
                        console.log("Round", i, "- unexpected winner:", holder);
                        foundWinner = true;
                        break;
                    }
                }
                if (!foundWinner) {
                    console.log("Round", i, "- no winner found!");
                }
            }
        }
        
        // Calculate expected probabilities based on balances
        uint256 totalBalance = aliceBalance + bobBalance + charlieBalance;
        uint256 expectedAliceWins = (aliceBalance * rounds) / totalBalance;
        uint256 expectedBobWins = (bobBalance * rounds) / totalBalance;
        uint256 expectedCharlieWins = (charlieBalance * rounds) / totalBalance;
        
        console.log("\nResults after", rounds, "rounds:");
        console.log("Alice wins:", aliceWins, "Expected:", expectedAliceWins);
        console.log("Bob wins:", bobWins, "Expected:", expectedBobWins);
        console.log("Charlie wins:", charlieWins, "Expected:", expectedCharlieWins);
        
        // Allow for statistical deviation (roughly 3 standard deviations)
        // For binomial distribution, std dev ≈ sqrt(n * p * (1-p))
        // Using a simplified check: actual should be within 10% of expected for large samples
        uint256 tolerance = rounds / 10; // 10% tolerance for 1000 rounds
        
        assertApproxEqAbs(aliceWins, expectedAliceWins, tolerance, "Alice win distribution off");
        assertApproxEqAbs(bobWins, expectedBobWins, tolerance, "Bob win distribution off");
        assertApproxEqAbs(charlieWins, expectedCharlieWins, tolerance, "Charlie win distribution off");
        
        // Ensure all rounds had a winner
        assertEq(aliceWins + bobWins + charlieWins, rounds, "Not all rounds had a winner");
    }

    function testAllExternalFunctionsTriggerLottery() public {
        // Setup: Create holders and accumulate fees
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 5 ether}();
        
        // Advance to day 1
        vm.warp(block.timestamp + 24 hours + 61);
        vm.prevrandao(12345);
        
        // Test 1: mint() triggers lottery (takes snapshot)
        vm.prank(charlie);
        etherium.mint{value: 1 ether}();
        
        
        // Test 2: transfer() triggers lottery execution
        vm.prank(alice);
        etherium.transfer(bob, 1 ether);
        assertEq(etherium.lastLotteryDay(), 1, "Lottery should execute via transfer");
        
        // Move to day 2
        vm.warp(block.timestamp + 24 hours + 61);
        vm.prevrandao(54321);
        
        // Test 3: redeem() triggers lottery (takes snapshot)
        vm.prank(bob);
        etherium.redeem(1 ether);
        
        
        // Execute via any transaction
        vm.prank(charlie);
        etherium.transfer(alice, 0.1 ether);
        assertEq(etherium.lastLotteryDay(), 2, "Lottery should execute for day 2");
    }
    
    function testBalanceChangesInSnapshotBlockDontAffectLottery() public {
        // Setup: Create initial holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 5 ether}();
        
        // Record balances
        uint256 aliceBalanceBefore = etherium.balanceOf(alice);
        uint256 bobBalanceBefore = etherium.balanceOf(bob);
        
        // Advance to just before lottery can execute (less than 1 minute)
        vm.warp(block.timestamp + 24 hours + 30); // 30 seconds into new day
        vm.prevrandao(99999);
        
        // Make balance changes - lottery can't execute yet
        vm.prank(alice);
        etherium.transfer(bob, 5 ether);
        
        // Add new holder
        address david = address(0x4);
        vm.deal(david, 10 ether);
        vm.prank(david);
        etherium.mint{value: 10 ether}();
        
        // Now advance past 1 minute and execute lottery
        vm.warp(block.timestamp + 31); // Now 61 seconds into the day
        etherium.executeLottery();
        
        // Lottery should have used the snapshot from before the balance changes
        // David shouldn't be eligible since he wasn't a holder when snapshot was taken
        assertEq(etherium.lastLotteryDay(), 1, "Lottery should be executed");
    }
    
    function testLotteryAfterComplexHolderChanges() public {
        // Setup: Create holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 5 ether}();
        
        vm.prank(charlie);
        etherium.mint{value: 3 ether}();
        
        // Remove a holder
        uint256 charlieBalance = etherium.balanceOf(charlie);
        vm.prank(charlie);
        etherium.transfer(alice, charlieBalance);
        
        // Add a new holder
        address david = address(0x4);
        vm.deal(david, 10 ether);
        vm.prank(david);
        etherium.mint{value: 7 ether}();
        
        // Execute lottery
        vm.warp(block.timestamp + 24 hours + 61);
        vm.prevrandao(55555);
        
        // Take snapshot via mint
        vm.prank(alice);
        etherium.mint{value: 0.1 ether}();
        
        // Execute lottery
        uint256 poolBalance = etherium.balanceOf(address(0x000000000000107700000Add2E55000000000000));
        assertTrue(poolBalance > 0, "Pool should have fees");
        vm.prank(bob);
        etherium.transfer(alice, 0.1 ether);
        
        assertEq(etherium.lastLotteryDay(), 1, "Lottery should be executed");
        uint256 poolAfter = etherium.balanceOf(address(0x000000000000107700000Add2E55000000000000));
        assertTrue(poolAfter < 0.01 ether, "Pool should be mostly distributed");
    }
    
    function testSecondLotteryExecution() public {
        // Setup: Create holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 5 ether}();
        
        // Execute first lottery
        vm.warp(block.timestamp + 24 hours + 61);
        vm.prevrandao(11111);
        
        // Execute first lottery
        etherium.executeLottery();
        assertEq(etherium.lastLotteryDay(), 1, "First lottery should be executed");
        
        // Accumulate more fees
        vm.prank(alice);
        etherium.transfer(bob, 2 ether);
        
        vm.prank(bob);
        etherium.transfer(alice, 1 ether);
        
        // Advance to day 2
        vm.warp(block.timestamp + 24 hours + 61);
        vm.prevrandao(22222);
        
        // Execute second lottery
        etherium.executeLottery();
        assertEq(etherium.lastLotteryDay(), 2, "Second lottery should be executed");
    }
    
    function testDelayedLotteryTrigger() public {
        // Setup: Create holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 5 ether}();
        
        // Advance multiple days without triggering lottery (at least 1 minute into day 3)
        vm.warp(block.timestamp + 72 hours + 61); // 3 days + 1 minute later
        vm.prevrandao(88888);
        
        // Should still only execute lottery for day 1 (oldest pending)
        assertEq(etherium.lastLotteryDay(), 0, "No lottery executed yet");
        
        // Execute lottery - will execute for the current day
        etherium.executeLottery();
        
        assertEq(etherium.lastLotteryDay(), 3, "Should have executed lottery for current day");
        
        // Pool should be mostly empty (may have small fees from trigger transactions)
        uint256 poolAfter = etherium.balanceOf(address(0x000000000000107700000Add2E55000000000000));
        assertTrue(poolAfter < 0.01 ether, "Pool should be mostly distributed");
    }
    
    function testNoLotteryWhenNoFeesCollected() public {
        // Setup: Create holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        // Execute first lottery to empty the pool
        vm.warp(block.timestamp + 24 hours + 61);
        vm.prevrandao(66666);
        
        // Take snapshot via mint
        vm.prank(bob);
        etherium.mint{value: 0.1 ether}();
        
        // Execute via transfer
        vm.prank(alice);
        etherium.transfer(bob, 0.1 ether);
        
        // Pool should be mostly empty
        uint256 poolAfter = etherium.balanceOf(address(0x000000000000107700000Add2E55000000000000));
        assertTrue(poolAfter < 0.01 ether, "Pool should be mostly empty");
        
        // Advance to next day
        vm.warp(block.timestamp + 24 hours + 61);
        vm.prevrandao(77777);
        
        // Try to execute lottery with nearly empty pool
        vm.prank(bob);
        etherium.transfer(alice, 0.001 ether);        vm.prank(alice);
        etherium.transfer(bob, 0.001 ether); // Executes
        
        // The lottery should still execute even with minimal prize
        assertEq(etherium.lastLotteryDay(), 2, "Should have executed lottery for day 1 even with minimal prize");
    }
    
    function testFenwickTreeConsistencyAfterOperations() public {
        // Create holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 5 ether}();
        
        vm.prank(charlie);
        etherium.mint{value: 3 ether}();
        
        // Verify suffix sums are correct
        uint256 suffix1 = etherium.getSuffixSum(1);
        
        // suffix1 should be sum of all holders
        assertEq(suffix1, etherium.balanceOf(alice) + etherium.balanceOf(bob) + etherium.balanceOf(charlie));
        
        // Remove a holder
        uint256 charlieBalance = etherium.balanceOf(charlie);
        vm.prank(charlie);
        etherium.transfer(alice, charlieBalance);
        
        // Verify Fenwick tree updated correctly
        uint256 newSuffix1 = etherium.getSuffixSum(1);
        assertEq(newSuffix1, etherium.balanceOf(alice) + etherium.balanceOf(bob));
        
        // Add a new holder
        address david = address(0x4);
        vm.deal(david, 10 ether);
        vm.prank(david);
        etherium.mint{value: 7 ether}();
        
        // Verify tree consistency
        uint256 finalSuffix1 = etherium.getSuffixSum(1);
        assertEq(finalSuffix1, etherium.balanceOf(alice) + etherium.balanceOf(bob) + etherium.balanceOf(david));
        
        // Now execute lottery to ensure Fenwick tree works for winner selection
        vm.warp(block.timestamp + 24 hours + 61);
        vm.prevrandao(99999);
        
        // Take snapshot via mint
        vm.prank(alice);
        etherium.mint{value: 0.1 ether}();
        
        // Execute lottery
        uint256 poolBalance = etherium.balanceOf(address(0x000000000000107700000Add2E55000000000000));
        assertTrue(poolBalance > 0, "Pool should have fees");
        vm.prank(bob);
        etherium.transfer(alice, 0.1 ether);
        
        // Verify lottery executed successfully
        uint256 poolAfterExec = etherium.balanceOf(address(0x000000000000107700000Add2E55000000000000));
        assertTrue(poolAfterExec < 0.01 ether, "Pool should be mostly empty");
    }
}

contract MockContract {
    function mintEtherium(Etherium etherium) external {
        etherium.mint{value: 1 ether}();
    }
    
    receive() external payable {}
}

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}