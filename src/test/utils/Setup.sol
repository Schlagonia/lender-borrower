// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {MorphoBlueLenderBorrower as LenderBorrower, ERC20} from "../../MorphoBlueLenderBorrower.sol";
import {MorphoBlueLenderBorrowerFactory as StrategyFactory} from "../../MorphoBlueLenderBorrowerFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {Id} from "../../interfaces/morpho/IMorpho.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    string internal constant RPC_ENV = "ETH_RPC_URL";

    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    StrategyFactory public strategyFactory;

    // Mainnet constants
    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    Id public constant MARKET_ID =
        Id.wrap(
            0x3a85e619751152991742810df6ec69ce473daef99e28a64ab2340d7b7ccfee49
        );
    address public constant LENDER_VAULT =
        0xBc65ad17c5C0a2A4D159fa5a503f4992c7B545FE; // USDC ERC4626 vault
    address public constant BORROW_USD_ORACLE =
        0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6; // USDC / USD

    address public borrowToken;
    address public lenderVault = LENDER_VAULT;
    address public morpho = MORPHO;
    address public borrowUsdOracle = BORROW_USD_ORACLE;
    Id public marketId = MARKET_ID;

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

    // Fuzz amounts sized for WBTC (8 decimals)
    uint256 public maxFuzzAmount = 5e7; // 0.5 WBTC
    uint256 public minFuzzAmount = 1e6; // 0.01 WBTC

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        string memory rpc = vm.envString(RPC_ENV);
        vm.createSelectFork(rpc);
        _setTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["WBTC"]);
        borrowToken = tokenAddrs["USDC"];

        // Set decimals
        decimals = asset.decimals();

        strategyFactory = new StrategyFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin,
            gov,
            morpho
        );

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        borrowToken = strategy.borrowToken();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(morpho, "morpho");
        vm.label(lenderVault, "lenderVault");
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                strategyFactory.newStrategy(
                    address(asset),
                    "Tokenized Strategy",
                    borrowToken,
                    lenderVault,
                    marketId,
                    borrowUsdOracle
                )
            )
        );

        vm.prank(management);
        _strategy.acceptManagement();

        // Set loss limit ratio to 1% (100 bps) to allow for interest accrual between reports
        vm.prank(management);
        _strategy.setLossLimitRatio(100);

        return address(_strategy);
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
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function _toUsd(
        uint256 _amount,
        address _token
    ) internal view returns (uint256) {
        if (_amount == 0) return 0;
        unchecked {
            return
                (_amount * _getPrice(_token)) /
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
                _getPrice(_token);
        }
    }

    function _getPrice(address _asset) internal view returns (uint256 price) {}
}
