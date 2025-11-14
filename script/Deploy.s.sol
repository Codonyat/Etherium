// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Strategy} from "../src/Strategy.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get WMON address from env (required for auctions)
        // Monad Mainnet WMON: 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A
        // Monad Testnet WMON: 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701
        address wmonAddress = vm.envAddress("WMON_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        Strategy monstr = new Strategy(wmonAddress);

        console.log("Strategy deployed at:", address(monstr));
        console.log("WMON address:", wmonAddress);
        console.log("Community token:", address(monstr.COMMUNITY_TOKEN()));
        console.log("Deployment time:", block.timestamp);
        console.log("Minting end time:", block.timestamp + 7 days);

        vm.stopBroadcast();
    }
}
