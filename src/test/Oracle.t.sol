pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup} from "./utils/Setup.sol";

import {StrategyAprOracle} from "../periphery/StrategyAprOracle.sol";

contract OracleTest is Setup {
    StrategyAprOracle public oracle;

    function setUp() public override {
        lenderVault = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;
        super.setUp();
        oracle = new StrategyAprOracle(management);
    }

    function checkOracle(address _strategy, uint256 _delta) public {
        // Check set up
        // TODO: Add checks for the setup

        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);

        console2.log("currentApr", currentApr);

        // Should be non-negative and reasonably bounded (< 1000% APR)
        assertGe(currentApr, 0, "ZERO");
        assertLt(currentApr, 10e18, "too high");

        // TODO: Uncomment to test the apr goes up and down based on debt changes

        uint256 negativeDebtChangeApr = oracle.aprAfterDebtChange(
            _strategy,
            -int256(_delta)
        );

        console2.log("negativeDebtChangeApr", negativeDebtChangeApr);

        // The apr should go up if deposits go down
        assertLt(currentApr, negativeDebtChangeApr, "negative change");

        uint256 positiveDebtChangeApr = oracle.aprAfterDebtChange(
            _strategy,
            int256(_delta)
        );

        console2.log("positiveDebtChangeApr", positiveDebtChangeApr);

        assertGt(currentApr, positiveDebtChangeApr, "positive change");

        // TODO: Uncomment if there are setter functions to test.
        /**
        vm.expectRevert("!governance");
        vm.prank(user);
        oracle.setterFunction(setterVariable);

        vm.prank(management);
        oracle.setterFunction(setterVariable);

        assertEq(oracle.setterVariable(), setterVariable);
        */
    }

    function test_oracle(uint256 _amount, uint16 _percentChange) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 _delta = (_amount * _percentChange) / MAX_BPS;

        checkOracle(address(strategy), _delta);
    }

    // TODO: Deploy multiple strategies with different tokens as `asset` to test against the oracle.
}
