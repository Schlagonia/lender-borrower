// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {MoonwellLenderBorrower, ERC20, CErc20I} from "./MoonwellLenderBorrower.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract MoonwellLenderBorrowerFactory {
    event NewStrategy(address indexed strategy, address indexed asset);

    address public immutable GOV;
    address public immutable emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => mapping(address => address)) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin,
        address _gov
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        GOV = _gov;
    }

    /**
     * @notice Deploy a new Strategy.
     * @return . The address of the new strategy.
     */
    function newStrategy(
        address _cToken,
        address _cBorrowToken,
        address _lenderVault
    ) external virtual returns (address) {
        address _asset = CErc20I(_cToken).underlying();
        address _borrowToken = CErc20I(_cBorrowToken).underlying();
        string memory _name = string(
            abi.encodePacked(
                "Moonwell ",
                ERC20(_asset).symbol(),
                " Lender ",
                ERC20(_borrowToken).symbol(),
                " Borrower"
            )
        );

        // tokenized strategies available setters.
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(
                new MoonwellLenderBorrower(
                    _asset,
                    _name,
                    _borrowToken,
                    _lenderVault,
                    GOV,
                    _cToken,
                    _cBorrowToken
                )
            )
        );

        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        _newStrategy.setKeeper(keeper);

        _newStrategy.setPendingManagement(management);

        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(address(_newStrategy), _asset);

        deployments[_asset][_borrowToken] = address(_newStrategy);
        return address(_newStrategy);
    }

    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        address _borrowToken = IStrategyInterface(_strategy).borrowToken();
        return deployments[_asset][_borrowToken] == _strategy;
    }
}
