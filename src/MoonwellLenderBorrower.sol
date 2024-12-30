// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {IOracle} from "./interfaces/IOracle.sol";
import {IAeroRouter} from "./interfaces/Aero/IAeroRouter.sol";

import {CompoundV2LenderBorrower, ERC20, CErc20I, SafeERC20, Math} from "./CompoundV2LenderBorrower.sol";

interface IWeth {
    function deposit() external payable;
}

interface MoonwellComptrollerI {
    function claimReward(address holder, CErc20I[] memory mTokens) external;
}

contract MoonwellLenderBorrower is CompoundV2LenderBorrower {
    using SafeERC20 for ERC20;

    ERC20 internal constant WELL =
        ERC20(0xA88594D404727625A9437C3f886C7643872296AE);

    IWeth internal constant WETH =
        IWeth(0x4200000000000000000000000000000000000006);

    IAeroRouter internal constant AERODROME_ROUTER =
        IAeroRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);

    mapping(address => mapping(address => IAeroRouter.Route[])) public routes;

    constructor(
        address _asset,
        string memory _name,
        address _borrowToken,
        address _lenderVault,
        address _gov,
        address _cToken,
        address _cBorrowToken
    )
        CompoundV2LenderBorrower(
            _asset,
            _name,
            _borrowToken,
            _lenderVault,
            _gov,
            _cToken,
            _cBorrowToken
        )
    {
        tokenInfo[address(WELL)] = TokenInfo({
            priceFeed: 0xBBF812FC0e45F58121983bd07C5079fF74433a61,
            decimals: uint96(10 ** WELL.decimals())
        });
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

    /// ----------------- HARVEST / TOKEN CONVERSIONS ----------------- \\

    /**
     * @notice Claims reward tokens
     */
    function _claimRewards() internal virtual override {
        CErc20I[] memory tokens = new CErc20I[](2);
        tokens[0] = cToken;
        tokens[1] = cBorrowToken;

        MoonwellComptrollerI(address(comptroller)).claimReward(
            address(this),
            tokens
        );
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
            uint256 borrowTokenNeeded;
            unchecked {
                borrowTokenNeeded = owe - have;
            }
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
            uint256 extra;
            unchecked {
                extra = have - owe;
            }

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

    receive() external payable {
        WETH.deposit{value: msg.value}();
    }
}
