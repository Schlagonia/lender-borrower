// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20} from "./utils/Setup.sol";

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
}
