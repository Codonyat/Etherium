// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/MockERC20.sol";

/** @dev deployment:
    With Ledger:
    forge script script/DeployMockERC20.s.sol --rpc-url mega_testnet_alchemy --broadcast --ledger --hd-paths $HD_PATH \
    --priority-gas-price 0.001gwei --with-gas-price 0.01gwei

    With Private Key:
    forge script script/DeployMockERC20.s.sol --rpc-url mega_testnet_alchemy --broadcast --private-key $PRIVATE_KEY \
    --priority-gas-price 0.001gwei --with-gas-price 0.01gwei
*/
contract DeployMockERC20Script is Script {
    function run() public {
        vm.startBroadcast();

        // Deploy mock MEGA token (with 18 decimals)
        MockERC20 mockToken = new MockERC20("Mock MEGA", "MEGA");

        console.log("Mock MEGA deployed at:", address(mockToken));

        vm.stopBroadcast();
    }
}
