// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrategyTestBase, MockContract} from "./helpers/StrategyTestBase.sol";

contract StrategyMintingTest is StrategyTestBase {
    function testMintingWithFee() public {
        uint256 monAmount = 1 ether;
        uint256 expectedTokens = (monAmount * 99) / 100; // 0.99 tokens per MON after 1% fee (1:1 ratio)
        uint256 expectedFee = monAmount / 100; // 0.01 tokens fee per MON

        vm.expectEmit(true, true, true, true);
        emit Minted(alice, monAmount, expectedTokens, expectedFee);

        vm.prank(alice);
        monstr.mint{value: monAmount}();

        assertEq(monstr.balanceOf(alice), expectedTokens);
        assertEq(monstr.balanceOf(monstr.FEES_POOL()), expectedFee);
        assertEq(address(monstr).balance, monAmount);
    }

    function testRedeemWithFee() public {
        // First mint some tokens
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        uint256 initialBalance = monstr.balanceOf(alice);
        uint256 redeemAmount = 1 ether; // Redeem 1 token
        uint256 expectedFee = 0.01 ether; // 1% fee
        uint256 netRedeemed = redeemAmount - expectedFee;
        uint256 expectedMon = netRedeemed; // 1:1 ratio (proportional to backing)

        uint256 aliceMonBefore = alice.balance;

        vm.expectEmit(true, true, true, true);
        emit Redeemed(alice, redeemAmount, expectedMon, expectedFee);

        vm.prank(alice);
        monstr.redeem(redeemAmount);

        assertEq(monstr.balanceOf(alice), initialBalance - redeemAmount);
        assertEq(alice.balance - aliceMonBefore, expectedMon);
    }

    function testMintingPeriodEnforcement() public {
        // During minting period - should succeed
        vm.prank(alice);
        monstr.mint{value: 1 ether}();
        assertGt(monstr.balanceOf(alice), 0);

        // Fast forward past minting period (7 days * 25 hours)
        vm.warp(block.timestamp + 7 * 25 hours + 1);

        // After minting period - should fail without capacity
        vm.expectRevert("Max supply reached");
        vm.prank(bob);
        monstr.mint{value: 1 ether}();

        // Create capacity by redeeming
        vm.prank(alice);
        monstr.redeem(0.1 ether);

        // Now minting should work up to capacity
        vm.prank(bob);
        monstr.mint{value: 0.09 ether}(); // Small amount within capacity
        assertGt(monstr.balanceOf(bob), 0);
    }

    function testCannotMintAfterPeriodWithoutCapacity() public {
        // Mint during period
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        // Move past minting period
        vm.warp(block.timestamp + 8 days);

        // Try to mint without capacity
        vm.expectRevert("Max supply reached");
        vm.prank(bob);
        monstr.mint{value: 1 ether}();

        // Redeem to create capacity
        vm.prank(alice);
        monstr.redeem(1 ether);

        // Now bob can mint within capacity
        vm.prank(bob);
        monstr.mint{value: 0.9 ether}();
        assertGt(monstr.balanceOf(bob), 0);
    }

    function testRedeemingAllMonstrDepleteContractMON() public {
        // Multiple users mint
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        vm.prank(bob);
        monstr.mint{value: 10 ether}();

        // Alice redeems all her tokens
        uint256 aliceBalance = monstr.balanceOf(alice);
        vm.prank(alice);
        monstr.redeem(aliceBalance);

        // Bob redeems all his tokens
        uint256 bobBalance = monstr.balanceOf(bob);
        vm.prank(bob);
        monstr.redeem(bobBalance);

        // Contract should have very little MON left (just fees)
        assertTrue(address(monstr).balance < 1 ether);
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
        monstr.mint{value: 100 ether}();

        // Move past minting period to set max supply
        vm.warp(block.timestamp + 8 days);

        // Burn some tokens to create capacity
        vm.prank(alice);
        monstr.redeem(1 ether);

        uint256 maxSupply = monstr.maxSupplyEver();
        assertEq(maxSupply, 100 ether); // 100 MON * 1:1 ratio

        // Generate fees and execute lottery multiple times
        for (uint256 i = 0; i < 10; i++) {
            // Transfer to generate fees
            vm.prank(alice);
            monstr.transfer(bob, 1 ether);

            // Move to next day and execute lottery
            vm.warp(block.timestamp + 25 hours + 61);
            monstr.executeLottery();
        }

        // Try to mint within capacity
        vm.prank(bob);
        monstr.mint{value: 0.9 ether}();

        // Total supply should never exceed max
        uint256 totalSupply = monstr.totalSupply();
        assertLe(totalSupply, maxSupply, "Total supply should not exceed max");
    }

    function testMONDonations() public {
        // Initial state
        uint256 initialContractBalance = address(monstr).balance;

        // Alice donates MON directly to the contract via receive()
        uint256 donationAmount = 5 ether;

        vm.prank(alice);
        (bool success, ) = address(monstr).call{value: donationAmount}("");
        assertTrue(success, "Donation should succeed");

        // Contract balance should increase
        assertEq(
            address(monstr).balance,
            initialContractBalance + donationAmount,
            "Contract balance should increase by donation amount"
        );

        // No tokens should be minted
        assertEq(
            monstr.balanceOf(alice),
            0,
            "No tokens should be minted for donations"
        );
        assertEq(
            monstr.totalSupply(),
            0,
            "Total supply should remain unchanged"
        );
    }

    function testContractsCanTransferMonstr() public {
        // Deploy a contract that will hold and transfer MONSTR
        MockContract mockContract = new MockContract();
        vm.deal(address(mockContract), 10 ether);

        // Contract mints MONSTR (gets 0.99 after 1% fee)
        mockContract.mintStrategy(monstr);
        assertEq(monstr.balanceOf(address(mockContract)), 0.99 ether);

        // Contract should not be tracked as holder (excluded from lottery)
        assertFalse(monstr.isHolder(address(mockContract)));

        // Test 1: Contract can transfer to EOA
        address alice = address(0x1234);
        mockContract.transferStrategy(monstr, alice, 0.1 ether);

        // Verify transfer succeeded with 1% fee
        assertEq(
            monstr.balanceOf(alice),
            0.099 ether,
            "Alice should receive 0.099 after 1% fee"
        );
        assertEq(
            monstr.balanceOf(address(mockContract)),
            0.89 ether,
            "Contract should have 0.89 left"
        );

        // Alice should now be tracked as holder (EOA)
        assertTrue(monstr.isHolder(alice), "Alice should be tracked as holder");

        // Test 2: Contract can transfer to another contract
        MockContract secondContract = new MockContract();
        mockContract.transferStrategy(
            monstr,
            address(secondContract),
            0.2 ether
        );

        // Verify transfer succeeded with 1% fee
        assertEq(
            monstr.balanceOf(address(secondContract)),
            0.198 ether,
            "Second contract should receive 0.198 after fee"
        );
        assertEq(
            monstr.balanceOf(address(mockContract)),
            0.69 ether,
            "First contract should have 0.69 left"
        );

        // Second contract should also not be tracked
        assertFalse(
            monstr.isHolder(address(secondContract)),
            "Second contract should not be tracked"
        );

        // Test 3: Contract can approve and another contract can transferFrom
        mockContract.approveStrategy(
            monstr,
            address(secondContract),
            0.3 ether
        );
        assertEq(
            monstr.allowance(address(mockContract), address(secondContract)),
            0.3 ether
        );

        secondContract.transferFromStrategy(
            monstr,
            address(mockContract),
            alice,
            0.3 ether
        );

        // Verify transferFrom succeeded with 1% fee
        assertEq(
            monstr.balanceOf(alice),
            0.099 ether + 0.297 ether,
            "Alice should have original 0.099 + 0.297 from transferFrom"
        );
        assertEq(
            monstr.balanceOf(address(mockContract)),
            0.39 ether,
            "First contract should have 0.39 left"
        );

        // Test 4: Verify contracts are still excluded from lottery after transfers
        assertEq(
            monstr.getHolderCount(),
            1,
            "Only Alice should be counted as holder"
        );

        // Move past minting period and generate fees
        vm.warp(block.timestamp + 8 days);

        // Contract transfers to generate fees
        mockContract.transferStrategy(monstr, alice, 0.1 ether);

        // Execute lottery
        vm.warp(block.timestamp + 25 hours + 61);
        monstr.executeLottery();

        // Check that only Alice (EOA) could win, not the contracts
        uint256 currentDay = monstr.getCurrentDay();
        (address winner, ) = monstr.lotteryUnclaimedPrizes(
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
        monstr.mint{value: 1 ether}();

        // Also mint for bob to have more supply
        vm.prank(bob);
        monstr.mint{value: 1 ether}();

        // Move past minting period
        vm.warp(block.timestamp + 8 days);

        // Do a small transaction to trigger max supply setting
        vm.prank(alice);
        monstr.transfer(bob, 0.01 ether);

        // Max supply is now set to 2 MONSTR (2 MON minted * 1:1)
        assertEq(
            monstr.maxSupplyEver(),
            2 ether,
            "Max supply should be 2 MONSTR"
        );

        // Now burn some tokens to create capacity for new mints
        vm.prank(alice);
        monstr.redeem(0.5 ether); // Burn 0.5 tokens to create capacity

        // State after redemption:
        // - Alice had 0.99 - 0.0099 (transfer) - 0.5 (redeem) = 0.4801 MONSTR
        // - Bob has 0.99 + 0.0099 (from transfer) = 0.9999 MONSTR
        // - FEES_POOL has 0.01 + 0.01 + 0.0001 (transfer fee) + 0.005 (redeem fee) = 0.0251 MONSTR
        // - Total supply = 0.4801 + 0.9999 + 0.0251 = 1.5051 MONSTR
        // - Contract MON = 2 MON - 0.495 MON (redeemed) = 1.505 MON

        // Donate a large amount of MON to increase the backing value
        vm.deal(address(this), 10000 ether);
        (bool success, ) = address(monstr).call{value: 10000 ether}("");
        assertTrue(success, "MON donation should succeed");

        // Now we have:
        // - Contract MON = 1.505 + 10000 = 10001.505 MON
        // - Total supply = 1.5051 MONSTR
        // - Mint formula: monstrToMint = (msg.value * totalSupply) / monBalance

        // With 1 wei of MON:
        // monstrToMint = (1 * 1.5051e18) / 10001.505e18 ≈ 0.00015 wei (much less than 100!)

        // Try to mint with 1 wei - should fail due to minimum requirement
        vm.prank(charlie);
        vm.expectRevert("Minimum mint amount is 100 wei");
        monstr.mint{value: 1 wei}();

        // To mint exactly 99 wei (below minimum):
        // 99 = (monAmount * 1.5051e18) / 10001.505e18
        // monAmount = 99 * 10001.505e18 / 1.5051e18 ≈ 657793 wei
        // Let's use 658000 wei which should mint about 99 wei

        vm.prank(charlie);
        vm.expectRevert("Minimum mint amount is 100 wei");
        monstr.mint{value: 658000 wei}();

        // To mint exactly 100 wei (at minimum):
        // 100 = (monAmount * 1.5051e18) / 10001.505e18
        // monAmount = 100 * 10001.505e18 / 1.5051e18 ≈ 664640 wei
        // Let's use 665000 wei which should mint about 100 wei

        // This should succeed as it mints at least 100 wei
        vm.prank(charlie);
        monstr.mint{value: 665000 wei}();

        // Verify Charlie received tokens (after 1% fee, so at least 99 wei)
        uint256 charlieBalance = monstr.balanceOf(charlie);
        assertEq(
            charlieBalance,
            99,
            "Charlie should have exactly 99 wei after fee"
        );
    }
}
