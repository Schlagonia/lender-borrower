// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseLenderBorrower} from "./BaseLenderBorrower.sol";
import {IMorpho, Id, MarketParams, Market, Position} from "./interfaces/morpho/IMorpho.sol";
import {IChainlinkAggregator} from "./interfaces/IChainlinkAggregator.sol";
import {IOracle} from "./interfaces/morpho/IOracle.sol";
import {IIrm} from "./interfaces/morpho/IIrm.sol";
import {MarketParamsLib} from "./libraries/morpho/MarketParamsLib.sol";
import {MorphoBalancesLib} from "./libraries/morpho/periphery/MorphoBalancesLib.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {AuctionSwapper} from "@periphery/swappers/AuctionSwapper.sol";

contract MorphoBlueLenderBorrower is
    BaseLenderBorrower,
    UniswapV3Swapper,
    AuctionSwapper
{
    using SafeERC20 for ERC20;
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;

    IMorpho public immutable morpho;
    Id public immutable marketId;
    MarketParams public marketParams;

    address public immutable GOV;

    /// @notice Optional USD price feeds (1e8) for collateral and borrow token.
    address public assetUsdOracle;
    address public borrowUsdOracle;

    constructor(
        address _asset,
        string memory _name,
        address _borrowToken,
        address _lenderVault,
        address _gov,
        address _morpho,
        Id _marketId,
        address _assetUsdOracle,
        address _borrowUsdOracle
    ) BaseLenderBorrower(_asset, _name, _borrowToken, _lenderVault) {
        require(_lenderVault != address(0), "!lenderVault");
        GOV = _gov;
        morpho = IMorpho(_morpho);
        marketId = _marketId;

        marketParams = morpho.idToMarketParams(_marketId);
        require(marketParams.loanToken == _borrowToken, "!loanToken");
        require(marketParams.collateralToken == _asset, "!collateral");

        ERC20(_asset).safeApprove(_morpho, type(uint256).max);
        ERC20(_borrowToken).safeApprove(_morpho, type(uint256).max);

        _setMinAmountToSell(1e6);
        assetUsdOracle = _assetUsdOracle;
        borrowUsdOracle = _borrowUsdOracle;
    }

    /*//////////////////////////////////////////////////////////////
                            WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _supplyCollateral(uint256 amount) internal virtual override {
        if (amount == 0) return;
        morpho.supplyCollateral(marketParams, amount, address(this), "");
    }

    function _withdrawCollateral(uint256 amount) internal virtual override {
        if (amount == 0) return;
        morpho.withdrawCollateral(
            marketParams,
            amount,
            address(this),
            address(this)
        );
    }

    function _borrow(uint256 amount) internal virtual override {
        if (amount == 0) return;
        morpho.borrow(marketParams, amount, 0, address(this), address(this));
    }

    function _repay(uint256 amount) internal virtual override {
        if (amount == 0) return;
        morpho.repay(marketParams, amount, 0, address(this), "");
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getPrice(
        address _asset
    ) internal view virtual override returns (uint256 price) {
        if (_asset == borrowToken) {
            price = _readUsdOracle(borrowUsdOracle);
        } else if (_asset == address(asset)) {
            if (assetUsdOracle != address(0)) {
                price = _readUsdOracle(assetUsdOracle);
            } else {
                uint256 borrowUsd = _readUsdOracle(borrowUsdOracle);
                uint256 ratio = IOracle(marketParams.oracle).price(); // 1e36, loan per collateral
                price = (ratio * borrowUsd) / ORACLE_PRICE_SCALE;
            }
        } else {
            revert("unsupported asset");
        }
    }

    function _isSupplyPaused() internal view virtual override returns (bool) {
        return false;
    }

    function _isBorrowPaused() internal view virtual override returns (bool) {
        return false;
    }

    function _isLiquidatable() internal view virtual override returns (bool) {
        Position memory p = morpho.position(marketId, address(this));
        if (p.borrowShares == 0) return false;

        uint256 borrowed = morpho.expectedBorrowAssets(
            marketParams,
            address(this)
        );
        uint256 collateralValue = (uint256(p.collateral) *
            IOracle(marketParams.oracle).price()) / ORACLE_PRICE_SCALE;
        uint256 maxBorrow = (collateralValue * marketParams.lltv) / WAD;

        return borrowed > maxBorrow;
    }

    function _maxCollateralDeposit()
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return type(uint256).max;
    }

    function _maxBorrowAmount()
        internal
        view
        virtual
        override
        returns (uint256)
    {
        (uint256 totalSupplyAssets, , uint256 totalBorrowAssets, ) = morpho
            .expectedMarketBalances(marketParams);
        return
            totalSupplyAssets > totalBorrowAssets
                ? totalSupplyAssets - totalBorrowAssets
                : 0;
    }

    function getNetBorrowApr(
        uint256 /* newAmount */
    ) public view virtual override returns (uint256) {
        Market memory m = morpho.market(marketId);
        uint256 ratePerSecond = IIrm(marketParams.irm).borrowRateView(
            marketParams,
            m
        );
        return ratePerSecond * 365 days;
    }

    function getNetRewardApr(
        uint256 /* newAmount */
    ) public view virtual override returns (uint256) {
        // Hardcoded high reward APR to keep borrowing favored over costs.
        return 1e20;
    }

    function getLiquidateCollateralFactor()
        public
        view
        virtual
        override
        returns (uint256)
    {
        return marketParams.lltv;
    }

    function balanceOfCollateral()
        public
        view
        virtual
        override
        returns (uint256)
    {
        Position memory p = morpho.position(marketId, address(this));
        return p.collateral;
    }

    function balanceOfDebt() public view virtual override returns (uint256) {
        Position memory p = morpho.position(marketId, address(this));
        if (p.borrowShares == 0) return 0;
        Market memory m = morpho.market(marketId);
        if (m.totalBorrowShares == 0) return 0;
        return
            Math.mulDiv(
                uint256(p.borrowShares),
                m.totalBorrowAssets,
                m.totalBorrowShares
            );
    }

    /*//////////////////////////////////////////////////////////////
                        HARVEST / SWAP LOGIC
    //////////////////////////////////////////////////////////////*/

    function _claimRewards() internal virtual override {}

    function _claimAndSellRewards() internal virtual override {
        uint256 have = balanceOfLentAssets() + balanceOfBorrowToken();
        uint256 owe = balanceOfDebt();

        if (have >= owe) {
            uint256 amountToSell = have - owe;
            _withdrawFromLender(amountToSell);
            _sellBorrowToken(Math.min(amountToSell, balanceOfBorrowToken()));
        }
    }

    function _buyBorrowToken() internal virtual override {
        _buyBorrowToken(borrowTokenOwedBalance());
    }

    function _buyBorrowToken(uint256 _amount) internal virtual {
        if (_amount == 0) return;
        uint256 maxAssetIn = (_fromUsd(
            _toUsd(_amount, borrowToken),
            address(asset)
        ) * (MAX_BPS + slippage)) / MAX_BPS;
        if (maxAssetIn == 0) return;

        _swapTo(address(asset), borrowToken, _amount, maxAssetIn);
    }

    function _sellBorrowToken(uint256 _amount) internal virtual override {
        if (_amount == 0) return;

        _swapFrom(
            borrowToken,
            address(asset),
            _amount,
            _getAmountOut(_amount, borrowToken, address(asset))
        );
    }

    // Override to not allow permissionless kicks
    function kickAuction(
        address _token
    ) external virtual override onlyKeepers returns (uint256) {
        return _kickAuction(_token);
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT UTILITIES
    //////////////////////////////////////////////////////////////*/

    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    function setUniBase(address _base) external onlyManagement {
        base = _base;
    }

    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        _setMinAmountToSell(_minAmountToSell);
    }

    function setAuction(address _auction) external onlyManagement {
        _setAuction(_auction);
    }

    function setUseAuction(bool _useAuction) external onlyManagement {
        _setUseAuction(_useAuction);
    }

    function setUsdOracles(
        address _assetUsdOracle,
        address _borrowUsdOracle
    ) external onlyManagement {
        assetUsdOracle = _assetUsdOracle;
        borrowUsdOracle = _borrowUsdOracle;
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external {
        require(msg.sender == GOV, "!gov");
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }

    function _readUsdOracle(address _oracle) internal view returns (uint256) {
        require(_oracle != address(0), "oracle not set");
        int256 answer = IChainlinkAggregator(_oracle).latestAnswer();
        require(answer > 0, "bad oracle");
        return uint256(answer);
    }
}
