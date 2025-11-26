// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {ILenderBorrower} from "./ILenderBorrower.sol";
import {IMorpho} from "./morpho/IMorpho.sol";
import {Id, MarketParams} from "./morpho/IMorpho.sol";

interface IStrategyInterface is IStrategy, ILenderBorrower {
    //TODO: Add your specific implementation interface in here.

    function GOV() external view returns (address);

    function sweep(address _token) external;

    // Morpho-specific views
    function morpho() external view returns (IMorpho);

    function marketId() external view returns (Id);

    function marketParams() external view returns (address, address, address, address, uint256);

    function rewardAprOracle() external view returns (address);

    function lenderVault() external view returns (address);

    function base() external view returns (address);

    function router() external view returns (address);

    // Morpho-specific management setters
    function setRewardAprOracle(address _oracle) external;

    function setUsdOracles(address _assetUsdOracle, address _borrowUsdOracle) external;

    function setUniFees(address _token0, address _token1, uint24 _fee) external;

    function setUniBase(address _base) external;

    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function setAuction(address _auction) external;

    function setUseAuction(bool _useAuction) external;
}
