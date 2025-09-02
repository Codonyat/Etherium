// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EtheriumTestBase, MockContract} from "./helpers/EtheriumTestBase.sol";
import {console} from "forge-std/Test.sol";

contract EtheriumFenwickTest is EtheriumTestBase {
    function testFenwickDebug() public {
        // Set up same scenario as probability test
        vm.prank(alice);
        etherium.mint{value: 1 ether}();

        vm.prank(bob);
        etherium.mint{value: 1 ether}();

        vm.prank(charlie);
        etherium.mint{value: 1 ether}();

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
        }

        // Check cumulative sums
        console.log("\nCumulative sums:");
        for (uint256 i = 1; i <= etherium.getHolderCount(); i++) {
            uint256 cumSum = etherium.getSuffixSum(i);
            console.log("Cumulative at index", i, ":", cumSum);
        }

        // Test winner selection with different random values
        uint256 totalSupply = etherium.getSuffixSum(etherium.getHolderCount());
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
            (address winner,) = etherium.getHolderByIndex(winnerIndex);
            console.log("Winner index:", winnerIndex);
            console.log("Winner address:", winner);
        }
    }

    function testFenwickTreeCumulativeSums() public {
        // Add holders with known balances
        vm.prank(alice);
        etherium.mint{value: 1 ether}(); // 990 tokens

        vm.prank(bob);
        etherium.mint{value: 2 ether}(); // 1980 tokens

        vm.prank(charlie);
        etherium.mint{value: 3 ether}(); // 2970 tokens

        // getSuffixSum returns cumulative sum from index to end
        // So getSuffixSum(1) returns total of all holders
        uint256 cumSum1 = etherium.getSuffixSum(1);
        uint256 cumSum2 = etherium.getSuffixSum(2);
        uint256 cumSum3 = etherium.getSuffixSum(3);

        // Total should be 990 + 1980 + 2970 = 5940
        assertEq(cumSum1, 5940 ether, "Suffix sum from index 1 should be total (5940)");
        assertEq(cumSum2, 1980 ether + 2970 ether, "Suffix sum from index 2 should be 4950");
        assertEq(cumSum3, 2970 ether, "Suffix sum from index 3 should be 2970");
    }

    function testFenwickTreeConsistencyAfterOperations() public {
        // Initial setup
        vm.prank(alice);
        etherium.mint{value: 5 ether}();

        vm.prank(bob);
        etherium.mint{value: 3 ether}();

        // Perform various operations
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);

        vm.prank(bob);
        etherium.transfer(charlie, 500 ether);

        // Add new holder
        vm.prank(david);
        etherium.mint{value: 2 ether}();

        // Check consistency - getSuffixSum(1) gets total from beginning
        uint256 totalFromFenwick = etherium.getSuffixSum(1);

        // Calculate expected total (accounting for fees)
        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 bobBalance = etherium.balanceOf(bob);
        uint256 charlieBalance = etherium.balanceOf(charlie);
        uint256 davidBalance = etherium.balanceOf(david);

        uint256 expectedHolderTotal = aliceBalance + bobBalance + charlieBalance + davidBalance;

        assertEq(totalFromFenwick, expectedHolderTotal, "Fenwick total should match sum of holder balances");
    }

    function testHolderTracking() public {
        // Initially no holders
        assertEq(etherium.getHolderCount(), 0);

        // Alice becomes a holder
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        assertEq(etherium.getHolderCount(), 1);
        assertTrue(etherium.isHolder(alice));

        // Bob becomes a holder
        vm.prank(bob);
        etherium.mint{value: 1 ether}();
        assertEq(etherium.getHolderCount(), 2);
        assertTrue(etherium.isHolder(bob));

        // Alice transfers all to Bob (Alice should be removed as holder)
        uint256 aliceBalance = etherium.balanceOf(alice);
        vm.prank(alice);
        etherium.transfer(bob, aliceBalance);

        // Alice should no longer be a holder
        assertFalse(etherium.isHolder(alice));
        // Holder count depends on whether alice was removed or not
        // In the implementation, holders are not removed when balance goes to 0
        // They're just tracked with 0 balance
        assertTrue(etherium.isHolder(bob));
    }

    function testPackedStorageOptimization() public {
        // Test that many holders can be efficiently tracked
        uint256 numHolders = 50;

        for (uint256 i = 0; i < numHolders; i++) {
            address holder = address(uint160(0x1000 + i));
            vm.deal(holder, 1 ether);
            vm.prank(holder);
            etherium.mint{value: 0.1 ether}();
        }

        assertEq(etherium.getHolderCount(), numHolders);

        // Verify all holders are tracked correctly
        for (uint256 i = 1; i <= numHolders; i++) {
            (address holder, uint256 balance) = etherium.getHolderByIndex(i);
            assertEq(holder, address(uint160(0x1000 + i - 1)));
            assertEq(balance, 99 ether); // 0.1 ETH * 990
        }
    }

    // Helper function for binary search
    function findWinnerIndex(uint256 position) internal view returns (uint256) {
        uint256 left = 1;
        uint256 right = etherium.getHolderCount();

        while (left < right) {
            uint256 mid = (left + right) / 2;
            uint256 cumSum = etherium.getSuffixSum(mid);

            if (cumSum <= position) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }

        return left;
    }
}
