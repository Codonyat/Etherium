// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Strategy, IWMEGA} from "../src/Strategy.sol";

// Malicious contract that mints in constructor to bypass exclusion
contract ConstructorMinter {
    Strategy public giga;
    
    constructor(Strategy _giga) payable {
        giga = _giga;
        // During constructor, code.length == 0, so we bypass contract exclusion
        if (msg.value > 0) {
            giga.mint{value: msg.value}();
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
    function deploy(bytes32 salt, bytes memory bytecode) external payable returns (address) {
        address addr;
        assembly {
            addr := create2(callvalue(), add(bytecode, 0x20), mload(bytecode), salt)
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

// Mock WMEGA for testing
contract MockWMEGA {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "MEGA transfer failed");
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

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }
}

contract StrategyFenwickCorruptionTest is Test {
    Strategy public giga;
    MockWMEGA public wmega;
    Create2Deployer public deployer;

    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        wmega = new MockWMEGA();
        giga = new Strategy(address(wmega));
        deployer = new Create2Deployer();
        
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }
    
    function testConstructorBypassPrevented() public {
        // Deploy malicious contract that mints in constructor
        vm.deal(address(this), 10 ether);
        ConstructorMinter malicious = new ConstructorMinter{value: 10 ether}(giga);
        
        // The contract should have tokens
        uint256 contractBalance = malicious.getBalance();
        assertGt(contractBalance, 0, "Contract should have minted tokens");
        console.log("Contract balance:", contractBalance);
        
        // Check if contract is in holder list (it might be due to constructor bypass)
        uint256 holderCount = giga.getHolderCount();
        console.log("Holder count after constructor mint:", holderCount);
        
        // Now the contract transfers tokens - this should update Fenwick tree properly
        // With the fix, the tree should be updated even though it's a contract
        uint256 initialFenwick = giga.getSuffixSum(1);
        console.log("Initial Fenwick sum:", initialFenwick);
        
        // Contract transfers some tokens
        malicious.transfer(alice, 1 ether);

        uint256 afterTransferFenwick = giga.getSuffixSum(1);
        console.log("Fenwick sum after transfer:", afterTransferFenwick);

        // The Fenwick tree should be properly updated
        // Alice gained 0.99 tokens, so Fenwick should increase by 0.99
        assertEq(
            afterTransferFenwick,
            initialFenwick - 0.01 ether, // Net decrease of 0.01 (fee)
            "Fenwick tree should be properly updated"
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
        bytes memory constructorArgs = abi.encode(address(giga));
        bytes memory fullBytecode = abi.encodePacked(bytecode, constructorArgs);
        bytes32 salt = keccak256("test");
        
        address futureContract = deployer.computeAddress(salt, fullBytecode);
        console.log("Future contract address:", futureContract);
        
        // Alice mints tokens
        vm.prank(alice);
        giga.mint{value: 10 ether}();

        // Alice sends tokens to the future contract address (before deployment)
        vm.prank(alice);
        giga.transfer(futureContract, 5 ether);
        
        // The future address should be in the Fenwick tree as an EOA
        uint256 holderCountBefore = giga.getHolderCount();
        console.log("Holder count before deployment:", holderCountBefore);
        
        // Check Fenwick tree includes the future contract
        uint256 fenwickBefore = giga.getSuffixSum(1);
        console.log("Fenwick sum before deployment:", fenwickBefore);
        
        // Now deploy the contract at that address
        vm.deal(address(this), 5 ether);
        address deployed = deployer.deploy{value: 5 ether}(salt, fullBytecode);
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

        // The deployed contract minted 4.95 tokens in its constructor, getting added to tree
        // After transfer: contract loses 1, bob gains 0.99, net -0.01
        // Expected: 9.85 + 4.95 - 0.01 = 14.79
        assertEq(fenwickAfter, fenwickBefore + 4.95 ether - 0.01 ether, "Fenwick includes contract due to constructor mint");
        
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
        // First deploy with no native token in constructor
        ConstructorMinter normalContract = new ConstructorMinter{value: 0}(giga);
        
        // Contract tries to mint after deployment (not in constructor)
        vm.deal(address(normalContract), 5 ether);
        vm.prank(address(normalContract));
        giga.mint{value: 5 ether}();
        
        // Contract should have tokens but NOT be in Fenwick tree
        uint256 contractBalance = giga.balanceOf(address(normalContract));
        assertGt(contractBalance, 0, "Contract should have tokens");
        
        // Check holder count - contract should not be counted
        uint256 holderCount = giga.getHolderCount();
        assertEq(holderCount, 0, "No holders should be tracked (only contract has tokens)");
        
        // Fenwick tree should be empty
        uint256 fenwickSum = giga.getSuffixSum(1);
        assertEq(fenwickSum, 0, "Fenwick should not track contract balance");
        
        // Even after transfers, contract should not enter Fenwick tree
        vm.prank(address(normalContract));
        giga.transfer(alice, 1 ether);
        
        // Now Alice should be tracked
        holderCount = giga.getHolderCount();
        assertEq(holderCount, 1, "Only Alice should be tracked");
        
        fenwickSum = giga.getSuffixSum(1);
        assertEq(fenwickSum, giga.balanceOf(alice), "Fenwick should only track Alice");
    }
    
    function testPhantomEntriesProperlyCleanedUp() public {
        // Create a scenario with phantom entries
        vm.deal(address(this), 20 ether);
        
        // Deploy multiple malicious contracts that mint in constructor
        ConstructorMinter mal1 = new ConstructorMinter{value: 5 ether}(giga);
        ConstructorMinter mal2 = new ConstructorMinter{value: 5 ether}(giga);
        
        uint256 initialHolderCount = giga.getHolderCount();
        console.log("Initial holder count:", initialHolderCount);
        
        // Both contracts transfer to create EOA holders
        mal1.transfer(alice, 2 ether);
        mal2.transfer(bob, 2 ether);
        
        // Check Fenwick consistency
        uint256 fenwickSum = giga.getSuffixSum(1);
        uint256 actualTotal = giga.balanceOf(alice) + 
                             giga.balanceOf(bob) + 
                             mal1.getBalance() + 
                             mal2.getBalance();
        
        console.log("Fenwick sum:", fenwickSum);
        console.log("Actual total:", actualTotal);
        
        // With the fix, Fenwick should properly track all balances
        assertEq(fenwickSum, actualTotal, "Fenwick should match actual balances");
        
        // Contracts transfer all remaining tokens
        mal1.transfer(alice, mal1.getBalance());
        mal2.transfer(bob, mal2.getBalance());
        
        // Final state should only have EOAs
        uint256 finalFenwick = giga.getSuffixSum(1);
        uint256 eoaTotal = giga.balanceOf(alice) + giga.balanceOf(bob);
        assertEq(finalFenwick, eoaTotal, "Final Fenwick should only track EOAs");
        
        // Holder count should reflect only EOAs
        uint256 finalHolderCount = giga.getHolderCount();
        assertEq(finalHolderCount, 2, "Should only have 2 EOA holders");
    }
}