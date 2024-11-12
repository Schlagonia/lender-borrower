// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {CompoundV3LenderBorrower, ERC20, SafeERC20} from "./CompoundV3LenderBorrower.sol";

/// Uniswap V3 Swapper
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

contract CompoundV3LenderBorrowerUniswap is
    CompoundV3LenderBorrower,
    UniswapV3Swapper
{
    using SafeERC20 for ERC20;

    constructor(
        address _asset,
        string memory _name,
        address _borrowToken,
        address _gov,
        address _weth,
        address _comet,
        address _depositor,
        uint24 _ethToAssetFee
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
        /// To sell reward tokens
        ERC20(rewardToken).safeApprove(address(router), type(uint256).max);

        /// Set the needed variables for the Uni Swapper
        /// Base will be weth
        base = WETH;
        /// Set the min amount for the swapper to sell
        minAmountToSell = 1e10;

        /// Default to .3% pool for comp/eth and to .05% pool for eth/borrowToken
        _setFees(3000, 500, _ethToAssetFee);
    }

    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    /**
     * @notice Set the fees for different token swaps
     * @dev Configures fees for token swaps and can only be called by management
     * @param _rewardToEthFee Fee for swapping reward tokens to ETH
     * @param _ethToBorrowTokenFee Fee for swapping ETH to borrowToken
     * @param _ethToAssetFee Fee for swapping ETH to asset token
     */
    function setFees(
        uint24 _rewardToEthFee,
        uint24 _ethToBorrowTokenFee,
        uint24 _ethToAssetFee
    ) external onlyManagement {
        _setFees(_rewardToEthFee, _ethToBorrowTokenFee, _ethToAssetFee);
    }

    /**
     * @notice Internal function to set the fees for token swaps involving `weth`
     * @dev Sets the swap fees for rewardToken to WETH, borrowToken to WETH, and asset to WETH
     * @param _rewardToEthFee Fee for swapping reward tokens to WETH
     * @param _ethToBorrowTokenFee Fee for swapping ETH to borrowToken
     * @param _ethToAssetFee Fee for swapping ETH to asset token
     */
    function _setFees(
        uint24 _rewardToEthFee,
        uint24 _ethToBorrowTokenFee,
        uint24 _ethToAssetFee
    ) internal {
        address _weth = base;
        _setUniFees(rewardToken, _weth, _rewardToEthFee);
        _setUniFees(borrowToken, _weth, _ethToBorrowTokenFee);
        _setUniFees(address(asset), _weth, _ethToAssetFee);
    }

    /**
     * @notice Swap the base token between `asset` and `weth`
     * @dev This can be used for management to change which pool to trade reward tokens.
     */
    function swapBase() external onlyManagement {
        base = base == address(asset) ? WETH : address(asset);
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
            if (maxRewardToken < rewardTokenBalance) {
                /// If we have enough swap an exact amount out
                _swapTo(
                    rewardToken,
                    borrowToken,
                    borrowTokenNeeded,
                    maxRewardToken
                );
            } else {
                /// if not swap everything we have
                _swapFrom(
                    rewardToken,
                    borrowToken,
                    rewardTokenBalance,
                    _getAmountOut(rewardTokenBalance, rewardToken, borrowToken)
                );
            }
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

            _swapTo(
                address(asset),
                borrowToken,
                borrowTokenStillOwed,
                maxAssetBalance
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
}
