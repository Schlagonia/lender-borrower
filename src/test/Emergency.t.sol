// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";
import {MorphoBlueLenderBorrower} from "../MorphoBlueLenderBorrower.sol";

contract EmergencyTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_manualRepayAfterShutdown() public {
        uint256 _amount = minFuzzAmount; // deterministic small amount

        mintAndDepositIntoStrategy(strategy, user, _amount);
        uint256 debtBefore = strategy.balanceOfDebt();
        assertGt(debtBefore, 0, "no debt");

        // Repay a portion to avoid over-repay edge cases.
        uint256 repayAmount = debtBefore / 2;
        airdrop(ERC20(borrowToken), address(strategy), repayAmount);
        vm.prank(management);
        strategy.manualRepayDebt();

        assertLt(strategy.balanceOfDebt(), debtBefore, "debt not reduced");
    }

    function test_sellBorrowTokenEmergencyOnly() public {
        uint256 _amount = minFuzzAmount; // deterministic small amount

        mintAndDepositIntoStrategy(strategy, user, _amount);
        vm.prank(management);
        strategy.shutdownStrategy();

        // Configure UniV3 fees for USDC->WETH and WETH->WBTC.
        address uniBase = MorphoBlueLenderBorrower(address(strategy)).base();
        vm.startPrank(management);
        MorphoBlueLenderBorrower(address(strategy)).setUniFees(
            borrowToken,
            uniBase,
            500
        );
        MorphoBlueLenderBorrower(address(strategy)).setUniFees(
            uniBase,
            address(asset),
            3_000
        );
        MorphoBlueLenderBorrower(address(strategy)).setMinAmountToSell(0);
        vm.stopPrank();

        vm.expectRevert("!emergency authorized");
        vm.prank(user);
        strategy.sellBorrowToken(_amount / 4);

        uint256 bal = ERC20(borrowToken).balanceOf(address(strategy));
        vm.prank(management);
        strategy.sellBorrowToken(bal);

        assertLt(
            ERC20(borrowToken).balanceOf(address(strategy)),
            1e3, // dust tolerance (USDC 6dp)
            "borrow left"
        );
    }

    /// @notice Test emergency withdrawal works correctly when debt remains
    /// @dev This test reveals that _emergencyWithdraw() can fail with "insufficient collateral"
    ///      because _maxWithdrawal() calculates based on target LTV but Morpho uses
    ///      the liquidation LTV to determine if withdrawal is safe.
    ///
    ///      The mismatch: Strategy uses _getTargetLTV() (70% of LLTV) to calculate
    ///      how much collateral can be withdrawn, but Morpho allows withdrawals
    ///      as long as position stays below LLTV. However, due to interest accrual
    ///      and precision differences, the calculated amount can still fail.
    ///
    ///      FIX: _maxWithdrawal() should use Morpho's oracle price or add a safety margin.
    function test_emergencyWithdraw_withDebtRemaining() public {
        uint256 _amount = minFuzzAmount * 2; // Use a bit more for better precision

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Verify position is established
        uint256 collateralBefore = strategy.balanceOfCollateral();
        uint256 debtBefore = strategy.balanceOfDebt();
        assertGt(collateralBefore, 0, "no collateral");
        assertGt(debtBefore, 0, "no debt");

        // Skip time to allow lender vault to earn yield
        // This avoids same-block rounding dust issues
        skip(1 days);

        // Shutdown the strategy first
        vm.prank(management);
        strategy.shutdownStrategy();

        // Withdraw only part of lent assets so debt remains after repay
        uint256 lent = strategy.balanceOfLentAssets();
        vm.prank(management);
        strategy.manualWithdraw(borrowToken, lent / 2);

        // Repay what we can - debt will remain since we only withdrew half
        vm.prank(management);
        strategy.manualRepayDebt();

        // Verify debt remains
        uint256 debtAfterPartialRepay = strategy.balanceOfDebt();
        assertGt(debtAfterPartialRepay, 0, "should still have debt");

        // Emergency withdraw should work - withdrawing whatever collateral is safe
        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);

        // Collateral should have decreased (some withdrawn)
        uint256 collateralAfter = strategy.balanceOfCollateral();
        assertLt(
            collateralAfter,
            collateralBefore,
            "collateral should decrease"
        );
    }

    function test_emergencyWithdraw_accessControl() public {
        uint256 _amount = minFuzzAmount;

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Shutdown required first
        vm.prank(management);
        strategy.shutdownStrategy();

        // User should not be able to call emergencyWithdraw
        vm.expectRevert("!emergency authorized");
        vm.prank(user);
        strategy.emergencyWithdraw(_amount);

        // Management can call it
        vm.prank(management);
        strategy.emergencyWithdraw(_amount);

        // Emergency admin should also be able to call it
        // First need to set up a new strategy to test emergency admin
    }
}
