// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {ILenderBorrower} from "./ILenderBorrower.sol";

interface IStrategyInterface is IStrategy, ILenderBorrower {
    //TODO: Add your specific implementation interface in here.
}
