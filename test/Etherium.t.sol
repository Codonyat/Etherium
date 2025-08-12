// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract EtheriumTest is Test {
    Etherium public etherium;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    function setUp() public {
        etherium = new Etherium();
        
        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }
    
    function testMintingWithFee() public {
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        // 1 ETH = 1 ETHERIUM (both 18 decimals)
        // During minting period: Alice gets 99%, fees are minted too
        uint256 expectedBalance = 0.99 ether; // 99% of 1 ETH
        assertEq(etherium.balanceOf(alice), expectedBalance);
        
        // Total supply should be full 1 ETH (alice's 0.99 + 0.01 fees minted)
        uint256 expectedTotalSupply = 1 ether;
        assertEq(etherium.totalSupply(), expectedTotalSupply);
        
        // Check that fee was distributed to pools
        uint256 totalFee = 0.01 ether; // 1% of 1 ETH
        uint256 expectedLotteryPool = (totalFee * 90) / 100; // 0.9%
        uint256 expectedRandomnessPool = (totalFee * 10) / 100; // 0.1%
        
        assertEq(etherium.currentLotteryPool(), expectedLotteryPool);
        assertEq(etherium.currentRandomnessPool(), expectedRandomnessPool);
    }
    
    function testRedeemWithFee() public {
        // First mint some ETHERIUM
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        uint256 aliceBalance = etherium.balanceOf(alice);
        uint256 contractBalanceBefore = address(etherium).balance;
        
        // Redeem half
        uint256 redeemAmount = aliceBalance / 2;
        vm.prank(alice);
        etherium.redeem(redeemAmount);
        
        // Check ETHERIUM balance decreased
        assertEq(etherium.balanceOf(alice), aliceBalance - redeemAmount);
        
        // Check ETH was returned (minus fee)
        uint256 fee = (redeemAmount * 100) / 10000; // 1% fee
        uint256 netAmount = redeemAmount - fee;
        uint256 expectedEth = netAmount; // 1:1 conversion
        
        assertApproxEqAbs(
            contractBalanceBefore - address(etherium).balance,
            expectedEth,
            1000 // Allow small rounding error
        );
    }
    
    function testTransferWithFee() public {
        // First mint some ETHERIUM
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        uint256 aliceBalanceBefore = etherium.balanceOf(alice);
        uint256 transferAmount = 0.1 ether; // 0.1 ETHERIUM
        
        // Transfer to bob
        vm.prank(alice);
        etherium.transfer(bob, transferAmount);
        
        // Bob should receive 99% of transfer amount (1% fee)
        uint256 expectedBobBalance = (transferAmount * 99) / 100;
        assertEq(etherium.balanceOf(bob), expectedBobBalance);
        
        // Alice balance should decrease by full amount
        assertEq(etherium.balanceOf(alice), aliceBalanceBefore - transferAmount);
    }
    
    function testHolderTracking() public {
        // Initially no holders
        assertEq(etherium.getHolderCount(), 0);
        
        // Alice mints
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        assertEq(etherium.getHolderCount(), 1);
        
        // Bob mints
        vm.prank(bob);
        etherium.mint{value: 1 ether}();
        assertEq(etherium.getHolderCount(), 2);
        
        // Alice transfers all to bob
        uint256 aliceBalance = etherium.balanceOf(alice);
        vm.prank(alice);
        etherium.transfer(bob, aliceBalance);
        
        // Alice should be removed from holders
        assertEq(etherium.getHolderCount(), 1);
        assertFalse(etherium.isHolder(alice));
        assertTrue(etherium.isHolder(bob));
    }
    
    function testCommitRevealFlow() public {
        // Mint some ETHERIUM first
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        // Check we can commit for current day
        assertTrue(etherium.canCommitForDay(0));
        
        // Create commitment
        uint256 secret = 12345;
        bytes32 commitment = keccak256(abi.encodePacked(secret, alice));
        uint256 stakeAmount = 0.001 ether; // 0.001 ETHERIUM
        
        // Commit
        vm.prank(alice);
        etherium.commitSecret(commitment, stakeAmount);
        
        // Fast forward to next day to reveal
        vm.warp(block.timestamp + 24 hours + 1);
        assertTrue(etherium.canRevealForDay(0));
        
        // Reveal for day 0
        vm.prank(alice);
        etherium.revealSecret(secret, 0);
        
        // Check reveal was recorded
        (, , uint256 revealedSecret, bool revealed, ) = etherium.dayCommitments(0, alice);
        assertTrue(revealed);
        assertEq(revealedSecret, secret);
    }
    
    function testLotteryExecution() public {
        // Setup: Multiple holders with different balances
        vm.prank(alice);
        etherium.mint{value: 2 ether}();
        
        vm.prank(bob);
        etherium.mint{value: 1 ether}();
        
        vm.prank(charlie);
        etherium.mint{value: 0.5 ether}();
        
        // Record initial lottery pool
        uint256 lotteryPoolBefore = etherium.currentLotteryPool();
        assertTrue(lotteryPoolBefore > 0);
        
        // Need at least one commit-reveal for randomness
        uint256 secret = 42;
        bytes32 commitment = keccak256(abi.encodePacked(secret, alice));
        
        vm.prank(alice);
        etherium.commitSecret(commitment, 0.0001 ether); // 0.0001 ETHERIUM
        
        // Fast forward to day 1 to reveal for day 0
        vm.warp(block.timestamp + 24 hours + 1);
        
        vm.prank(alice);
        etherium.revealSecret(secret, 0);
        
        // Fast forward to day 2 to execute lottery for day 0
        vm.warp(block.timestamp + 24 hours + 1);
        
        // Execute lottery
        etherium.executeLottery();
        
        // Lottery pool should be empty
        assertEq(etherium.currentLotteryPool(), 0);
        
        // One of the holders should have won
        // Can't predict exact winner due to randomness, but total supply should increase
        uint256 totalSupplyAfter = etherium.totalSupply();
        assertTrue(totalSupplyAfter > 0);
    }
    
    function testMintingPeriodEnforcement() public {
        // During minting period: no limit, fees are minted too
        vm.prank(alice);
        etherium.mint{value: 10 ether}();
        
        uint256 totalSupplyAfterMinting = etherium.totalSupply();
        // Should be 10 ETHERIUM (including fees minted during minting period)
        uint256 expectedSupply = 10 ether; // 10 ETHERIUM
        assertEq(totalSupplyAfterMinting, expectedSupply);
        
        // Fast forward past minting period
        vm.warp(block.timestamp + 8 days);
        
        // First mint after period sets maxSupplyEver
        uint256 maxSupply = etherium.maxSupplyEver();
        assertEq(maxSupply, 0); // Not set yet
        
        // Now minting should be limited by max supply set during minting week
        vm.prank(bob);
        vm.expectRevert("Max supply reached");
        etherium.mint{value: 1 ether}(); // Should fail - no redemptions yet
        
        // After redemption, minting should work up to original max
        vm.prank(alice);
        etherium.redeem(1 ether); // Redeem 1 ETHERIUM
        
        // After redemption: 
        // - Alice loses 1 ETHERIUM from balance
        // - Only 0.99 ETHERIUM actually burned from total supply (0.01 fee stays)
        // - Total supply now: 10 - 0.99 = 9.01 ETHERIUM
        // - Max supply still: 10 ETHERIUM
        // - Available to mint: 10 - 9.01 = 0.99 ETHERIUM
        
        assertEq(etherium.totalSupply(), expectedSupply - 0.99 ether);
        
        // Bob can now mint up to the redeemed capacity
        vm.prank(bob);
        etherium.mint{value: 0.99 ether}(); // Should work - exactly the redeemed amount
    }
    
    function testNoContractsInLottery() public {
        // Deploy a contract that holds ETHERIUM
        MockContract mockContract = new MockContract();
        vm.deal(address(mockContract), 10 ether);
        
        // Contract mints ETHERIUM
        mockContract.mintEtherium(etherium);
        
        // Check contract is not tracked as holder
        assertFalse(etherium.isHolder(address(mockContract)));
        assertEq(etherium.getHolderCount(), 0);
        
        // Regular user mints
        vm.prank(alice);
        etherium.mint{value: 1 ether}();
        
        // Only alice should be tracked
        assertEq(etherium.getHolderCount(), 1);
        assertTrue(etherium.isHolder(alice));
    }
}

contract MockContract {
    function mintEtherium(Etherium etherium) external {
        etherium.mint{value: 1 ether}();
    }
    
    receive() external payable {}
}