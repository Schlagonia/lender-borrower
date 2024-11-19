// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

//import {MoonwellLenderBorrowerAprOracle} from "../src/periphery/MoonwellLenderBorrowerAprOracle.sol";
import {MoonwellLenderBorrowerFactory} from "../src/MoonwellLenderBorrowerFactory.sol";

// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {

    address public management = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;
    function run() external {
        vm.startBroadcast();

        //StrategyAprMoonwellLenderBorrowerAprOracle oracle = new StrategyAprMoonwellLenderBorrowerAprOracle();

        //console.log("Oracle is ", address(oracle));

        MoonwellLenderBorrowerFactory factory = new MoonwellLenderBorrowerFactory(
            management,
            management,
            management,
            management,
            management
        );

        console.log("Address is ", address(factory));
        
        address strategy = factory.newStrategy(
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            "Moonwell USDC Lender WETH Borrower",
            0x4200000000000000000000000000000000000006,
            0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22,
            0x628ff693426583D9a7FB391E54366292F509D457,
            0xb65f1e6394AaDC3dc1AD4B8E5cF79Bbb566Dc195
        );

        console.log("Strategy is ", strategy);

        vm.stopBroadcast();
    }
}
