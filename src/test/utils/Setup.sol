// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {Depositor, Comet, ERC20} from "../../Depositor.sol";
import {CompoundV3LenderBorrowerAero, IAeroRouter} from "../../CompoundV3LenderBorrowerAero.sol";
import {StrategyFactory} from "../../StrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;
    Depositor public depositor;
    StrategyFactory public strategyFactory;

    address internal constant AERODROME_FACTORY =
        0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    address public borrowToken;
    address public comet;
    address public rewardToken;

    mapping(string => address) public tokenAddrs;
    mapping(string => address) public comets;

    // Addresses for different roles we will use repeatedly.
    address public gov = address(69);
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 100e18;
    uint256 public minFuzzAmount = 1e17;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["WETH"]);
        comet = comets["AERO"];

        // Set decimals
        decimals = asset.decimals();

        strategyFactory = new StrategyFactory(
            gov,
            tokenAddrs["WETH"],
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        rewardToken = strategy.rewardToken();
        depositor = Depositor(strategy.depositor());
        borrowToken = strategy.borrowToken();

        setRoutes();

        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                strategyFactory.newStrategy(
                    address(asset),
                    "Tokenized Strategy",
                    address(comet)
                )
            )
        );

        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }

    function setRoutes() public {
        IAeroRouter.Route[] memory borrowRoute = new IAeroRouter.Route[](3);
        borrowRoute[0] = IAeroRouter.Route({
            from: address(rewardToken),
            to: tokenAddrs["DOLA"],
            stable: false,
            factory: AERODROME_FACTORY
        });

        borrowRoute[1] = IAeroRouter.Route({
            from: tokenAddrs["DOLA"],
            to: tokenAddrs["USDC"],
            stable: true,
            factory: AERODROME_FACTORY
        });

        borrowRoute[2] = IAeroRouter.Route({
            from: tokenAddrs["USDC"],
            to: borrowToken,
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(management);
        strategy.setRoutes(rewardToken, borrowToken, borrowRoute);

        IAeroRouter.Route[] memory assetRoute = new IAeroRouter.Route[](3);
        assetRoute[0] = IAeroRouter.Route({
            from: rewardToken,
            to: tokenAddrs["DOLA"],
            stable: false,
            factory: AERODROME_FACTORY
        });

        assetRoute[1] = IAeroRouter.Route({
            from: tokenAddrs["DOLA"],
            to: tokenAddrs["USDC"],
            stable: true,
            factory: AERODROME_FACTORY
        });

        assetRoute[2] = IAeroRouter.Route({
            from: tokenAddrs["USDC"],
            to: address(asset),
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(management);
        strategy.setRoutes(rewardToken, address(asset), assetRoute);

        IAeroRouter.Route[] memory assetToBorrowRoute = new IAeroRouter.Route[](
            2
        );
        assetToBorrowRoute[0] = IAeroRouter.Route({
            from: address(asset),
            to: tokenAddrs["USDC"],
            stable: false,
            factory: AERODROME_FACTORY
        });

        assetToBorrowRoute[1] = IAeroRouter.Route({
            from: tokenAddrs["USDC"],
            to: borrowToken,
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(management);
        strategy.setRoutes(address(asset), borrowToken, assetToBorrowRoute);
        
        IAeroRouter.Route[] memory borrowToAssetRoute = new IAeroRouter.Route[](
            2
        );
        borrowToAssetRoute[0] = IAeroRouter.Route({
            from: borrowToken,
            to: tokenAddrs["USDC"],
            stable: false,
            factory: AERODROME_FACTORY
        });

        borrowToAssetRoute[1] = IAeroRouter.Route({
            from: tokenAddrs["USDC"],
            to: address(asset),
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(management);
        strategy.setRoutes(borrowToken, address(asset), borrowToAssetRoute);
        
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address _gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(_gov);
        IFactory(factory).set_protocol_fee_recipient(_gov);

        vm.prank(_gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0x4200000000000000000000000000000000000006;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        tokenAddrs["AERO"] = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
        tokenAddrs["DOLA"] = 0x4621b7A9c75199271F773Ebd9A499dbd165c3191;
        comets["WETH"] = 0xA17581A9E3356d9A858b789D68B4d866e593aE94;
        comets["USDC"] = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
        comets["USDT"] = 0x3Afdc9BCA9213A35503b077a6072F3D0d5AB0840;
        comets["AERO"] = 0x784efeB622244d2348d4F2522f8860B96fbEcE89;
    }

    function _toUsd(
        uint256 _amount,
        address _token
    ) internal view returns (uint256) {
        if (_amount == 0) return 0;
        unchecked {
            return
                (_amount * _getCompoundPrice(_token)) /
                (uint256(10 ** ERC20(_token).decimals()));
        }
    }

    function _fromUsd(
        uint256 _amount,
        address _token
    ) internal view returns (uint256) {
        if (_amount == 0) return 0;
        unchecked {
            return
                (_amount * (uint256(10 ** ERC20(_token).decimals()))) /
                _getCompoundPrice(_token);
        }
    }

    function _getCompoundPrice(
        address _asset
    ) internal view returns (uint256 price) {
        price = Comet(comet).getPrice(strategy.tokenInfo(_asset).priceFeed);
    }
}
