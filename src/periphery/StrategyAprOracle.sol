// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {Depositor, Comet} from "../Depositor.sol";

contract StrategyAprOracle {
    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param . The difference in debt.
     * @return . The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 /*_delta*/
    ) external view returns (uint256) {
        Depositor depositor = Depositor(
            IStrategyInterface(_strategy).depositor()
        );

        Comet comet = Comet(IStrategyInterface(_strategy).comet());

        uint256 newUtilization = (comet.totalBorrow() * 1e18) /
            comet.totalSupply();

        uint256 borrowApr = depositor.getBorrowApr(newUtilization);
        uint256 supplyApr = depositor.getSupplyApr(newUtilization);
        uint256 netRewardApr = depositor.getNetRewardApr(0);

        uint256 netApr = netRewardApr + supplyApr - borrowApr;

        return (netApr * IStrategyInterface(_strategy).getCurrentLTV()) / 1e18;
    }
}
