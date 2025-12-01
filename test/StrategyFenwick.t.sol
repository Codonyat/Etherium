// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrategyTestBase, MockContract} from "./helpers/StrategyTestBase.sol";
import {console} from "forge-std/Test.sol";

contract StrategyFenwickTest is StrategyTestBase {
    function testFenwickDebug() public {
        // Set up same scenario as probability test
        vm.prank(alice);
        giga.mint{value: 1 ether}();

        vm.prank(bob);
        giga.mint{value: 1 ether}();

        vm.prank(charlie);
        giga.mint{value: 1 ether}();

        // Take snapshot
        MockContract trigger = new MockContract();
        vm.deal(address(trigger), 1 ether);
        trigger.mintStrategy(giga);

        // Check what indices point to what
        console.log("Holder indices:");
        for (uint256 i = 1; i <= giga.getHolderCount(); i++) {
            (address holder, uint256 balance) = giga.getHolderByIndex(i);
            console.log("Index:", i);
            console.log("Holder:", holder);
            console.log("Balance:", balance);
        }

        // Check cumulative sums
        console.log("\nCumulative sums:");
        for (uint256 i = 1; i <= giga.getHolderCount(); i++) {
            uint256 cumSum = giga.getSuffixSum(i);
            console.log("Cumulative at index", i, ":", cumSum);
        }

        // Test winner selection with different random values
        uint256 totalSupply = giga.getSuffixSum(giga.getHolderCount());
        console.log("\nTotal supply from Fenwick:", totalSupply);

        // Test different random positions
        uint256[] memory testPositions = new uint256[](5);
        testPositions[0] = 0;
        testPositions[1] = totalSupply / 4;
        testPositions[2] = totalSupply / 2;
        testPositions[3] = (totalSupply * 3) / 4;
        testPositions[4] = totalSupply - 1;

        for (uint256 i = 0; i < testPositions.length; i++) {
            uint256 position = testPositions[i];
            console.log("\nTesting position:", position);

            // Binary search to find winner
            uint256 winnerIndex = findWinnerIndex(position);
            (address winner, ) = giga.getHolderByIndex(winnerIndex);
            console.log("Winner index:", winnerIndex);
            console.log("Winner address:", winner);
        }
    }

    function testFenwickTreeCumulativeSums() public {
        // Add holders with known balances
        vm.prank(alice);
        giga.mint{value: 1 ether}(); // 0.99 tokens

        vm.prank(bob);
        giga.mint{value: 2 ether}(); // 1.98 tokens

        vm.prank(charlie);
        giga.mint{value: 3 ether}(); // 2.97 tokens

        // getSuffixSum returns cumulative sum from index to end
        // So getSuffixSum(1) returns total of all holders
        uint256 cumSum1 = giga.getSuffixSum(1);
        uint256 cumSum2 = giga.getSuffixSum(2);
        uint256 cumSum3 = giga.getSuffixSum(3);

        // Total should be 0.99 + 1.98 + 2.97 = 5.94
        assertEq(
            cumSum1,
            5.94 ether,
            "Suffix sum from index 1 should be total (5.94)"
        );
        assertEq(
            cumSum2,
            1.98 ether + 2.97 ether,
            "Suffix sum from index 2 should be 4.95"
        );
        assertEq(cumSum3, 2.97 ether, "Suffix sum from index 3 should be 2.97");
    }

    function testFenwickTreeConsistencyAfterOperations() public {
        // Initial setup
        vm.prank(alice);
        giga.mint{value: 5 ether}();

        vm.prank(bob);
        giga.mint{value: 3 ether}();

        // Perform various operations
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        vm.prank(bob);
        giga.transfer(charlie, 0.5 ether);

        // Add new holder
        vm.prank(david);
        giga.mint{value: 2 ether}();

        // Check consistency - getSuffixSum(1) gets total from beginning
        uint256 totalFromFenwick = giga.getSuffixSum(1);

        // Calculate expected total (accounting for fees)
        uint256 aliceBalance = giga.balanceOf(alice);
        uint256 bobBalance = giga.balanceOf(bob);
        uint256 charlieBalance = giga.balanceOf(charlie);
        uint256 davidBalance = giga.balanceOf(david);

        uint256 expectedHolderTotal = aliceBalance +
            bobBalance +
            charlieBalance +
            davidBalance;

        assertEq(
            totalFromFenwick,
            expectedHolderTotal,
            "Fenwick total should match sum of holder balances"
        );
    }

    function testHolderTracking() public {
        // Initially no holders
        assertEq(giga.getHolderCount(), 0);

        // Alice becomes a holder
        vm.prank(alice);
        giga.mint{value: 1 ether}();
        assertEq(giga.getHolderCount(), 1);
        assertTrue(giga.isHolder(alice));

        // Bob becomes a holder
        vm.prank(bob);
        giga.mint{value: 1 ether}();
        assertEq(giga.getHolderCount(), 2);
        assertTrue(giga.isHolder(bob));

        // Alice transfers all to Bob (Alice should be removed as holder)
        uint256 aliceBalance = giga.balanceOf(alice);
        vm.prank(alice);
        giga.transfer(bob, aliceBalance);

        // Alice should no longer be a holder
        assertFalse(giga.isHolder(alice));
        // Holder count depends on whether alice was removed or not
        // In the implementation, holders are not removed when balance goes to 0
        // They're just tracked with 0 balance
        assertTrue(giga.isHolder(bob));
    }

    function testPackedStorageOptimization() public {
        // Test that many holders can be efficiently tracked
        uint256 numHolders = 50;

        for (uint256 i = 0; i < numHolders; i++) {
            address holder = address(uint160(0x1000 + i));
            vm.deal(holder, 1 ether);
            vm.prank(holder);
            giga.mint{value: 0.1 ether}();
        }

        assertEq(giga.getHolderCount(), numHolders);

        // Verify all holders are tracked correctly
        for (uint256 i = 1; i <= numHolders; i++) {
            (address holder, uint256 balance) = giga.getHolderByIndex(i);
            assertEq(holder, address(uint160(0x1000 + i - 1)));
            assertEq(balance, 0.099 ether); // 0.1 MEGA * 0.99 (after 1% fee)
        }
    }

    // Helper function for binary search
    function findWinnerIndex(uint256 position) internal view returns (uint256) {
        uint256 left = 1;
        uint256 right = giga.getHolderCount();

        while (left < right) {
            uint256 mid = (left + right) / 2;
            uint256 cumSum = giga.getSuffixSum(mid);

            if (cumSum <= position) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        return left;
    }
}
