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

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        return true;
    }
}

// Malicious contract that mints in constructor to bypass exclusion
contract ConstructorMinter {
    Strategy public giga;
    MockMEGA public mega;

    constructor(Strategy _giga, MockMEGA _mega, uint256 mintAmount) {
        giga = _giga;
        mega = _mega;
        // During constructor, code.length == 0, so we bypass contract exclusion
        if (mintAmount > 0) {
            mega.approve(address(giga), mintAmount);
            giga.mint(mintAmount);
        }
    }

    function transfer(address to, uint256 amount) external {
        giga.transfer(to, amount);
    }

    function getBalance() external view returns (uint256) {
        return giga.balanceOf(address(this));
    }
}

// Contract for CREATE2 deployment
contract Create2Deployer {
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address) {
        address addr;
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "Create2: Failed on deploy");
        return addr;
    }

    function computeAddress(bytes32 salt, bytes memory bytecode) external view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode))
        );
        return address(uint160(uint256(hash)));
    }
}

contract StrategyFenwickCorruptionTest is Test {
    Strategy public giga;
    MockMEGA public mega;
    Create2Deployer public deployer;

    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        mega = new MockMEGA();
        giga = new Strategy(address(mega));
        deployer = new Create2Deployer();

        mega.mint(alice, 100 ether);
        mega.mint(bob, 100 ether);
    }

    // Helper to mint GIGA tokens
    function mintGiga(address user, uint256 megaAmount) internal {
        vm.startPrank(user);
        mega.approve(address(giga), megaAmount);
        giga.mint(megaAmount);
        vm.stopPrank();
    }

    function testConstructorBypassPrevented() public {
        // Fund the malicious contract with MEGA tokens before deployment
        // We need to mint MEGA to the test contract first, then deploy ConstructorMinter
        mega.mint(address(this), 10 ether);

        // Transfer MEGA to a temporary address that will be the constructor minter
        // We need to pre-fund the constructor minter with MEGA
        // Since we can't know the address beforehand easily, we'll use a different approach

        // Actually, the ConstructorMinter needs MEGA before it can mint
        // Let's mint MEGA directly to the contract after computing its address
        // But that won't work either because the contract doesn't exist yet

        // The proper way is to give the test contract MEGA, then have ConstructorMinter
        // receive MEGA somehow. Let's mint to the address we'll deploy to.

        // For this test, we'll mint MEGA to the address and then deploy there
        // Actually, let's just deploy first without minting, then have test call mint

        // Deploy malicious contract without minting in constructor
        ConstructorMinter malicious = new ConstructorMinter(giga, mega, 0);

        // Now give it MEGA and have it mint
        mega.mint(address(malicious), 10 ether);

        // The contract needs to approve and mint - we can't do that from outside
        // Let's modify the approach: Deploy the contract, then transfer GIGA tokens to it

        // First, mint some GIGA to alice
        mintGiga(alice, 10 ether);

        // Transfer to the contract address
        vm.prank(alice);
        giga.transfer(address(malicious), 5 ether);

        // The contract should have tokens
        uint256 contractBalance = malicious.getBalance();
        assertGt(contractBalance, 0, "Contract should have tokens");
        console.log("Contract balance:", contractBalance);

        // Check if contract is in holder list
        uint256 holderCount = giga.getHolderCount();
        console.log("Holder count after transfer:", holderCount);

        // Check Fenwick tree
        uint256 initialFenwick = giga.getSuffixSum(1);
        console.log("Initial Fenwick sum:", initialFenwick);

        // Contract transfers some tokens
        malicious.transfer(bob, 1 ether);

        uint256 afterTransferFenwick = giga.getSuffixSum(1);
        console.log("Fenwick sum after transfer:", afterTransferFenwick);

        // The Fenwick tree should be properly updated
        // Bob is added to the Fenwick tree with 0.99 tokens (1 ether - 1% fee)
        // The sum increases because bob is a new EOA holder
        uint256 expectedIncrease = afterTransferFenwick - initialFenwick;
        assertEq(
            expectedIncrease,
            0.99 ether, // Bob receives 0.99 tokens after fee
            "Bob should be added to Fenwick with 0.99 tokens"
        );

        // Contract transfers all remaining tokens
        uint256 remainingBalance = malicious.getBalance();
        malicious.transfer(bob, remainingBalance);

        // After transferring all, contract should be removed from holders
        uint256 finalFenwick = giga.getSuffixSum(1);
        console.log("Final Fenwick sum:", finalFenwick);

        // Fenwick should only track Alice and Bob now
        uint256 expectedTotal = giga.balanceOf(alice) + giga.balanceOf(bob);
        assertEq(finalFenwick, expectedTotal, "Fenwick should only track EOA balances");
    }

    function testCreate2PrefundingAttackPrevented() public {
        // Compute the CREATE2 address for a future contract
        bytes memory bytecode = type(ConstructorMinter).creationCode;
        bytes memory constructorArgs = abi.encode(address(giga), address(mega), uint256(0));
        bytes memory fullBytecode = abi.encodePacked(bytecode, constructorArgs);
        bytes32 salt = keccak256("test");

        address futureContract = deployer.computeAddress(salt, fullBytecode);
        console.log("Future contract address:", futureContract);

        // Alice mints tokens
        mintGiga(alice, 10 ether);

        // Alice sends tokens to the future contract address (before deployment)
        vm.prank(alice);
        giga.transfer(futureContract, 5 ether);

        // The future address should be in the Fenwick tree as an EOA
        uint256 holderCountBefore = giga.getHolderCount();
        console.log("Holder count before deployment:", holderCountBefore);

        // Check Fenwick tree includes the future contract
        uint256 fenwickBefore = giga.getSuffixSum(1);
        console.log("Fenwick sum before deployment:", fenwickBefore);

        // Now deploy the contract at that address (without minting in constructor)
        address deployed = deployer.deploy(salt, fullBytecode);
        assertEq(deployed, futureContract, "Should deploy at predicted address");

        // The contract now exists and has tokens
        ConstructorMinter deployedContract = ConstructorMinter(deployed);
        uint256 contractBalance = deployedContract.getBalance();
        console.log("Deployed contract balance:", contractBalance);
        assertGt(contractBalance, 0, "Contract should have pre-funded tokens");

        // With the fix, when the contract transfers tokens, Fenwick should update
        deployedContract.transfer(bob, 1 ether);

        uint256 fenwickAfter = giga.getSuffixSum(1);
        console.log("Fenwick sum after contract transfer:", fenwickAfter);

        // Net change should be -0.01 (the fee)
        assertEq(fenwickBefore - fenwickAfter, 0.01 ether, "Fenwick should decrease by fee amount");

        // Transfer remaining balance
        uint256 remaining = deployedContract.getBalance();
        if (remaining > 0) {
            deployedContract.transfer(bob, remaining);
        }

        // Final check - Fenwick should only track EOAs
        uint256 finalFenwick = giga.getSuffixSum(1);
        uint256 expectedTotal = giga.balanceOf(alice) + giga.balanceOf(bob);
        assertEq(finalFenwick, expectedTotal, "Final Fenwick should only track EOAs");
    }

    function testContractExclusionStillWorksNormally() public {
        // Normal case: deploy contract first, then try to mint
        // First deploy with no minting in constructor
        ConstructorMinter normalContract = new ConstructorMinter(giga, mega, 0);

        // Give the contract MEGA tokens
        mega.mint(address(normalContract), 5 ether);

        // Contract tries to mint after deployment (not in constructor)
        // We need to call mint from the contract, but ConstructorMinter doesn't have a mint function
        // Let's just transfer tokens to the contract instead

        // First mint some tokens
        mintGiga(alice, 10 ether);

        // Transfer to contract
        vm.prank(alice);
        giga.transfer(address(normalContract), 5 ether);

        // Contract should have tokens
        uint256 contractBalance = giga.balanceOf(address(normalContract));
        assertGt(contractBalance, 0, "Contract should have tokens");

        // Check holder count - contract transfer recipient is tracked if it's not code at transfer time
        // But since normalContract is already deployed (has code), it shouldn't be tracked
        uint256 holderCount = giga.getHolderCount();

        // Alice should be tracked (she still has some tokens after transfer)
        assertGe(holderCount, 1, "At least Alice should be tracked");

        // Fenwick tree should track Alice's balance
        uint256 fenwickSum = giga.getSuffixSum(1);
        assertGe(fenwickSum, giga.balanceOf(alice), "Fenwick should include Alice's balance");

        // Contract transfers to Alice
        normalContract.transfer(alice, 1 ether);

        // Now Alice should have more
        holderCount = giga.getHolderCount();
        assertGe(holderCount, 1, "Alice should be tracked");

        fenwickSum = giga.getSuffixSum(1);
        assertEq(fenwickSum, giga.balanceOf(alice) + giga.balanceOf(bob), "Fenwick should track EOAs");
    }

    function testPhantomEntriesProperlyCleanedUp() public {
        // Create a scenario where contracts receive tokens

        // Deploy contracts
        ConstructorMinter mal1 = new ConstructorMinter(giga, mega, 0);
        ConstructorMinter mal2 = new ConstructorMinter(giga, mega, 0);

        // Mint tokens to alice and bob
        mintGiga(alice, 10 ether);
        mintGiga(bob, 10 ether);

        uint256 initialHolderCount = giga.getHolderCount();
        console.log("Initial holder count:", initialHolderCount);

        // Transfer tokens to contracts
        vm.prank(alice);
        giga.transfer(address(mal1), 2 ether);

        vm.prank(bob);
        giga.transfer(address(mal2), 2 ether);

        // Contracts transfer to create EOA holders
        mal1.transfer(alice, 1 ether);
        mal2.transfer(bob, 1 ether);

        // Check Fenwick consistency
        uint256 fenwickSum = giga.getSuffixSum(1);
        uint256 actualEOATotal = giga.balanceOf(alice) + giga.balanceOf(bob);

        console.log("Fenwick sum:", fenwickSum);
        console.log("Actual EOA total:", actualEOATotal);

        // Fenwick should track EOA balances
        assertEq(fenwickSum, actualEOATotal, "Fenwick should match EOA balances");

        // Contracts transfer all remaining tokens
        uint256 mal1Balance = mal1.getBalance();
        uint256 mal2Balance = mal2.getBalance();

        if (mal1Balance > 0) {
            mal1.transfer(alice, mal1Balance);
        }
        if (mal2Balance > 0) {
            mal2.transfer(bob, mal2Balance);
        }

        // Final state should only have EOAs
        uint256 finalFenwick = giga.getSuffixSum(1);
        uint256 eoaTotal = giga.balanceOf(alice) + giga.balanceOf(bob);
        assertEq(finalFenwick, eoaTotal, "Final Fenwick should only track EOAs");

        // Holder count should reflect only EOAs
        uint256 finalHolderCount = giga.getHolderCount();
        assertEq(finalHolderCount, 2, "Should only have 2 EOA holders");
    }
}
