pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_emergencyWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        vm.prank(management);
        (uint256 gain, ) = strategy.report();

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        checkStrategyTotals(strategy, _amount + gain, _amount + gain, 0);

        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);

        assertEq(ERC20(borrowToken).balanceOf(address(strategy)), 0);
        assertEq(strategy.balanceOfLentAssets(), 0);
        assertLt(strategy.balanceOfCollateral(), _amount + gain);

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_manualWithdraw_noShutdown(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        checkStrategyTotals(strategy, _amount, _amount, 0);

        uint256 ltv = strategy.getCurrentLTV();

        assertEq(ERC20(borrowToken).balanceOf(address(strategy)), 0);
        assertRelApproxEq(strategy.getCurrentLTV(), ltv, 10);

        uint256 balance = strategy.balanceOfLentAssets();

        vm.expectRevert("!emergency authorized");
        vm.prank(user);
        strategy.manualWithdraw(address(borrowToken), balance);

        vm.prank(management);
        strategy.manualWithdraw(address(borrowToken), balance);

        assertEq(strategy.balanceOfLentAssets(), 0);
        assertEq(ERC20(borrowToken).balanceOf(address(strategy)), balance);
        assertRelApproxEq(strategy.getCurrentLTV(), ltv, 10);

        vm.expectRevert("!emergency authorized");
        vm.prank(user);
        strategy.claimAndSellRewards();

        vm.prank(management);
        strategy.claimAndSellRewards();

        vm.expectRevert("!emergency authorized");
        vm.prank(user);
        strategy.manualRepayDebt();

        vm.prank(management);
        strategy.manualRepayDebt();

        assertEq(strategy.balanceOfLentAssets(), 0);
        assertEq(ERC20(borrowToken).balanceOf(address(strategy)), 0);
        assertEq(strategy.getCurrentLTV(), 0);

        // Set the LTV to 1 so it doesn't lever up
        vm.startPrank(management);
        strategy.setLtvMultipliers(1, strategy.warningLTVMultiplier());
        vm.stopPrank();

        vm.prank(management);
        strategy.tend();

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw par of the funds
        vm.prank(user);
        strategy.redeem(_amount / 2, user, user);

        assertRelApproxEq(
            asset.balanceOf(user),
            balanceBefore + (_amount / 2),
            10
        );
    }

    function test_sweep(uint256 _amount) public {
        address gov = strategy.GOV();
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        airdrop(asset, address(strategy), _amount);
        // Airdrop extra base token to deposit
        airdrop(ERC20(borrowToken), address(strategy), _amount * 2);

        vm.expectRevert();
        vm.prank(user);
        strategy.sweep(borrowToken);

        vm.expectRevert();
        vm.prank(management);
        strategy.sweep(borrowToken);

        // Sweep Base token
        uint256 beforeBalance = ERC20(borrowToken).balanceOf(gov);

        vm.prank(gov);
        strategy.sweep(borrowToken);

        assertEq(
            ERC20(borrowToken).balanceOf(gov),
            beforeBalance + _amount,
            "base swept"
        );

        // Cant sweep asset
        vm.expectRevert("!asset");
        vm.prank(gov);
        strategy.sweep(address(asset));
    }

    // TODO: Add tests for any emergency function added.
}
