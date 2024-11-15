// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface CompoundOracleI {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
    function getFeed(string memory symbol) external view returns (address);
}
