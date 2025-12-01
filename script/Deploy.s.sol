// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Strategy} from "../src/Strategy.sol";
import {WMEGAAddresses} from "./WMEGAAddresses.sol";

/** @dev deployment:
    With Ledger:
    forge script script/Deploy.s.sol --rpc-url mega_testnet_alchemy --broadcast --ledger --hd-paths $HD_PATH \
    --priority-gas-price 0.001gwei --with-gas-price 0.01gwei

    With Private Key:
    forge script script/Deploy.s.sol --rpc-url mega_testnet_alchemy --broadcast --private-key $PRIVATE_KEY \
    --priority-gas-price 0.001gwei --with-gas-price 0.01gwei
*/
contract DeployScript is Script {
    function run() public {
        address wmegaAddress = WMEGAAddresses.getWMEGAAddressStrict();

        vm.startBroadcast();

        Strategy giga = new Strategy(wmegaAddress);

        console.log("Strategy deployed at:", address(giga));
        console.log("WMEGA address:", wmegaAddress);
        console.log("Community token:", address(giga.COMMUNITY_TOKEN()));
        console.log("Deployment time:", block.timestamp);
        console.log("Minting end time:", block.timestamp + 7 days);

        vm.stopBroadcast();
    }
}
