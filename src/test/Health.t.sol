// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";

contract HealthTest is Setup {
    uint256 internal constant WAD = 1e18;

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

    function test_tendReducesLTV(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 ltvBefore = strategy.getCurrentLTV();
        assertGt(ltvBefore, 0, "no initial LTV");

        // Tighten warning band to trigger a rebalance
        vm.prank(management);
        strategy.setLtvMultipliers(6_000, 6_100);

        // Verify tend is triggered
        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(trigger, "tend should trigger");

        // Execute tend
        vm.prank(keeper);
        strategy.tend();

        uint256 ltvAfter = strategy.getCurrentLTV();

        // LTV should have decreased toward the new target (6000 bps = 60% of LLTV)
        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() * 6_000) /
            MAX_BPS;

        // After tend, LTV should be closer to target than before
        // Since we set target to 60% and warning to 61%, after tend we should be around 60%
        assertLt(ltvAfter, ltvBefore, "LTV didn't decrease");

        // LTV should now be near target (within 5% relative tolerance)
        assertApproxEq(
            ltvAfter,
            targetLTV,
            targetLTV / 20,
            "LTV not near target"
        );
    }

    function test_isLiquidatableDetection(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Default LTV is 70% of LLTV, which is safe
        uint256 currentLTV = strategy.getCurrentLTV();
        uint256 lltv = strategy.getLiquidateCollateralFactor();

        // Verify we're below liquidation threshold
        assertLt(currentLTV, lltv, "already at liquidation");

        // Verify the detection mechanism works:
        // When LTV is above warning, tendTrigger returns true
        // Set very low target/warning so current LTV is above warning
        vm.prank(management);
        strategy.setLtvMultipliers(1_000, 2_000); // Very low target, current LTV way above warning

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(trigger, "should trigger when above warning LTV");

        // Verify getCurrentLTV is still returning a sensible value
        uint256 ltvNow = strategy.getCurrentLTV();
        assertGt(ltvNow, 0, "LTV should be positive");

        // The current LTV should be above the new warning (2000 bps = 20% of LLTV)
        uint256 warningLTV = (lltv * 2_000) / MAX_BPS;
        assertGt(ltvNow, warningLTV, "LTV should be above warning");
    }
}
