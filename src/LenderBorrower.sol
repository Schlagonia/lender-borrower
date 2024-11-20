// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {BaseLenderBorrower, ERC20, SafeERC20, Math} from "./BaseLenderBorrower.sol";

abstract contract LenderBorrower is BaseLenderBorrower {
    using SafeERC20 for ERC20;

    /// @notice The governance address
    address public immutable GOV;

    constructor(
        address _asset,
        string memory _name,
        address _borrowToken,
        address _gov
    ) BaseLenderBorrower(_asset, _name, _borrowToken) {
        GOV = _gov;
    }

    // ----------------- WRITE FUNCTIONS ----------------- \\

    /**
     * @notice Supplies a specified amount of `asset` as collateral.
     * @param amount The amount of the asset to supply.
     */
    function _supplyCollateral(uint256 amount) internal virtual override;

    /**
     * @notice Withdraws a specified amount of collateral.
     * @param amount The amount of the collateral to withdraw.
     */
    function _withdrawCollateral(uint256 amount) internal virtual override;

    /**
     * @notice Borrows a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to borrow.
     */
    function _borrow(uint256 amount) internal virtual override;

    /**
     * @notice Repays a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to repay.
     */
    function _repay(uint256 amount) internal virtual override;

    /**
     * @notice Lends a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to lend.
     */
    function _lendBorrowToken(uint256 amount) internal virtual override;

    /**
     * @notice Withdraws a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to withdraw.
     */
    function _withdrawBorrowToken(uint256 amount) internal virtual override;

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
    function _maxBorrowAmount()
        internal
        view
        virtual
        override
        returns (uint256);

    /**
     * @notice Gets the max amount of `borrowToken` that could be deposited to the lender
     * @return The max deposit amount
     */
    function _lenderMaxDeposit()
        internal
        view
        virtual
        override
        returns (uint256);

    /**
     * @notice Gets the amount of borrowToken that could be withdrawn from the lender
     * @return The lender liquidity
     */
    function _lenderMaxWithdraw()
        internal
        view
        virtual
        override
        returns (uint256);

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
        returns (uint256);

    /**
     * @notice Gets supplied collateral balance
     * @return Collateral balance
     */
    function balanceOfCollateral()
        public
        view
        virtual
        override
        returns (uint256);

    /**
     * @notice Gets current borrow balance
     * @return Borrow balance
     */
    function balanceOfDebt() public view virtual override returns (uint256);

    /**
     * @notice Gets full depositor balance
     * @return Depositor balance
     */
    function balanceOfLentAssets()
        public
        view
        virtual
        override
        returns (uint256);

    /// ----------------- HARVEST / TOKEN CONVERSIONS ----------------- \\

    /**
     * @notice Claims reward tokens
     */
    function _claimRewards() internal virtual override;

    /**
     * @notice Claims and sells available reward tokens
     * @dev Handles claiming, selling rewards for base tokens if needed, and selling remaining rewards for asset
     */
    function _claimAndSellRewards() internal virtual override;

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
