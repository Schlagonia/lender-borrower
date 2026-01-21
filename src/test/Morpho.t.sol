// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";
import {MorphoBlueLenderBorrower} from "../MorphoBlueLenderBorrower.sol";
import {IMorpho, Position, Market, MarketParams} from "../interfaces/morpho/IMorpho.sol";
import {IOracle} from "../interfaces/morpho/IOracle.sol";
import {IChainlinkAggregator} from "../interfaces/IChainlinkAggregator.sol";

contract MorphoTest is Setup {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;

    function setUp() public virtual override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                        MORPHO INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_morphoPositionCreated(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        IMorpho morphoInstance = strategy.morpho();
        Position memory pos = morphoInstance.position(
            strategy.marketId(),
            address(strategy)
        );

        assertGt(pos.collateral, 0, "collateral in morpho");
        assertGt(pos.borrowShares, 0, "borrow shares in morpho");
    }

    function test_morphoCollateralSupply(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Collateral in strategy should match Morpho position
        uint256 strategyCollateral = strategy.balanceOfCollateral();

        IMorpho morphoInstance = strategy.morpho();
        Position memory pos = morphoInstance.position(
            strategy.marketId(),
            address(strategy)
        );

        assertEq(strategyCollateral, pos.collateral, "collateral mismatch");
    }

    function test_morphoBorrowingWorks(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Verify we have borrowed tokens in lender vault
        uint256 lentAssets = strategy.balanceOfLentAssets();
        assertGt(lentAssets, 0, "should have lent borrowed tokens");

        // Verify debt matches what we borrowed
        uint256 debt = strategy.balanceOfDebt();
        assertGt(debt, 0, "should have debt");

        // Lent should be approximately equal to debt
        assertApproxEq(lentAssets, debt, debt / 10, "lent ~= debt");
    }

    function test_morphoRepayWorks(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 debtBefore = strategy.balanceOfDebt();

        // Airdrop borrow token and repay manually
        uint256 repayAmount = debtBefore / 3;
        airdrop(ERC20(borrowToken), address(strategy), repayAmount);

        vm.prank(management);
        strategy.manualRepayDebt();

        uint256 debtAfter = strategy.balanceOfDebt();
        assertLt(debtAfter, debtBefore, "debt should decrease");
    }

    function test_morphoWithdrawCollateralWorks(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 collateralBefore = strategy.balanceOfCollateral();
        uint256 assetBalanceBefore = strategy.balanceOfAsset();

        // Withdraw half (small enough to maintain healthy LTV)
        uint256 withdrawAmount = _amount / 3;

        vm.prank(user);
        strategy.withdraw(withdrawAmount, user, user);

        // After withdrawal, collateral should have decreased
        uint256 collateralAfter = strategy.balanceOfCollateral();
        assertLt(
            collateralAfter,
            collateralBefore,
            "collateral should decrease"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_morphoOraclePrice() public {
        (, , address oracleAddr, , ) = strategy.marketParams();

        uint256 price = IOracle(oracleAddr).price();

        // Price should be > 0 and reasonable (in 1e36 scale)
        assertGt(price, 0, "oracle price should be positive");

        // For BTC/USDC market, price should be roughly BTC_PRICE * 1e36 / 1e8 (adjusting for decimals)
        // At ~$90k BTC, this would be around 9e40 to 1e41
        assertGt(price, 1e38, "price seems too low for BTC");
        assertLt(price, 1e42, "price seems too high");
    }

    function test_ltvMatchesOraclePricing(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 collateral = strategy.balanceOfCollateral();
        uint256 debt = strategy.balanceOfDebt();
        assertGt(collateral, 0, "no collateral");
        assertGt(debt, 0, "no debt");

        (, , address oracleAddr, , ) = strategy.marketParams();
        uint256 ratio = IOracle(oracleAddr).price(); // loan per collateral, 1e36 scale
        assertGt(ratio, 0, "oracle price should be positive");

        address loanToken = strategy.borrowToken();
        uint256 loanScale = uint256(10 ** ERC20(loanToken).decimals());

        address borrowOracle = MorphoBlueLenderBorrower(address(strategy))
            .borrowUsdOracle();
        int256 answer = IChainlinkAggregator(borrowOracle).latestAnswer();
        assertGt(answer, 0, "borrow usd oracle");
        uint256 borrowUsd = uint256(answer); // 1e8

        // Compute LTV using Morpho oracle spec with decimals normalization.
        uint256 collateralInLoan = (collateral * ratio) / ORACLE_PRICE_SCALE;
        uint256 collateralUsd = (collateralInLoan * borrowUsd) / loanScale;
        uint256 debtUsd = (debt * borrowUsd) / loanScale;
        uint256 expectedLTV = (debtUsd * WAD) / collateralUsd;

        uint256 currentLTV = strategy.getCurrentLTV();
        assertApproxEq(
            currentLTV,
            expectedLTV,
            expectedLTV / 20,
            "ltv mismatch"
        );
    }

    function test_isLiquidatable_false(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // With default LTV settings, should not be liquidatable
        // _isLiquidatable is internal, but we can check tendTrigger behavior
        uint256 currentLTV = strategy.getCurrentLTV();
        uint256 lltv = strategy.getLiquidateCollateralFactor();

        assertLt(currentLTV, lltv, "should be below liquidation threshold");
    }

    /*//////////////////////////////////////////////////////////////
                        MARKET PARAMETERS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_marketParams_correctTokens() public {
        (address loanToken, address collateralToken, , , ) = strategy
            .marketParams();

        assertEq(loanToken, borrowToken, "loan token should be borrow token");
        assertEq(collateralToken, address(asset), "collateral should be asset");
    }

    function test_marketParams_validLLTV() public {
        (, , , , uint256 lltv) = strategy.marketParams();

        // LLTV should be between 50% and 95%
        assertGt(lltv, 5e17, "LLTV too low");
        assertLt(lltv, 95e16, "LLTV too high");

        // LLTV from marketParams should match getLiquidateCollateralFactor
        assertEq(
            lltv,
            strategy.getLiquidateCollateralFactor(),
            "LLTV mismatch"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTEREST ACCRUAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_debtIncreasesOverTime(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 debtBefore = strategy.balanceOfDebt();

        // Skip time to accrue interest
        skip(30 days);

        uint256 debtAfter = strategy.balanceOfDebt();

        // Debt should have increased due to interest
        assertGt(debtAfter, debtBefore, "debt should increase over time");
    }

    function test_lentAssetsIncreaseOverTime(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 lentBefore = strategy.balanceOfLentAssets();

        // Skip time for lender vault to accrue yield
        skip(30 days);

        uint256 lentAfter = strategy.balanceOfLentAssets();

        // Lent assets should have increased due to yield
        assertGe(lentAfter, lentBefore, "lent assets should not decrease");
    }

    /*//////////////////////////////////////////////////////////////
                        MAX BORROW/DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_availableDepositLimit(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        uint256 limitBefore = strategy.availableDepositLimit(user);
        assertGt(limitBefore, 0, "should have deposit room initially");

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 limitAfter = strategy.availableDepositLimit(user);
        // Limit should decrease after deposit
        assertLt(
            limitAfter,
            limitBefore,
            "limit should decrease after deposit"
        );
    }

    function test_availableWithdrawLimit(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        uint256 limitBefore = strategy.availableWithdrawLimit(user);
        // Initially should have some limit (at least 1 for rounding)
        assertGe(limitBefore, 1, "should have minimal withdraw room");

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 limitAfter = strategy.availableWithdrawLimit(user);
        assertGt(limitAfter, 0, "should have withdraw room after deposit");

        // Limit should be roughly the collateral minus what's locked for LTV
        uint256 collateral = strategy.balanceOfCollateral();
        assertLe(
            limitAfter,
            collateral + strategy.balanceOfAsset() + 1,
            "limit too high"
        );
    }
}
