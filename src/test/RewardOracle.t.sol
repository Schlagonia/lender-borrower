// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";
import {Id} from "../interfaces/morpho/IMorpho.sol";
import {StrategyAprOracle} from "../periphery/StrategyAprOracle.sol";
import {ManualBorrowRewardAprOracle} from "../periphery/ManualBorrowRewardAprOracle.sol";

contract RewardOracleTest is Setup {
    Id internal constant OETH_USDC_MARKET_ID =
        Id.wrap(0xb8fef900b383db2dbbf4458c7f46acf5b140f26d603a6d1829963f241b82510e);

    StrategyAprOracle public strategyAprOracle;
    ManualBorrowRewardAprOracle public rewardOracle;

    function setUp() public override {
        lenderVault = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;
        super.setUp();

        strategyAprOracle = new StrategyAprOracle(gov);
        rewardOracle = new ManualBorrowRewardAprOracle(management);
    }

    function test_setBorrowRewardApr_onlyManagement() public {
        Id currentMarketId = strategy.marketId();

        vm.expectRevert("!management");
        vm.prank(user);
        rewardOracle.setBorrowRewardAprBps(currentMarketId, 777);
    }

    function test_setBorrowRewardAprBps() public {
        vm.prank(management);
        rewardOracle.setBorrowRewardAprBps(OETH_USDC_MARKET_ID, 321);

        assertEq(rewardOracle.borrowRewardApr(OETH_USDC_MARKET_ID), 321 * 1e14);
    }

    function test_setRewardAprOracle_onlyGovernance() public {
        vm.prank(gov);
        strategyAprOracle.setRewardAprOracle(address(strategy), address(rewardOracle));

        assertEq(strategyAprOracle.rewardAprOracles(address(strategy)), address(rewardOracle));
    }

    function test_setRewardAprOracle_revertsForNonGovernance() public {
        vm.expectRevert("!governance");
        vm.prank(management);
        strategyAprOracle.setRewardAprOracle(address(strategy), address(rewardOracle));
    }

    function test_strategyAprOracle_addsBorrowRewardApr() public {
        Id currentMarketId = strategy.marketId();

        vm.prank(gov);
        strategyAprOracle.setRewardAprOracle(address(strategy), address(rewardOracle));

        uint256 baselineApr = strategyAprOracle.aprAfterDebtChange(address(strategy), 0);
        uint256 rewardApr = 777 * 1e14;

        vm.prank(management);
        rewardOracle.setBorrowRewardAprBps(currentMarketId, 777);

        assertEq(strategyAprOracle.aprAfterDebtChange(address(strategy), 0), baselineApr + rewardApr);
    }
}
