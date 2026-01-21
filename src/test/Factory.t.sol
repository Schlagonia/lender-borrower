// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";
import {MorphoBlueLenderBorrowerFactory} from "../MorphoBlueLenderBorrowerFactory.sol";
import {MorphoBlueLenderBorrower} from "../MorphoBlueLenderBorrower.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {Id} from "../interfaces/morpho/IMorpho.sol";

contract FactoryTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                        FACTORY DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_factoryDeploysCorrectly() public {
        assertEq(strategyFactory.management(), management, "wrong management");
        assertEq(
            strategyFactory.performanceFeeRecipient(),
            performanceFeeRecipient,
            "wrong fee recipient"
        );
        assertEq(strategyFactory.keeper(), keeper, "wrong keeper");
        assertEq(
            strategyFactory.emergencyAdmin(),
            emergencyAdmin,
            "wrong emergency admin"
        );
        assertEq(strategyFactory.GOV(), gov, "wrong gov");
        assertEq(strategyFactory.morpho(), morpho, "wrong morpho");
    }

    function test_newStrategyInitializesCorrectly() public {
        // Strategy was created in setup
        assertEq(strategy.asset(), address(asset), "wrong asset");
        assertEq(strategy.borrowToken(), borrowToken, "wrong borrow token");
        assertEq(strategy.GOV(), gov, "wrong gov");
        assertEq(address(strategy.morpho()), morpho, "wrong morpho");
        assertEq(
            Id.unwrap(strategy.marketId()),
            Id.unwrap(marketId),
            "wrong market id"
        );
    }

    function test_deploymentTracksByMarketId() public {
        address deployed = strategyFactory.deployments(marketId);
        assertEq(deployed, address(strategy), "deployment not tracked");
    }

    /*//////////////////////////////////////////////////////////////
                        FACTORY ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setAddresses_onlyManagement() public {
        address newManagement = address(0x999);
        address newFeeRecipient = address(0x888);
        address newKeeper = address(0x777);
        address newEmergencyAdmin = address(0x666);

        // Non-management cannot change
        vm.prank(user);
        vm.expectRevert("!management");
        strategyFactory.setAddresses(
            newManagement,
            newFeeRecipient,
            newKeeper,
            newEmergencyAdmin
        );

        // Management can change
        vm.prank(management);
        strategyFactory.setAddresses(
            newManagement,
            newFeeRecipient,
            newKeeper,
            newEmergencyAdmin
        );

        assertEq(
            strategyFactory.management(),
            newManagement,
            "management not updated"
        );
        assertEq(
            strategyFactory.performanceFeeRecipient(),
            newFeeRecipient,
            "fee recipient not updated"
        );
        assertEq(strategyFactory.keeper(), newKeeper, "keeper not updated");
        assertEq(
            strategyFactory.emergencyAdmin(),
            newEmergencyAdmin,
            "emergency admin not updated"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    STRATEGY CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_strategyHasCorrectMarketParams() public {
        (
            address loanToken,
            address collateralToken,
            address oracle,
            address irm,
            uint256 lltv
        ) = strategy.marketParams();

        assertEq(loanToken, borrowToken, "wrong loan token");
        assertEq(collateralToken, address(asset), "wrong collateral token");
        assertTrue(oracle != address(0), "oracle not set");
        assertTrue(irm != address(0), "irm not set");
        assertGt(lltv, 0, "lltv not set");
    }

    function test_strategyDefaultParameters() public {
        assertEq(strategy.targetLTVMultiplier(), 7_000, "wrong target LTV");
        assertEq(strategy.warningLTVMultiplier(), 8_000, "wrong warning LTV");
        assertEq(
            strategy.leaveDebtBehind(),
            false,
            "leaveDebtBehind should be false"
        );
        assertEq(
            strategy.depositLimit(),
            type(uint256).max,
            "wrong deposit limit"
        );
    }
}
