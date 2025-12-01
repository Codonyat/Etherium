// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrategyTestBase, MockContract} from "./helpers/StrategyTestBase.sol";

contract StrategyMintingTest is StrategyTestBase {
    function testMintingWithFee() public {
        uint256 nativeAmount = 1 ether;
        uint256 expectedTokens = (nativeAmount * 99) / 100; // 0.99 tokens per MEGA after 1% fee (1:1 ratio)
        uint256 expectedFee = nativeAmount / 100; // 0.01 tokens fee per MEGA

        vm.expectEmit(true, true, true, true);
        emit Minted(alice, nativeAmount, expectedTokens, expectedFee);

        vm.prank(alice);
        giga.mint{value: nativeAmount}();

        assertEq(giga.balanceOf(alice), expectedTokens);
        assertEq(giga.balanceOf(giga.FEES_POOL()), expectedFee);
        assertEq(address(giga).balance, nativeAmount);
    }

    function testRedeemWithFee() public {
        // First mint some tokens
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        uint256 initialBalance = giga.balanceOf(alice);
        uint256 redeemAmount = 1 ether; // Redeem 1 token
        uint256 expectedFee = 0.01 ether; // 1% fee
        uint256 netRedeemed = redeemAmount - expectedFee;
        uint256 expectedNative = netRedeemed; // 1:1 ratio (proportional to backing)

        uint256 aliceNativeBefore = alice.balance;

        vm.expectEmit(true, true, true, true);
        emit Redeemed(alice, redeemAmount, expectedNative, expectedFee);

        vm.prank(alice);
        giga.redeem(redeemAmount);

        assertEq(giga.balanceOf(alice), initialBalance - redeemAmount);
        assertEq(alice.balance - aliceNativeBefore, expectedNative);
    }

    function testMintingPeriodEnforcement() public {
        // During minting period - should succeed
        vm.prank(alice);
        giga.mint{value: 1 ether}();
        assertGt(giga.balanceOf(alice), 0);

        // Fast forward past minting period
        skipPastMintingPeriod();

        // After minting period - should fail without capacity
        vm.expectRevert("Max supply reached");
        vm.prank(bob);
        giga.mint{value: 1 ether}();

        // Create capacity by redeeming
        vm.prank(alice);
        giga.redeem(0.1 ether);

        // Now minting should work up to capacity
        vm.prank(bob);
        giga.mint{value: 0.09 ether}(); // Small amount within capacity
        assertGt(giga.balanceOf(bob), 0);
    }

    function testCannotMintAfterPeriodWithoutCapacity() public {
        // Mint during period
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        // Move past minting period
        skipPastMintingPeriod();

        // Try to mint without capacity
        vm.expectRevert("Max supply reached");
        vm.prank(bob);
        giga.mint{value: 1 ether}();

        // Redeem to create capacity
        vm.prank(alice);
        giga.redeem(1 ether);

        // Now bob can mint within capacity
        vm.prank(bob);
        giga.mint{value: 0.9 ether}();
        assertGt(giga.balanceOf(bob), 0);
    }

    function testRedeemingAllTokensDepletesContractNative() public {
        // Multiple users mint
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        vm.prank(bob);
        giga.mint{value: 10 ether}();

        // Alice redeems all her tokens
        uint256 aliceBalance = giga.balanceOf(alice);
        vm.prank(alice);
        giga.redeem(aliceBalance);

        // Bob redeems all his tokens
        uint256 bobBalance = giga.balanceOf(bob);
        vm.prank(bob);
        giga.redeem(bobBalance);

        // Contract should have very little MEGA left (just fees)
        assertTrue(address(giga).balance < 1 ether);
    }

    function testMaxSupplyNeverExceededWithBeneficiaryDonations() public {
        // Setup beneficiaries
        address beneficiary1 = address(0x1001);
        address beneficiary2 = address(0x1002);
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        // Fund beneficiaries
        vm.deal(beneficiary1, 100 ether);
        vm.deal(beneficiary2, 100 ether);

        // Initial mint during minting period
        vm.prank(alice);
        giga.mint{value: 100 ether}();

        // Move past minting period to set max supply
        vm.warp(block.timestamp + 8 days);

        // Burn some tokens to create capacity
        vm.prank(alice);
        giga.redeem(1 ether);

        uint256 maxSupply = giga.maxSupplyEver();
        assertEq(maxSupply, 100 ether); // 100 MEGA * 1:1 ratio

        // Generate fees and execute lottery multiple times
        for (uint256 i = 0; i < 10; i++) {
            // Transfer to generate fees
            vm.prank(alice);
            giga.transfer(bob, 1 ether);

            // Move to next day and execute lottery
            vm.warp(block.timestamp + 25 hours + 61);
            giga.executeLottery();
        }

        // Try to mint within capacity
        vm.prank(bob);
        giga.mint{value: 0.9 ether}();

        // Total supply should never exceed max
        uint256 totalSupply = giga.totalSupply();
        assertLe(totalSupply, maxSupply, "Total supply should not exceed max");
    }

    function testNativeDonations() public {
        // Initial state
        uint256 initialContractBalance = address(giga).balance;

        // Alice donates MEGA directly to the contract via receive()
        uint256 donationAmount = 5 ether;

        vm.prank(alice);
        (bool success, ) = address(giga).call{value: donationAmount}("");
        assertTrue(success, "Donation should succeed");

        // Contract balance should increase
        assertEq(
            address(giga).balance,
            initialContractBalance + donationAmount,
            "Contract balance should increase by donation amount"
        );

        // No tokens should be minted
        assertEq(
            giga.balanceOf(alice),
            0,
            "No tokens should be minted for donations"
        );
        assertEq(
            giga.totalSupply(),
            0,
            "Total supply should remain unchanged"
        );
    }

    function testContractsCanTransferTokens() public {
        // Deploy a contract that will hold and transfer GIGA
        MockContract mockContract = new MockContract();
        vm.deal(address(mockContract), 10 ether);

        // Contract mints GIGA (gets 0.99 after 1% fee)
        mockContract.mintStrategy(giga);
        assertEq(giga.balanceOf(address(mockContract)), 0.99 ether);

        // Contract should not be tracked as holder (excluded from lottery)
        assertFalse(giga.isHolder(address(mockContract)));

        // Test 1: Contract can transfer to EOA
        address alice = address(0x1234);
        mockContract.transferStrategy(giga, alice, 0.1 ether);

        // Verify transfer succeeded with 1% fee
        assertEq(
            giga.balanceOf(alice),
            0.099 ether,
            "Alice should receive 0.099 after 1% fee"
        );
        assertEq(
            giga.balanceOf(address(mockContract)),
            0.89 ether,
            "Contract should have 0.89 left"
        );

        // Alice should now be tracked as holder (EOA)
        assertTrue(giga.isHolder(alice), "Alice should be tracked as holder");

        // Test 2: Contract can transfer to another contract
        MockContract secondContract = new MockContract();
        mockContract.transferStrategy(
            giga,
            address(secondContract),
            0.2 ether
        );

        // Verify transfer succeeded with 1% fee
        assertEq(
            giga.balanceOf(address(secondContract)),
            0.198 ether,
            "Second contract should receive 0.198 after fee"
        );
        assertEq(
            giga.balanceOf(address(mockContract)),
            0.69 ether,
            "First contract should have 0.69 left"
        );

        // Second contract should also not be tracked
        assertFalse(
            giga.isHolder(address(secondContract)),
            "Second contract should not be tracked"
        );

        // Test 3: Contract can approve and another contract can transferFrom
        mockContract.approveStrategy(
            giga,
            address(secondContract),
            0.3 ether
        );
        assertEq(
            giga.allowance(address(mockContract), address(secondContract)),
            0.3 ether
        );

        secondContract.transferFromStrategy(
            giga,
            address(mockContract),
            alice,
            0.3 ether
        );

        // Verify transferFrom succeeded with 1% fee
        assertEq(
            giga.balanceOf(alice),
            0.099 ether + 0.297 ether,
            "Alice should have original 0.099 + 0.297 from transferFrom"
        );
        assertEq(
            giga.balanceOf(address(mockContract)),
            0.39 ether,
            "First contract should have 0.39 left"
        );

        // Test 4: Verify contracts are still excluded from lottery after transfers
        assertEq(
            giga.getHolderCount(),
            1,
            "Only Alice should be counted as holder"
        );

        // Move past minting period and generate fees
        vm.warp(block.timestamp + 8 days);

        // Contract transfers to generate fees
        mockContract.transferStrategy(giga, alice, 0.1 ether);

        // Execute lottery
        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        // Check that only Alice (EOA) could win, not the contracts
        uint256 currentDay = giga.getCurrentDay();
        (address winner, ) = giga.lotteryUnclaimedPrizes(
            (currentDay - 1) % 7
        );
        if (winner != address(0)) {
            // If there's a winner, it must be Alice (the only EOA holder)
            assertEq(
                winner,
                alice,
                "Winner must be Alice, the only EOA holder"
            );
        }
    }

    function testMinimumMintAmountAfterMintingPeriod() public {
        // First mint some tokens during minting period to create initial supply
        vm.prank(alice);
        giga.mint{value: 1 ether}();

        // Also mint for bob to have more supply
        vm.prank(bob);
        giga.mint{value: 1 ether}();

        // Move past minting period
        skipPastMintingPeriod();

        // Do a small transaction to trigger max supply setting
        vm.prank(alice);
        giga.transfer(bob, 0.01 ether);

        // Max supply is now set to 2 GIGA (2 MEGA minted * 1:1)
        assertEq(
            giga.maxSupplyEver(),
            2 ether,
            "Max supply should be 2 GIGA"
        );

        // Now burn some tokens to create capacity for new mints
        vm.prank(alice);
        giga.redeem(0.5 ether); // Burn 0.5 tokens to create capacity

        // State after redemption:
        // - Alice had 0.99 - 0.0099 (transfer) - 0.5 (redeem) = 0.4801 GIGA
        // - Bob has 0.99 + 0.0099 (from transfer) = 0.9999 GIGA
        // - FEES_POOL has 0.01 + 0.01 + 0.0001 (transfer fee) + 0.005 (redeem fee) = 0.0251 GIGA
        // - Total supply = 0.4801 + 0.9999 + 0.0251 = 1.5051 GIGA
        // - Contract MEGA = 2 MEGA - 0.495 MEGA (redeemed) = 1.505 MEGA

        // Donate a large amount of MEGA to increase the backing value
        vm.deal(address(this), 10000 ether);
        (bool success, ) = address(giga).call{value: 10000 ether}("");
        assertTrue(success, "Native donation should succeed");

        // Now we have:
        // - Contract MEGA = 1.505 + 10000 = 10001.505 MEGA
        // - Total supply = 1.5051 GIGA
        // - Mint formula: gigaToMint = (msg.value * totalSupply) / nativeBalance

        // With 1 wei of MEGA:
        // gigaToMint = (1 * 1.5051e18) / 10001.505e18 ≈ 0.00015 wei (much less than 100!)

        // Try to mint with 1 wei - should fail due to minimum requirement
        vm.prank(charlie);
        vm.expectRevert("Minimum mint amount is 100 wei");
        giga.mint{value: 1 wei}();

        // To mint exactly 99 wei (below minimum):
        // 99 = (nativeAmount * 1.5051e18) / 10001.505e18
        // nativeAmount = 99 * 10001.505e18 / 1.5051e18 ≈ 657793 wei
        // Let's use 658000 wei which should mint about 99 wei

        vm.prank(charlie);
        vm.expectRevert("Minimum mint amount is 100 wei");
        giga.mint{value: 658000 wei}();

        // To mint exactly 100 wei (at minimum):
        // 100 = (nativeAmount * 1.5051e18) / 10001.505e18
        // nativeAmount = 100 * 10001.505e18 / 1.5051e18 ≈ 664640 wei
        // Let's use 665000 wei which should mint about 100 wei

        // This should succeed as it mints at least 100 wei
        vm.prank(charlie);
        giga.mint{value: 665000 wei}();

        // Verify Charlie received tokens (after 1% fee, so at least 99 wei)
        uint256 charlieBalance = giga.balanceOf(charlie);
        assertEq(
            charlieBalance,
            99,
            "Charlie should have exactly 99 wei after fee"
        );
    }
}
