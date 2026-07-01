// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {ILenderBorrower} from "./ILenderBorrower.sol";
import {IMorpho} from "./morpho/IMorpho.sol";
import {Id} from "./morpho/IMorpho.sol";

interface IStrategyInterface is IStrategy, ILenderBorrower {
    //TODO: Add your specific implementation interface in here.

    function GOV() external view returns (address);

    function sweep(address _token) external;

    // Morpho-specific views
    function morpho() external view returns (IMorpho);

    function marketId() external view returns (Id);

    function marketParams()
        external
        view
        returns (address, address, address, address, uint256);

    function lenderVault() external view returns (address);

    function rewardTokens(uint256 _index) external view returns (address);

    // Morpho-specific management setters
    function setRewardAprOracle(address _oracle) external;

    function setUsdOracles(
        address _assetUsdOracle,
        address _borrowUsdOracle
    ) external;

    function setAuction(address _auction) external;

    function setUseAuction(bool _useAuction) external;

    function addRewardToken(address _rewardToken) external;

    function removeRewardToken(address _rewardToken) external;

    function getRewardTokens() external view returns (address[] memory);

    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}
