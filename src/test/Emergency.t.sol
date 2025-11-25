// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";
import {MorphoBlueLenderBorrower} from "../MorphoBlueLenderBorrower.sol";

contract EmergencyTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_manualRepayAfterShutdown(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount / 10);

        mintAndDepositIntoStrategy(strategy, user, _amount);
        assertGt(strategy.balanceOfDebt(), 0, "no debt");

        vm.prank(management);
        strategy.shutdownStrategy();

        // Repay outstanding debt.
        uint256 debt = strategy.balanceOfDebt();
        airdrop(ERC20(borrowToken), address(strategy), debt + 10);
        vm.prank(management);
        strategy.manualRepayDebt();

        // Ensure debt is cleared post repay; collateral may remain if withdraw restricted.
        assertEq(strategy.balanceOfDebt(), 0, "debt left");
    }

    function test_sellBorrowTokenEmergencyOnly(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount / 10);

        mintAndDepositIntoStrategy(strategy, user, _amount);
        vm.prank(management);
        strategy.shutdownStrategy();

        // Repay debt first.
        uint256 debt = strategy.balanceOfDebt();
        airdrop(ERC20(borrowToken), address(strategy), debt + _amount / 4);
        vm.prank(management);
        strategy.manualRepayDebt();

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
}
