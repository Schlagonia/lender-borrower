// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";
import {StrategyFactory} from "../src/StrategyFactory.sol";

// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {

    address public management;
    function run() external {
        vm.startBroadcast();

        StrategyAprOracle oracle = new StrategyAprOracle();

        console.log("Oracle is ", address(oracle));

        /**

        StrategyFactory factory = new StrategyFactory(
            management,
            0x4200000000000000000000000000000000000006,
            management,
            management,
            management,
            management
        );

        console.log("Address is ", address(factory));
        */

        vm.stopBroadcast();
    }
}

