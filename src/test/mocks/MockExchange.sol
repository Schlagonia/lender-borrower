// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IExchange} from "../../interfaces/IExchange.sol";

contract MockExchange is IExchange {
    using SafeERC20 for IERC20;

    uint256 internal constant PRICE_SCALE = 1e8;

    address public immutable BORROW;
    address public immutable COLLATERAL;
    address public immutable sweeper;

    uint256 public borrowPrice;
    uint256 public collateralPrice;

    uint8 internal immutable borrowDecimals;
    uint8 internal immutable collateralDecimals;

    constructor(
        address _borrow,
        address _collateral,
        uint256 _borrowPrice,
        uint256 _collateralPrice,
        address _sweeper
    ) {
        require(_borrow != address(0) && _collateral != address(0), "token");
        require(_borrowPrice > 0 && _collateralPrice > 0, "price");
        require(_sweeper != address(0), "sweeper");

        BORROW = _borrow;
        COLLATERAL = _collateral;
        borrowPrice = _borrowPrice;
        collateralPrice = _collateralPrice;
        sweeper = _sweeper;
        borrowDecimals = IERC20Metadata(_borrow).decimals();
        collateralDecimals = IERC20Metadata(_collateral).decimals();
    }

    function setPrices(
        uint256 _borrowPrice,
        uint256 _collateralPrice
    ) external {
        require(msg.sender == sweeper, "!sweeper");
        require(_borrowPrice > 0 && _collateralPrice > 0, "price");

        borrowPrice = _borrowPrice;
        collateralPrice = _collateralPrice;
    }

    function swap(
        uint256 amount,
        uint256 minAmount,
        bool fromBorrow
    ) external returns (uint256) {
        require(amount > 0, "amount");

        if (fromBorrow) {
            uint256 collateralOut = _quoteExactInput(
                amount,
                borrowPrice,
                collateralPrice,
                borrowDecimals,
                collateralDecimals
            );
            require(collateralOut >= minAmount, "slippage");

            IERC20(BORROW).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(COLLATERAL).safeTransfer(msg.sender, collateralOut);
            return collateralOut;
        }

        uint256 collateralIn = _quoteExactOutput(
            amount,
            collateralPrice,
            borrowPrice,
            collateralDecimals,
            borrowDecimals
        );
        require(collateralIn <= minAmount, "slippage");

        IERC20(COLLATERAL).safeTransferFrom(
            msg.sender,
            address(this),
            collateralIn
        );
        IERC20(BORROW).safeTransfer(msg.sender, amount);
        return collateralIn;
    }

    function sweep(IERC20 _token) external {
        require(msg.sender == sweeper, "!sweeper");
        _token.safeTransfer(sweeper, _token.balanceOf(address(this)));
    }

    function _quoteExactInput(
        uint256 amountIn,
        uint256 priceIn,
        uint256 priceOut,
        uint8 decimalsIn,
        uint8 decimalsOut
    ) internal pure returns (uint256) {
        return
            (amountIn * priceIn * (10 ** decimalsOut)) /
            (priceOut * (10 ** decimalsIn));
    }

    function _quoteExactOutput(
        uint256 amountOut,
        uint256 priceIn,
        uint256 priceOut,
        uint8 decimalsIn,
        uint8 decimalsOut
    ) internal pure returns (uint256) {
        return
            Math.ceilDiv(
                amountOut * priceOut * (10 ** decimalsIn),
                priceIn * (10 ** decimalsOut)
            );
    }
}
