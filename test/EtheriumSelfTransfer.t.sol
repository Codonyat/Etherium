// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract EtheriumSelfTransferTest is Test {
    Etherium public etherium;

    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        etherium = new Etherium();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function testSelfTransferFenwickConsistency() public {
        // Alice mints tokens
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        uint256 aliceBalanceBefore = etherium.balanceOf(alice);
        uint256 fenwickBefore = etherium.getSuffixSum(1);

        console.log("Alice balance before self-transfer:", aliceBalanceBefore);
        console.log("Fenwick sum before self-transfer:", fenwickBefore);

        // Alice transfers to herself
        vm.prank(alice);
        etherium.transfer(alice, 100 ether);

        uint256 aliceBalanceAfter = etherium.balanceOf(alice);
        uint256 fenwickAfter = etherium.getSuffixSum(1);

        console.log("Alice balance after self-transfer:", aliceBalanceAfter);
        console.log("Fenwick sum after self-transfer:", fenwickAfter);

        // Alice should lose 1% fee even on self-transfer
        assertEq(aliceBalanceAfter, aliceBalanceBefore - 1 ether, "Should charge fee on self-transfer");

        // Fenwick should still be consistent
        assertEq(fenwickAfter, aliceBalanceAfter, "Fenwick should match Alice's balance");
    }

    function testSelfTransferWithMultipleHolders() public {
        // Multiple users mint
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 5 ether}();

        uint256 totalBefore = etherium.balanceOf(alice) + etherium.balanceOf(bob);
        uint256 fenwickBefore = etherium.getSuffixSum(1);
        assertEq(fenwickBefore, totalBefore, "Initial Fenwick should match total");

        // Alice self-transfers
        vm.prank(alice);
        etherium.transfer(alice, 500 ether);

        uint256 totalAfter = etherium.balanceOf(alice) + etherium.balanceOf(bob);
        uint256 fenwickAfter = etherium.getSuffixSum(1);

        // Total should decrease by fee amount
        assertEq(totalBefore - totalAfter, 5 ether, "Total should decrease by fee");

        // Fenwick should still track correctly
        assertEq(fenwickAfter, totalAfter, "Fenwick should match new total");
    }

    function testRapidSelfTransfers() public {
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        uint256 expectedBalance = 9900 ether;

        // Do 10 self-transfers rapidly
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(alice);
            etherium.transfer(alice, 100 ether);
            expectedBalance -= 1 ether; // 1% fee each time

            // Check Fenwick consistency after each transfer
            uint256 fenwick = etherium.getSuffixSum(1);
            uint256 aliceBalance = etherium.balanceOf(alice);
            assertEq(fenwick, aliceBalance, "Fenwick should match balance");
            assertEq(aliceBalance, expectedBalance, "Balance should match expected");
        }
    }

    function testSyntheticAddressesNotInFenwick() public {
        // Verify that FEES_POOL and LOT_POOL are never tracked in Fenwick tree
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        // After minting, alice has 9900, FEES_POOL has 100
        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 feesBalance = etherium.balanceOf(etherium.FEES_POOL());

        assertEq(aliceBalance, 9900 ether, "Alice should have 9900");
        assertEq(feesBalance, 100 ether, "FEES_POOL should have 100");

        // Fenwick should only track Alice, not FEES_POOL
        uint256 fenwick = etherium.getSuffixSum(1);
        assertEq(fenwick, aliceBalance, "Fenwick should only track Alice");

        // Do a transfer to generate more fees
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);

        // Check that Fenwick still only tracks real holders
        uint256 totalHolderBalance = etherium.balanceOf(alice) + etherium.balanceOf(bob);
        uint256 fenwickAfter = etherium.getSuffixSum(1);
        assertEq(fenwickAfter, totalHolderBalance, "Fenwick should only track real holders");

        // Verify fees went to FEES_POOL but aren't in Fenwick
        uint256 newFeesBalance = etherium.balanceOf(etherium.FEES_POOL());
        assertGt(newFeesBalance, feesBalance, "FEES_POOL should have more fees");
    }
}
