// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.18;

interface IOracle {
    function latestAnswer() external view returns (int256);
}
