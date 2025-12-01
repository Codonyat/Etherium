// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy, IWMEGA} from "../src/Strategy.sol";

// Mock WMEGA for testing
contract MockWMEGA {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "MEGA transfer failed");
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

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

contract StrategySelfTransferTest is Test {
    Strategy public giga;
    MockWMEGA public wmega;

    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        wmega = new MockWMEGA();
        giga = new Strategy(address(wmega));

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function testSelfTransferFenwickConsistency() public {
        // Alice mints tokens
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        uint256 aliceBalanceBefore = giga.balanceOf(alice);
        uint256 fenwickBefore = giga.getSuffixSum(1);

        console.log("Alice balance before self-transfer:", aliceBalanceBefore);
        console.log("Fenwick sum before self-transfer:", fenwickBefore);

        // Alice transfers to herself
        vm.prank(alice);
        giga.transfer(alice, 100 ether);

        uint256 aliceBalanceAfter = giga.balanceOf(alice);
        uint256 fenwickAfter = giga.getSuffixSum(1);

        console.log("Alice balance after self-transfer:", aliceBalanceAfter);
        console.log("Fenwick sum after self-transfer:", fenwickAfter);

        // Alice should lose 1% fee even on self-transfer
        assertEq(
            aliceBalanceAfter,
            aliceBalanceBefore - 1 ether,
            "Should charge fee on self-transfer"
        );

        // Fenwick should still be consistent
        assertEq(
            fenwickAfter,
            aliceBalanceAfter,
            "Fenwick should match Alice's balance"
        );
    }

    function testSelfTransferWithMultipleHolders() public {
        // Multiple users mint
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        vm.prank(bob);
        giga.mint{value: 5 ether}();

        uint256 totalBefore = giga.balanceOf(alice) + giga.balanceOf(bob);
        uint256 fenwickBefore = giga.getSuffixSum(1);
        assertEq(
            fenwickBefore,
            totalBefore,
            "Initial Fenwick should match total"
        );

        // Alice self-transfers
        vm.prank(alice);
        giga.transfer(alice, 500 ether);

        uint256 totalAfter = giga.balanceOf(alice) + giga.balanceOf(bob);
        uint256 fenwickAfter = giga.getSuffixSum(1);

        // Total should decrease by fee amount
        assertEq(
            totalBefore - totalAfter,
            5 ether,
            "Total should decrease by fee"
        );

        // Fenwick should still track correctly
        assertEq(fenwickAfter, totalAfter, "Fenwick should match new total");
    }

    function testRapidSelfTransfers() public {
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        uint256 expectedBalance = 9.9 ether;

        // Do 10 self-transfers rapidly
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(alice);
            giga.transfer(alice, 0.9 ether);
            expectedBalance -= 0.009 ether; // 1% fee each time

            // Check Fenwick consistency after each transfer
            uint256 fenwick = giga.getSuffixSum(1);
            uint256 aliceBalance = giga.balanceOf(alice);
            assertEq(fenwick, aliceBalance, "Fenwick should match balance");
            assertEq(
                aliceBalance,
                expectedBalance,
                "Balance should match expected"
            );
        }
    }

    function testSyntheticAddressesNotInFenwick() public {
        // Verify that FEES_POOL and LOT_POOL are never tracked in Fenwick tree
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        // After minting, alice has 9900, FEES_POOL has 100
        uint256 aliceBalance = giga.balanceOf(alice);
        uint256 feesBalance = giga.balanceOf(giga.FEES_POOL());

        assertEq(aliceBalance, 9.9 ether, "Alice should have 9.9");
        assertEq(feesBalance, 0.1 ether, "FEES_POOL should have 0.1");

        // Fenwick should only track Alice, not FEES_POOL
        uint256 fenwick = giga.getSuffixSum(1);
        assertEq(fenwick, aliceBalance, "Fenwick should only track Alice");

        // Do a transfer to generate more fees
        vm.prank(alice);
        giga.transfer(bob, 1 ether);

        // Check that Fenwick still only tracks real holders
        uint256 totalHolderBalance = giga.balanceOf(alice) +
            giga.balanceOf(bob);
        uint256 fenwickAfter = giga.getSuffixSum(1);
        assertEq(
            fenwickAfter,
            totalHolderBalance,
            "Fenwick should only track real holders"
        );

        // Verify fees went to FEES_POOL but aren't in Fenwick
        uint256 newFeesBalance = giga.balanceOf(giga.FEES_POOL());
        assertGt(
            newFeesBalance,
            feesBalance,
            "FEES_POOL should have more fees"
        );
    }
}
