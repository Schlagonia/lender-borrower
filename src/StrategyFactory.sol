// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {Depositor, Comet, ERC20} from "./Depositor.sol";
import {CompoundV3LenderBorrowerAero} from "./CompoundV3LenderBorrowerAero.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

interface IOracle {
    function setOracle(address, address) external;
}

contract StrategyFactory {
    event NewStrategy(address indexed strategy, address indexed asset);

    address public immutable gov;
    address public immutable weth;
    address public immutable emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    address public oracle;
    address internal constant APR_ORACLE =
        0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92;

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

        originalDepositor = address(new Depositor());
    }

    /**
     * @notice Deploy a new Strategy.
     * @param _asset The underlying asset for the strategy to use.
     * @param _name The name of the strategy.
     * @param _comet The comet address for the strategy to use.
     * @return . The address of the new strategy.
     */
    function newStrategy(
        address _asset,
        string calldata _name,
        address _comet
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
                new CompoundV3LenderBorrowerAero(
                    _asset,
                    _name,
                    borrowToken,
                    gov,
                    weth,
                    _comet,
                    depositor
                )
            )
        );

        /// Set strategy on Depositor.
        Depositor(depositor).setStrategy(address(_newStrategy));

        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        _newStrategy.setKeeper(keeper);

        _newStrategy.setPendingManagement(management);

        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        _newStrategy.setProfitMaxUnlockTime(2 days);

        IOracle(APR_ORACLE).setOracle(address(_newStrategy), oracle);

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

    function setOracle(address _oracle) external {
        require(msg.sender == management, "!management");
        oracle = _oracle;
    }

    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        address _comet = IStrategyInterface(_strategy).comet();
        return deployedStrategy[_asset][_comet] == _strategy;
    }
}
