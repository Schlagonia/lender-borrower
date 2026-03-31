// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Id} from "../interfaces/morpho/IMorpho.sol";

contract ManualBorrowRewardAprOracle {
    address public immutable management;

    mapping(Id => uint256) public borrowRewardApr;

    constructor(address _management) {
        management = _management;
    }

    function setBorrowRewardAprBps(Id _marketId, uint256 _aprBps) external {
        require(msg.sender == management, "!management");
        borrowRewardApr[_marketId] = _aprBps * 1e14;
    }
}
