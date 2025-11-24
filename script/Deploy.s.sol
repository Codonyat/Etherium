// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Strategy} from "../src/Strategy.sol";

/** @dev deployment:
    With Ledger:
    forge script script/Deploy.s.sol --rpc-url https://testnet-rpc.monad.xyz --broadcast --ledger --hd-paths $HD_PATH

    With Private Key:
    forge script script/Deploy.s.sol --rpc-url https://testnet-rpc.monad.xyz --broadcast --private-key $PRIVATE_KEY
*/
contract DeployScript is Script {
    address wmonAddress;

    function setUp() public {
        // Monad Mainnet
        if (block.chainid == 143) {
            wmonAddress = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
        }
        // Monad Testnet
        else if (block.chainid == 10143) {
            wmonAddress = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
        } else {
            revert("Not a supported chain.");
        }
    }

    function run() public {
        vm.startBroadcast();

        Strategy monstr = new Strategy(wmonAddress);

        console.log("Strategy deployed at:", address(monstr));
        console.log("WMON address:", wmonAddress);
        console.log("Community token:", address(monstr.COMMUNITY_TOKEN()));
        console.log("Deployment time:", block.timestamp);
        console.log("Minting end time:", block.timestamp + 7 days);

        vm.stopBroadcast();
    }
}
