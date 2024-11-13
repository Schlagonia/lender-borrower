// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IAeroRouter} from "./Aero/IAeroRouter.sol";
import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {ILenderBorrower} from "./ILenderBorrower.sol";

interface IStrategyInterface is IStrategy, ILenderBorrower, IBaseHealthCheck {
    struct TokenInfo {
        address priceFeed;
        uint96 decimals;
    }

    function GOV() external view returns (address);

    function comet() external view returns (address);

    function tokenInfo(address _token) external view returns (TokenInfo memory);

    function setPriceFeed(address _token, address _priceFeed) external;

    function depositor() external view returns (address);

    function rewardToken() external view returns (address);

    function rewardsContract() external view returns (address);

    function sweep(address _token) external;

    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function minAmountToSell() external view returns (uint256);

    function setRoutes(
        address _token0,
        address _token1,
        IAeroRouter.Route[] memory _routes
    ) external;

    function routes(
        address _token0,
        address _token1
    ) external view returns (IAeroRouter.Route[] memory);
}
