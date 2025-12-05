// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";
import {MorphoBlueLenderBorrower} from "../MorphoBlueLenderBorrower.sol";

contract LTVTest is Setup {
    uint256 internal constant WAD = 1e18;

    function setUp() public virtual override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                        LTV CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialLTV_withinTarget(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 currentLTV = strategy.getCurrentLTV();
        uint256 targetLTV = (strategy.getLiquidateCollateralFactor() *
            strategy.targetLTVMultiplier()) / MAX_BPS;
        uint256 warningLTV = (strategy.getLiquidateCollateralFactor() *
            strategy.warningLTVMultiplier()) / MAX_BPS;

        // LTV should be at or near target, definitely below warning
        assertLe(currentLTV, warningLTV, "LTV above warning");

        // LTV should be close to target (within 10% relative)
        assertApproxEq(
            currentLTV,
            targetLTV,
            targetLTV / 10,
            "LTV not near target"
        );
    }

    function test_getCurrentLTV_noCollateral() public {
        // With no position, LTV should be 0
        assertEq(strategy.getCurrentLTV(), 0, "empty LTV should be 0");
    }

    function test_getLiquidateCollateralFactor() public {
        uint256 lltv = strategy.getLiquidateCollateralFactor();

        // LLTV should be a reasonable value (e.g., between 50% and 95%)
        assertGt(lltv, 5e17, "LLTV too low"); // > 50%
        assertLt(lltv, 95e16, "LLTV too high"); // < 95%
    }

    function test_ltvMultipliers_bounds() public {
        // Test extreme valid values
        vm.prank(management);
        strategy.setLtvMultipliers(1, 2);
        assertEq(strategy.targetLTVMultiplier(), 1);
        assertEq(strategy.warningLTVMultiplier(), 2);

        // Restore to normal
        vm.prank(management);
        strategy.setLtvMultipliers(7_000, 8_000);
    }

    function test_warningLTV_triggersRebalance(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 initialLTV = strategy.getCurrentLTV();

        // Lower the warning threshold so current position is above it
        vm.prank(management);
        strategy.setLtvMultipliers(5_000, 5_500);

        uint256 newWarningLTV = (strategy.getLiquidateCollateralFactor() *
            5_500) / MAX_BPS;

        // Current LTV should now be above the new warning threshold
        assertGt(initialLTV, newWarningLTV, "LTV should be above warning");

        // Tend should be triggered
        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(trigger, "tend should trigger");

        // Execute tend
        vm.prank(keeper);
        strategy.tend();

        // LTV should have decreased
        uint256 ltvAfterTend = strategy.getCurrentLTV();
        assertLt(ltvAfterTend, initialLTV, "LTV should decrease after tend");
    }

    /*//////////////////////////////////////////////////////////////
                        DEBT/COLLATERAL BALANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_balanceOfCollateral(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        uint256 collateralBefore = strategy.balanceOfCollateral();
        assertEq(collateralBefore, 0, "should have no collateral initially");

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 collateralAfter = strategy.balanceOfCollateral();
        assertGt(collateralAfter, 0, "should have collateral after deposit");

        // Collateral should be close to the deposited amount
        assertApproxEq(
            collateralAfter,
            _amount,
            _amount / 20,
            "collateral ~= deposit"
        );
    }

    function test_balanceOfDebt(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        uint256 debtBefore = strategy.balanceOfDebt();
        assertEq(debtBefore, 0, "should have no debt initially");

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 debtAfter = strategy.balanceOfDebt();
        assertGt(debtAfter, 0, "should have debt after deposit");
    }

    function test_balanceOfLentAssets(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        uint256 lentBefore = strategy.balanceOfLentAssets();
        assertEq(lentBefore, 0, "should have no lent assets initially");

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 lentAfter = strategy.balanceOfLentAssets();
        assertGt(lentAfter, 0, "should have lent assets after deposit");

        // Lent should be close to debt (we lend borrowed tokens)
        uint256 debt = strategy.balanceOfDebt();
        assertApproxEq(lentAfter, debt, debt / 10, "lent ~= debt");
    }

    function test_borrowTokenOwedBalance_zeroBefore() public {
        assertEq(
            strategy.borrowTokenOwedBalance(),
            0,
            "should owe nothing initially"
        );
    }

    function test_borrowTokenOwedBalance_zeroOrSmallWhenBalanced(
        uint256 _amount
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // After deposit, lent should >= debt, so owed should be 0 or very small (dust)
        uint256 owed = strategy.borrowTokenOwedBalance();
        // Allow for small dust amounts due to rounding
        assertLe(owed, 100, "should not owe significant amount when balanced");
    }

    /*//////////////////////////////////////////////////////////////
                        LEVERAGE POSITION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_leveragePosition_increasesDebt(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 debt = strategy.balanceOfDebt();
        uint256 collateral = strategy.balanceOfCollateral();

        // Debt should be > 0 due to leverage
        assertGt(debt, 0, "should have debt from leverage");

        // Collateral should equal deposit amount
        assertApproxEq(
            collateral,
            _amount,
            _amount / 50,
            "collateral ~= amount"
        );
    }

    function test_multipleLeverageCycles(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount / 3);

        // First deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);
        uint256 debt1 = strategy.balanceOfDebt();
        uint256 collateral1 = strategy.balanceOfCollateral();

        // Second deposit
        mintAndDepositIntoStrategy(strategy, user, _amount);
        uint256 debt2 = strategy.balanceOfDebt();
        uint256 collateral2 = strategy.balanceOfCollateral();

        assertGt(debt2, debt1, "debt should increase");
        assertGt(collateral2, collateral1, "collateral should increase");

        // Collateral should be approximately 2x first collateral
        assertApproxEq(
            collateral2,
            collateral1 * 2,
            collateral1 / 5,
            "collateral ~= 2x"
        );
    }
}
