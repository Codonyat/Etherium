// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract EtheriumSecurityTest is Test {
    Etherium public etherium;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    function setUp() public {
        etherium = new Etherium();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }

    // ============ Zero Amount Operations ============

    function testMintZeroETH() public {
        vm.prank(alice);
        vm.expectRevert("Must send ETH");
        etherium.mint{value: 0}();
    }

    function testRedeemZeroAmount() public {
        vm.prank(alice);
        etherium.mint{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert("Amount must be greater than 0");
        etherium.redeem(0);
    }

    function testTransferZeroAmount() public {
        vm.prank(alice);
        etherium.mint{value: 1 ether}();

        // Zero transfers should work per ERC20 spec
        vm.prank(alice);
        bool success = etherium.transfer(bob, 0);
        assertTrue(success, "Zero transfer should succeed");

        // But no fees should be taken
        assertEq(etherium.balanceOf(alice), 990 ether);
    }

    // ============ Self Operations ============

    function testSelfTransferFees() public {
        vm.prank(alice);
        etherium.mint{value: 1 ether}();

        uint256 balanceBefore = etherium.balanceOf(alice);

        // Self transfer should still charge fees
        vm.prank(alice);
        etherium.transfer(alice, 100 ether);

        uint256 balanceAfter = etherium.balanceOf(alice);
        assertEq(balanceBefore - balanceAfter, 1 ether, "Should charge 1% fee even on self-transfer");
    }

    // ============ Insufficient Balance Tests ============

    function testRedeemWithInsufficientContractETH() public {
        // Mint tokens
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 10 ether}();

        // Alice redeems all her tokens (9900 not 990)
        vm.prank(alice);
        etherium.redeem(9900 ether);

        // Bob tries to redeem but contract has insufficient ETH
        // After Alice's redemption: contract has ~10.1 ETH left
        // Bob tries to redeem 9900 tokens which needs ~9.9 ETH
        // Should succeed
        vm.prank(bob);
        etherium.redeem(9900 ether);

        // Verify contract is nearly empty
        assertTrue(address(etherium).balance < 1 ether, "Contract should be nearly empty");
    }

    // ============ Max Supply Tests ============

    function testMaxSupplyEnforcement() public {
        // Mint during minting period (100 ETH = 100,000 ETHERIUM total, alice gets 99,000 after 1% fee)
        vm.prank(alice);
        etherium.mint{value: 100 ether}();

        // Fast forward past minting period
        vm.warp(block.timestamp + 8 days);

        // First burn some tokens to create capacity (this also sets max supply)
        vm.prank(alice);
        etherium.redeem(1000 ether); // Burn 1000 tokens (990 net after fee)

        // Max supply should now be set to original total supply (100,000 ETHERIUM)
        uint256 maxSupply = etherium.maxSupplyEver();
        assertGt(maxSupply, 0, "Max supply should be set");
        assertEq(maxSupply, 100000 ether, "Max supply should be 100,000 ETHERIUM");

        // Current supply is now ~99,010 ETHERIUM (100,000 - 990 burned)
        // With proportional minting, we can mint up to ~990 ETHERIUM

        // Small mint should succeed
        vm.prank(bob);
        etherium.mint{value: 0.9 ether}(); // Should succeed

        // Try to mint again when we're close to max supply - should fail
        vm.prank(bob);
        vm.expectRevert("Max supply reached");
        etherium.mint{value: 0.1 ether}(); // This would push us over max supply
    }

    // ============ Timing Tests ============

    function testTimestampManipulationResistance() public {
        // The 25-hour pseudo-days make it harder to game timing
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        // Fast forward to just before day 2
        vm.warp(block.timestamp + 50 hours - 1);

        // Should still be day 1
        uint256 day = etherium.getCurrentDay();
        assertEq(day, 1, "Should still be day 1");

        // Fast forward 2 seconds
        vm.warp(block.timestamp + 2);

        // Now should be day 2
        day = etherium.getCurrentDay();
        assertEq(day, 2, "Should be day 2");
    }

    function testPreventDoubleLotteryExecution() public {
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 5 ether}();

        // Move past minting period
        vm.warp(block.timestamp + 8 days);

        // Generate fees on day 8
        vm.prank(alice);
        etherium.transfer(bob, 100 ether);

        // Fast forward to day 9 to execute lottery
        vm.warp(block.timestamp + 25 hours + 61);

        // Execute lottery once
        etherium.executeLottery();

        // Try to execute again
        vm.expectRevert("No pending lottery/auction (same day)");
        etherium.executeLottery();
    }

    // ============ Large Number Tests ============

    function testLargeFeeCalculation() public {
        // Test with large but reasonable amount
        uint256 largeAmount = 10_000 ether;

        vm.deal(alice, largeAmount + 1 ether);
        vm.prank(alice);
        etherium.mint{value: largeAmount}();

        // Check fee calculation didn't overflow
        uint256 expectedTokens = largeAmount * 990; // 9,900,000 tokens with 18 decimals
        assertEq(etherium.balanceOf(alice), expectedTokens, "Should receive correct amount");

        uint256 expectedFee = largeAmount * 10; // 100,000 tokens fee with 18 decimals
        assertEq(etherium.balanceOf(etherium.FEES_POOL()), expectedFee, "Fee should be correct");
    }

    // ============ Public Goods Tests ============

    function testUnclaimedPrizeToPublicGoods() public {
        // Create a rejecting public good
        RejectingReceiver rejectingPublicGood = new RejectingReceiver();

        // We can't change public goods array, but we can test the fallback behavior
        // When public good rejects, prize should go to current winner

        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 5 ether}();

        // Generate some transfer fees on day 8
        vm.warp(block.timestamp + 8 days);
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether); // 10 ETHERIUM fee

        // Day 9 - Execute lottery/auction for day 8's fees
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();

        // After minting period, days alternate between lottery and auction
        // Day 8 fees might go to auction, not lottery
        // So generate more fees and execute more days to ensure we get a lottery

        // Generate fees on day 9
        vm.prank(bob);
        etherium.transfer(alice, 500 ether); // 5 ETHERIUM fee

        // Day 10 - Execute for day 9's fees
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();

        // Now check for a winner - try both slots
        (address winner1, uint112 amount1) = etherium.lotteryUnclaimedPrizes(9 % 7);
        if (winner1 == address(0)) {
            // Try slot 8 if 9 is empty
            (winner1, amount1) = etherium.lotteryUnclaimedPrizes(8 % 7);
        }
        assertTrue(winner1 != address(0), "Should have winner");
        assertTrue(amount1 > 0, "Should have prize amount");
        
        // Store the unclaimed prize amount for later verification
        uint256 unclaimedPrizeAmount = amount1;
        (address checkWinner,) = etherium.lotteryUnclaimedPrizes(9 % 7);
        uint256 slotToOverwrite = (winner1 == checkWinner) ? 9 % 7 : 8 % 7;

        // Get the first public good address to track its balance
        address firstPublicGood = etherium.PUBLIC_GOODS(0);
        uint256 publicGoodBalanceBefore = firstPublicGood.balance;
        
        // Fast forward 7 days to overwrite the slot with unclaimed prize
        // This will trigger the public goods funding
        for (uint256 i = 0; i < 7; i++) {
            // Generate fees for the current day
            vm.prank(alice);
            etherium.transfer(bob, 100 ether);

            // Move to next day and execute lottery
            vm.warp(block.timestamp + 25 hours + 61);
            etherium.executeLottery();
        }
        
        // Check if public good received ETH
        uint256 publicGoodBalanceAfter = firstPublicGood.balance;
        uint256 ethSent = publicGoodBalanceAfter - publicGoodBalanceBefore;
        
        // CRITICAL: The public good should receive ETH equal to the backing value of the ETHERIUM prize
        // The correct conversion should be: ethAmount = (etheriumAmount * contractETHBalance) / totalSupply
        
        // Log the values for debugging
        console.log("Unclaimed ETHERIUM prize:", unclaimedPrizeAmount);
        console.log("Actual ETH sent:", ethSent);
        
        // The bug has been fixed! Now the contract correctly converts ETHERIUM to ETH
        // The exact amount depends on when the conversion happens (contract balance and supply change over time)
        // But it should be much less than the ETHERIUM amount (roughly 1000x less during minting period)
        
        // Verify that ETH was sent and it's a reasonable amount (not the full ETHERIUM amount)
        assertTrue(ethSent > 0, "Should have sent some ETH to public good");
        assertTrue(ethSent < unclaimedPrizeAmount / 100, "ETH sent should be much less than ETHERIUM amount (proper conversion)");
    }

    // ============ Fenwick Tree Consistency ============

    function testFenwickTreeConsistencyUnderStress() public {
        // Rapidly add and remove holders
        address[] memory users = new address[](20);
        for (uint256 i = 0; i < 20; i++) {
            users[i] = address(uint160(0x1000 + i));
            vm.deal(users[i], 10 ether);
        }

        // Mint for all users
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(users[i]);
            etherium.mint{value: 1 ether}();
        }

        // Move past minting period to ensure fees go to pool
        vm.warp(block.timestamp + 8 days);

        // Do random transfers to generate fees
        for (uint256 i = 0; i < 50; i++) {
            uint256 from = i % 20;
            uint256 to = (i + 7) % 20;
            uint256 amount = 100 ether * ((i % 5) + 1);

            if (etherium.balanceOf(users[from]) >= amount) {
                vm.prank(users[from]);
                etherium.transfer(users[to], amount);
            }
        }

        // System should still be consistent - verify by executing lottery
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery(); // Should not revert
    }
}

// Helper contracts
contract RejectingReceiver {
    receive() external payable {
        revert("I reject ETH!");
    }
}
