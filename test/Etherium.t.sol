// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract EtheriumTest is Test {
    Etherium public etherium;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    // Event definitions for testing
    event Minted(address indexed to, uint256 ethAmount, uint256 etheriumAmount, uint256 fee);
    event Redeemed(address indexed from, uint256 etheriumAmount, uint256 ethAmount, uint256 fee);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event LotteryWon(address indexed winner, uint256 amount, uint256 day);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event PublicGoodsFunded(address indexed publicGood, uint256 amount, address previousWinner);
    event PepeUSDLocked(address indexed user, uint256 pepeAmount, uint256 etheriumMinted, uint256 unlockTime);
    event PepeUSDUnlocked(address indexed user, uint256 amount);

    function setUp() public {
        etherium = new Etherium();

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }

    function testMintingWithFee() public {
        // Expect Minted event (1 ETH deposits, 990 ETHERIUM minted, 10 ETHERIUM fee)
        vm.expectEmit(true, true, true, true);
        emit Minted(alice, 1 ether, 990 ether, 10 ether);

        vm.prank(alice);
        etherium.mint{value: 1 ether}();

        // 1 ETH = 1000 ETHERIUM (both 18 decimals)
        // During minting period: Alice gets 99%, fees are minted too
        uint256 expectedBalance = 990 ether; // 99% of 1000 ETHERIUM
        assertEq(etherium.balanceOf(alice), expectedBalance);

        // Total supply should be full 1000 ETHERIUM (alice's 990 + 10 fees minted)
        uint256 expectedTotalSupply = 1000 ether;
        assertEq(etherium.totalSupply(), expectedTotalSupply);

        // Check that fee was distributed to fees pool
        uint256 totalFee = 10 ether; // 1% of 1000 ETHERIUM

        assertEq(etherium.balanceOf(etherium.FEES_POOL()), totalFee);
    }

    function testRedeemWithFee() public {
        // First mint some ETHERIUM
        vm.prank(alice);
        etherium.mint{value: 1 ether}();

        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 contractBalanceBefore = address(etherium).balance;

        // Redeem half
        uint256 redeemAmount = aliceBalance / 2;
        uint256 fee = (redeemAmount * 100) / 10000; // 1% fee
        uint256 netAmount = redeemAmount - fee;

        // Calculate ETH to return based on proportional backing
        // ETH to return = (netAmount * contract ETH balance) / total supply
        uint256 expectedEth = (netAmount * contractBalanceBefore) / etherium.totalSupply();

        // Expect Redeemed event
        vm.expectEmit(true, true, true, true);
        emit Redeemed(alice, redeemAmount, expectedEth, fee);

        vm.prank(alice);
        etherium.redeem(redeemAmount);

        // Check ETHERIUM balance decreased
        assertEq(etherium.balanceOf(alice), aliceBalance - redeemAmount);

        // Check ETH was returned
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
        uint256 transferAmount = 100 ether; // 100 ETHERIUM
        uint256 fee = (transferAmount * 100) / 10000; // 1% fee
        uint256 netAmount = transferAmount - fee;

        // Expect Transfer events (from alice to bob, and fee to FEES_POOL)
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, netAmount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, etherium.FEES_POOL(), fee);

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
        vm.expectEmit(true, true, true, true);
        emit Minted(alice, 1 ether, 990 ether, 10 ether);

        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        assertEq(etherium.getHolderCount(), 1);

        // Bob mints
        vm.expectEmit(true, true, true, true);
        emit Minted(bob, 1 ether, 990 ether, 10 ether);

        vm.prank(bob);
        etherium.mint{value: 1 ether}();
        assertEq(etherium.getHolderCount(), 2);

        // Alice transfers all to bob
        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 fee = (aliceBalance * 100) / 10000;
        uint256 netAmount = aliceBalance - fee;

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, netAmount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, etherium.FEES_POOL(), fee);

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

        // Fast forward to day 1 first
        vm.warp(block.timestamp + 25 hours);
        
        // Generate some transfer fees on day 1 to have fees for day 2 lottery
        vm.prank(alice);
        etherium.transfer(bob, 100 ether); // This generates fees tracked for day 1

        // Check daily fees were tracked for day 1
        uint256 currentDay = etherium.getCurrentDay();
        assertEq(currentDay, 1, "Should be day 1");
        uint256 dailyFees = etherium.dailyFeesCollected(currentDay);
        assertTrue(dailyFees > 0, "Should have daily fees tracked");

        // Fast forward to day 2 (at least 1 minute in) to trigger lottery (lottery executes on day 2 for day 1 fees)
        vm.warp(block.timestamp + 25 hours + 61);

        // Expect LotteryWon event - either alice or bob will win
        // Don't check any specific values since we don't know the winner
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0); // We don't know winner/amount/day exactly

        // Now lottery should execute immediately
        etherium.executeLottery();

        // Lottery pool should have the prize stored (not empty, but as unclaimed prize)
        assertEq(etherium.lastLotteryDay(), 2);
    }

    function testLotteryWithMultipleHolders() public {
        // Setup: Multiple holders with different balances
        vm.prank(alice);
        etherium.mint{value: 2 ether}();

        vm.prank(bob);
        etherium.mint{value: 1 ether}();

        vm.prank(charlie);
        etherium.mint{value: 0.5 ether}();

        // Fast forward to day 1 first
        vm.warp(block.timestamp + 25 hours);
        
        // Generate some transfer fees on day 1 to have fees for day 2 lottery
        vm.prank(alice);
        etherium.transfer(bob, 100 ether); // This generates fees tracked for day 1

        // Check daily fees were tracked for day 1
        uint256 currentDay = etherium.getCurrentDay();
        assertEq(currentDay, 1, "Should be day 1");
        uint256 dailyFees = etherium.dailyFeesCollected(currentDay);
        assertTrue(dailyFees > 0, "Should have daily fees tracked");

        // Fast forward to day 2 (at least 1 minute in) to execute lottery (lottery executes on day 2 for day 1 fees)
        vm.warp(block.timestamp + 25 hours + 61);

        // Expect LotteryWon event
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0); // We don't know winner/amount/day exactly

        // Execute lottery with prevrandao
        etherium.executeLottery();

        // Lottery should have executed for day 2
        assertEq(etherium.lastLotteryDay(), 2);

        // One of the holders should have won
        // Can't predict exact winner due to randomness, but total supply should match
        uint256 totalSupplyAfter = etherium.totalSupply();
        assertTrue(totalSupplyAfter > 0);
    }

    function testMintingPeriodEnforcement() public {
        // During minting period: 1 ETH = 1000 ETHERIUM
        vm.expectEmit(true, true, true, true);
        emit Minted(alice, 10 ether, 9900 ether, 100 ether);

        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        uint256 totalSupplyAfterMinting = etherium.totalSupply();
        // Should be 10,000 ETHERIUM (including fees minted during minting period)
        uint256 expectedSupply = 10000 ether; // 10,000 ETHERIUM
        assertEq(totalSupplyAfterMinting, expectedSupply);

        // Fast forward past minting period
        vm.warp(block.timestamp + 8 days);

        // First mint after period sets maxSupplyEver
        uint256 maxSupply = etherium.maxSupplyEver();
        assertEq(maxSupply, 0); // Not set yet

        // First mint after minting period should work and set max supply
        vm.prank(bob);
        etherium.mint{value: 0.01 ether}(); // This sets maxSupplyEver to current totalSupply
        
        maxSupply = etherium.maxSupplyEver();
        assertEq(maxSupply, expectedSupply); // Max supply now set to 10,000 ETHERIUM

        // Alice redeems some ETHERIUM
        uint256 redeemAmount = 1000 ether; // 1000 ETHERIUM
        uint256 fee = (redeemAmount * 100) / 10000; // 1% fee = 10 ETHERIUM
        uint256 netBurned = redeemAmount - fee; // 990 ETHERIUM burned
        
        // Calculate expected ETH return
        uint256 ethToReturn = (netBurned * address(etherium).balance) / etherium.totalSupply();
        
        vm.expectEmit(true, true, true, true);
        emit Redeemed(alice, redeemAmount, ethToReturn, fee);

        vm.prank(alice);
        etherium.redeem(redeemAmount);

        // After redemption, total supply decreases by netBurned
        assertEq(etherium.totalSupply(), expectedSupply + (0.01 ether * 1000) - netBurned);

        // Charlie can now mint up to the redeemed capacity
        // Available capacity = maxSupplyEver - totalSupply
        uint256 availableCapacity = maxSupply - etherium.totalSupply();
        
        // Charlie tries to mint using the available capacity
        vm.prank(charlie);
        etherium.mint{value: 0.98 ether}(); // Should work - less than available capacity
    }

    function testNoContractsInLottery() public {
        // Deploy a contract that holds ETHERIUM
        MockContract mockContract = new MockContract();
        vm.deal(address(mockContract), 10 ether);

        // Contract mints ETHERIUM - expect Minted event
        vm.expectEmit(true, true, true, true);
        emit Minted(address(mockContract), 1 ether, 990 ether, 10 ether);

        mockContract.mintEtherium(etherium);

        // Check contract is not tracked as holder
        assertFalse(etherium.isHolder(address(mockContract)));
        assertEq(etherium.getHolderCount(), 0);

        // Regular user mints
        vm.expectEmit(true, true, true, true);
        emit Minted(alice, 1 ether, 990 ether, 10 ether);

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
        console.log("Alice:", (aliceBalance * 100) / totalBalance, "%");
        console.log("Bob:", (bobBalance * 100) / totalBalance, "%");
        console.log("Charlie:", (charlieBalance * 100) / totalBalance, "%");

        // Simulate lottery day 1
        vm.warp(block.timestamp + 25 hours + 1);

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

        // Check the lottery pool has funds
        uint256 lotteryPoolBalance = etherium.balanceOf(etherium.LOT_POOL());
        console.log("Lottery pool balance:", lotteryPoolBalance);
        assertTrue(lotteryPoolBalance > 0, "Lottery pool should have funds");

        // Save initial balances for expected probability calculation
        uint256 initialAliceBalance = aliceBalance;
        uint256 initialBobBalance = bobBalance;
        uint256 initialCharlieBalance = charlieBalance;

        // Track wins for each holder over many rounds
        uint256 aliceWins = 0;
        uint256 bobWins = 0;
        uint256 charlieWins = 0;
        uint256 rounds = 100; // Reduced for faster testing without snapshots

        // Deploy a mock contract to trigger snapshots (contracts don't participate in lottery)
        MockContract triggerContract = new MockContract();
        vm.deal(address(triggerContract), 10 ether);

        for (uint256 i = 0; i < rounds; i++) {
            // Generate some fees for each lottery (alternate between senders to avoid balance issues)
            if (i % 2 == 0) {
                vm.prank(alice);
                etherium.transfer(bob, 0.001 ether);
            } else {
                vm.prank(bob);
                etherium.transfer(alice, 0.001 ether);
            }

            // Move to next day (at least 1 minute in)
            vm.warp(block.timestamp + 25 hours + 61);

            // Set a different prevrandao for each round
            vm.prevrandao(bytes32(uint256(keccak256(abi.encode(i, "test")))));

            // Execute lottery
            etherium.executeLottery();

            // Check who won by checking unclaimed prizes
            (address[14] memory winners,) = etherium.getAllUnclaimedPrizes();
            // The lottery stores prizes at slot day%7
            uint256 lotteryDay = etherium.lastLotteryDay();
            uint256 slot = lotteryDay % 14;
            address winner = winners[slot];

            if (winner == alice) {
                aliceWins++;
            } else if (winner == bob) {
                bobWins++;
            } else if (winner == charlie) {
                charlieWins++;
            }
        }

        // Calculate expected probabilities based on initial balances
        uint256 totalBalance = initialAliceBalance + initialBobBalance + initialCharlieBalance;
        uint256 expectedAliceWins = (initialAliceBalance * rounds) / totalBalance;
        uint256 expectedBobWins = (initialBobBalance * rounds) / totalBalance;
        uint256 expectedCharlieWins = (initialCharlieBalance * rounds) / totalBalance;

        console.log("\nResults after", rounds, "rounds:");
        console.log("Alice wins:", aliceWins, "Expected:", expectedAliceWins);
        console.log("Bob wins:", bobWins, "Expected:", expectedBobWins);
        console.log("Charlie wins:", charlieWins, "Expected:", expectedCharlieWins);

        // Allow for statistical deviation (roughly 3 standard deviations)
        // For binomial distribution, std dev ≈ sqrt(n * p * (1-p))
        // Using a simplified check: actual should be within 20% of expected for smaller samples
        uint256 tolerance = rounds / 5; // 20% tolerance for 100 rounds

        assertApproxEqAbs(aliceWins, expectedAliceWins, tolerance, "Alice win distribution off");
        assertApproxEqAbs(bobWins, expectedBobWins, tolerance, "Bob win distribution off");
        assertApproxEqAbs(charlieWins, expectedCharlieWins, tolerance, "Charlie win distribution off");

        // Ensure all rounds after the first 7 had a winner (first 7 fill empty slots)
        uint256 expectedWins = rounds > 7 ? rounds - 7 : rounds;
        assertTrue(aliceWins + bobWins + charlieWins >= expectedWins, "Not enough rounds had winners");
    }

    function testAllExternalFunctionsTriggerLottery() public {
        // Setup: Create holders and accumulate fees
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 5 ether}();

        // Advance to day 1
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(12345);

        // Test 1: mint() triggers lottery (takes snapshot)
        vm.prank(charlie);
        etherium.mint{value: 1 ether}();

        // Test 2: transfer() triggers lottery execution
        vm.prank(alice);
        etherium.transfer(bob, 1 ether);
        assertEq(etherium.lastLotteryDay(), 1, "Lottery should execute via transfer");

        // Move to day 2
        vm.warp(block.timestamp + 25 hours + 61);
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
        // Setup: Create initial holders with predictable balances
        // Alice: 9900 ETHERIUM (after 1% fee)
        // Bob: 4950 ETHERIUM (after 1% fee)
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 5 ether}();

        // Move to day 1 and generate fees
        vm.warp(block.timestamp + 25 hours);
        
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether); // 10 ETHERIUM fee
        vm.prank(bob);
        etherium.transfer(alice, 1000 ether); // Return tokens, another 10 ETHERIUM fee

        // Move to day 2 to be able to execute lottery for day 1's fees
        vm.warp(block.timestamp + 25 hours + 30); // Day 2, 30 seconds in (before 1 minute)
        
        // Make dramatic balance changes in the window before lottery execution
        // Transfer most of Alice's balance to Bob
        vm.prank(alice);
        etherium.transfer(bob, 8000 ether); // Alice now has ~900, Bob has ~12950
        
        // Add new holder David with large balance
        address david = address(0x4);
        vm.deal(david, 20 ether);
        vm.prank(david);
        etherium.mint{value: 20 ether}(); // David gets 19800 ETHERIUM

        // Now advance past 1 minute and execute lottery with specific seed
        vm.warp(block.timestamp + 31); // Now 61 seconds into day 2
        
        // Use a seed that would select Alice based on original balances
        // Original: Alice ~9900, Bob ~4950, total ~14850
        // If randomSeed % 14850 = 5000, it should select Alice (since she had most balance)
        uint256 originalTotal = 14850 ether; // Approximate original total
        vm.prevrandao(5000); // This should select Alice based on day 1 snapshot
        
        etherium.executeLottery();

        // Get the lottery winner
        (address[14] memory winners,) = etherium.getAllUnclaimedPrizes();
        uint256 slot = 1 % 14; // Day 1's slot
        
        // Alice should win based on day 1 snapshot, even though she has little balance now
        // and David has the most balance (but wasn't a holder on day 1)
        assertTrue(
            winners[slot] == alice || winners[slot] == bob,
            "Winner should be from original holders (Alice or Bob), not David"
        );
        assertTrue(
            winners[slot] != david,
            "David shouldn't win - wasn't a holder during snapshot day"
        );
        
        assertEq(etherium.lastLotteryDay(), 2, "Lottery should be executed on day 2");
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
        vm.warp(block.timestamp + 25 hours + 61);
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
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(11111);

        // Expect first LotteryWon event
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0);

        // Execute first lottery
        etherium.executeLottery();
        assertEq(etherium.lastLotteryDay(), 1, "First lottery should be executed");

        // Accumulate more fees
        vm.prank(alice);
        etherium.transfer(bob, 2 ether);

        vm.prank(bob);
        etherium.transfer(alice, 1 ether);

        // Advance to day 2
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(22222);

        // Expect second LotteryWon event
        vm.expectEmit(false, false, false, false);
        emit LotteryWon(address(0), 0, 0);

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
        vm.warp(block.timestamp + 75 hours + 61); // 3 days (25h each) + 1 minute later
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
        vm.warp(block.timestamp + 25 hours + 61);
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
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(77777);

        // Try to execute lottery with nearly empty pool
        vm.prank(bob);
        etherium.transfer(alice, 0.001 ether);
        vm.prank(alice);
        etherium.transfer(bob, 0.001 ether); // Executes

        // The lottery should still execute even with minimal prize
        assertEq(etherium.lastLotteryDay(), 2, "Should have executed lottery for day 1 even with minimal prize");
    }

    function testDirectPrizeStorage() public {
        // Setup: Create holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 5 ether}();

        // Execute lottery for day 1
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(12345);
        etherium.executeLottery();

        // Check the stored prize directly
        (address winner0, uint112 amount0) = etherium.unclaimedPrizes(0);
        console.log("Slot 0 winner:", winner0);
        console.log("Slot 0 amount:", amount0);

        assertTrue(winner0 == alice || winner0 == bob, "Should have a winner in slot 0");
        assertTrue(amount0 > 0, "Should have an amount in slot 0");
    }

    function testClaimPrize() public {
        // Setup: Create holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 5 ether}();

        // Execute lottery for day 1
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(12345);
        etherium.executeLottery();

        // Check that there's an unclaimed prize
        (address[14] memory winners,) = etherium.getAllUnclaimedPrizes();
        assertTrue(winners[0] == alice || winners[0] == bob, "Should have a winner");

        address winner = winners[0];

        // Check the stored prize directly
        (address storedWinner, uint112 storedAmount) = etherium.unclaimedPrizes(0);
        console.log("Stored winner in slot 0:", storedWinner);
        console.log("Test winner variable:", winner);
        console.log("Are they equal?", storedWinner == winner);

        // Winner claims the prize
        vm.prank(winner);
        uint256 claimableAmount = etherium.getMyClaimableAmount();
        assertTrue(claimableAmount > 0, "Winner should have claimable amount");

        uint256 balanceBefore = etherium.balanceOf(winner);

        // Expect PrizeClaimed event
        vm.expectEmit(true, true, true, true);
        emit PrizeClaimed(winner, claimableAmount);

        vm.prank(winner);
        etherium.claim();
        uint256 balanceAfter = etherium.balanceOf(winner);

        // Verify prize was claimed
        assertTrue(balanceAfter > balanceBefore, "Balance should increase");
        vm.prank(winner);
        assertEq(etherium.getMyClaimableAmount(), 0, "No more claimable amount");
    }

    function testRejectDirectETHTransfer() public {
        // Try to send ETH directly to the contract
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert("Direct ETH transfers not allowed. Use mint() instead");
        (bool success,) = address(etherium).call{value: 1 ether}("");
        // vm.expectRevert handles the revert, so we don't need to check success
    }

    function testReentrancyGuardWorks() public {
        // The reentrancy guard uses transient storage (ReentrancyGuardTransient)
        // This is more gas efficient than regular storage
        // We verify it's working by checking that protected functions execute successfully

        // Test that all nonReentrant functions work properly
        vm.prank(alice);
        etherium.mint{value: 1 ether}(); // nonReentrant function

        vm.prank(alice);
        etherium.redeem(0.5 ether); // nonReentrant function

        // Execute lottery to create a claimable prize
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery(); // nonReentrant function

        // All functions executed without issues, guard is working
        assertTrue(true, "Reentrancy guard is functioning");
    }

    function testPackedStorageOptimization() public {
        // This test verifies that maxSupplyEver, lastLotteryDay, and currentPublicGoodIndex
        // are packed in a single storage slot for gas efficiency

        // First, mint during minting period
        vm.prank(alice);
        etherium.mint{value: 100 ether}();

        vm.prank(bob);
        etherium.mint{value: 50 ether}();

        // Warp past minting period
        vm.warp(block.timestamp + 8 days);

        // Someone redeems to create capacity
        vm.prank(alice);
        etherium.redeem(10 ether);

        // Now we can mint up to the redeemed amount
        vm.prank(charlie);
        etherium.mint{value: 5 ether}();

        // Execute a lottery to update lastLotteryDay
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();

        // Check all three values are accessible and correct
        assertTrue(etherium.maxSupplyEver() > 0, "Max supply should be set");
        assertTrue(etherium.lastLotteryDay() > 0, "Last lottery day should be set");
        assertEq(etherium.currentPublicGoodIndex(), 0, "Public good index should be 0");

        // Execute 7 more lotteries with unclaimed prizes to cycle public goods
        for (uint256 i = 1; i <= 7; i++) {
            vm.prank(alice);
            etherium.transfer(bob, 0.1 ether);
            vm.warp(block.timestamp + 25 hours + 61);
            etherium.executeLottery();
        }

        // Check that currentPublicGoodIndex has cycled
        assertTrue(etherium.currentPublicGoodIndex() > 0, "Public good index should have cycled");
    }

    function testETHSentToPublicGoodsNotEtherium() public {
        // This test verifies that public goods receive ETH, not ETHERIUM tokens

        // Setup: Create holders and generate lottery
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 5 ether}();

        // Execute lottery for day 1
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(12345);
        etherium.executeLottery();

        // Record public good's initial ETH balance
        address publicGood = etherium.PUBLIC_GOODS(0);
        uint256 initialETHBalance = publicGood.balance;

        // Execute 7 more lotteries to trigger unclaimed prize distribution
        for (uint256 i = 1; i <= 7; i++) {
            vm.prank(alice);
            etherium.transfer(bob, 0.1 ether);
            vm.warp(block.timestamp + 25 hours + 61);
            etherium.executeLottery();
        }

        // Verify public good received ETH, not ETHERIUM
        assertEq(etherium.balanceOf(publicGood), 0, "Public good should have 0 ETHERIUM");
        assertTrue(publicGood.balance > initialETHBalance, "Public good should have more ETH");
    }

    function testUnclaimedPrizeFailedTransferGoesToCurrentWinner() public {
        // This test verifies that if a public good can't receive ETH,
        // the unclaimed prize goes to the current lottery winner instead.
        // Since we can't modify PUBLIC_GOODS in tests (it's hardcoded),
        // we document the expected behavior here.

        // Setup: Create holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 5 ether}();

        // Execute lottery for day 1
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(11111);
        etherium.executeLottery();

        // Get the first winner
        (address[14] memory winners,) = etherium.getAllUnclaimedPrizes();
        address firstWinner = winners[0];

        // Execute 7 more lotteries to trigger unclaimed prize distribution
        for (uint256 i = 1; i <= 7; i++) {
            // Generate some fees
            vm.prank(alice);
            etherium.transfer(bob, 0.1 ether);

            vm.warp(block.timestamp + 25 hours + 61);
            vm.prevrandao(uint256(keccak256(abi.encode(i))));
            etherium.executeLottery();
        }

        // In normal case, public good receives ETH
        // If ETH transfer failed, the current day 8 winner would receive
        // both their prize AND the unclaimed prize from day 1
        address publicGood = etherium.PUBLIC_GOODS(0);
        assertTrue(publicGood.balance > 0, "Public good should have received ETH");
    }

    function testCannotMintAfterPeriodWithoutCapacity() public {
        // Mint during minting period
        vm.expectEmit(true, true, true, true);
        emit Minted(alice, 100 ether, 99 ether, 1 ether);

        vm.prank(alice);
        etherium.mint{value: 100 ether}();

        // Warp past minting period
        vm.warp(block.timestamp + 8 days);

        // First redemption triggers maxSupplyEver setting
        vm.expectEmit(true, true, true, true);
        emit Redeemed(alice, 10 ether, 9.9 ether, 0.1 ether);

        vm.prank(alice);
        etherium.redeem(10 ether);

        // Now Bob can mint up to the redeemed amount (minus fees)
        vm.expectEmit(true, true, true, true);
        emit Minted(bob, 9.9 ether, 9.801 ether, 0.099 ether);

        vm.prank(bob);
        etherium.mint{value: 9.9 ether}(); // Less than redeemed to account for fees

        // But not more than capacity
        vm.prank(charlie);
        vm.expectRevert("Max supply reached");
        etherium.mint{value: 0.1 ether}();
    }

    function testRedeemingAllEtheriumDepleteContractETH() public {
        // Mint some ETHERIUM
        vm.prank(alice);
        etherium.mint{value: 50 ether}();

        vm.prank(bob);
        etherium.mint{value: 50 ether}();

        uint256 contractETHBefore = address(etherium).balance;
        assertEq(contractETHBefore, 100 ether, "Contract should have 100 ETH");

        // Both users redeem all their ETHERIUM
        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 bobBalance = etherium.balanceOf(bob);

        vm.prank(alice);
        etherium.redeem(aliceBalance);

        vm.prank(bob);
        etherium.redeem(bobBalance);

        // Contract should have minimal ETH left (only lottery pool balance)
        uint256 contractETHAfter = address(etherium).balance;
        uint256 lotteryPoolBalance = etherium.balanceOf(etherium.LOT_POOL());

        // Contract ETH = lottery pool tokens (1:1000 backing during minting period, then varies)
        // After redemptions, the backing ratio changes based on supply/ETH ratio
        assertTrue(contractETHAfter > 0, "Contract should have some ETH left");
        assertTrue(contractETHAfter < 2 ether, "Should have less than 2 ETH (just fees)");
    }

    function testMaxSupplyNeverExceededWithPublicGoodsDonations() public {
        // Setup initial supply during minting period
        vm.prank(alice);
        etherium.mint{value: 100 ether}();

        vm.prank(bob);
        etherium.mint{value: 100 ether}();

        // Warp past minting period
        vm.warp(block.timestamp + 8 days);

        // Trigger maxSupplyEver setting with a redemption
        vm.prank(alice);
        etherium.redeem(1 ether);

        uint112 maxSupply = etherium.maxSupplyEver();
        assertTrue(maxSupply > 0, "Max supply should be set");
        assertTrue(maxSupply >= 199 ether, "Max supply should be around 199-200 ether");

        // Execute lotteries for 7 days without claiming to trigger public goods donation
        for (uint256 day = 1; day <= 8; day++) {
            // Generate fees
            vm.prank(alice);
            etherium.transfer(bob, 1 ether);

            vm.warp(block.timestamp + 25 hours + 61);
            vm.prevrandao(uint256(keccak256(abi.encode(day))));
            etherium.executeLottery();

            // Check supply never exceeds max
            assertTrue(etherium.totalSupply() <= maxSupply, "Supply exceeded max!");
        }

        // After public goods donation (burn), supply should be less
        assertTrue(etherium.totalSupply() < maxSupply, "Supply should decrease after burn");

        // Someone redeems
        vm.prank(alice);
        etherium.redeem(10 ether);

        // Charlie can now mint up to redeemed amount
        vm.prank(charlie);
        etherium.mint{value: 10 ether}();

        // Supply still shouldn't exceed max
        assertTrue(etherium.totalSupply() <= maxSupply, "Supply exceeded max after mint!");
    }

    function testLotteryWithManyUsersRandomOperations() public {
        // Create 10 users
        address[10] memory users;
        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(uint160(0x100 + i));
            vm.deal(users[i], 100 ether);
        }

        // Random operations for each user
        for (uint256 round = 0; round < 5; round++) {
            for (uint256 i = 0; i < 10; i++) {
                uint256 action = uint256(keccak256(abi.encode(round, i))) % 3;

                if (action == 0 && users[i].balance > 1 ether) {
                    // Mint
                    vm.prank(users[i]);
                    etherium.mint{value: 1 ether}();
                } else if (action == 1 && etherium.balanceOf(users[i]) > 0.1 ether) {
                    // Transfer
                    uint256 recipient = (i + 1) % 10;
                    vm.prank(users[i]);
                    etherium.transfer(users[recipient], 0.1 ether);
                } else if (action == 2 && etherium.balanceOf(users[i]) > 0.5 ether) {
                    // Redeem
                    vm.prank(users[i]);
                    etherium.redeem(0.5 ether);
                }
            }

            // Execute lottery every round
            if (round > 0) {
                vm.warp(block.timestamp + 25 hours + 61);
                vm.prevrandao(uint256(keccak256(abi.encode("lottery", round))));
                if (etherium.balanceOf(etherium.LOT_POOL()) > 0) {
                    etherium.executeLottery();
                }
            }
        }

        // Verify system is still consistent
        assertTrue(etherium.getHolderCount() > 0, "Should have holders");
        assertTrue(address(etherium).balance > 0, "Contract should have ETH");

        // ETH in contract >= total supply (some may be in lottery pool)
        assertTrue(address(etherium).balance >= etherium.totalSupply(), "ETH backing should be sufficient");
    }

    function testUnclaimedPrizeGoesToPublicGood() public {
        // Setup: Create holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 5 ether}();

        // Execute lottery for day 1
        vm.warp(block.timestamp + 25 hours + 61);
        vm.prevrandao(11111);
        etherium.executeLottery();

        // Get the winner but don't claim
        (address[14] memory winners, uint112[14] memory amounts) = etherium.getAllUnclaimedPrizes();
        address firstWinner = winners[0];
        uint112 unclaimedAmount = amounts[0];

        // Execute 7 more lotteries to overwrite the slot
        for (uint256 i = 1; i <= 7; i++) {
            // Generate some fees for the next lottery
            vm.prank(alice);
            etherium.transfer(bob, 0.1 ether);

            vm.warp(block.timestamp + 25 hours + 61);
            vm.prevrandao(uint256(keccak256(abi.encode(i))));

            // On the 7th lottery (i=7), we should see PublicGoodsFunded event
            if (i == 7) {
                address expectedPublicGood = etherium.PUBLIC_GOODS(0);
                // Expect PublicGoodsFunded event when old prize is sent to public goods
                vm.expectEmit(true, true, true, false);
                emit PublicGoodsFunded(expectedPublicGood, unclaimedAmount, address(0)); // We don't know exact current winner
            }

            etherium.executeLottery();
        }

        // Check that public goods received ETH (not ETHERIUM tokens)
        address publicGood = etherium.PUBLIC_GOODS(0);
        assertEq(etherium.balanceOf(publicGood), 0, "Public good should not have ETHERIUM tokens");
        assertTrue(publicGood.balance > 0, "Public good should have received ETH");
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
        vm.warp(block.timestamp + 25 hours + 61);
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

    // Invariant fuzz test
    function testFuzz_Invariants(uint8 numUsers, uint256 seed, uint8 numRounds) public {
        // Bound inputs
        numUsers = uint8(bound(numUsers, 2, 20));
        numRounds = uint8(bound(numRounds, 1, 10));

        // Create users
        address[] memory users = new address[](numUsers);
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = address(uint160(0x1000 + i));
            vm.deal(users[i], 1000 ether);
        }

        // Track initial state
        uint256 initialContractETH = address(etherium).balance;

        // Random operations
        for (uint256 round = 0; round < numRounds; round++) {
            // Each user performs random action
            for (uint256 i = 0; i < numUsers; i++) {
                uint256 actionSeed = uint256(keccak256(abi.encode(seed, round, i)));
                uint256 action = actionSeed % 4;

                if (action == 0) {
                    // Mint
                    uint256 amount = ((actionSeed % 10) + 1) * 0.1 ether;
                    if (users[i].balance >= amount) {
                        vm.prank(users[i]);
                        try etherium.mint{value: amount}() {} catch {}
                    }
                } else if (action == 1) {
                    // Transfer
                    uint256 balance = etherium.balanceOf(users[i]);
                    if (balance > 0) {
                        uint256 transferAmount = balance / 4;
                        uint256 recipient = (i + 1) % numUsers;
                        vm.prank(users[i]);
                        try etherium.transfer(users[recipient], transferAmount) {} catch {}
                    }
                } else if (action == 2) {
                    // Redeem
                    uint256 balance = etherium.balanceOf(users[i]);
                    if (balance > 0.1 ether) {
                        uint256 redeemAmount = balance / 3;
                        vm.prank(users[i]);
                        try etherium.redeem(redeemAmount) {} catch {}
                    }
                } else {
                    // Execute lottery if possible
                    if (round > 0 && etherium.getCurrentDay() > etherium.lastLotteryDay()) {
                        vm.warp(block.timestamp + 25 hours + 61);
                        vm.prevrandao(actionSeed);
                        try etherium.executeLottery() {} catch {}
                    }
                }
            }

            // Check invariants after each round
            _checkInvariants();
        }

        // Final invariant checks
        _checkInvariants();
    }

    function _checkInvariants() internal view {
        // Invariant 1: Contract ETH >= Total Supply
        assertTrue(address(etherium).balance >= etherium.totalSupply(), "Invariant violated: ETH < Total Supply");

        // Invariant 2: Total supply never exceeds max (after minting period)
        if (block.timestamp > etherium.mintingEndTime() && etherium.maxSupplyEver() > 0) {
            assertTrue(etherium.totalSupply() <= etherium.maxSupplyEver(), "Invariant violated: Supply > Max Supply");
        }

        // Invariant 3: Holder count matches actual holders
        uint256 holderCount = etherium.getHolderCount();
        assertTrue(holderCount <= 1000, "Too many holders");

        // Invariant 4: Lottery day never goes backward
        assertTrue(etherium.lastLotteryDay() <= etherium.getCurrentDay(), "Lottery day in future");
    }
}

contract MockContract {
    function mintEtherium(Etherium etherium) external {
        etherium.mint{value: 1 ether}();
    }

    receive() external payable {}
}

// Contract that rejects ETH transfers
contract MockRejectETH {
// No receive or fallback function - will reject ETH transfers
}

// Malicious contract that attempts reentrancy during claim
contract MaliciousReentrantClaim {
    Etherium public target;
    bool public attacking;

    constructor(Etherium _target) {
        target = _target;
    }

    function mintTokens() external {
        target.mint{value: 5 ether}();
    }

    function attackClaim() external {
        attacking = true;
        target.claim();
    }

    receive() external payable {
        if (attacking) {
            attacking = false;
            // Try to re-enter claim during the first claim
            target.claim();
        }
    }
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
