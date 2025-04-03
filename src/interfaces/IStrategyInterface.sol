// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {ILenderBorrower} from "./ILenderBorrower.sol";

interface IStrategyInterface is IStrategy, ILenderBorrower {
    //TODO: Add your specific implementation interface in here.

    function GOV() external view returns (address);

    function sweep(address _token) external;

    function lenderVault() external view returns (address);

    function CONTROLLER() external view returns (address);

    function AMM() external view returns (address);
}
