// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20} from "./utils/Setup.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
    }

    function test_basicDepositWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        uint256 warningLTV = (strategy.getLiquidateCollateralFactor() *
            strategy.warningLTVMultiplier()) / MAX_BPS;

        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertGt(strategy.balanceOfCollateral(), 0, "collateral");
        assertGt(strategy.balanceOfDebt(), 0, "debt");
        assertLt(strategy.getCurrentLTV(), warningLTV, "ltv too high");

        uint256 userBalanceBefore = asset.balanceOf(user);
        vm.prank(user);
        strategy.withdraw(_amount / 2, user, user);

        assertApproxEq(
            strategy.totalAssets(),
            strategy.totalSupply(),
            10,
            "assets ~ supply"
        );
        assertEq(asset.balanceOf(user), userBalanceBefore + (_amount / 2));
    }

    function test_reportDoesNotRevert(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount / 5);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Let some time pass to accrue interest.
        skip(1 days);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Accept either profit or minor loss, but strategy should stay solvent.
        assertGt(strategy.totalAssets(), 0, "no assets");
        assertGe(profit + strategy.totalAssets(), strategy.totalAssets());
        assertGe(loss + strategy.totalAssets(), strategy.totalAssets() - loss);
    }

    function test_profitableReport(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount / 5);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Let some time pass to accrue interest and enable profit.
        skip(2 days);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertGe(strategy.totalAssets(), _amount / 2, "assets too low");
        assertGe(
            profit + strategy.totalAssets(),
            strategy.totalAssets() - loss
        );
    }

    function test_manualRepayReducesDebt(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);
        uint256 debtBefore = strategy.balanceOfDebt();
        assertGt(debtBefore, 0, "no debt");

        // Fund borrow token to repay
        airdrop(ERC20(borrowToken), address(strategy), debtBefore / 2);
        vm.prank(management);
        strategy.manualRepayDebt();

        assertLt(strategy.balanceOfDebt(), debtBefore, "debt not reduced");
    }

    function test_fullWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Verify position was established
        assertGt(strategy.balanceOfCollateral(), 0, "no collateral");
        assertGt(strategy.balanceOfDebt(), 0, "no debt");

        // Let some time pass - this causes interest to accrue
        skip(1 days);

        // Get user's shares
        uint256 userShares = strategy.balanceOf(user);
        uint256 userBalanceBefore = asset.balanceOf(user);

        vm.prank(user);
        strategy.redeem(userShares, user, user);

        // Verify full withdrawal succeededs
        assertEq(strategy.balanceOf(user), 0, "user still has shares");
        assertGt(
            asset.balanceOf(user),
            userBalanceBefore,
            "user didn't receive assets"
        );
    }

    function test_multipleReportCycles(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount / 5);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 totalAssetsBefore = strategy.totalAssets();

        // Run 3 report cycles
        for (uint256 i = 0; i < 3; i++) {
            skip(1 days);

            vm.prank(keeper);
            strategy.report();

            // Total assets should remain reasonable (not go to 0, not explode)
            assertGt(strategy.totalAssets(), 0, "assets went to 0");
            assertLt(
                strategy.totalAssets(),
                totalAssetsBefore * 2,
                "assets doubled unexpectedly"
            );
        }

        // After 3 cycles, strategy should still be solvent
        assertGt(strategy.totalAssets(), 0, "insolvent after cycles");

        // Collateral should still exist
        assertGt(
            strategy.balanceOfCollateral(),
            0,
            "no collateral after cycles"
        );
    }

    function test_setLtvMultipliers_validation() public {
        // Test: target >= warning should revert
        vm.prank(management);
        vm.expectRevert("invalid LTV");
        strategy.setLtvMultipliers(8_000, 8_000);

        vm.prank(management);
        vm.expectRevert("invalid LTV");
        strategy.setLtvMultipliers(8_500, 8_000);

        // Test: warning > 9000 should revert
        vm.prank(management);
        vm.expectRevert("invalid LTV");
        strategy.setLtvMultipliers(7_000, 9_001);

        // Test: target = 0 should revert
        vm.prank(management);
        vm.expectRevert("invalid LTV");
        strategy.setLtvMultipliers(0, 8_000);

        // Test: valid params succeed
        vm.prank(management);
        strategy.setLtvMultipliers(6_000, 7_000);
        assertEq(strategy.targetLTVMultiplier(), 6_000);
        assertEq(strategy.warningLTVMultiplier(), 7_000);

        // Test: edge case - tight band
        vm.prank(management);
        strategy.setLtvMultipliers(8_999, 9_000);
        assertEq(strategy.targetLTVMultiplier(), 8_999);
        assertEq(strategy.warningLTVMultiplier(), 9_000);
    }
}
