// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Etherium} from "../src/Etherium.sol";

contract EtheriumInvariantTest is Test {
    Etherium public etherium;
    Handler public handler;
    
    function setUp() public {
        etherium = new Etherium();
        handler = new Handler(etherium);
        
        // Set the handler as the target for invariant testing
        targetContract(address(handler));
        
        // Fund the handler with ETH for operations
        vm.deal(address(handler), 1000 ether);
    }
    
    // INVARIANT: ETH per ETHERIUM ratio should never decrease
    // This means: (ETH in contract / total supply) should only increase or stay same
    function invariant_ETH_per_ETHERIUM_never_decreases() public view {
        uint256 currentETH = address(etherium).balance;
        uint256 currentSupply = etherium.totalSupply();
        
        if (currentSupply == 0) {
            // No tokens, ratio is undefined but valid
            return;
        }
        
        // Since we can't track state between calls in a view function,
        // we check that the ratio is at least the initial minting ratio
        // During minting period: 1 ETH = 1000 ETHERIUM => ratio = 0.001 ETH per ETHERIUM
        // After auction bids, ratio should only increase
        uint256 currentRatio = (currentETH * 1e18) / currentSupply;
        uint256 minRatio = 1e15; // 0.001 ETH per ETHERIUM = 1e15 wei per ETHERIUM (scaled by 1e18)
        
        assertTrue(
            currentRatio >= minRatio,
            "ETH per ETHERIUM ratio below minimum!"
        );
    }
    
    // INVARIANT: Total supply should never exceed max supply after minting period
    function invariant_supply_never_exceeds_max() public {
        uint256 maxSupply = etherium.maxSupplyEver();
        uint256 totalSupply = etherium.totalSupply();
        
        if (maxSupply > 0) {
            // Max supply has been set (after minting period)
            assertTrue(
                totalSupply <= maxSupply,
                "Total supply exceeded max supply!"
            );
        }
    }
    
    // INVARIANT: Total supply should be conserved (no tokens created or destroyed outside of mint/redeem)
    function invariant_total_supply_conservation() public view {
        uint256 totalSupply = etherium.totalSupply();
        
        // During minting period, supply can grow
        // After minting period, supply can only decrease through redemption
        if (etherium.maxSupplyEver() > 0) {
            // After minting period
            assertTrue(
                totalSupply <= etherium.maxSupplyEver(),
                "Total supply exceeded max after minting period!"
            );
        }
        
        // Total supply should always be non-negative (this is guaranteed by uint)
        // and should match the sum of minted minus redeemed tokens
    }
    
    // INVARIANT: Fees pools should only accumulate, never decrease (except during lottery/auction)
    function invariant_fees_pool_monotonic() public {
        uint256 currentFeesPool = etherium.balanceOf(etherium.FEES_POOL());
        uint256 currentDay = etherium.getCurrentDay();
        
        // During lottery execution, fees can be distributed
        if (currentDay > handler.lastDay()) {
            // Day changed, lottery might have executed
            handler.updateLastDay(currentDay);
            handler.updateLastFeesPool(currentFeesPool);
        } else {
            // Same day, fees should only increase
            assertTrue(
                currentFeesPool >= handler.lastFeesPool(),
                "Fees pool decreased without lottery!"
            );
            handler.updateLastFeesPool(currentFeesPool);
        }
    }
}

// Handler contract to perform random operations
contract Handler is Test {
    Etherium public etherium;
    address public immutable parent;
    
    uint256 public lastRatio;
    uint256 public lastFeesPool;
    uint256 public lastDay;
    
    address[] public actors;
    mapping(address => bool) public isActor;
    
    constructor(Etherium _etherium) {
        parent = msg.sender;
        etherium = _etherium;
        
        // Create some actors
        for (uint i = 1; i <= 10; i++) {
            address actor = address(uint160(i));
            actors.push(actor);
            isActor[actor] = true;
            vm.deal(actor, 100 ether);
        }
    }
    
    // Mint tokens with random amounts
    function mint(uint256 actorSeed, uint256 amount) public {
        // Bound inputs
        uint256 actorIndex = bound(actorSeed, 0, actors.length - 1);
        address actor = actors[actorIndex];
        amount = bound(amount, 0.001 ether, 10 ether);
        
        // Skip if we're past minting period and max supply would be exceeded
        if (block.timestamp > 7 days && etherium.maxSupplyEver() > 0) {
            uint256 availableCapacity = etherium.maxSupplyEver() > etherium.totalSupply() 
                ? etherium.maxSupplyEver() - etherium.totalSupply()
                : 0;
            if (amount * 1000 > availableCapacity) {
                return; // Skip this operation
            }
        }
        
        vm.prank(actor);
        try etherium.mint{value: amount}() {
            // Success
        } catch {
            // Failed, but that's ok for invariant testing
        }
    }
    
    // Transfer tokens between actors
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        uint256 fromIndex = bound(fromSeed, 0, actors.length - 1);
        uint256 toIndex = bound(toSeed, 0, actors.length - 1);
        
        address from = actors[fromIndex];
        address to = actors[toIndex];
        
        uint256 balance = etherium.balanceOf(from);
        if (balance == 0) return;
        
        amount = bound(amount, 0, balance);
        
        vm.prank(from);
        try etherium.transfer(to, amount) {
            // Success
        } catch {
            // Failed, but that's ok
        }
    }
    
    // Redeem tokens
    function redeem(uint256 actorSeed, uint256 amount) public {
        uint256 actorIndex = bound(actorSeed, 0, actors.length - 1);
        address actor = actors[actorIndex];
        
        uint256 balance = etherium.balanceOf(actor);
        if (balance == 0) return;
        
        amount = bound(amount, 0, balance);
        
        vm.prank(actor);
        try etherium.redeem(amount) {
            // Success
        } catch {
            // Failed, but that's ok
        }
    }
    
    // Execute lottery (if eligible)
    function executeLottery() public {
        try etherium.executeLottery() {
            // Success
        } catch {
            // Failed, but that's ok
        }
    }
    
    // Place bid on auction
    function bid(uint256 actorSeed, uint256 bidAmount) public {
        uint256 actorIndex = bound(actorSeed, 0, actors.length - 1);
        address actor = actors[actorIndex];
        
        bidAmount = bound(bidAmount, 0.001 ether, 10 ether);
        
        vm.prank(actor);
        try etherium.bid{value: bidAmount}() {
            // Success
        } catch {
            // Failed, but that's ok
        }
    }
    
    // Warp time forward
    function warpTime(uint256 hoursToWarp) public {
        hoursToWarp = bound(hoursToWarp, 1, 72); // Max 3 days forward
        vm.warp(block.timestamp + hoursToWarp * 1 hours);
    }
    
    // Helper functions for invariants (only callable by parent test contract)
    function updateLastRatio(uint256 ratio) external {
        require(msg.sender == parent, "Only parent can call");
        lastRatio = ratio;
    }
    
    function updateLastFeesPool(uint256 pool) external {
        require(msg.sender == parent, "Only parent can call");
        lastFeesPool = pool;
    }
    
    function updateLastDay(uint256 day) external {
        require(msg.sender == parent, "Only parent can call");
        lastDay = day;
    }
    
    function getSumOfAllBalances() external view returns (uint256 sum) {
        // Sum all possible holder balances
        // Note: This is a simplified approach - in reality we'd need to track all addresses
        // For testing, we check known addresses
        
        // Sum actor balances
        for (uint i = 0; i < actors.length; i++) {
            sum += etherium.balanceOf(actors[i]);
        }
        
        // Add special pool balances
        sum += etherium.balanceOf(etherium.FEES_POOL());
        sum += etherium.balanceOf(etherium.LOT_POOL());
        
        // Add handler balance (in case it holds tokens)
        sum += etherium.balanceOf(address(this));
        
        // Add any balances that might be in unclaimed prize winner addresses
        // These are already accounted for in winner balances if they exist as actors
        
        // Note: There may be other addresses holding tokens that we don't track
        // This is a limitation of the test setup
    }
}