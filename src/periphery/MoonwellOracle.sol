// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOracle} from "../interfaces/IOracle.sol";
import {IAeroRouter} from "../interfaces/Aero/IAeroRouter.sol";
contract MoonwellOracle is IOracle {
    IAeroRouter internal constant AERODROME_ROUTER =
        IAeroRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);

    address internal constant AERODROME_FACTORY =
        0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    address internal constant WELL = 0xA88594D404727625A9437C3f886C7643872296AE;

    address internal constant WETH = 0x4200000000000000000000000000000000000006;

    function latestAnswer() external view returns (int256) {
        return int256(_toUsd(_getAeroAmountOut()));
    }

    function _toUsd(uint256 _amount) internal view virtual returns (uint256) {
        if (_amount == 0) return 0;
        unchecked {
            return
                (_amount *
                    uint256(
                        IOracle(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70)
                            .latestAnswer()
                    )) / 1e18; // WETH/ USD Oracle
        }
    }

    function _getAeroAmountOut() internal view returns (uint256) {
        IAeroRouter.Route[] memory _routes = new IAeroRouter.Route[](1);

        _routes[0] = IAeroRouter.Route({
            from: WELL,
            to: WETH,
            stable: false,
            factory: AERODROME_FACTORY
        });

        return AERODROME_ROUTER.getAmountsOut(1e18, _routes)[_routes.length];
    }
}
