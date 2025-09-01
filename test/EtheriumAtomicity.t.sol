// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract EtheriumAtomicityTest is Test {
    Etherium public etherium;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    function setUp() public {
        etherium = new Etherium();
        
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }
    
    function testFenwickTreeAtomicityDuringTransfers() public {
        // Setup: Create holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 5 ether}();
        
        vm.prank(charlie);
        etherium.mint{value: 3 ether}();
        
        // Verify initial Fenwick tree state
        uint256 initialSuffix1 = etherium.getSuffixSum(1);
        uint256 expectedInitialTotal = etherium.balanceOf(alice) + 
                                       etherium.balanceOf(bob) + 
                                       etherium.balanceOf(charlie);
        assertEq(initialSuffix1, expectedInitialTotal, "Initial Fenwick sum incorrect");
        
        // Perform multiple transfers in same transaction
        vm.startPrank(alice);
        etherium.transfer(bob, 100 ether);
        etherium.transfer(charlie, 200 ether);
        vm.stopPrank();
        
        // Verify Fenwick tree is still consistent
        uint256 afterSuffix1 = etherium.getSuffixSum(1);
        uint256 expectedAfterTotal = etherium.balanceOf(alice) + 
                                     etherium.balanceOf(bob) + 
                                     etherium.balanceOf(charlie);
        assertEq(afterSuffix1, expectedAfterTotal, "Fenwick sum inconsistent after transfers");
    }
    
    function testFenwickTreeAtomicityDuringMintAndBurn() public {
        // Initial mint
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        // Check Fenwick consistency after mint
        uint256 suffix1AfterMint = etherium.getSuffixSum(1);
        assertEq(suffix1AfterMint, etherium.balanceOf(alice), "Fenwick incorrect after mint");
        
        // Move past minting period to enable redemption
        vm.warp(block.timestamp + 8 days);
        
        // Trigger max supply setting
        vm.prank(alice);
        etherium.redeem(100 ether);
        
        // Check Fenwick consistency after redemption
        uint256 suffix1AfterRedeem = etherium.getSuffixSum(1);
        assertEq(suffix1AfterRedeem, etherium.balanceOf(alice), "Fenwick incorrect after redeem");
        
        // Add another holder
        vm.prank(bob);
        etherium.mint{value: 0.09 ether}(); // Within capacity after redemption
        
        // Verify both holders are tracked correctly
        uint256 finalSuffix1 = etherium.getSuffixSum(1);
        uint256 expectedFinal = etherium.balanceOf(alice) + etherium.balanceOf(bob);
        assertEq(finalSuffix1, expectedFinal, "Fenwick incorrect with multiple holders");
    }
    
    function testFenwickTreeAtomicityDuringComplexOperations() public {
        // Create initial holders
        address[10] memory users;
        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(uint160(0x100 + i));
            vm.deal(users[i], 10 ether);
            vm.prank(users[i]);
            etherium.mint{value: 1 ether}();
        }
        
        // Verify initial state
        uint256 totalSupply = etherium.totalSupply();
        uint256 fenwickTotal = etherium.getSuffixSum(1);
        
        // Fenwick only tracks user holders, not pools
        assertTrue(fenwickTotal <= totalSupply, "Fenwick should not exceed total supply");
        
        // Perform random transfers
        for (uint256 round = 0; round < 20; round++) {
            uint256 from = round % 10;
            uint256 to = (round + 3) % 10;
            uint256 amount = 50 ether + (round * 10 ether);
            
            if (etherium.balanceOf(users[from]) >= amount) {
                vm.prank(users[from]);
                etherium.transfer(users[to], amount);
            }
        }
        
        // Calculate expected total from individual balances
        uint256 expectedTotal = 0;
        for (uint256 i = 0; i < 10; i++) {
            expectedTotal += etherium.balanceOf(users[i]);
        }
        
        // Verify Fenwick tree still consistent
        uint256 finalFenwickTotal = etherium.getSuffixSum(1);
        assertEq(finalFenwickTotal, expectedTotal, "Fenwick tree inconsistent after complex operations");
    }
    
    function testAtomicityWithReentrancy() public {
        // This test ensures that even with potential reentrancy, 
        // the Fenwick tree remains consistent due to atomic updates
        
        // Create a malicious contract that tries to reenter
        MaliciousReentrant malicious = new MaliciousReentrant(etherium);
        vm.deal(address(malicious), 10 ether);
        
        // Initial state
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        uint256 initialFenwick = etherium.getSuffixSum(1);
        assertEq(initialFenwick, etherium.balanceOf(alice), "Initial Fenwick incorrect");
        
        // Try to transfer to malicious contract
        // The reentrancy guard should prevent any issues
        vm.prank(alice);
        etherium.transfer(address(malicious), 100 ether);
        
        // Verify Fenwick tree is still consistent
        // Note: Smart contracts are excluded from Fenwick tree (only EOAs are tracked)
        // So the malicious contract balance won't be in the Fenwick sum
        uint256 finalFenwick = etherium.getSuffixSum(1);
        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 maliciousBalance = etherium.balanceOf(address(malicious));
        
        // Only Alice's balance should be in the Fenwick tree
        assertEq(finalFenwick, aliceBalance, "Fenwick should only track Alice (EOA)");
        
        // Verify the transfer happened correctly
        assertEq(aliceBalance, 9800 ether, "Alice should have 9800 tokens");
        assertEq(maliciousBalance, 99 ether, "Malicious contract should have 99 tokens");
    }
    
    function testFenwickTreeWithZeroBalanceTransitions() public {
        // Test that Fenwick tree correctly handles accounts going to/from zero balance
        
        // Alice mints
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 fenwick1 = etherium.getSuffixSum(1);
        assertEq(fenwick1, aliceBalance, "Initial Fenwick incorrect");
        
        // Alice transfers entire balance to Bob (Alice goes to 0)
        vm.prank(alice);
        etherium.transfer(bob, aliceBalance);
        
        // Alice should be removed from holders
        uint256 fenwick2 = etherium.getSuffixSum(1);
        assertEq(fenwick2, etherium.balanceOf(bob), "Fenwick should only track Bob");
        
        // Alice mints again (goes from 0 to positive)
        vm.prank(alice);
        etherium.mint{value: 2 ether}();
        
        // Both should be tracked now
        uint256 fenwick3 = etherium.getSuffixSum(1);
        uint256 expectedTotal = etherium.balanceOf(alice) + etherium.balanceOf(bob);
        assertEq(fenwick3, expectedTotal, "Fenwick should track both holders");
    }
}

// Helper contract for reentrancy test
contract MaliciousReentrant {
    Etherium public etherium;
    bool public attacked = false;
    
    constructor(Etherium _etherium) {
        etherium = _etherium;
    }
    
    // Try to reenter when receiving tokens
    function onERC20Received(address, uint256) external returns (bytes4) {
        if (!attacked) {
            attacked = true;
            // Try to mint during a transfer (should fail due to reentrancy guard)
            try etherium.mint{value: 1 ether}() {
                // Should not reach here
            } catch {
                // Expected to fail
            }
        }
        return this.onERC20Received.selector;
    }
    
    receive() external payable {}
}