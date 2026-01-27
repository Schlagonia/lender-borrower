// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {MorphoBlueLenderBorrower} from "./MorphoBlueLenderBorrower.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";
import {Id} from "./interfaces/morpho/IMorpho.sol";

contract MorphoBlueLenderBorrowerFactory {
    event NewStrategy(address indexed strategy, Id indexed marketId);

    address public immutable GOV;
    address public immutable morpho;
    address public immutable router;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;
    address public emergencyAdmin;

    /// @notice Track deployments by market id.
    mapping(Id => mapping(address => address)) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin,
        address _gov,
        address _morpho,
        address _router
    ) {
        require(_gov != address(0));
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        GOV = _gov;
        morpho = _morpho;
        router = _router;
    }

    function newStrategy(
        address _asset,
        string calldata _name,
        address _borrowToken,
        address _lenderVault,
        Id _marketId,
        address _borrowUsdOracle
    ) external virtual returns (address) {
        require(
            deployments[_marketId][_lenderVault] == address(0),
            "deployment already exists"
        );
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(
                new MorphoBlueLenderBorrower(
                    _asset,
                    _name,
                    _borrowToken,
                    _lenderVault,
                    GOV,
                    morpho,
                    _marketId,
                    _borrowUsdOracle,
                    router
                )
            )
        );

        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        _newStrategy.setKeeper(keeper);
        _newStrategy.setPendingManagement(management);
        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(address(_newStrategy), _marketId);
        deployments[_marketId][_lenderVault] = address(_newStrategy);
        return address(_newStrategy);
    }

    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }
}
