// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EtheriumTestBase, MockContract} from "./helpers/EtheriumTestBase.sol";

contract EtheriumMintingTest is EtheriumTestBase {
    function testMintingWithFee() public {
        uint256 ethAmount = 1 ether;
        uint256 expectedTokens = ethAmount * 990; // 990 tokens per ETH after 1% fee
        uint256 expectedFee = ethAmount * 10; // 10 tokens fee per ETH

        vm.expectEmit(true, true, true, true);
        emit Minted(alice, ethAmount, expectedTokens, expectedFee);

        vm.prank(alice);
        etherium.mint{value: ethAmount}();

        assertEq(etherium.balanceOf(alice), expectedTokens);
        assertEq(etherium.balanceOf(etherium.FEES_POOL()), expectedFee);
        assertEq(address(etherium).balance, ethAmount);
    }

    function testRedeemWithFee() public {
        // First mint some tokens
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        uint256 initialBalance = etherium.balanceOf(alice);
        uint256 redeemAmount = 1000 ether; // Redeem 1000 tokens
        uint256 expectedFee = 10 ether; // 1% fee
        uint256 netRedeemed = redeemAmount - expectedFee;
        uint256 expectedEth = netRedeemed / 1000; // 1000:1 ratio

        uint256 aliceEthBefore = alice.balance;

        vm.expectEmit(true, true, true, true);
        emit Redeemed(alice, redeemAmount, expectedEth, expectedFee);

        vm.prank(alice);
        etherium.redeem(redeemAmount);

        assertEq(etherium.balanceOf(alice), initialBalance - redeemAmount);
        assertEq(alice.balance - aliceEthBefore, expectedEth);
    }

    function testMintingPeriodEnforcement() public {
        // During minting period - should succeed
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        assertGt(etherium.balanceOf(alice), 0);

        // Fast forward past minting period (7 days * 25 hours)
        vm.warp(block.timestamp + 7 * 25 hours + 1);

        // After minting period - should fail without capacity
        vm.expectRevert("Max supply reached");
        vm.prank(bob);
        etherium.mint{value: 1 ether}();

        // Create capacity by redeeming
        vm.prank(alice);
        etherium.redeem(100 ether);

        // Now minting should work up to capacity
        vm.prank(bob);
        etherium.mint{value: 0.09 ether}(); // Small amount within capacity
        assertGt(etherium.balanceOf(bob), 0);
    }

    function testCannotMintAfterPeriodWithoutCapacity() public {
        // Mint during period
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        // Move past minting period
        vm.warp(block.timestamp + 8 days);

        // Try to mint without capacity
        vm.expectRevert("Max supply reached");
        vm.prank(bob);
        etherium.mint{value: 1 ether}();

        // Redeem to create capacity
        vm.prank(alice);
        etherium.redeem(1000 ether);

        // Now bob can mint within capacity
        vm.prank(bob);
        etherium.mint{value: 0.9 ether}();
        assertGt(etherium.balanceOf(bob), 0);
    }

    function testRedeemingAllEtheriumDepleteContractETH() public {
        // Multiple users mint
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 10 ether}();

        // Alice redeems all her tokens
        uint256 aliceBalance = etherium.balanceOf(alice);
        vm.prank(alice);
        etherium.redeem(aliceBalance);

        // Bob redeems all his tokens
        uint256 bobBalance = etherium.balanceOf(bob);
        vm.prank(bob);
        etherium.redeem(bobBalance);

        // Contract should have very little ETH left (just fees)
        assertTrue(address(etherium).balance < 1 ether);
    }

    function testMaxSupplyNeverExceededWithPublicGoodsDonations() public {
        // Setup public goods
        address publicGood1 = address(0x1001);
        address publicGood2 = address(0x1002);
        address[] memory publicGoods = new address[](2);
        publicGoods[0] = publicGood1;
        publicGoods[1] = publicGood2;

        // Fund public goods
        vm.deal(publicGood1, 100 ether);
        vm.deal(publicGood2, 100 ether);

        // Initial mint during minting period
        vm.prank(alice);
        etherium.mint{value: 100 ether}();

        // Move past minting period to set max supply
        vm.warp(block.timestamp + 8 days);

        // Burn some tokens to create capacity
        vm.prank(alice);
        etherium.redeem(1000 ether);

        uint256 maxSupply = etherium.maxSupplyEver();
        assertEq(maxSupply, 100000 ether); // 100 ETH * 1000 ratio

        // Generate fees and execute lottery multiple times
        for (uint256 i = 0; i < 10; i++) {
            // Transfer to generate fees
            vm.prank(alice);
            etherium.transfer(bob, 100 ether);

            // Move to next day and execute lottery
            vm.warp(block.timestamp + 25 hours + 61);
            etherium.executeLottery();
        }

        // Try to mint within capacity
        vm.prank(bob);
        etherium.mint{value: 0.9 ether}();

        // Total supply should never exceed max
        uint256 totalSupply = etherium.totalSupply();
        assertLe(totalSupply, maxSupply, "Total supply should not exceed max");
    }

    function testETHDonations() public {
        // Initial state
        uint256 initialContractBalance = address(etherium).balance;

        // Alice donates ETH directly to the contract via receive()
        uint256 donationAmount = 5 ether;

        vm.prank(alice);
        (bool success,) = address(etherium).call{value: donationAmount}("");
        assertTrue(success, "Donation should succeed");

        // Contract balance should increase
        assertEq(
            address(etherium).balance,
            initialContractBalance + donationAmount,
            "Contract balance should increase by donation amount"
        );

        // No tokens should be minted
        assertEq(etherium.balanceOf(alice), 0, "No tokens should be minted for donations");
        assertEq(etherium.totalSupply(), 0, "Total supply should remain unchanged");
    }

    function testContractsCanTransferEtherium() public {
        // Deploy a contract that will hold and transfer ETHERIUM
        MockContract mockContract = new MockContract();
        vm.deal(address(mockContract), 10 ether);

        // Contract mints ETHERIUM (gets 990 after 1% fee)
        mockContract.mintEtherium(etherium);
        assertEq(etherium.balanceOf(address(mockContract)), 990 ether);

        // Contract should not be tracked as holder (excluded from lottery)
        assertFalse(etherium.isHolder(address(mockContract)));

        // Test 1: Contract can transfer to EOA
        address alice = address(0x1234);
        mockContract.transferEtherium(etherium, alice, 100 ether);

        // Verify transfer succeeded with 1% fee
        assertEq(etherium.balanceOf(alice), 99 ether, "Alice should receive 99 after 1% fee");
        assertEq(etherium.balanceOf(address(mockContract)), 890 ether, "Contract should have 890 left");

        // Alice should now be tracked as holder (EOA)
        assertTrue(etherium.isHolder(alice), "Alice should be tracked as holder");

        // Test 2: Contract can transfer to another contract
        MockContract secondContract = new MockContract();
        mockContract.transferEtherium(etherium, address(secondContract), 200 ether);

        // Verify transfer succeeded with 1% fee
        assertEq(etherium.balanceOf(address(secondContract)), 198 ether, "Second contract should receive 198 after fee");
        assertEq(etherium.balanceOf(address(mockContract)), 690 ether, "First contract should have 690 left");

        // Second contract should also not be tracked
        assertFalse(etherium.isHolder(address(secondContract)), "Second contract should not be tracked");

        // Test 3: Contract can approve and another contract can transferFrom
        mockContract.approveEtherium(etherium, address(secondContract), 300 ether);
        assertEq(etherium.allowance(address(mockContract), address(secondContract)), 300 ether);

        secondContract.transferFromEtherium(etherium, address(mockContract), alice, 300 ether);

        // Verify transferFrom succeeded with 1% fee
        assertEq(
            etherium.balanceOf(alice), 99 ether + 297 ether, "Alice should have original 99 + 297 from transferFrom"
        );
        assertEq(etherium.balanceOf(address(mockContract)), 390 ether, "First contract should have 390 left");

        // Test 4: Verify contracts are still excluded from lottery after transfers
        assertEq(etherium.getHolderCount(), 1, "Only Alice should be counted as holder");

        // Move past minting period and generate fees
        vm.warp(block.timestamp + 8 days);

        // Contract transfers to generate fees
        mockContract.transferEtherium(etherium, alice, 100 ether);

        // Execute lottery
        vm.warp(block.timestamp + 25 hours + 61);
        etherium.executeLottery();

        // Check that only Alice (EOA) could win, not the contracts
        uint256 currentDay = etherium.getCurrentDay();
        (address winner,) = etherium.lotteryUnclaimedPrizes((currentDay - 1) % 7);
        if (winner != address(0)) {
            // If there's a winner, it must be Alice (the only EOA holder)
            assertEq(winner, alice, "Winner must be Alice, the only EOA holder");
        }
    }
}
