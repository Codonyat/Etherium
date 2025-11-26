// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/MockERC20.sol";

/** @dev deployment:
    With Ledger:
    forge script script/DeployMockERC20.s.sol --rpc-url https://testnet-rpc.monad.xyz --broadcast --ledger --hd-paths $HD_PATH

    With Private Key:
    forge script script/DeployMockERC20.s.sol --rpc-url https://testnet-rpc.monad.xyz --broadcast --private-key $PRIVATE_KEY
*/
contract DeployMockERC20Script is Script {
    function run() public {
        vm.startBroadcast();

        // Get deployer address (msg.sender during broadcast)
        address deployer = msg.sender;

        // Deploy mock token with 1000 tokens (with 18 decimals)
        MockERC20 mockToken = new MockERC20(
            "Mock Token",
            "MOCK",
            deployer,
            1000 * 10**18
        );

        console.log("MockERC20 deployed at:", address(mockToken));
        console.log("Deployer address:", deployer);
        console.log("Initial balance:", mockToken.balanceOf(deployer));

        vm.stopBroadcast();
    }
}
