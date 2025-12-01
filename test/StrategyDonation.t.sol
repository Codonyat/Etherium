// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy} from "../src/Strategy.sol";

// Mock ERC20 MEGA for testing
contract MockMEGA {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
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
}

contract StrategyDonationTest is Test {
    Strategy public giga;
    MockMEGA public mega;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public donor = address(0x3);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Minted(
        address indexed to,
        uint256 megaAmount,
        uint256 gigaAmount,
        uint256 fee
    );
    event Redeemed(
        address indexed from,
        uint256 gigaAmount,
        uint256 megaAmount,
        uint256 fee
    );

    function setUp() public {
        mega = new MockMEGA();
        giga = new Strategy(address(mega));

        mega.mint(alice, 100 ether);
        mega.mint(bob, 100 ether);
        mega.mint(donor, 100 ether);
    }

    // Helper to mint GIGA tokens
    function mintGiga(address user, uint256 megaAmount) internal {
        vm.startPrank(user);
        mega.approve(address(giga), megaAmount);
        giga.mint(megaAmount);
        vm.stopPrank();
    }

    // Helper to donate MEGA to the contract
    function donateMega(address from, uint256 amount) internal {
        vm.prank(from);
        mega.transfer(address(giga), amount);
    }

    function testDonationIncreasesRedemptionValue() public {
        // Alice mints first
        uint256 mintAmount = 10 ether;
        uint256 expectedTokens = mintAmount * 99 / 100; // 9.9 tokens after 1% fee
        uint256 expectedFee = mintAmount / 100; // 0.1 tokens fee

        mintGiga(alice, mintAmount);

        assertEq(
            giga.balanceOf(alice),
            expectedTokens,
            "Alice should receive 9.9 tokens"
        );
        assertEq(
            giga.balanceOf(giga.FEES_POOL()),
            expectedFee,
            "Fees pool should have 0.1 tokens"
        );

        uint256 totalSupplyBefore = giga.totalSupply();
        uint256 contractBalanceBefore = giga.getMegaReserve();
        assertEq(
            totalSupplyBefore,
            10 ether,
            "Total supply should be 10 tokens"
        );
        assertEq(
            contractBalanceBefore,
            mintAmount,
            "Contract should hold 10 MEGA"
        );

        // Calculate redemption value before donation
        uint256 redeemAmount = 1 ether; // 1 GIGA
        uint256 fee = redeemAmount / 100; // 0.01 GIGA fee
        uint256 netAmount = redeemAmount - fee; // 0.99 GIGA
        uint256 redemptionValueBefore = (netAmount * contractBalanceBefore) /
            totalSupplyBefore;
        assertEq(
            redemptionValueBefore,
            0.99 ether,
            "Redemption value before should be 0.99 MEGA"
        );

        // Donor sends 5 MEGA to the contract (donation)
        uint256 donationAmount = 5 ether;
        donateMega(donor, donationAmount);

        // Check contract balance increased
        assertEq(
            giga.getMegaReserve(),
            contractBalanceBefore + donationAmount,
            "Contract balance should increase by 5 MEGA"
        );

        // Check total supply unchanged
        assertEq(
            giga.totalSupply(),
            totalSupplyBefore,
            "Total supply should remain 10 tokens"
        );

        // Calculate redemption value after donation
        uint256 redemptionValueAfter = (netAmount * giga.getMegaReserve()) /
            giga.totalSupply();
        assertEq(
            redemptionValueAfter,
            1.485 ether,
            "Redemption value after should be 1.485 MEGA"
        );

        // Redemption value should increase by 50%
        assertEq(
            redemptionValueAfter - redemptionValueBefore,
            0.495 ether,
            "Redemption value should increase by 0.495 MEGA"
        );
    }

    function testDonationDoesntAffectMinting() public {
        // Initial mint
        mintGiga(alice, 1 ether);
        assertEq(
            giga.balanceOf(alice),
            0.99 ether,
            "Alice should get 0.99 tokens"
        );

        // Donate MEGA
        uint256 donationAmount = 10 ether;
        donateMega(donor, donationAmount);
        assertEq(
            giga.getMegaReserve(),
            11 ether,
            "Contract should have 11 MEGA"
        );

        // Bob mints after donation
        mintGiga(bob, 1 ether);

        // Bob should still get the standard amount (0.99 GIGA after 1% fee)
        assertEq(
            giga.balanceOf(bob),
            0.99 ether,
            "Bob should get 0.99 tokens despite donation"
        );
        assertEq(
            giga.getMegaReserve(),
            12 ether,
            "Contract should have 12 MEGA"
        );
    }

    function testDonationDoesntBreakLottery() public {
        // Setup holders
        mintGiga(alice, 10 ether);
        assertEq(
            giga.balanceOf(alice),
            9.9 ether,
            "Alice should have 9.9 tokens"
        );

        mintGiga(bob, 10 ether);
        assertEq(
            giga.balanceOf(bob),
            9.9 ether,
            "Bob should have 9.9 tokens"
        );

        // Generate fees on day 0
        uint256 transferAmount = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 0.99 ether); // Bob receives 0.99 after fee

        vm.prank(alice);
        giga.transfer(bob, transferAmount);
        assertEq(
            giga.balanceOf(alice),
            8.9 ether,
            "Alice should have 8.9 tokens"
        );
        assertEq(
            giga.balanceOf(bob),
            10.89 ether,
            "Bob should have 10.89 tokens"
        );
        assertEq(
            giga.balanceOf(giga.FEES_POOL()),
            0.21 ether,
            "Fees pool should have 0.21 tokens"
        );

        // Donate MEGA
        uint256 donationAmount = 5 ether;
        donateMega(donor, donationAmount);
        assertEq(
            giga.getMegaReserve(),
            25 ether,
            "Contract should have 25 MEGA"
        );

        // Move to day 1
        vm.warp(block.timestamp + 25 hours);

        // Generate fees on day 1
        vm.expectEmit(true, true, true, true);
        emit Transfer(bob, alice, 0.99 ether);

        vm.prank(bob);
        giga.transfer(alice, transferAmount);
        assertEq(
            giga.balanceOf(bob),
            9.89 ether,
            "Bob should have 9.89 tokens"
        );
        assertEq(
            giga.balanceOf(alice),
            9.89 ether,
            "Alice should have 9.89 tokens"
        );
        assertEq(
            giga.balanceOf(giga.FEES_POOL()),
            0.22 ether,
            "Fees pool should have 0.22 tokens"
        );

        // Move to day 2 and execute lottery
        vm.warp(block.timestamp + 25 hours + 61);

        // Lottery should execute without issues
        giga.executeLottery();

        // Check lottery executed
        assertEq(
            giga.lastLotteryDay(),
            2,
            "Lottery should be executed for day 2"
        );
    }

    function testMultipleDonations() public {
        // Initial setup
        mintGiga(alice, 1 ether);

        uint256 initialBalance = giga.getMegaReserve();

        // Multiple donations
        for (uint256 i = 0; i < 5; i++) {
            address currentDonor = address(uint160(0x100 + i));
            mega.mint(currentDonor, 10 ether);
            donateMega(currentDonor, 1 ether);
        }

        // Contract should have received all donations
        assertEq(giga.getMegaReserve(), initialBalance + 5 ether);

        // Total supply should be unchanged
        assertEq(giga.totalSupply(), 1 ether); // Only from Alice's mint (1:1 ratio)
    }

    function testDonationAfterMintingPeriod() public {
        // Mint during minting period
        mintGiga(alice, 10 ether);

        // Move past minting period
        vm.warp(block.timestamp + giga.MINTING_PERIOD() + 1 days);

        // Alice redeems to trigger max supply setting
        vm.prank(alice);
        giga.redeem(0.1 ether);

        uint256 maxSupply = giga.maxSupplyEver();
        assertTrue(maxSupply > 0, "Max supply should be set");

        // Donate MEGA after minting period
        donateMega(donor, 5 ether);

        // Max supply should remain unchanged
        assertEq(giga.maxSupplyEver(), maxSupply);

        // Bob can still mint (within capacity)
        mega.mint(bob, 10 ether);
        mintGiga(bob, 0.09 ether);
    }

    function testRedemptionWithDonation() public {
        // Alice mints
        uint256 mintAmount = 10 ether;
        mintGiga(alice, mintAmount);

        uint256 aliceTokens = giga.balanceOf(alice);
        assertEq(aliceTokens, 9.9 ether, "Alice should have 9.9 tokens");

        // Donate 5 MEGA
        uint256 donationAmount = 5 ether;
        donateMega(donor, donationAmount);
        assertEq(
            giga.getMegaReserve(),
            15 ether,
            "Contract should have 15 MEGA"
        );

        // Alice redeems half her tokens
        uint256 redeemAmount = aliceTokens / 2; // 4,950 tokens
        uint256 redeemFee = redeemAmount / 100; // 49.5 tokens fee
        uint256 netRedeemed = redeemAmount - redeemFee; // 4,900.5 tokens
        uint256 expectedNative = (netRedeemed * 15 ether) / giga.totalSupply(); // (4900.5 * 15) / 10000 = 7.35075 MEGA

        uint256 aliceMegaBefore = mega.balanceOf(alice);

        vm.expectEmit(true, true, true, true);
        emit Redeemed(alice, redeemAmount, expectedNative, redeemFee);

        vm.prank(alice);
        giga.redeem(redeemAmount);

        uint256 aliceMegaAfter = mega.balanceOf(alice);
        uint256 megaReceived = aliceMegaAfter - aliceMegaBefore;

        // Alice should have received more MEGA due to donation
        assertEq(
            megaReceived,
            expectedNative,
            "Alice should receive exact MEGA amount"
        );
        assertTrue(
            megaReceived > 7.35 ether,
            "Should receive over 7.35 MEGA due to donation"
        );
        assertEq(
            giga.balanceOf(alice),
            4.95 ether,
            "Alice should have 4,950 tokens left"
        );
    }

    function testFuzzDonations(uint256 donationAmount, uint8 numDonors) public {
        // Bound inputs
        donationAmount = bound(donationAmount, 0.001 ether, 10 ether);
        numDonors = uint8(bound(numDonors, 1, 10));

        // Initial mint
        mintGiga(alice, 1 ether);

        uint256 totalDonated = 0;
        uint256 initialBalance = giga.getMegaReserve();

        // Make donations
        for (uint256 i = 0; i < numDonors; i++) {
            address currentDonor = address(uint160(0x1000 + i));
            mega.mint(currentDonor, donationAmount + 1 ether);
            donateMega(currentDonor, donationAmount);
            totalDonated += donationAmount;
        }

        // Verify accounting
        assertEq(giga.getMegaReserve(), initialBalance + totalDonated);
        assertEq(giga.totalSupply(), 1 ether); // Unchanged
    }
}
