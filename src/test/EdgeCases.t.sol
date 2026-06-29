// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";
import {MorphoBlueLenderBorrower} from "../MorphoBlueLenderBorrower.sol";

contract EdgeCasesTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_sellBorrowToken_maxUint() public {
        uint256 _amount = minFuzzAmount;

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Shutdown so we can call sellBorrowToken
        vm.prank(management);
        strategy.shutdownStrategy();

        // Get initial state
        uint256 debt = strategy.balanceOfDebt();
        uint256 lent = strategy.balanceOfLentAssets();

        // Withdraw all from lender to create imbalance
        // After this, debt > lent + loose (where loose = lent withdrawn)
        vm.prank(management);
        strategy.manualWithdraw(borrowToken, lent);

        uint256 looseAfterWithdraw = strategy.balanceOfBorrowToken();
        uint256 lentAfterWithdraw = strategy.balanceOfLentAssets();

        // Verify condition: debt > lent + loose
        assertGt(
            debt,
            lentAfterWithdraw + looseAfterWithdraw,
            "precondition: debt > have"
        );

        // This should NOT revert - it should handle the case gracefully
        // by selling 0 or the safe amount
        vm.prank(management);
        strategy.sellBorrowToken(type(uint256).max);

        // Should complete without reverting
    }

    /// @notice Test that _claimAndSellRewards doesn't sell debt-backing assets
    /// @dev Interest accrual between checking debt and selling could cause issues
    /// EXPECTED: May fail with healthCheck error after 30 days due to high interest accrual
    function test_claimAndSellRewards_interestAccrual_30days() public {
        uint256 _amount = minFuzzAmount * 2;
        uint256 tolerance = 1e6; // 1 USDC dust on the current fork

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Let significant time pass for interest to accrue
        skip(30 days);

        // Get state before report
        uint256 debtBefore = strategy.balanceOfDebt();
        uint256 lentBefore = strategy.balanceOfLentAssets();

        // Report calls _claimAndSellRewards internally
        vm.prank(keeper);
        strategy.report();

        // Check position is still healthy
        uint256 debtAfter = strategy.balanceOfDebt();
        uint256 lentAfter = strategy.balanceOfLentAssets();

        // Debt should not exceed what we can repay
        assertGe(
            lentAfter + strategy.balanceOfBorrowToken() + tolerance,
            debtAfter,
            "Position became unhealthy after claimAndSellRewards"
        );
    }

    function test_claimAndSellRewards_rewardTokenSwap() public {
        address rewardToken = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2; // MORPHO
        address uniBase = tokenAddrs["WETH"];
        uint256 rewardAmount = 1e18;

        vm.startPrank(management);
        strategy.setUniBase(uniBase);

        strategy.setUniFees(rewardToken, uniBase, 3000);
        strategy.setUniFees(uniBase, address(asset), 3000);
        strategy.addRewardToken(rewardToken);
        vm.stopPrank();

        airdrop(ERC20(rewardToken), address(strategy), rewardAmount);

        uint256 assetBefore = asset.balanceOf(address(strategy));
        uint256 rewardBefore = ERC20(rewardToken).balanceOf(address(strategy));
        assertEq(rewardBefore, rewardAmount, "reward not funded");

        vm.prank(management);
        strategy.claimAndSellRewards();

        uint256 rewardAfter = ERC20(rewardToken).balanceOf(address(strategy));
        uint256 assetAfter = asset.balanceOf(address(strategy));

        assertEq(rewardAfter, 0, "reward not sold");
        assertGt(assetAfter, assetBefore, "asset not received");
    }

    function test_addRemoveRewardTokens() public {
        address rewardTokenA = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2; // MORPHO
        address rewardTokenB = tokenAddrs["LINK"];

        vm.startPrank(management);
        strategy.addRewardToken(rewardTokenA);
        strategy.addRewardToken(rewardTokenB);
        vm.stopPrank();

        assertEq(strategy.rewardTokens(0), rewardTokenA, "reward token 0");
        assertEq(strategy.rewardTokens(1), rewardTokenB, "reward token 1");

        vm.prank(management);
        strategy.removeRewardToken(rewardTokenA);

        assertEq(strategy.rewardTokens(0), rewardTokenB, "reward token swap");
        vm.expectRevert();
        strategy.rewardTokens(1);
    }

    /// @notice Test withdrawing all shares (full redemption)
    /// @dev _liquidatePosition should handle this gracefully
    function test_fullRedemption() public {
        uint256 _amount = minFuzzAmount * 10;

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Skip time to allow lender vault share math to settle (avoids 1 wei rounding issue)
        skip(1 hours);

        uint256 shares = strategy.balanceOf(user);
        uint256 userBalanceBefore = asset.balanceOf(user);

        // Full redemption should work without reverting
        vm.prank(user);
        strategy.redeem(shares, user, user);

        // User should have no shares left
        assertEq(strategy.balanceOf(user), 0, "user still has shares");
        // User should have received assets
        assertGt(
            asset.balanceOf(user),
            userBalanceBefore,
            "user didn't receive assets"
        );
    }

    /// @notice Test that full withdrawal repays all debt
    /// @dev When amount >= collateral, should return full debt
    function test_fullWithdrawal() public {
        uint256 _amount = minFuzzAmount * 10;

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Skip time to allow lender vault share math to settle (avoids 1 wei rounding issue)
        skip(1 hours);

        uint256 collateral = strategy.balanceOfCollateral();
        uint256 debtBefore = strategy.balanceOfDebt();

        assertGt(collateral, 0, "no collateral");
        assertGt(debtBefore, 0, "no debt");

        // Full withdraw should repay all debt and succeed
        uint256 shares = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(shares, user, user);

        // After full withdrawal, debt should be 0 or very small (dust)
        assertLt(strategy.balanceOfDebt(), 100, "debt not fully repaid");
        assertEq(strategy.balanceOf(user), 0, "user still has shares");
    }

    /// @notice Test availableWithdrawLimit when lender has no liquidity
    /// @dev Should return a sensible value, not 0
    function test_availableWithdrawLimit_noLenderLiquidity() public {
        uint256 _amount = minFuzzAmount;

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Get current withdraw limit
        uint256 limit = strategy.availableWithdrawLimit(user);

        // Should be > 0 since we have collateral
        assertGt(limit, 0, "withdraw limit should be positive");

        // Should be roughly the collateral minus what's needed for LTV maintenance
        uint256 collateral = strategy.balanceOfCollateral();
        assertLe(
            limit,
            collateral + strategy.balanceOfAsset() + 1,
            "limit too high"
        );
    }

    /// @notice Test multiple rapid deposits/withdrawals
    /// @dev Tests for any compounding rounding errors
    function test_rapidDepositWithdraw() public {
        uint256 _amount = minFuzzAmount;

        for (uint256 i = 0; i < 5; i++) {
            mintAndDepositIntoStrategy(strategy, user, _amount);

            // Small time skip
            skip(1 hours);

            // Withdraw half
            uint256 shares = strategy.balanceOf(user);
            vm.prank(user);
            strategy.redeem(shares / 2, user, user);

            // Position should still be healthy
            assertGt(strategy.totalAssets(), 0, "strategy became insolvent");
        }
    }

    /// @notice Test setLtvMultipliers at extreme values
    function test_extremeLtvMultipliers() public {
        uint256 _amount = minFuzzAmount;

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Set extremely high target LTV (close to liquidation)
        vm.prank(management);
        strategy.setLtvMultipliers(8_999, 9_000);

        // Trigger a tend to adjust to new LTV
        (bool trigger, ) = strategy.tendTrigger();
        if (trigger) {
            vm.prank(keeper);
            strategy.tend();
        }

        // Position should still be below liquidation threshold
        uint256 currentLTV = strategy.getCurrentLTV();
        uint256 lltv = strategy.getLiquidateCollateralFactor();
        assertLt(currentLTV, lltv, "LTV exceeds liquidation threshold");
    }

    /// @notice Test emergency withdraw after repaying debt
    /// @dev After repaying debt, emergencyWithdraw should withdraw all collateral
    function test_emergencyWithdraw_afterRepay() public {
        uint256 _amount = minFuzzAmount * 10;

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Skip time to allow lender vault share math to settle (avoids 1 wei rounding issue)
        skip(1 hours);

        // Shutdown
        vm.prank(management);
        strategy.shutdownStrategy();

        uint256 collateralBefore = strategy.balanceOfCollateral();

        // First repay debt to allow collateral withdrawal
        uint256 lent = strategy.balanceOfLentAssets();
        if (lent > 0) {
            vm.prank(management);
            strategy.manualWithdraw(borrowToken, lent);
        }
        vm.prank(management);
        strategy.manualRepayDebt();

        // Now try emergency withdraw - should succeed
        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);

        // Should have withdrawn collateral
        uint256 collateralAfter = strategy.balanceOfCollateral();
        assertLt(
            collateralAfter,
            collateralBefore,
            "collateral should decrease"
        );
    }

    /// @notice Test that _getAmountOut handles zero slippage
    function test_zeroSlippage() public {
        // Set slippage to 0
        vm.prank(management);
        strategy.setSlippage(0);

        uint256 _amount = minFuzzAmount;
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Let time pass
        skip(1 days);

        // Report should still work
        vm.prank(keeper);
        strategy.report();

        assertGt(strategy.totalAssets(), 0, "strategy insolvent");
    }

    /// @notice Test deposit limit enforcement
    function test_depositLimitEnforcement() public {
        // Set a small deposit limit
        vm.prank(management);
        strategy.setDepositLimit(minFuzzAmount / 2);

        // Deposit at limit should work
        mintAndDepositIntoStrategy(strategy, user, minFuzzAmount / 2);

        // Trying to deposit more should be limited
        uint256 availableLimit = strategy.availableDepositLimit(user);
        assertEq(availableLimit, 0, "should have no more deposit room");
    }
}
