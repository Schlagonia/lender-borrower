// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {IAeroRouter} from "./interfaces/Aero/IAeroRouter.sol";
import {CompoundV3LenderBorrower, ERC20, SafeERC20, Math} from "./CompoundV3LenderBorrower.sol";

contract CompoundV3LenderBorrowerAero is CompoundV3LenderBorrower {
    using SafeERC20 for ERC20;

    IAeroRouter internal constant AERODROME_ROUTER =
        IAeroRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);

    uint256 public minAmountToSell;

    mapping(address => mapping(address => IAeroRouter.Route[])) public routes;

    constructor(
        address _asset,
        string memory _name,
        address _borrowToken,
        address _gov,
        address _weth,
        address _comet,
        address _depositor
    )
        CompoundV3LenderBorrower(
            _asset,
            _name,
            _borrowToken,
            _gov,
            _weth,
            _comet,
            _depositor
        )
    {
        minAmountToSell = 1e10;
        /// To sell reward tokens
        ERC20(rewardToken).safeApprove(
            address(AERODROME_ROUTER),
            type(uint256).max
        );
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

    /**
     * @notice Claims and sells available reward tokens
     * @dev Handles claiming, selling rewards for base tokens if needed, and selling remaining rewards for asset
     */
    function _claimAndSellRewards() internal virtual override {
        // Claim rewards should have already been accrued.
        _claimRewards();

        uint256 rewardTokenBalance;
        uint256 borrowTokenNeeded = borrowTokenOwedBalance();

        if (borrowTokenNeeded > 0) {
            rewardTokenBalance = ERC20(rewardToken).balanceOf(address(this));
            /// We estimate how much we will need in order to get the amount of base
            /// Accounts for slippage and diff from oracle price, just to assure no horrible sandwich
            uint256 maxRewardToken = (_fromUsd(
                _toUsd(borrowTokenNeeded, borrowToken),
                rewardToken
            ) * (MAX_BPS + slippage)) / MAX_BPS;

            // Swap the least amount needed.
            rewardTokenBalance = Math.min(rewardTokenBalance, maxRewardToken);

            _swapFrom(
                rewardToken,
                borrowToken,
                rewardTokenBalance,
                _getAmountOut(rewardTokenBalance, rewardToken, borrowToken)
            );
        }

        rewardTokenBalance = ERC20(rewardToken).balanceOf(address(this));
        _swapFrom(
            rewardToken,
            address(asset),
            rewardTokenBalance,
            _getAmountOut(rewardTokenBalance, rewardToken, address(asset))
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
}
