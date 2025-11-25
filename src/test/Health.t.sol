// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";

contract HealthTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_tendTriggerHealthyWhenIdle(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "idle trigger");

        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "healthy trigger");
    }

    function test_tendTriggerWarningWhenDebtHigh(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Tighten warning band to make existing leverage breach it.
        vm.prank(management);
        strategy.setLtvMultipliers(6_000, 6_100);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(trigger, "should trigger at warning");
    }
}
