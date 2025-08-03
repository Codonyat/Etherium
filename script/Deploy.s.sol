// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Etherium} from "../src/Etherium.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        Etherium etherium = new Etherium();
        
        console.log("Etherium deployed at:", address(etherium));
        console.log("Deployment time:", block.timestamp);
        console.log("Minting end time:", block.timestamp + 7 days);
        
        vm.stopBroadcast();
    }
}