// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {CErc20I} from "./interfaces/compound/CErc20I.sol";
import {ComptrollerI} from "./interfaces/compound/ComptrollerI.sol";
import {IAeroRouter} from "./interfaces/Aero/IAeroRouter.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {BaseLenderBorrower, ERC20, SafeERC20, Math} from "./BaseLenderBorrower.sol";

import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

interface MoonwellComptrollerI is ComptrollerI {
    function claimReward(address holder, CErc20I[] memory mTokens) external;
}

abstract contract LenderBorrower is BaseLenderBorrower, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    ERC20 internal constant WELL =
        ERC20(0xA88594D404727625A9437C3f886C7643872296AE);
    ERC20 internal constant WETH =
        ERC20(0x4200000000000000000000000000000000000006);
    ERC20 internal constant USDC =
        ERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    IAeroRouter public constant AERODROME_ROUTER =
        IAeroRouter(0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5);

    address internal constant AERODROME_FACTORY =
        0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    /// @notice The governance address
    address public immutable GOV;

    CErc20I public immutable cToken;

    CErc20I public immutable cBorrowToken;

    MoonwellComptrollerI public immutable comptroller;

    IERC4626 public immutable lenderVault;

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

        lenderVault = IERC4626(_lenderVault);
        require(lenderVault.asset() == _borrowToken, "!lenderVault");

        asset.safeApprove(_cToken, type(uint256).max);

        ERC20(_borrowToken).safeApprove(_lenderVault, type(uint256).max);
    }

    // ----------------- WRITE FUNCTIONS ----------------- \\

    /**
     * @notice Supplies a specified amount of `asset` as collateral.
     * @param amount The amount of the asset to supply.
     */
    function _supplyCollateral(uint256 amount) internal virtual override {
        require(cToken.mint(amount) == 0);
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
        lenderVault.withdraw(amount, address(this), address(this));
    }

    // ----------------- INTERNAL VIEW FUNCTIONS ----------------- \\

    /**
     * @notice Gets asset price returned 1e18
     * @param _asset The asset address
     * @return price asset price
     */
    function _getPrice(
        address _asset
    ) internal view virtual override returns (uint256 price);

    /**
     * @notice Checks if lending or borrowing is paused
     * @return True if paused, false otherwise
     */
    function _isPaused() internal view virtual override returns (bool);

    /**
     * @notice Checks if the strategy is liquidatable
     * @return True if liquidatable, false otherwise
     */
    function _isLiquidatable() internal view virtual override returns (bool);

    /**
     * @notice Gets the supply cap for the collateral asset if any
     * @return The supply cap
     */
    function _maxCollateralDeposit()
        internal
        view
        virtual
        override
        returns (uint256);

    /**
     * @notice Gets the max amount of `borrowToken` that could be borrowed
     * @return The max borrow amount
     */
    function _maxBorrowAmount() internal view virtual override returns (uint256);

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
        return lenderVault.maxWithdraw(address(this));
    }

    /**
     * @notice Gets net borrow APR from depositor
     * @param newAmount Simulated supply amount
     * @return Net borrow APR
     */
    function getNetBorrowApr(
        uint256 newAmount
    ) public view virtual override returns (uint256);

    /**
     * @notice Gets net reward APR from depositor
     * @param newAmount Simulated supply amount
     * @return Net reward APR
     */
    function getNetRewardApr(
        uint256 newAmount
    ) public view virtual override returns (uint256);

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
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(
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
    function _claimRewards() internal virtual override {
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

        uint256 wellBalance = WELL.balanceOf(address(this));
        if (wellBalance != 0) {
            IAeroRouter.Route[] memory routes = new IAeroRouter.Route[](1);
            routes[0].from = address(WELL);
            routes[0].to = address(WETH);
            routes[0].factory = AERODROME_FACTORY;

            AERODROME_ROUTER.swapExactTokensForTokens(
                wellBalance, // amountIn
                0, // amountOutMin,
                routes,
                address(this),
                type(uint256).max
            );
        }

        uint256 rewardTokenBalance;
        uint256 borrowTokenNeeded = borrowTokenOwedBalance();

        if (borrowTokenNeeded > 0) {
            rewardTokenBalance = WETH.balanceOf(address(this));
            /// We estimate how much we will need in order to get the amount of base
            /// Accounts for slippage and diff from oracle price, just to assure no horrible sandwich
            uint256 maxRewardToken = (_fromUsd(
                _toUsd(borrowTokenNeeded, address(borrowToken)),
                address(WETH)
            ) * (MAX_BPS + slippage)) / MAX_BPS;
            if (maxRewardToken < rewardTokenBalance) {
                /// If we have enough swap an exact amount out
                _swapTo(
                    address(WETH),
                    borrowToken,
                    borrowTokenNeeded,
                    maxRewardToken
                );
            } else {
                /// if not swap everything we have
                _swapFrom(
                    address(WETH),
                    borrowToken,
                    rewardTokenBalance,
                    _getAmountOut(
                        rewardTokenBalance,
                        address(WETH),
                        address(borrowToken)
                    )
                );
            }
        }

        rewardTokenBalance = WETH.balanceOf(address(this));
        _swapFrom(
            address(WETH),
            address(asset),
            rewardTokenBalance,
            _getAmountOut(rewardTokenBalance, address(WETH), address(asset))
        );
    }

    /**
     * @dev Buys the borrow token using the strategy's assets.
     * This function should only ever be called when withdrawing all funds from the strategy if there is debt left over.
     * Initially, it tries to sell rewards for the needed amount of base token, then it will swap assets.
     * Using this function in a standard withdrawal can cause it to be sandwiched, which is why rewards are used first.
     */
    function _buyBorrowToken() internal virtual override;

    /**
     * @dev Will swap from the base token => underlying asset.
     */
    function _sellBorrowToken(uint256 _amount) internal virtual override;

    /// @notice Sweep of non-asset ERC20 tokens to governance
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external {
        require(msg.sender == GOV, "!gov");
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }
}
