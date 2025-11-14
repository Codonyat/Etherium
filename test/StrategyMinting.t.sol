// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrategyTestBase, MockContract} from "./helpers/StrategyTestBase.sol";

contract StrategyMintingTest is StrategyTestBase {
    function testMintingWithFee() public {
        uint256 ethAmount = 1 ether;
        uint256 expectedTokens = ethAmount * 990; // 990 tokens per ETH after 1% fee
        uint256 expectedFee = ethAmount * 10; // 10 tokens fee per ETH

        vm.expectEmit(true, true, true, true);
        emit Minted(alice, ethAmount, expectedTokens, expectedFee);

        vm.prank(alice);
        monstr.mint{value: ethAmount}();

        assertEq(monstr.balanceOf(alice), expectedTokens);
        assertEq(monstr.balanceOf(monstr.FEES_POOL()), expectedFee);
        assertEq(address(monstr).balance, ethAmount);
    }

    function testRedeemWithFee() public {
        // First mint some tokens
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        uint256 initialBalance = monstr.balanceOf(alice);
        uint256 redeemAmount = 1000 ether; // Redeem 1000 tokens
        uint256 expectedFee = 10 ether; // 1% fee
        uint256 netRedeemed = redeemAmount - expectedFee;
        uint256 expectedEth = netRedeemed / 1000; // 1000:1 ratio

        uint256 aliceEthBefore = alice.balance;

        vm.expectEmit(true, true, true, true);
        emit Redeemed(alice, redeemAmount, expectedEth, expectedFee);

        vm.prank(alice);
        monstr.redeem(redeemAmount);

        assertEq(monstr.balanceOf(alice), initialBalance - redeemAmount);
        assertEq(alice.balance - aliceEthBefore, expectedEth);
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
        monstr.redeem(100 ether);

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
        monstr.redeem(1000 ether);

        // Now bob can mint within capacity
        vm.prank(bob);
        monstr.mint{value: 0.9 ether}();
        assertGt(monstr.balanceOf(bob), 0);
    }

    function testRedeemingAllMonstrDepleteContractETH() public {
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

        // Contract should have very little ETH left (just fees)
        assertTrue(address(monstr).balance < 1 ether);
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
        monstr.mint{value: 100 ether}();

        // Move past minting period to set max supply
        vm.warp(block.timestamp + 8 days);

        // Burn some tokens to create capacity
        vm.prank(alice);
        monstr.redeem(1000 ether);

        uint256 maxSupply = monstr.maxSupplyEver();
        assertEq(maxSupply, 100000 ether); // 100 ETH * 1000 ratio

        // Generate fees and execute lottery multiple times
        for (uint256 i = 0; i < 10; i++) {
            // Transfer to generate fees
            vm.prank(alice);
            monstr.transfer(bob, 100 ether);

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

    function testETHDonations() public {
        // Initial state
        uint256 initialContractBalance = address(monstr).balance;

        // Alice donates ETH directly to the contract via receive()
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

        // Contract mints MONSTR (gets 990 after 1% fee)
        mockContract.mintStrategy(monstr);
        assertEq(monstr.balanceOf(address(mockContract)), 990 ether);

        // Contract should not be tracked as holder (excluded from lottery)
        assertFalse(monstr.isHolder(address(mockContract)));

        // Test 1: Contract can transfer to EOA
        address alice = address(0x1234);
        mockContract.transferStrategy(monstr, alice, 100 ether);

        // Verify transfer succeeded with 1% fee
        assertEq(
            monstr.balanceOf(alice),
            99 ether,
            "Alice should receive 99 after 1% fee"
        );
        assertEq(
            monstr.balanceOf(address(mockContract)),
            890 ether,
            "Contract should have 890 left"
        );

        // Alice should now be tracked as holder (EOA)
        assertTrue(
            monstr.isHolder(alice),
            "Alice should be tracked as holder"
        );

        // Test 2: Contract can transfer to another contract
        MockContract secondContract = new MockContract();
        mockContract.transferStrategy(
            monstr,
            address(secondContract),
            200 ether
        );

        // Verify transfer succeeded with 1% fee
        assertEq(
            monstr.balanceOf(address(secondContract)),
            198 ether,
            "Second contract should receive 198 after fee"
        );
        assertEq(
            monstr.balanceOf(address(mockContract)),
            690 ether,
            "First contract should have 690 left"
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
            300 ether
        );
        assertEq(
            monstr.allowance(address(mockContract), address(secondContract)),
            300 ether
        );

        secondContract.transferFromStrategy(
            monstr,
            address(mockContract),
            alice,
            300 ether
        );

        // Verify transferFrom succeeded with 1% fee
        assertEq(
            monstr.balanceOf(alice),
            99 ether + 297 ether,
            "Alice should have original 99 + 297 from transferFrom"
        );
        assertEq(
            monstr.balanceOf(address(mockContract)),
            390 ether,
            "First contract should have 390 left"
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
        mockContract.transferStrategy(monstr, alice, 100 ether);

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
        monstr.transfer(bob, 1 ether);

        // Max supply is now set to 2000 MONSTR (2 ETH minted * 1000)
        assertEq(
            monstr.maxSupplyEver(),
            2000 ether,
            "Max supply should be 2000 MONSTR"
        );

        // Now burn some tokens to create capacity for new mints
        vm.prank(alice);
        monstr.redeem(500 ether); // Burn 500 tokens to create capacity

        // State after redemption:
        // - Alice had 990 - 0.99 (transfer) - 500 (redeem) = 489.01 MONSTR
        // - Bob has 990 + 0.99 (from transfer) = 990.99 MONSTR
        // - FEES_POOL has 10 + 10 + 0.01 (transfer fee) + 5 (redeem fee) = 25.01 MONSTR
        // - Total supply = 489.01 + 990.99 + 25.01 = 1505.01 MONSTR
        // - Contract ETH = 2 ETH - 0.495 ETH (redeemed) = 1.505 ETH

        // Donate a large amount of ETH to increase the backing value
        vm.deal(address(this), 10000 ether);
        (bool success, ) = address(monstr).call{value: 10000 ether}("");
        assertTrue(success, "ETH donation should succeed");

        // Now we have:
        // - Contract ETH = 1.505 + 10000 = 10001.505 ETH
        // - Total supply = 1505.01 MONSTR
        // - Mint formula: monstrToMint = (msg.value * totalSupply) / ethBalance

        // With 1 wei of ETH:
        // monstrToMint = (1 * 1505.01e18) / 10001.505e18 ≈ 0.15 wei (much less than 100!)

        // Try to mint with 1 wei - should fail due to minimum requirement
        vm.prank(charlie);
        vm.expectRevert("Minimum mint amount is 100 wei");
        monstr.mint{value: 1 wei}();

        // To mint exactly 99 wei (below minimum):
        // 99 = (ethAmount * 1505.01e18) / 10001.505e18
        // ethAmount = 99 * 10001.505e18 / 1505.01e18 ≈ 657.79 wei
        // Let's use 658 wei which should mint about 99 wei

        vm.prank(charlie);
        vm.expectRevert("Minimum mint amount is 100 wei");
        monstr.mint{value: 658 wei}();

        // To mint exactly 100 wei (at minimum):
        // 100 = (ethAmount * 1505.01e18) / 10001.505e18
        // ethAmount = 100 * 10001.505e18 / 1505.01e18 ≈ 664.63 wei
        // Let's use 665 wei which should mint about 100 wei

        // This should succeed as it mints at least 100 wei
        vm.prank(charlie);
        monstr.mint{value: 665 wei}();

        // Verify Charlie received tokens (after 1% fee, so at least 99 wei)
        uint256 charlieBalance = monstr.balanceOf(charlie);
        assertEq(
            charlieBalance,
            99,
            "Charlie should have exactly 99 wei after fee"
        );
    }
}
