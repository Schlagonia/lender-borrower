// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {AprOracle} from "@periphery/AprOracle/AprOracle.sol";
import {CErc20I} from "../interfaces/compound/CErc20I.sol";
import {InterestRateModel} from "../interfaces/compound/InterestRateModel.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {IMultiRewardDistributor} from "../interfaces/compound/IMultiRewardDistributor.sol";
import {ComptrollerI} from "../interfaces/compound/ComptrollerI.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CompoundOracleI} from "../interfaces/compound/CompoundOracleI.sol";

contract MoonwellLenderBorrowerAprOracle {
    uint256 internal constant MAX_BPS = 10000;
    AprOracle internal constant APR_ORACLE =
        AprOracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92);

    uint256 internal constant SECONDS_PER_YEAR = 60 * 60 * 24 * 365;

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return . The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view virtual returns (uint256) {
        uint256 supplyRate = getNetSupplyRate(_strategy, _delta);

        uint256 targetLTV = (IStrategyInterface(_strategy)
            .getLiquidateCollateralFactor() *
            IStrategyInterface(_strategy).targetLTVMultiplier()) / MAX_BPS;
        int256 borrowDelta = (_delta * int256(targetLTV)) / 1e18;

        int256 borrowRate = getNetBorrowRate(_strategy, borrowDelta);

        uint256 lendRate = APR_ORACLE.getStrategyApr(
            IStrategyInterface(_strategy).lenderVault(),
            borrowDelta
        );

        return uint256(int256(supplyRate + lendRate) - borrowRate);
    }

    function getNetSupplyRate(
        address _strategy,
        int256 _delta
    ) public view returns (uint256) {
        CErc20I _cToken = CErc20I(IStrategyInterface(_strategy).cToken());
        uint256 supplyRate = _getSupplyRatePerSec(_cToken, _delta);
        uint256 rewardSupplyRate = _getRewardSupplyRate(
            _strategy,
            _cToken,
            _delta
        );

        return supplyRate * SECONDS_PER_YEAR + rewardSupplyRate;
    }

    function getNetBorrowRate(
        address _strategy,
        int256 _delta
    ) public view returns (int256) {
        CErc20I _cToken = CErc20I(IStrategyInterface(_strategy).cBorrowToken());
        uint256 borrowRate = _getBorrowRatePerSec(_cToken, _delta);
        uint256 rewardBorrowRate = _getRewardBorrowRate(
            _strategy,
            _cToken,
            _delta
        );

        return int256(borrowRate * SECONDS_PER_YEAR) - int256(rewardBorrowRate);
    }

    function _getSupplyRatePerSec(
        CErc20I _cToken,
        int256 _delta
    ) internal view virtual returns (uint256 _supplyRatePerSec) {
        InterestRateModel irm = InterestRateModel(_cToken.interestRateModel());

        _supplyRatePerSec = irm.getSupplyRate(
            uint256(int256(_cToken.getCash()) + _delta),
            _cToken.totalBorrows(),
            _cToken.totalReserves(),
            _cToken.reserveFactorMantissa()
        );
    }

    function _getBorrowRatePerSec(
        CErc20I _cToken,
        int256 _delta
    ) internal view virtual returns (uint256) {
        InterestRateModel irm = InterestRateModel(_cToken.interestRateModel());

        return
            irm.getBorrowRate(
                uint256(int256(_cToken.getCash()) - _delta),
                uint256(int256(_cToken.totalBorrows()) + _delta),
                _cToken.totalReserves()
            );
    }

    function _getRewardSupplyRate(
        address _strategy,
        CErc20I _cToken,
        int256 _delta
    ) internal view virtual returns (uint256) {
        IMultiRewardDistributor.MarketConfig[]
            memory configs = IMultiRewardDistributor(
                ComptrollerI(_cToken.comptroller()).rewardDistributor()
            ).getAllMarketConfigs(address(_cToken));

        uint256 rewardRatePerSec = 0;
        for (uint256 i = 0; i < configs.length; i++) {
            if (
                configs[i].supplyEmissionsPerSec > 0 &&
                configs[i].endTime > block.timestamp
            ) {
                rewardRatePerSec += _toUSD(
                    _strategy,
                    configs[i].supplyEmissionsPerSec,
                    configs[i].emissionToken
                );
            }
        }

        return
            (_fromUsd(
                _strategy,
                rewardRatePerSec,
                IStrategyInterface(_strategy).asset()
            ) *
                SECONDS_PER_YEAR *
                1e18) /
            uint256(
                int256(
                    _cToken.getCash() +
                        _cToken.totalBorrows() -
                        _cToken.totalReserves()
                ) + _delta
            );
    }

    function _getRewardBorrowRate(
        address _strategy,
        CErc20I _cToken,
        int256 _delta
    ) internal view virtual returns (uint256) {
        IMultiRewardDistributor.MarketConfig[]
            memory configs = IMultiRewardDistributor(
                ComptrollerI(_cToken.comptroller()).rewardDistributor()
            ).getAllMarketConfigs(address(_cToken));

        uint256 rewardRatePerSec = 0;
        for (uint256 i = 0; i < configs.length; i++) {
            if (
                configs[i].borrowEmissionsPerSec > 0 &&
                configs[i].endTime > block.timestamp
            ) {
                rewardRatePerSec += _toUSD(
                    _strategy,
                    configs[i].borrowEmissionsPerSec,
                    configs[i].emissionToken
                );
            }
        }

        return
            (_fromUsd(
                _strategy,
                rewardRatePerSec,
                IStrategyInterface(_strategy).borrowToken()
            ) *
                SECONDS_PER_YEAR *
                1e18) / uint256(int256(_cToken.totalBorrows()) + _delta);
    }

    function _toUSD(
        address _strategy,
        uint256 _amount,
        address _emissionToken
    ) internal view returns (uint256) {
        return
            (_amount * _getPrice(_strategy, _emissionToken)) /
            (10 ** ERC20(_emissionToken).decimals());
    }

    function _fromUsd(
        address _strategy,
        uint256 _amount,
        address _token
    ) internal view virtual returns (uint256) {
        if (_amount == 0) return 0;
        unchecked {
            return
                (_amount * (10 ** ERC20(_token).decimals())) /
                _getPrice(_strategy, _token);
        }
    }

    function _getPrice(
        address _strategy,
        address _token
    ) internal view returns (uint256) {
        address priceFeed = IStrategyInterface(_strategy)
            .tokenInfo(_token)
            .priceFeed;
        if (priceFeed != address(0)) {
            return uint256(IOracle(priceFeed).latestAnswer());
        }

        uint256 decimalDelta = 1e18 / (10 ** ERC20(_token).decimals());
        // Compound oracle expects the token to be the cToken
        if (_token == IStrategyInterface(_strategy).asset()) {
            _token = IStrategyInterface(_strategy).cToken();
        } else if (_token == IStrategyInterface(_strategy).borrowToken()) {
            _token = IStrategyInterface(_strategy).cBorrowToken();
        }

        return
            CompoundOracleI(
                ComptrollerI(IStrategyInterface(_strategy).comptroller())
                    .oracle()
            ).getUnderlyingPrice(_token) / (1e10 * decimalDelta);
    }
}
