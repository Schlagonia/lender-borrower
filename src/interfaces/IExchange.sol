// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.23;

interface IExchange {
    function exchange(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _minAmount
    ) external returns (uint256);
}
