// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract EtheriumDonationTest is Test {
    Etherium public etherium;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public donor = address(0x3);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Minted(address indexed to, uint256 ethAmount, uint256 etheriumAmount, uint256 fee);
    event Redeemed(address indexed from, uint256 etheriumAmount, uint256 ethAmount, uint256 fee);

    function setUp() public {
        etherium = new Etherium();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(donor, 100 ether);
    }

    function testDonationIncreasesRedemptionValue() public {
        // Alice mints first
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        uint256 totalSupplyBefore = etherium.totalSupply();
        uint256 contractBalanceBefore = address(etherium).balance;

        // Calculate redemption value before donation
        uint256 redeemAmount = 1000 ether; // 1000 ETHERIUM
        uint256 fee = redeemAmount / 100;
        uint256 netAmount = redeemAmount - fee;
        uint256 redemptionValueBefore = (netAmount * contractBalanceBefore) / totalSupplyBefore;

        // Donor sends 5 ETH to the contract
        vm.prank(donor);
        (bool success,) = address(etherium).call{value: 5 ether}("");
        assertTrue(success, "Donation should succeed");

        // Check contract balance increased
        assertEq(address(etherium).balance, contractBalanceBefore + 5 ether);

        // Check total supply unchanged
        assertEq(etherium.totalSupply(), totalSupplyBefore);

        // Calculate redemption value after donation
        uint256 redemptionValueAfter = (netAmount * address(etherium).balance) / etherium.totalSupply();

        // Redemption value should increase
        assertTrue(redemptionValueAfter > redemptionValueBefore, "Redemption value should increase");
    }

    function testDonationDoesntAffectMinting() public {
        // Initial mint
        vm.prank(alice);
        etherium.mint{value: 1 ether}();

        // Donate ETH
        vm.prank(donor);
        (bool success,) = address(etherium).call{value: 10 ether}("");
        assertTrue(success);

        // Bob mints after donation
        vm.prank(bob);
        etherium.mint{value: 1 ether}();

        // Bob should still get the standard amount (990 ETHERIUM after 1% fee)
        assertEq(etherium.balanceOf(bob), 990 ether);
    }

    function testDonationDoesntBreakLottery() public {
        // Setup holders
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        vm.prank(bob);
        etherium.mint{value: 10 ether}();

        // Generate fees on day 0
        vm.prank(alice);
        etherium.transfer(bob, 1000 ether);

        // Donate ETH
        vm.prank(donor);
        (bool success,) = address(etherium).call{value: 5 ether}("");
        assertTrue(success);

        // Move to day 1
        vm.warp(block.timestamp + 25 hours);

        // Generate fees on day 1
        vm.prank(bob);
        etherium.transfer(alice, 1000 ether);

        // Move to day 2 and execute lottery
        vm.warp(block.timestamp + 25 hours + 61);

        // Lottery should execute without issues
        etherium.executeLottery();

        // Check lottery executed
        assertEq(etherium.lastLotteryDay(), 2);
    }

    function testMultipleDonations() public {
        // Initial setup
        vm.prank(alice);
        etherium.mint{value: 1 ether}();

        uint256 initialBalance = address(etherium).balance;

        // Multiple donations
        for (uint256 i = 0; i < 5; i++) {
            address currentDonor = address(uint160(0x100 + i));
            vm.deal(currentDonor, 10 ether);
            vm.prank(currentDonor);
            (bool success,) = address(etherium).call{value: 1 ether}("");
            assertTrue(success, "Each donation should succeed");
        }

        // Contract should have received all donations
        assertEq(address(etherium).balance, initialBalance + 5 ether);

        // Total supply should be unchanged
        assertEq(etherium.totalSupply(), 1000 ether); // Only from Alice's mint
    }

    function testDonationAfterMintingPeriod() public {
        // Mint during minting period
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        // Move past minting period
        vm.warp(block.timestamp + 8 days);

        // Alice redeems to trigger max supply setting
        vm.prank(alice);
        etherium.redeem(100 ether);

        uint256 maxSupply = etherium.maxSupplyEver();
        assertTrue(maxSupply > 0, "Max supply should be set");

        // Donate ETH after minting period
        vm.prank(donor);
        (bool success,) = address(etherium).call{value: 5 ether}("");
        assertTrue(success, "Donation should work after minting period");

        // Max supply should remain unchanged
        assertEq(etherium.maxSupplyEver(), maxSupply);

        // Bob can still mint (within capacity)
        vm.prank(bob);
        etherium.mint{value: 0.09 ether}();
    }

    function testRedemptionWithDonation() public {
        // Alice mints
        vm.prank(alice);
        etherium.mint{value: 10 ether}();

        uint256 aliceTokens = etherium.balanceOf(alice);

        // Donate 5 ETH
        vm.prank(donor);
        (bool success,) = address(etherium).call{value: 5 ether}("");
        assertTrue(success);

        // Alice redeems half her tokens
        uint256 redeemAmount = aliceTokens / 2;
        uint256 aliceEthBefore = alice.balance;

        vm.prank(alice);
        etherium.redeem(redeemAmount);

        uint256 aliceEthAfter = alice.balance;

        // Alice should have received more ETH due to donation
        // She should get roughly (15 ETH * 0.5) = 7.5 ETH minus fees
        assertTrue(aliceEthAfter - aliceEthBefore > 7 ether, "Should receive bonus from donation");
    }

    function testFuzzDonations(uint256 donationAmount, uint8 numDonors) public {
        // Bound inputs
        donationAmount = bound(donationAmount, 0.001 ether, 10 ether);
        numDonors = uint8(bound(numDonors, 1, 10));

        // Initial mint
        vm.prank(alice);
        etherium.mint{value: 1 ether}();

        uint256 totalDonated = 0;
        uint256 initialBalance = address(etherium).balance;

        // Make donations
        for (uint256 i = 0; i < numDonors; i++) {
            address currentDonor = address(uint160(0x1000 + i));
            vm.deal(currentDonor, donationAmount + 1 ether);
            vm.prank(currentDonor);
            (bool success,) = address(etherium).call{value: donationAmount}("");
            assertTrue(success, "Donation should succeed");
            totalDonated += donationAmount;
        }

        // Verify accounting
        assertEq(address(etherium).balance, initialBalance + totalDonated);
        assertEq(etherium.totalSupply(), 1000 ether); // Unchanged
    }
}
