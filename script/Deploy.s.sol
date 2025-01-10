// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Script.sol";

import {MoonwellOracle} from "../src/periphery/MoonwellOracle.sol";
import {MoonwellLenderBorrowerAprOracle} from "../src/periphery/MoonwellLenderBorrowerAprOracle.sol";
import {MoonwellLenderBorrowerFactory} from "../src/MoonwellLenderBorrowerFactory.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {

    address public signer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    address public management = 0xde9e11D8a6894D47A3b407464b58b5dB9C97a58c;

    address public keeper = 0xb53B0b397522840EF85D73E56f3292E4B5cc5c91;

    address public sms = 0x01fE3347316b2223961B20689C65eaeA71348e93;

    address public chad = 0xbfAABa9F56A39B814281D68d2Ad949e88D06b02E;

    address internal constant WELL = 0xA88594D404727625A9437C3f886C7643872296AE;

    function run() external {
        vm.startBroadcast();
        
        MoonwellLenderBorrowerFactory factory = new MoonwellLenderBorrowerFactory(
            management,
            management,
            keeper,
            sms,
            chad
        );

        console.log("Address is ", address(factory));
        
        MoonwellLenderBorrowerAprOracle oracle = new MoonwellLenderBorrowerAprOracle();

        console.log("Apr Oracle is ", address(oracle));

        factory.setOracle(address(oracle));

        factory.setAddresses(management, management, keeper);

        address strategy = factory.newStrategy(
            0x628ff693426583D9a7FB391E54366292F509D457,
            0xb65f1e6394AaDC3dc1AD4B8E5cF79Bbb566Dc195,
            0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22
            
        );

        console.log("Strategy is ", strategy);
        

        vm.stopBroadcast();
    }
}
