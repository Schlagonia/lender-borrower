// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseLenderBorrower} from "./BaseLenderBorrower.sol";
import {IMorpho, Id, MarketParams, Position} from "./interfaces/morpho/IMorpho.sol";
import {IChainlinkAggregator} from "./interfaces/IChainlinkAggregator.sol";
import {IOracle} from "./interfaces/morpho/IOracle.sol";
import {MorphoBalancesLib, MorphoLib} from "./libraries/morpho/periphery/MorphoBalancesLib.sol";
import {SharesMathLib} from "./libraries/morpho/SharesMathLib.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

contract MorphoBlueLenderBorrower is BaseLenderBorrower, UniswapV3Swapper {
    using SafeERC20 for ERC20;
    using MorphoBalancesLib for IMorpho;
    using MorphoLib for IMorpho;

    uint256 internal constant ORACLE_PRICE_SCALE = 1e36;

    IMorpho public immutable morpho;
    Id public immutable marketId;
    MarketParams public marketParams;

    address public immutable GOV;

    /// @notice USD price feed (1e8) for borrow token.
    /// @dev Collateral price is derived using Morpho's oracle (collateral -> borrow) then this oracle (borrow -> USD).
    address public borrowUsdOracle;

    constructor(
        address _asset,
        string memory _name,
        address _borrowToken,
        address _lenderVault,
        address _gov,
        address _morpho,
        Id _marketId,
        address _borrowUsdOracle,
        address _router
    ) BaseLenderBorrower(_asset, _name, _borrowToken, _lenderVault) {
        GOV = _gov;
        morpho = IMorpho(_morpho);
        marketId = _marketId;

        marketParams = morpho.idToMarketParams(_marketId);
        require(
            marketParams.loanToken == _borrowToken &&
                marketParams.collateralToken == _asset,
            "!market"
        );

        ERC20(_asset).forceApprove(_morpho, type(uint256).max);
        ERC20(_borrowToken).forceApprove(_morpho, type(uint256).max);

        _setMinAmountToSell(1e4);
        router = _router;

        require(IChainlinkAggregator(_borrowUsdOracle).decimals() == 8);
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

    // Need to give shares as input to avoid rounding errors on full repays.
    function _repay(uint256 amount) internal virtual override {
        if (amount == 0) return;
        (
            ,
            ,
            uint256 totalBorrowAssets,
            uint256 totalBorrowShares
        ) = MorphoBalancesLib.expectedMarketBalances(morpho, marketParams);

        uint256 shares = Math.min(
            SharesMathLib.toSharesDown(
                amount,
                totalBorrowAssets,
                totalBorrowShares
            ),
            morpho.borrowShares(marketId, address(this))
        );

        morpho.repay(marketParams, 0, shares, address(this), "");
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
            // Use Morpho's oracle to get collateral price in borrow token, then convert to USD
            // Morpho oracle returns: (borrow token amount) / (collateral amount) scaled by 1e36
            uint256 borrowUsd = _readUsdOracle(borrowUsdOracle);
            uint256 ratio = IOracle(marketParams.oracle).price(); // 1e36, loan per collateral
            price = (ratio * borrowUsd) / ORACLE_PRICE_SCALE;
        } else {
            revert("!asset");
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

        uint256 collateralValue = (uint256(p.collateral) *
            IOracle(marketParams.oracle).price()) / ORACLE_PRICE_SCALE;
        uint256 maxBorrow = (collateralValue * marketParams.lltv) / WAD;

        return balanceOfDebt() > maxBorrow;
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
        return 1;
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
        return morpho.expectedBorrowAssets(marketParams, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        HARVEST / SWAP LOGIC
    //////////////////////////////////////////////////////////////*/

    function _claimRewards() internal virtual override {}

    function _claimAndSellRewards() internal virtual override {
        uint256 have = balanceOfLentAssets() + balanceOfBorrowToken();
        uint256 owe = balanceOfDebt();

        if (have > owe) {
            uint256 amountToSell = have - owe;
            _withdrawFromLender(amountToSell);
            _sellBorrowToken(Math.min(amountToSell, balanceOfBorrowToken()));
        }
    }

    function _buyBorrowToken() internal virtual override {
        uint256 _amount = borrowTokenOwedBalance();

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

    function setBorrowUsdOracle(
        address _borrowUsdOracle
    ) external onlyManagement {
        require(IChainlinkAggregator(_borrowUsdOracle).decimals() == 8);
        borrowUsdOracle = _borrowUsdOracle;
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external {
        require(msg.sender == GOV, "!gov");
        require(
            _token != address(asset) &&
                _token != address(borrowToken) &&
                _token != address(lenderVault),
            "!sweep"
        );
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }

    function _readUsdOracle(address _oracle) internal view returns (uint256) {
        int256 answer = IChainlinkAggregator(_oracle).latestAnswer();
        require(answer > 0, "0");
        return uint256(answer);
    }
}
