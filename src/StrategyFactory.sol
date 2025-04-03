// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {CrvUsdLenderBorrower, ERC20} from "./CrvUsdLenderBorrower.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

interface ICurveFactory {
    function get_controller(
        address _collateral
    ) external view returns (address);
    function stablecoin() external view returns (address);
    function get_amm(address _collateral) external view returns (address);
}

contract StrategyFactory {
    event NewStrategy(address indexed strategy, address indexed asset);

    address public immutable GOV;
    address public immutable emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    address public immutable CURVE_FACTORY;

    address public immutable CRV_USD;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => mapping(address => address)) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin,
        address _gov,
        address _curveFactory
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
        GOV = _gov;
        CURVE_FACTORY = _curveFactory;
        CRV_USD = ICurveFactory(_curveFactory).stablecoin();
    }

    /**
     * @notice Deploy a new Strategy.
     * @param _asset The underlying asset for the strategy to use.
     * @param _lenderVault The address of the lender vault to use.
     * @return . The address of the new strategy.
     */
    function newStrategy(
        address _asset,
        address _lenderVault
    ) external virtual returns (address) {
        string memory _name = string.concat(
            ERC20(_lenderVault).name(),
            "Lender crvUSD Borrower"
        );

        address _controller = ICurveFactory(CURVE_FACTORY).get_controller(
            _asset
        );
        address _amm = ICurveFactory(CURVE_FACTORY).get_amm(_asset);
        // tokenized strategies available setters.
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(
                new CrvUsdLenderBorrower(
                    _asset,
                    _name,
                    CRV_USD,
                    _lenderVault,
                    GOV,
                    _controller,
                    _amm
                )
            )
        );

        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        _newStrategy.setKeeper(keeper);

        _newStrategy.setPendingManagement(management);

        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(address(_newStrategy), _asset);

        deployments[_asset][_lenderVault] = address(_newStrategy);
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
        address _lenderVault = IStrategyInterface(_strategy).lenderVault();
        return deployments[_asset][_lenderVault] == _strategy;
    }
}
