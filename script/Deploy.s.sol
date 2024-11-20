// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

import {MoonwellOracle} from "../src/periphery/MoonwellOracle.sol";
import {MoonwellLenderBorrowerAprOracle} from "../src/periphery/MoonwellLenderBorrowerAprOracle.sol";
import {MoonwellLenderBorrowerFactory} from "../src/MoonwellLenderBorrowerFactory.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {

    address public management;

    address internal constant WELL = 0xA88594D404727625A9437C3f886C7643872296AE;

    IStrategyInterface public strategy = IStrategyInterface(0xD95872cF52477DD9116DBD1c5A3d9d595D37024a);

    function run() external {
        vm.startBroadcast();

        MoonwellLenderBorrowerAprOracle oracle = new MoonwellLenderBorrowerAprOracle();

        console.log("Apr Oracle is ", address(oracle));


        MoonwellOracle moonwellOracle = new MoonwellOracle();

        console.log("Moonwell Oracle is ", address(moonwellOracle));

        strategy.setPriceFeed(WELL, address(moonwellOracle));

        /**
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
        */

        vm.stopBroadcast();
    }
}
