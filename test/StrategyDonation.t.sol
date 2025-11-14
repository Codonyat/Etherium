// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy, IWMON} from "../src/Strategy.sol";
import {MockWMON} from "././helpers/WSTRATHelpers.sol";

contract StrategyDonationTest is Test {
    Strategy public monstr;
    MockWMON public wmon;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public donor = address(0x3);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Minted(
        address indexed to,
        uint256 monAmount,
        uint256 monstrAmount,
        uint256 fee
    );
    event Redeemed(
        address indexed from,
        uint256 monstrAmount,
        uint256 monAmount,
        uint256 fee
    );

    function setUp() public {
        wmon = new MockWMON();
        monstr = new Strategy(address(wmon));

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(donor, 100 ether);
    }

    function testDonationIncreasesRedemptionValue() public {
        // Alice mints first
        uint256 mintAmount = 10 ether;
        uint256 expectedTokens = mintAmount * 990; // 9,900 tokens after 1% fee
        uint256 expectedFee = mintAmount * 10; // 100 tokens fee

        vm.expectEmit(true, true, true, true);
        emit Minted(alice, mintAmount, expectedTokens, expectedFee);

        vm.prank(alice);
        monstr.mint{value: mintAmount}();

        assertEq(
            monstr.balanceOf(alice),
            expectedTokens,
            "Alice should receive 9,900 tokens"
        );
        assertEq(
            monstr.balanceOf(monstr.FEES_POOL()),
            expectedFee,
            "Fees pool should have 100 tokens"
        );

        uint256 totalSupplyBefore = monstr.totalSupply();
        uint256 contractBalanceBefore = address(monstr).balance;
        assertEq(
            totalSupplyBefore,
            10000 ether,
            "Total supply should be 10,000 tokens"
        );
        assertEq(
            contractBalanceBefore,
            mintAmount,
            "Contract should hold 10 MON"
        );

        // Calculate redemption value before donation
        uint256 redeemAmount = 1000 ether; // 1000 MONSTR
        uint256 fee = redeemAmount / 100; // 10 MONSTR fee
        uint256 netAmount = redeemAmount - fee; // 990 MONSTR
        uint256 redemptionValueBefore = (netAmount * contractBalanceBefore) /
            totalSupplyBefore;
        assertEq(
            redemptionValueBefore,
            0.99 ether,
            "Redemption value before should be 0.99 MON"
        );

        // Donor sends 5 MON to the contract
        uint256 donationAmount = 5 ether;
        vm.prank(donor);
        (bool success, ) = address(monstr).call{value: donationAmount}("");
        assertTrue(success, "Donation should succeed");

        // Check contract balance increased
        assertEq(
            address(monstr).balance,
            contractBalanceBefore + donationAmount,
            "Contract balance should increase by 5 MON"
        );

        // Check total supply unchanged
        assertEq(
            monstr.totalSupply(),
            totalSupplyBefore,
            "Total supply should remain 10,000 tokens"
        );

        // Calculate redemption value after donation
        uint256 redemptionValueAfter = (netAmount * address(monstr).balance) /
            monstr.totalSupply();
        assertEq(
            redemptionValueAfter,
            1.485 ether,
            "Redemption value after should be 1.485 MON"
        );

        // Redemption value should increase by 50%
        assertEq(
            redemptionValueAfter - redemptionValueBefore,
            0.495 ether,
            "Redemption value should increase by 0.495 MON"
        );
    }

    function testDonationDoesntAffectMinting() public {
        // Initial mint
        vm.expectEmit(true, true, true, true);
        emit Minted(alice, 1 ether, 990 ether, 10 ether);

        vm.prank(alice);
        monstr.mint{value: 1 ether}();
        assertEq(
            monstr.balanceOf(alice),
            990 ether,
            "Alice should get 990 tokens"
        );

        // Donate MON
        uint256 donationAmount = 10 ether;
        vm.prank(donor);
        (bool success, ) = address(monstr).call{value: donationAmount}("");
        assertTrue(success, "Donation should succeed");
        assertEq(
            address(monstr).balance,
            11 ether,
            "Contract should have 11 MON"
        );

        // Bob mints after donation
        vm.expectEmit(true, true, true, true);
        emit Minted(bob, 1 ether, 990 ether, 10 ether);

        vm.prank(bob);
        monstr.mint{value: 1 ether}();

        // Bob should still get the standard amount (990 MONSTR after 1% fee)
        assertEq(
            monstr.balanceOf(bob),
            990 ether,
            "Bob should get 990 tokens despite donation"
        );
        assertEq(
            address(monstr).balance,
            12 ether,
            "Contract should have 12 MON"
        );
    }

    function testDonationDoesntBreakLottery() public {
        // Setup holders
        vm.prank(alice);
        monstr.mint{value: 10 ether}();
        assertEq(
            monstr.balanceOf(alice),
            9900 ether,
            "Alice should have 9,900 tokens"
        );

        vm.prank(bob);
        monstr.mint{value: 10 ether}();
        assertEq(
            monstr.balanceOf(bob),
            9900 ether,
            "Bob should have 9,900 tokens"
        );

        // Generate fees on day 0
        uint256 transferAmount = 1000 ether;

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 990 ether); // Bob receives 990 after fee

        vm.prank(alice);
        monstr.transfer(bob, transferAmount);
        assertEq(
            monstr.balanceOf(alice),
            8900 ether,
            "Alice should have 8,900 tokens"
        );
        assertEq(
            monstr.balanceOf(bob),
            10890 ether,
            "Bob should have 10,890 tokens"
        );
        assertEq(
            monstr.balanceOf(monstr.FEES_POOL()),
            210 ether,
            "Fees pool should have 210 tokens"
        );

        // Donate MON
        uint256 donationAmount = 5 ether;
        vm.prank(donor);
        (bool success, ) = address(monstr).call{value: donationAmount}("");
        assertTrue(success, "Donation should succeed");
        assertEq(
            address(monstr).balance,
            25 ether,
            "Contract should have 25 MON"
        );

        // Move to day 1
        vm.warp(block.timestamp + 25 hours);

        // Generate fees on day 1
        vm.expectEmit(true, true, true, true);
        emit Transfer(bob, alice, 990 ether);

        vm.prank(bob);
        monstr.transfer(alice, transferAmount);
        assertEq(
            monstr.balanceOf(bob),
            9890 ether,
            "Bob should have 9,890 tokens"
        );
        assertEq(
            monstr.balanceOf(alice),
            9890 ether,
            "Alice should have 9,890 tokens"
        );
        assertEq(
            monstr.balanceOf(monstr.FEES_POOL()),
            220 ether,
            "Fees pool should have 220 tokens"
        );

        // Move to day 2 and execute lottery
        vm.warp(block.timestamp + 25 hours + 61);

        // Lottery should execute without issues
        monstr.executeLottery();

        // Check lottery executed
        assertEq(
            monstr.lastLotteryDay(),
            2,
            "Lottery should be executed for day 2"
        );
    }

    function testMultipleDonations() public {
        // Initial setup
        vm.prank(alice);
        monstr.mint{value: 1 ether}();

        uint256 initialBalance = address(monstr).balance;

        // Multiple donations
        for (uint256 i = 0; i < 5; i++) {
            address currentDonor = address(uint160(0x100 + i));
            vm.deal(currentDonor, 10 ether);
            vm.prank(currentDonor);
            (bool success, ) = address(monstr).call{value: 1 ether}("");
            assertTrue(success, "Each donation should succeed");
        }

        // Contract should have received all donations
        assertEq(address(monstr).balance, initialBalance + 5 ether);

        // Total supply should be unchanged
        assertEq(monstr.totalSupply(), 1000 ether); // Only from Alice's mint
    }

    function testDonationAfterMintingPeriod() public {
        // Mint during minting period
        vm.prank(alice);
        monstr.mint{value: 10 ether}();

        // Move past minting period
        vm.warp(block.timestamp + 8 days);

        // Alice redeems to trigger max supply setting
        vm.prank(alice);
        monstr.redeem(100 ether);

        uint256 maxSupply = monstr.maxSupplyEver();
        assertTrue(maxSupply > 0, "Max supply should be set");

        // Donate MON after minting period
        vm.prank(donor);
        (bool success, ) = address(monstr).call{value: 5 ether}("");
        assertTrue(success, "Donation should work after minting period");

        // Max supply should remain unchanged
        assertEq(monstr.maxSupplyEver(), maxSupply);

        // Bob can still mint (within capacity)
        vm.prank(bob);
        monstr.mint{value: 0.09 ether}();
    }

    function testRedemptionWithDonation() public {
        // Alice mints
        uint256 mintAmount = 10 ether;
        vm.expectEmit(true, true, true, true);
        emit Minted(alice, mintAmount, 9900 ether, 100 ether);

        vm.prank(alice);
        monstr.mint{value: mintAmount}();

        uint256 aliceTokens = monstr.balanceOf(alice);
        assertEq(aliceTokens, 9900 ether, "Alice should have 9,900 tokens");

        // Donate 5 MON
        uint256 donationAmount = 5 ether;
        vm.prank(donor);
        (bool success, ) = address(monstr).call{value: donationAmount}("");
        assertTrue(success, "Donation should succeed");
        assertEq(
            address(monstr).balance,
            15 ether,
            "Contract should have 15 MON"
        );

        // Alice redeems half her tokens
        uint256 redeemAmount = aliceTokens / 2; // 4,950 tokens
        uint256 redeemFee = redeemAmount / 100; // 49.5 tokens fee
        uint256 netRedeemed = redeemAmount - redeemFee; // 4,900.5 tokens
        uint256 expectedEth = (netRedeemed * 15 ether) / monstr.totalSupply(); // (4900.5 * 15) / 10000 = 7.35075 MON

        uint256 aliceEthBefore = alice.balance;

        vm.expectEmit(true, true, true, true);
        emit Redeemed(alice, redeemAmount, expectedEth, redeemFee);

        vm.prank(alice);
        monstr.redeem(redeemAmount);

        uint256 aliceEthAfter = alice.balance;
        uint256 ethReceived = aliceEthAfter - aliceEthBefore;

        // Alice should have received more MON due to donation
        assertEq(
            ethReceived,
            expectedEth,
            "Alice should receive exact MON amount"
        );
        assertTrue(
            ethReceived > 7.35 ether,
            "Should receive over 7.35 MON due to donation"
        );
        assertEq(
            monstr.balanceOf(alice),
            4950 ether,
            "Alice should have 4,950 tokens left"
        );
    }

    function testFuzzDonations(uint256 donationAmount, uint8 numDonors) public {
        // Bound inputs
        donationAmount = bound(donationAmount, 0.001 ether, 10 ether);
        numDonors = uint8(bound(numDonors, 1, 10));

        // Initial mint
        vm.prank(alice);
        monstr.mint{value: 1 ether}();

        uint256 totalDonated = 0;
        uint256 initialBalance = address(monstr).balance;

        // Make donations
        for (uint256 i = 0; i < numDonors; i++) {
            address currentDonor = address(uint160(0x1000 + i));
            vm.deal(currentDonor, donationAmount + 1 ether);
            vm.prank(currentDonor);
            (bool success, ) = address(monstr).call{value: donationAmount}("");
            assertTrue(success, "Donation should succeed");
            totalDonated += donationAmount;
        }

        // Verify accounting
        assertEq(address(monstr).balance, initialBalance + totalDonated);
        assertEq(monstr.totalSupply(), 1000 ether); // Unchanged
    }
}
