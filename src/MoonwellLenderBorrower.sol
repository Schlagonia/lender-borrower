// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {IOracle} from "./interfaces/IOracle.sol";
import {CErc20I} from "./interfaces/compound/CErc20I.sol";
import {ComptrollerI} from "./interfaces/compound/ComptrollerI.sol";
import {CompoundOracleI} from "./interfaces/compound/CompoundOracleI.sol";

import {IAeroRouter} from "./interfaces/Aero/IAeroRouter.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {BaseLenderBorrower, ERC20, SafeERC20, Math} from "./BaseLenderBorrower.sol";

import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";

interface IWeth {
    function deposit() external payable;
}

interface MoonwellComptrollerI is ComptrollerI {
    function claimReward(address holder, CErc20I[] memory mTokens) external;
}

import "forge-std/console2.sol";

contract MoonwellLenderBorrower is BaseLenderBorrower, TradeFactorySwapper {
    using SafeERC20 for ERC20;

    struct TokenInfo {
        address priceFeed;
        uint96 decimals;
    }

    modifier accrue() {
        accrueInterest();
        _;
    }

    ERC20 internal constant WELL =
        ERC20(0xA88594D404727625A9437C3f886C7643872296AE);

    IWeth internal constant WETH =
        IWeth(0x4200000000000000000000000000000000000006);

    IAeroRouter internal constant AERODROME_ROUTER =
        IAeroRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);

    /// @notice The governance address
    address public immutable GOV;

    CErc20I public immutable cToken;

    CErc20I public immutable cBorrowToken;

    MoonwellComptrollerI public immutable comptroller;

    IERC4626 public immutable lenderVault;

    uint256 public minAmountToSell;

    /// Mapping from token => struct containing its reused info
    mapping(address => TokenInfo) public tokenInfo;

    mapping(address => mapping(address => IAeroRouter.Route[])) public routes;

    constructor(
        address _asset,
        string memory _name,
        address _borrowToken,
        address _gov,
        address _cToken,
        address _cBorrowToken,
        address _lenderVault
    ) BaseLenderBorrower(_asset, _name, _borrowToken) {
        GOV = _gov;
        cToken = CErc20I(_cToken);
        require(cToken.underlying() == _asset, "!asset");

        cBorrowToken = CErc20I(_cBorrowToken);
        require(cBorrowToken.underlying() == _borrowToken, "!borrowToken");

        comptroller = MoonwellComptrollerI(cToken.comptroller());

        address[] memory cTokens = new address[](1);
        cTokens[0] = _cToken;
        comptroller.enterMarkets(cTokens);

        lenderVault = IERC4626(_lenderVault);
        require(lenderVault.asset() == _borrowToken, "!lenderVault");

        asset.safeApprove(_cToken, type(uint256).max);
        ERC20(_borrowToken).safeApprove(_lenderVault, type(uint256).max);
        ERC20(_borrowToken).safeApprove(_cBorrowToken, type(uint256).max);

        CompoundOracleI compoundOracle = CompoundOracleI(comptroller.oracle());

        tokenInfo[_borrowToken] = TokenInfo({
            priceFeed: compoundOracle.getFeed(ERC20(_borrowToken).symbol()),
            decimals: uint96(10 ** ERC20(_borrowToken).decimals())
        });

        tokenInfo[address(asset)] = TokenInfo({
            priceFeed: compoundOracle.getFeed(ERC20(address(asset)).symbol()),
            decimals: uint96(10 ** ERC20(address(asset)).decimals())
        });

        tokenInfo[address(WELL)] = TokenInfo({
            priceFeed: address(0),
            decimals: uint96(10 ** WELL.decimals())
        });
    }

    function accrueInterest() public virtual {
        if (cToken.accrualBlockTimestamp() != block.timestamp) {
            cToken.exchangeRateCurrent();
        }
        if (cBorrowToken.accrualBlockTimestamp() != block.timestamp) {
            cBorrowToken.exchangeRateCurrent();
        }
    }

    // Override each state changing function to accrue interest first.

    function _deployFunds(uint256 _amount) internal virtual override accrue {
        super._deployFunds(_amount);
    }

    function _freeFunds(uint256 _amount) internal virtual override accrue {
        super._freeFunds(_amount);
    }

    function _harvestAndReport()
        internal
        virtual
        override
        accrue
        returns (uint256)
    {
        return super._harvestAndReport();
    }

    function _tend(uint256 _totalIdle) internal virtual override accrue {
        super._tend(_totalIdle);
    }

    function setPriceFeed(
        address _token,
        address _priceFeed
    ) external onlyManagement {
        // Make sure it works
        IOracle(_priceFeed).latestAnswer();
        tokenInfo[_token].priceFeed = _priceFeed;
    }

    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    function setRoutes(
        address _token0,
        address _token1,
        IAeroRouter.Route[] calldata _routes
    ) external onlyManagement {
        delete routes[_token0][_token1];

        for (uint256 i = 0; i < _routes.length; i++) {
            routes[_token0][_token1].push(_routes[i]);
        }
    }

    // ----------------- WRITE FUNCTIONS ----------------- \\

    /**
     * @notice Supplies a specified amount of `asset` as collateral.
     * @param amount The amount of the asset to supply.
     */
    function _supplyCollateral(uint256 amount) internal virtual override {
        if (amount != 0) {
            require(cToken.mint(amount) == 0);
        } else {
            // If 0 still update the balances
            cToken.exchangeRateCurrent();
        }
    }

    /**
     * @notice Withdraws a specified amount of collateral.
     * @param amount The amount of the collateral to withdraw.
     */
    function _withdrawCollateral(uint256 amount) internal virtual override {
        require(cToken.redeemUnderlying(amount) == 0);
    }

    /**
     * @notice Borrows a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to borrow.
     */
    function _borrow(uint256 amount) internal virtual override {
        require(cBorrowToken.borrow(amount) == 0);
    }

    /**
     * @notice Repays a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to repay.
     */
    function _repay(uint256 amount) internal virtual override {
        require(cBorrowToken.repayBorrow(amount) == 0);
    }

    /**
     * @notice Lends a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to lend.
     */
    function _lendBorrowToken(uint256 amount) internal virtual override {
        lenderVault.deposit(amount, address(this));
    }

    /**
     * @notice Withdraws a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to withdraw.
     */
    function _withdrawBorrowToken(uint256 amount) internal virtual override {
        // Use previewWithdraw to round up.
        uint256 shares = Math.min(
            lenderVault.previewWithdraw(amount),
            lenderVault.balanceOf(address(this))
        );
        lenderVault.redeem(shares, address(this), address(this));
    }

    // ----------------- INTERNAL VIEW FUNCTIONS ----------------- \\

    /**
     * @notice Converts a token amount to USD value
     * @dev Uses Compound price feed and token decimals
     * @param _amount The token amount
     * @param _token The token address
     * @return The USD value scaled by 1e8
     */
    function _toUsd(
        uint256 _amount,
        address _token
    ) internal view virtual override returns (uint256) {
        if (_amount == 0) return 0;
        unchecked {
            return
                (_amount * _getPrice(_token)) /
                (uint256(tokenInfo[_token].decimals));
        }
    }

    /**
     * @notice Converts a USD amount to token value
     * @dev Uses Compound price feed and token decimals
     * @param _amount The USD amount (scaled by 1e8)
     * @param _token The token address
     * @return The token amount
     */
    function _fromUsd(
        uint256 _amount,
        address _token
    ) internal view virtual override returns (uint256) {
        if (_amount == 0) return 0;
        unchecked {
            return
                (_amount * (uint256(tokenInfo[_token].decimals))) /
                _getPrice(_token);
        }
    }

    /**
     * @notice Gets asset price returned 1e18
     * @param _token The asset address
     * @return price asset price
     */
    function _getPrice(
        address _token
    ) internal view virtual override returns (uint256) {
        address priceFeed = tokenInfo[_token].priceFeed;
        if (priceFeed == address(0)) {
            return
                _toUsd(
                    _getAeroAmountOut(
                        tokenInfo[_token].decimals,
                        _token,
                        address(asset)
                    ),
                    address(asset)
                );
        }
        return uint256(IOracle(priceFeed).latestAnswer());
    }

    /**
     * @notice Checks if lending or borrowing is paused
     * @return True if paused, false otherwise
     */
    function _isPaused() internal view virtual override returns (bool) {
        return comptroller.borrowGuardianPaused(address(cToken));
    }

    /**
     * @notice Checks if the strategy is liquidatable
     * @return True if liquidatable, false otherwise
     */
    function _isLiquidatable() internal view virtual override returns (bool) {
        (, , uint256 shortfall) = comptroller.getAccountLiquidity(
            address(this)
        );
        return shortfall > 0;
    }

    /**
     * @notice Gets the supply cap for the collateral asset if any
     * @return The supply cap
     */
    function _maxCollateralDeposit()
        internal
        view
        virtual
        override
        returns (uint256)
    {
        uint256 totalCash = cToken.getCash();
        uint256 totalBorrows = cToken.totalBorrows();
        uint256 totalReserves = cToken.totalReserves();
        return
            comptroller.supplyCaps(address(cToken)) -
            (totalCash + totalBorrows - totalReserves);
    }

    /**
     * @notice Gets the max amount of `borrowToken` that could be borrowed
     * @return The max borrow amount
     */
    function _maxBorrowAmount()
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return cBorrowToken.getCash();
    }

    /**
     * @notice Gets the max amount of `borrowToken` that could be deposited to the lender
     * @return The max deposit amount
     */
    function _lenderMaxDeposit()
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return lenderVault.maxDeposit(address(this));
    }

    /**
     * @notice Gets the amount of borrowToken that could be withdrawn from the lender
     * @return The lender liquidity
     */
    function _lenderMaxWithdraw()
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return
            lenderVault.convertToAssets(lenderVault.maxRedeem(address(this)));
    }

    /**
     * @notice Gets net borrow APR from depositor
     * @param newAmount Simulated supply amount
     * @return Net borrow APR
     */
    function getNetBorrowApr(
        uint256 newAmount
    ) public view virtual override returns (uint256) {
        return 1e18;
    }

    /**
     * @notice Gets net reward APR from depositor
     * @param newAmount Simulated supply amount
     * @return Net reward APR
     */
    function getNetRewardApr(
        uint256 newAmount
    ) public view virtual override returns (uint256) {
        return 3e18;
    }

    /**
     * @notice Gets liquidation collateral factor for asset
     * @return Liquidation collateral factor
     */
    function getLiquidateCollateralFactor()
        public
        view
        virtual
        override
        returns (uint256)
    {
        (, uint256 collateralFactorMantissa) = comptroller.markets(
            address(cToken)
        );
        return collateralFactorMantissa;
    }

    /**
     * @notice Gets supplied collateral balance
     * @return Collateral balance
     */
    function balanceOfCollateral()
        public
        view
        virtual
        override
        returns (uint256)
    {
        return
            (cToken.balanceOf(address(this)) * cToken.exchangeRateStored()) /
            1e18;
    }

    /**
     * @notice Gets current borrow balance
     * @return Borrow balance
     */
    function balanceOfDebt() public view virtual override returns (uint256) {
        return cBorrowToken.borrowBalanceStored(address(this));
    }

    /**
     * @notice Gets full depositor balance
     * @return Depositor balance
     */
    function balanceOfLentAssets()
        public
        view
        virtual
        override
        returns (uint256)
    {
        return
            lenderVault.convertToAssets(lenderVault.balanceOf(address(this)));
    }

    /// ----------------- HARVEST / TOKEN CONVERSIONS ----------------- \\

    /**
     * @notice Claims reward tokens
     */
    function _claimRewards()
        internal
        virtual
        override(BaseLenderBorrower, TradeFactorySwapper)
    {
        CErc20I[] memory tokens = new CErc20I[](2);
        tokens[0] = cToken;
        tokens[1] = cBorrowToken;

        comptroller.claimReward(address(this), tokens);
    }

    /**
     * @notice Claims and sells available reward tokens
     * @dev Handles claiming, selling rewards for base tokens if needed, and selling remaining rewards for asset
     */
    function _claimAndSellRewards() internal virtual override {
        _claimRewards();

        uint256 rewardTokenBalance;
        uint256 have = balanceOfLentAssets() + balanceOfBorrowToken();
        uint256 owe = balanceOfDebt();

        if (owe > have) {
            uint256 borrowTokenNeeded = owe - have;
            rewardTokenBalance = WELL.balanceOf(address(this));
            /// We estimate how much we will need in order to get the amount of base
            /// Accounts for slippage and diff from oracle price, just to assure no horrible sandwich
            uint256 maxRewardToken = (_fromUsd(
                _toUsd(borrowTokenNeeded, address(borrowToken)),
                address(WELL)
            ) * (MAX_BPS + slippage)) / MAX_BPS;

            // Swap the least amount needed.
            rewardTokenBalance = Math.min(rewardTokenBalance, maxRewardToken);

            _swapFrom(
                address(WELL),
                borrowToken,
                rewardTokenBalance,
                _getAmountOut(rewardTokenBalance, address(WELL), borrowToken)
            );
        } else {
            // We have more than enough to cover our debt, so we can just withdraw and swap the extra
            uint256 extra = have - owe;

            _withdrawFromLender(extra);

            // Actual amount withdrawn may differ from input
            _sellBorrowToken(Math.min(extra, balanceOfBorrowToken()));
        }

        rewardTokenBalance = WELL.balanceOf(address(this));
        _swapFrom(
            address(WELL),
            address(asset),
            rewardTokenBalance,
            _getAmountOut(rewardTokenBalance, address(WELL), address(asset))
        );
    }

    /**
     * @dev Buys the borrow token using the strategy's assets.
     * This function should only ever be called when withdrawing all funds from the strategy if there is debt left over.
     * Initially, it tries to sell rewards for the needed amount of base token, then it will swap assets.
     * Using this function in a standard withdrawal can cause it to be sandwiched, which is why rewards are used first.
     */
    function _buyBorrowToken() internal virtual override {
        /// Try to obtain the required amount from rewards tokens before swapping assets and reporting losses.
        _claimAndSellRewards();

        uint256 borrowTokenStillOwed = borrowTokenOwedBalance();
        /// Check if our debt balance is still greater than our base token balance
        if (borrowTokenStillOwed > 0) {
            /// Need to account for both slippage and diff in the oracle price.
            /// Should be only swapping very small amounts so its just to make sure there is no massive sandwich
            uint256 maxAssetBalance = (_fromUsd(
                _toUsd(borrowTokenStillOwed, borrowToken),
                address(asset)
            ) * (MAX_BPS + slippage)) / MAX_BPS;
            /// Under 10 can cause rounding errors from token conversions, no need to swap that small amount
            if (maxAssetBalance <= 10) return;

            _swapFrom(
                address(asset),
                borrowToken,
                maxAssetBalance,
                borrowTokenStillOwed
            );
        }
    }

    /**
     * @dev Will swap from the base token => underlying asset.
     */
    function _sellBorrowToken(uint256 _amount) internal virtual override {
        _swapFrom(
            borrowToken,
            address(asset),
            _amount,
            _getAmountOut(_amount, borrowToken, address(asset))
        );
    }

    function _getAeroAmountOut(
        uint256 _amountIn,
        address _from,
        address _to
    ) internal view returns (uint256) {
        IAeroRouter.Route[] memory _routes = routes[_from][_to];
        return
            AERODROME_ROUTER.getAmountsOut(_amountIn, _routes)[_routes.length];
    }

    function _swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal virtual {
        if (_amountIn > minAmountToSell) {
            _checkAllowance(address(AERODROME_ROUTER), _from, _amountIn);

            AERODROME_ROUTER.swapExactTokensForTokens(
                _amountIn,
                _minAmountOut,
                routes[_from][_to],
                address(this),
                block.timestamp
            );
        }
    }

    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal virtual {
        if (ERC20(_token).allowance(address(this), _contract) < _amount) {
            ERC20(_token).safeApprove(_contract, 0);
            ERC20(_token).safeApprove(_contract, _amount);
        }
    }

    function setTradeFactory(address _tradeFactory) external onlyManagement {
        _setTradeFactory(_tradeFactory, address(asset));
    }

    function addToken(address _token) external onlyManagement {
        require(
            _token != address(asset) &&
                _token != borrowToken &&
                _token != address(lenderVault),
            "!allowed"
        );
        _addToken(_token, address(asset));
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external {
        require(msg.sender == GOV, "!gov");
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }

    receive() external payable {
        WETH.deposit{value: msg.value}();
    }
}
