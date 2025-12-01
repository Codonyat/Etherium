// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy} from "../src/Strategy.sol";

// Mock MEGA ERC20 for this standalone test
contract MockMEGALocal {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
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

contract StrategyAtomicityTest is Test {
    Strategy public giga;
    MockMEGALocal public mega;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

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
        mega = new MockMEGALocal();
        giga = new Strategy(address(mega));

        // Fund accounts with MEGA tokens
        mega.mint(alice, 100 ether);
        mega.mint(bob, 100 ether);
        mega.mint(charlie, 100 ether);
    }

    // Helper to approve and mint
    function mintGiga(address user, uint256 amount) internal {
        vm.startPrank(user);
        mega.approve(address(giga), amount);
        giga.mint(amount);
        vm.stopPrank();
    }

    function testFenwickTreeAtomicityDuringTransfers() public {
        // Setup: Create holders with exact amounts
        mintGiga(alice, 10 ether);
        assertEq(
            giga.balanceOf(alice),
            9.9 ether,
            "Alice should have 9,900 tokens"
        );

        mintGiga(bob, 5 ether);
        assertEq(
            giga.balanceOf(bob),
            4.95 ether,
            "Bob should have 4,950 tokens"
        );

        mintGiga(charlie, 3 ether);
        assertEq(
            giga.balanceOf(charlie),
            2.97 ether,
            "Charlie should have 2,970 tokens"
        );

        // Verify initial Fenwick tree state
        uint256 initialSuffix1 = giga.getSuffixSum(1);
        uint256 expectedInitialTotal = 9.9 ether + 4.95 ether + 2.97 ether; // 17.82 tokens
        assertEq(
            initialSuffix1,
            expectedInitialTotal,
            "Initial Fenwick sum should be 17,820 tokens"
        );

        // Perform multiple transfers in same transaction
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 0.099 ether); // 0.1 - 1% fee = 0.099
        giga.transfer(bob, 0.1 ether);
        assertEq(
            giga.balanceOf(alice),
            9.8 ether,
            "Alice should have 9.8 tokens after first transfer"
        );
        assertEq(
            giga.balanceOf(bob),
            5.049 ether,
            "Bob should have 5.049 tokens"
        );

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, charlie, 0.198 ether); // 0.2 - 1% fee = 0.198
        giga.transfer(charlie, 0.2 ether);
        assertEq(
            giga.balanceOf(alice),
            9.6 ether,
            "Alice should have 9.6 tokens after second transfer"
        );
        assertEq(
            giga.balanceOf(charlie),
            3.168 ether,
            "Charlie should have 3.168 tokens"
        );
        vm.stopPrank();

        // Verify Fenwick tree is still consistent
        uint256 afterSuffix1 = giga.getSuffixSum(1);
        uint256 expectedAfterTotal = 9.6 ether + 5.049 ether + 3.168 ether; // 17.817 tokens (0.003 tokens to fees)
        assertEq(
            afterSuffix1,
            expectedAfterTotal,
            "Fenwick sum should be 17.817 tokens after transfers"
        );
    }

    function testFenwickTreeAtomicityDuringMintAndBurn() public {
        // Initial mint
        mintGiga(alice, 10 ether);
        assertEq(
            giga.balanceOf(alice),
            9.9 ether,
            "Alice should have 9,900 tokens"
        );

        // Check Fenwick consistency after mint
        uint256 suffix1AfterMint = giga.getSuffixSum(1);
        assertEq(
            suffix1AfterMint,
            9.9 ether,
            "Fenwick should be 9,900 after mint"
        );

        // Move past minting period to enable redemption
        vm.warp(block.timestamp + giga.MINTING_PERIOD() + 1 days);

        // Trigger max supply setting
        uint256 redeemAmount = 0.1 ether;
        uint256 redeemFee = 0.001 ether; // 1% of 0.1
        uint256 netRedeemed = 0.099 ether;
        uint256 megaReturned = netRedeemed; // 0.099 MEGA (1:1 ratio)

        vm.expectEmit(true, true, true, true);
        emit Redeemed(alice, redeemAmount, megaReturned, redeemFee);
        vm.prank(alice);
        giga.redeem(redeemAmount);
        assertEq(
            giga.balanceOf(alice),
            9.8 ether,
            "Alice should have 9.8 tokens after redeem"
        );

        // Check Fenwick consistency after redemption
        uint256 suffix1AfterRedeem = giga.getSuffixSum(1);
        assertEq(
            suffix1AfterRedeem,
            9.8 ether,
            "Fenwick should be 9.8 after redeem"
        );

        // Add another holder - mint slightly more to meet minimum requirement
        uint256 mintAmount = 0.0001 ether;
        uint256 expectedTokens = (mintAmount * giga.totalSupply()) /
            giga.getMegaReserve();
        uint256 expectedFee = expectedTokens / 100;
        uint256 expectedNet = expectedTokens - expectedFee;

        mintGiga(bob, mintAmount);
        assertEq(
            giga.balanceOf(bob),
            expectedNet,
            "Bob should have expected tokens"
        );

        // Verify both holders are tracked correctly
        uint256 finalSuffix1 = giga.getSuffixSum(1);
        uint256 expectedFinal = 9.8 ether + expectedNet;
        assertEq(
            finalSuffix1,
            expectedFinal,
            "Fenwick should be correct with both holders"
        );
    }

    function testFenwickTreeAtomicityDuringComplexOperations() public {
        // Create initial holders
        address[10] memory users;
        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(uint160(0x100 + i));
            mega.mint(users[i], 10 ether);
            vm.startPrank(users[i]);
            mega.approve(address(giga), 1 ether);
            giga.mint(1 ether);
            vm.stopPrank();
        }

        // Verify initial state
        uint256 totalSupply = giga.totalSupply();
        uint256 fenwickTotal = giga.getSuffixSum(1);

        // Fenwick only tracks user holders, not pools
        assertTrue(
            fenwickTotal <= totalSupply,
            "Fenwick should not exceed total supply"
        );

        // Perform random transfers
        for (uint256 round = 0; round < 20; round++) {
            uint256 from = round % 10;
            uint256 to = (round + 3) % 10;
            uint256 amount = 0.05 ether + (round * 0.01 ether);

            if (giga.balanceOf(users[from]) >= amount) {
                vm.prank(users[from]);
                giga.transfer(users[to], amount);
            }
        }

        // Calculate expected total from individual balances
        uint256 expectedTotal = 0;
        for (uint256 i = 0; i < 10; i++) {
            expectedTotal += giga.balanceOf(users[i]);
        }

        // Verify Fenwick tree still consistent
        uint256 finalFenwickTotal = giga.getSuffixSum(1);
        assertEq(
            finalFenwickTotal,
            expectedTotal,
            "Fenwick tree inconsistent after complex operations"
        );
    }

    function testAtomicityWithReentrancy() public {
        // This test ensures that even with potential reentrancy,
        // the Fenwick tree remains consistent due to atomic updates

        // Create a malicious contract that tries to reenter
        MaliciousReentrant malicious = new MaliciousReentrant(giga, mega);
        mega.mint(address(malicious), 10 ether);

        // Initial state
        mintGiga(alice, 10 ether);

        uint256 initialFenwick = giga.getSuffixSum(1);
        assertEq(
            initialFenwick,
            giga.balanceOf(alice),
            "Initial Fenwick incorrect"
        );

        // Try to transfer to malicious contract
        // The reentrancy guard should prevent any issues
        uint256 transferAmount = 0.1 ether;
        uint256 netTransferred = 0.099 ether;

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(malicious), netTransferred);
        vm.prank(alice);
        giga.transfer(address(malicious), transferAmount);

        // Verify Fenwick tree is still consistent
        // Note: Smart contracts are excluded from Fenwick tree (only EOAs are tracked)
        // So the malicious contract balance won't be in the Fenwick sum
        uint256 finalFenwick = giga.getSuffixSum(1);
        uint256 aliceBalance = giga.balanceOf(alice);
        uint256 maliciousBalance = giga.balanceOf(address(malicious));

        // Only Alice's balance should be in the Fenwick tree
        assertEq(
            finalFenwick,
            aliceBalance,
            "Fenwick should only track Alice (EOA)"
        );

        // Verify the transfer happened correctly with exact amounts
        assertEq(
            aliceBalance,
            9.8 ether,
            "Alice should have exactly 9.8 tokens"
        );
        assertEq(
            maliciousBalance,
            netTransferred,
            "Malicious contract should have exactly 0.099 tokens"
        );
        assertEq(
            giga.balanceOf(giga.FEES_POOL()),
            0.101 ether,
            "Fees pool should have 0.101 tokens total"
        );
    }

    function testFenwickTreeWithZeroBalanceTransitions() public {
        // Test that Fenwick tree correctly handles accounts going to/from zero balance

        // Alice mints
        mintGiga(alice, 1 ether);

        uint256 aliceBalance = giga.balanceOf(alice);
        uint256 fenwick1 = giga.getSuffixSum(1);
        assertEq(fenwick1, aliceBalance, "Initial Fenwick incorrect");

        // Alice transfers entire balance to Bob (Alice goes to 0)
        vm.prank(alice);
        giga.transfer(bob, aliceBalance);

        // Alice should be removed from holders
        uint256 fenwick2 = giga.getSuffixSum(1);
        assertEq(
            fenwick2,
            giga.balanceOf(bob),
            "Fenwick should only track Bob"
        );

        // Alice mints again (goes from 0 to positive)
        mintGiga(alice, 2 ether);

        // Both should be tracked now
        uint256 fenwick3 = giga.getSuffixSum(1);
        uint256 expectedTotal = giga.balanceOf(alice) + giga.balanceOf(bob);
        assertEq(fenwick3, expectedTotal, "Fenwick should track both holders");
    }
}

// Helper contract for reentrancy test
contract MaliciousReentrant {
    Strategy public giga;
    MockMEGALocal public mega;
    bool public attacked = false;

    constructor(Strategy _giga, MockMEGALocal _mega) {
        giga = _giga;
        mega = _mega;
    }

    // Try to reenter when receiving tokens
    function onERC20Received(address, uint256) external returns (bytes4) {
        if (!attacked) {
            attacked = true;
            // Try to mint during a transfer (should fail due to reentrancy guard)
            mega.approve(address(giga), 1 ether);
            try giga.mint(1 ether) {
                // Should not reach here
            } catch {
                // Expected to fail
            }
        }
        return this.onERC20Received.selector;
    }

    receive() external payable {}
}
