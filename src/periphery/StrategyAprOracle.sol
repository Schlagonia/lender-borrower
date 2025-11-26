// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {AprOracle} from "@periphery/AprOracle/AprOracle.sol";
import {MorphoBlueLenderBorrower} from "../MorphoBlueLenderBorrower.sol";
import {IMorpho, Id, Market, MarketParams} from "../interfaces/morpho/IMorpho.sol";
import {IOracle} from "../interfaces/morpho/IOracle.sol";
import {IIrm} from "../interfaces/morpho/IIrm.sol";
import {MorphoBalancesLib} from "../libraries/morpho/periphery/MorphoBalancesLib.sol";
import {Governance} from "@periphery/utils/Governance.sol";

interface IRewardAprOracle {
    function borrowRewardApr(Id _id) external view returns (uint256);
}

contract StrategyAprOracle is Governance {
    using MorphoBalancesLib for IMorpho;

    uint256 internal constant SECONDS_PER_YEAR = 31_556_952;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;
    AprOracle internal constant APR_ORACLE =
        AprOracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92);

    mapping(address => address) public rewardAprOracles;

    constructor(address _governance) Governance(_governance) {}

    function setRewardAprOracle(
        address _strategy,
        address _rewardAprOracle
    ) external onlyGovernance {
        rewardAprOracles[_strategy] = _rewardAprOracle;
    }

    /**
     * @notice Expected APR after a debt change. Positive _delta means more debt (assets) to the strategy.
     * @param _strategy The strategy to evaluate.
     * @param _delta Debt change in terms of strategy asset (ignored for this simple approximation).
     * @return apr The expected net APR in 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view returns (uint256 apr) {
        MorphoBlueLenderBorrower strat = MorphoBlueLenderBorrower(_strategy);
        int256 borrowDelta = _borrowDelta(strat, _delta);
        uint256 borrowApr = _borrowApr(strat);

        // Reward APR from the lender vault (borrow token APR).
        uint256 rewardApr = APR_ORACLE.getStrategyApr(
            address(strat.lenderVault()),
            borrowDelta
        );

        // Include external rewardApr oracle if set.
        if (strat.rewardAprOracle() != address(0)) {
            address rewardAprOracle = rewardAprOracles[address(strat)];
            if (rewardAprOracle != address(0)) {
                rewardApr += IRewardAprOracle(rewardAprOracle).borrowRewardApr(
                    strat.marketId()
                );
            }
        }

        // Net APR, floor at 0 to avoid underflow for unprofitable positions.
        apr = rewardApr >= borrowApr ? rewardApr - borrowApr : 0;
    }

    function _borrowDelta(
        MorphoBlueLenderBorrower strat,
        int256 deltaAsset
    ) internal view returns (int256) {
        if (deltaAsset == 0) return 0;

        // target LTV = liqCF (1e18) * multiplier (bps) / 1e4
        uint256 targetLtv = (strat.getLiquidateCollateralFactor() *
            strat.targetLTVMultiplier()) / 10_000;

        int256 assetAtTarget = (deltaAsset * int256(targetLtv)) / int256(WAD);

        // Convert asset amount to borrow token via Morpho oracle price (loan per collateral, 1e36).
        (, , address oracleAddr, , ) = strat.marketParams();
        uint256 price = IOracle(oracleAddr).price(); // 1e36
        if (price == 0) return 0;

        return (assetAtTarget * int256(price)) / int256(ORACLE_PRICE_SCALE);
    }

    function _borrowApr(
        MorphoBlueLenderBorrower strat
    ) internal view returns (uint256) {
        (
            address loanToken,
            address collateralToken,
            address oracleAddr,
            address irmAddr,
            uint256 lltv
        ) = strat.marketParams();
        MarketParams memory params = MarketParams({
            loanToken: loanToken,
            collateralToken: collateralToken,
            oracle: oracleAddr,
            irm: irmAddr,
            lltv: lltv
        });

        // Accrued market balances for accurate rate calc.
        (uint256 tsa, uint256 tss, uint256 tba, uint256 tbs) = strat
            .morpho()
            .expectedMarketBalances(params);
        Market memory market = strat.morpho().market(strat.marketId());
        market.totalSupplyAssets = uint128(tsa);
        market.totalSupplyShares = uint128(tss);
        market.totalBorrowAssets = uint128(tba);
        market.totalBorrowShares = uint128(tbs);

        uint256 borrowRatePerSec = IIrm(params.irm).borrowRateView(
            params,
            market
        );
        return borrowRatePerSec * SECONDS_PER_YEAR;
    }
}
