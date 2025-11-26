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
}
