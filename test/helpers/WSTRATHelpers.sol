// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IWMEGA, Strategy} from "../.././src/Strategy.sol";

contract MockWMEGA {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "MEGA transfer failed");
        emit Transfer(msg.sender, address(0), amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
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

        emit Transfer(from, to, amount);
        return true;
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }
}

import {Test} from "forge-std/Test.sol";

abstract contract WMEGATestBase is Test {
    IWMEGA public wmega;

    function setupWMEGA() internal {
        // Deploy mock WMEGA for tests that don't inherit from StrategyTestBase
        MockWMEGA mockWmega = new MockWMEGA();
        wmega = IWMEGA(address(mockWmega));
    }

    function getWMEGAAndApprove(
        address user,
        address spender,
        uint256 amount
    ) internal {
        vm.startPrank(user);
        wmega.deposit{value: amount}();
        wmega.approve(spender, amount);
        vm.stopPrank();
    }

    // Helper function to skip past the minting period
    function skipPastMintingPeriod(Strategy strategy) internal {
        uint256 mintingPeriod = strategy.MINTING_PERIOD();
        vm.warp(block.timestamp + mintingPeriod + 1 days);
    }
}
