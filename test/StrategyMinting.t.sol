// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrategyTestBase, MockContract} from "./helpers/StrategyTestBase.sol";

contract StrategyMintingTest is StrategyTestBase {
    function testMintingWithFee() public {
        uint256 megaAmount = 1 ether;
        uint256 expectedTokens = (megaAmount * 99) / 100; // 0.99 tokens per MEGA after 1% fee (1:1 ratio)
        uint256 expectedFee = megaAmount / 100; // 0.01 tokens fee per MEGA

        mintGiga(alice, megaAmount);

        assertEq(giga.balanceOf(alice), expectedTokens);
        assertEq(giga.balanceOf(giga.FEES_POOL()), expectedFee);
        assertEq(giga.getMegaReserve(), megaAmount);
    }

    function testRedeemWithFee() public {
        // First mint some tokens
        mintGiga(alice, 10 ether);

        uint256 initialBalance = giga.balanceOf(alice);
        uint256 redeemAmount = 1 ether; // Redeem 1 token
        uint256 expectedFee = 0.01 ether; // 1% fee
        uint256 netRedeemed = redeemAmount - expectedFee;
        uint256 expectedMega = netRedeemed; // 1:1 ratio (proportional to backing)

        uint256 aliceMegaBefore = mega.balanceOf(alice);

        vm.expectEmit(true, true, true, true);
        emit Redeemed(alice, redeemAmount, expectedMega, expectedFee);

        vm.prank(alice);
        giga.redeem(redeemAmount);

        assertEq(giga.balanceOf(alice), initialBalance - redeemAmount);
        assertEq(mega.balanceOf(alice) - aliceMegaBefore, expectedMega);
    }

    function testMintingPeriodEnforcement() public {
        // During minting period - should succeed
        mintGiga(alice, 1 ether);
        assertGt(giga.balanceOf(alice), 0);

        // Fast forward past minting period
        skipPastMintingPeriod();

        // After minting period - should fail without capacity
        vm.startPrank(bob);
        mega.approve(address(giga), 1 ether);
        vm.expectRevert("Max supply reached");
        giga.mint(1 ether);
        vm.stopPrank();

        // Create capacity by redeeming
        vm.prank(alice);
        giga.redeem(0.1 ether);

        // Now minting should work up to capacity
        mintGiga(bob, 0.09 ether); // Small amount within capacity
        assertGt(giga.balanceOf(bob), 0);
    }

    function testCannotMintAfterPeriodWithoutCapacity() public {
        // Mint during period
        mintGiga(alice, 10 ether);

        // Move past minting period
        skipPastMintingPeriod();

        // Try to mint without capacity
        vm.startPrank(bob);
        mega.approve(address(giga), 1 ether);
        vm.expectRevert("Max supply reached");
        giga.mint(1 ether);
        vm.stopPrank();

        // Redeem to create capacity
        vm.prank(alice);
        giga.redeem(1 ether);

        // Now bob can mint within capacity
        mintGiga(bob, 0.9 ether);
        assertGt(giga.balanceOf(bob), 0);
    }

    function testRedeemingAllTokensDepletesContractMega() public {
        // Multiple users mint
        mintGiga(alice, 10 ether);
        mintGiga(bob, 10 ether);

        // Alice redeems all her tokens
        uint256 aliceBalance = giga.balanceOf(alice);
        vm.prank(alice);
        giga.redeem(aliceBalance);

        // Bob redeems all his tokens
        uint256 bobBalance = giga.balanceOf(bob);
        vm.prank(bob);
        giga.redeem(bobBalance);

        // Contract should have very little MEGA left (just fees)
        assertTrue(giga.getMegaReserve() < 1 ether);
    }

    function testMaxSupplyNeverExceededWithBeneficiaryDonations() public {
        // Setup beneficiaries
        address beneficiary1 = address(0x1001);
        address beneficiary2 = address(0x1002);
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        // Fund beneficiaries
        mega.mint(beneficiary1, 100 ether);
        mega.mint(beneficiary2, 100 ether);

        // Initial mint during minting period
        mintGiga(alice, 100 ether);

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
        mintGiga(bob, 0.9 ether);

        // Total supply should never exceed max
        uint256 totalSupply = giga.totalSupply();
        assertLe(totalSupply, maxSupply, "Total supply should not exceed max");
    }

    function testMegaDonations() public {
        // Initial state
        uint256 initialContractBalance = giga.getMegaReserve();

        // Alice donates MEGA directly to the contract via transfer
        uint256 donationAmount = 5 ether;

        vm.prank(alice);
        mega.transfer(address(giga), donationAmount);

        // Contract balance should increase
        assertEq(
            giga.getMegaReserve(),
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
        MockContract mockContract = new MockContract(mega);
        mega.mint(address(mockContract), 10 ether);

        // Contract mints GIGA (gets 0.99 after 1% fee)
        mockContract.mintStrategy(giga, 1 ether);
        assertEq(giga.balanceOf(address(mockContract)), 0.99 ether);

        // Contract should not be tracked as holder (excluded from lottery)
        assertFalse(giga.isHolder(address(mockContract)));

        // Test 1: Contract can transfer to EOA
        address testAlice = address(0x1234);
        mockContract.transferStrategy(giga, testAlice, 0.1 ether);

        // Verify transfer succeeded with 1% fee
        assertEq(
            giga.balanceOf(testAlice),
            0.099 ether,
            "Alice should receive 0.099 after 1% fee"
        );
        assertEq(
            giga.balanceOf(address(mockContract)),
            0.89 ether,
            "Contract should have 0.89 left"
        );

        // testAlice should now be tracked as holder (EOA)
        assertTrue(giga.isHolder(testAlice), "testAlice should be tracked as holder");

        // Test 2: Contract can transfer to another contract
        MockContract secondContract = new MockContract(mega);
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
            testAlice,
            0.3 ether
        );

        // Verify transferFrom succeeded with 1% fee
        assertEq(
            giga.balanceOf(testAlice),
            0.099 ether + 0.297 ether,
            "testAlice should have original 0.099 + 0.297 from transferFrom"
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
            "Only testAlice should be counted as holder"
        );

        // Move past minting period and generate fees
        vm.warp(block.timestamp + 8 days);

        // Contract transfers to generate fees
        mockContract.transferStrategy(giga, testAlice, 0.1 ether);

        // Execute lottery
        vm.warp(block.timestamp + 25 hours + 61);
        giga.executeLottery();

        // Check that only testAlice (EOA) could win, not the contracts
        uint256 currentDay = giga.getCurrentDay();
        (address winner, ) = giga.lotteryUnclaimedPrizes(
            (currentDay - 1) % 7
        );
        if (winner != address(0)) {
            // If there's a winner, it must be testAlice (the only EOA holder)
            assertEq(
                winner,
                testAlice,
                "Winner must be testAlice, the only EOA holder"
            );
        }
    }

    function testMinimumMintAmountAfterMintingPeriod() public {
        // First mint some tokens during minting period to create initial supply
        mintGiga(alice, 1 ether);

        // Also mint for bob to have more supply
        mintGiga(bob, 1 ether);

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
        mega.mint(address(this), 10000 ether);
        mega.transfer(address(giga), 10000 ether);

        // Now we have:
        // - Contract MEGA = 1.505 + 10000 = 10001.505 MEGA
        // - Total supply = 1.5051 GIGA
        // - Mint formula: gigaToMint = (megaAmount * totalSupply) / megaBalance

        // With 1 wei of MEGA:
        // gigaToMint = (1 * 1.5051e18) / 10001.505e18 ≈ 0.00015 wei (much less than 100!)

        // Try to mint with 1 wei - should fail due to minimum requirement
        vm.startPrank(charlie);
        mega.approve(address(giga), 1 wei);
        vm.expectRevert("Minimum mint amount is 100 wei");
        giga.mint(1 wei);
        vm.stopPrank();

        // To mint exactly 99 wei (below minimum):
        // 99 = (megaAmount * 1.5051e18) / 10001.505e18
        // megaAmount = 99 * 10001.505e18 / 1.5051e18 ≈ 657793 wei
        // Let's use 658000 wei which should mint about 99 wei

        vm.startPrank(charlie);
        mega.approve(address(giga), 658000 wei);
        vm.expectRevert("Minimum mint amount is 100 wei");
        giga.mint(658000 wei);
        vm.stopPrank();

        // To mint exactly 100 wei (at minimum):
        // 100 = (megaAmount * 1.5051e18) / 10001.505e18
        // megaAmount = 100 * 10001.505e18 / 1.5051e18 ≈ 664640 wei
        // Let's use 665000 wei which should mint about 100 wei

        // This should succeed as it mints at least 100 wei
        vm.startPrank(charlie);
        mega.approve(address(giga), 665000 wei);
        giga.mint(665000 wei);
        vm.stopPrank();

        // Verify Charlie received tokens (after 1% fee, so at least 99 wei)
        uint256 charlieBalance = giga.balanceOf(charlie);
        assertEq(
            charlieBalance,
            99,
            "Charlie should have exactly 99 wei after fee"
        );
    }
}
