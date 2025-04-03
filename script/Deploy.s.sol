// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {StrategyFactory} from "../src/StrategyFactory.sol";
import {CrvUsdLenderBorrower} from "../src/CrvUsdLenderBorrower.sol";

contract Deploy is Script {

    address public management = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;
    address public sms = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address public controllerFactory = 0xC9332fdCB1C491Dcc683bAe86Fe3cb70360738BC;

    function run() public {
        vm.startBroadcast();

        StrategyFactory factory = new StrategyFactory(
            management,
            management,
            management,
            sms,
            sms,
            controllerFactory
        );

        console2.log("Factory deployed at", address(factory));

        vm.stopBroadcast();
    }
}
