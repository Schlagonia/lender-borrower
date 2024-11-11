// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {LenderBorrower, Depositor, Comet, ERC20} from "./LenderBorrower.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract StrategyFactory {
    event NewStrategy(address indexed strategy, address indexed asset);

    address public immutable gov;
    address public immutable weth;
    address public immutable emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Address of the original depositor contract used for cloning
    address public immutable originalDepositor;

    /// @notice Mapping of an asset => comet => its deployed strategy if exists
    mapping(address => mapping(address => address)) public deployedStrategy;

    constructor(
        address _gov,
        address _weth,
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) {
        gov = _gov;
        weth = _weth;
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;

        /// Deploy an original depositor to clone
        originalDepositor = address(new Depositor());
    }

    /**
     * @notice Deploy a new Strategy.
     * @param _asset The underlying asset for the strategy to use.
     * @param _name The name of the strategy.
     * @param _comet The comet address for the strategy to use.
     * @param _ethToAssetFee The fee for the strategy to use.
     * @return . The address of the new strategy.
     */
    function newStrategy(
        address _asset,
        string calldata _name,
        address _comet,
        uint24 _ethToAssetFee
    ) external virtual returns (address) {
        require(
            deployedStrategy[_asset][_comet] == address(0),
            "already deployed"
        );

        address borrowToken = Comet(_comet).baseToken();
        address depositor = Depositor(originalDepositor).cloneDepositor(_comet);

        // tokenized strategies available setters.
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(
                new LenderBorrower(
                    _asset,
                    _name,
                    borrowToken,
                    gov,
                    weth,
                    _comet,
                    depositor,
                    _ethToAssetFee
                )
            )
        );

        /// Set strategy on Depositor.
        Depositor(depositor).setStrategy(address(_newStrategy));

        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        _newStrategy.setKeeper(keeper);

        _newStrategy.setPendingManagement(management);

        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(address(_newStrategy), _asset);

        deployedStrategy[_asset][_comet] = address(_newStrategy);

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

    function isDeployedStrategy(address _strategy)
        external
        view
        returns (bool)
    {
        address _asset = IStrategyInterface(_strategy).asset();
        address _comet = IStrategyInterface(_strategy).comet();
        return deployedStrategy[_asset][_comet] == _strategy;
    }
}
