// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IAeroRouter} from "./Aero/IAeroRouter.sol";
import {ITradeFactorySwapper} from "@periphery/swappers/interfaces/ITradeFactorySwapper.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {ILenderBorrower} from "./ILenderBorrower.sol";

interface IStrategyInterface is
    IStrategy,
    ILenderBorrower,
    ITradeFactorySwapper
{
    //TODO: Add your specific implementation interface in here.

    struct TokenInfo {
        address priceFeed;
        uint96 decimals;
    }

    function accrueInterest() external;

    function GOV() external view returns (address);

    function cToken() external view returns (address);

    function cBorrowToken() external view returns (address);

    function comptroller() external view returns (address);

    function lenderVault() external view returns (address);

    function tokenInfo(address _token) external view returns (TokenInfo memory);

    function setPriceFeed(address _token, address _priceFeed) external;

    function WELL() external view returns (address);

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
