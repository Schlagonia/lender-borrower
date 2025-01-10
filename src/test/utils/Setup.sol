// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {MockStrategy} from "@periphery/test/mocks/MockStrategy.sol";

import {MoonwellOracle} from "../../periphery/MoonwellOracle.sol";
import {CErc20I} from "../../interfaces/compound/CErc20I.sol";
import {CompoundOracleI} from "../../interfaces/compound/CompoundOracleI.sol";
import {ComptrollerI} from "../../interfaces/compound/ComptrollerI.sol";
import {MoonwellLenderBorrower, ERC20, IOracle, IAeroRouter} from "../../MoonwellLenderBorrower.sol";
import {MoonwellLenderBorrowerFactory} from "../../MoonwellLenderBorrowerFactory.sol";
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

    MoonwellLenderBorrowerFactory public strategyFactory;

    MoonwellOracle public moonwellOracle =
        MoonwellOracle(0xBBF812FC0e45F58121983bd07C5079fF74433a61);

    ERC20 internal constant WELL =
        ERC20(0xA88594D404727625A9437C3f886C7643872296AE);

    address internal constant AERODROME_FACTORY =
        0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    address public borrowToken;
    CErc20I public cToken = CErc20I(0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22);
    CErc20I public cBorrowToken =
        CErc20I(0x628ff693426583D9a7FB391E54366292F509D457);
    IStrategyInterface public lenderVault;
    address public rewardToken = address(WELL);

    mapping(string => address) public tokenAddrs;

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
    uint256 public maxFuzzAmount = 1_000_000e6;
    uint256 public minFuzzAmount = 1e6;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["USDC"]);
        borrowToken = tokenAddrs["WETH"];

        lenderVault = IStrategyInterface(
            address(new MockStrategy(borrowToken))
        ); // 0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca
        lenderVault.setProfitMaxUnlockTime(0);
        lenderVault.setPerformanceFee(0);

        // Set decimals
        decimals = asset.decimals();

        strategyFactory = new MoonwellLenderBorrowerFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin,
            gov
        );

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

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
                    address(cToken),
                    address(cBorrowToken),
                    address(lenderVault)
                )
            )
        );

        vm.prank(management);
        _strategy.acceptManagement();

        vm.prank(management);
        _strategy.setProfitMaxUnlockTime(2 days);

        return address(_strategy);
    }

    function setRoutes() public {
        IAeroRouter.Route[] memory borrowRoute = new IAeroRouter.Route[](1);
        borrowRoute[0] = IAeroRouter.Route({
            from: rewardToken,
            to: tokenAddrs["WETH"],
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(management);
        strategy.setRoutes(rewardToken, borrowToken, borrowRoute);

        IAeroRouter.Route[] memory assetRoute = new IAeroRouter.Route[](2);
        assetRoute[0] = IAeroRouter.Route({
            from: rewardToken,
            to: tokenAddrs["WETH"],
            stable: false,
            factory: AERODROME_FACTORY
        });
        assetRoute[1] = IAeroRouter.Route({
            from: tokenAddrs["WETH"],
            to: address(asset),
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(management);
        strategy.setRoutes(rewardToken, address(asset), assetRoute);

        IAeroRouter.Route[] memory assetToBorrowRoute = new IAeroRouter.Route[](
            1
        );
        assetToBorrowRoute[0] = IAeroRouter.Route({
            from: address(asset),
            to: borrowToken,
            stable: false,
            factory: AERODROME_FACTORY
        });

        vm.prank(management);
        strategy.setRoutes(address(asset), borrowToken, assetToBorrowRoute);

        IAeroRouter.Route[] memory borrowToAssetRoute = new IAeroRouter.Route[](
            1
        );
        borrowToAssetRoute[0] = IAeroRouter.Route({
            from: borrowToken,
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
        address priceFeed = strategy.tokenInfo(_asset).priceFeed;
        if (priceFeed != address(0)) {
            return uint256(IOracle(priceFeed).latestAnswer());
        }

        uint256 decimalDelta = 1e18 / (10 ** ERC20(_asset).decimals());
        // Compound oracle expects the token to be the cToken
        if (_asset == address(asset)) {
            _asset = address(cToken);
        } else if (_asset == address(borrowToken)) {
            _asset = address(cBorrowToken);
        }

        return
            CompoundOracleI(ComptrollerI(strategy.comptroller()).oracle())
                .getUnderlyingPrice(_asset) / (1e10 * decimalDelta);
    }
}
