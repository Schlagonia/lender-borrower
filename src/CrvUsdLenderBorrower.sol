// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {IAMM} from "./interfaces/IAMM.sol";
import {IController} from "./interfaces/IController.sol";

import {BaseLenderBorrower, ERC20, SafeERC20, Math} from "./BaseLenderBorrower.sol";

contract CrvUsdLenderBorrower is BaseLenderBorrower {
    using SafeERC20 for ERC20;

    /// @notice The governance address
    address public immutable GOV;

    /// @notice The controller address
    address public immutable CONTROLLER;

    address public immutable AMM;

    uint256 public immutable CRVUSD_INDEX;

    uint256 public immutable ASSET_INDEX;

    constructor(
        address _asset,
        string memory _name,
        address _borrowToken,
        address _lenderVault,
        address _gov,
        address _controller,
        address _amm
    ) BaseLenderBorrower(_asset, _name, _borrowToken, _lenderVault) {
        GOV = _gov;
        CONTROLLER = _controller;
        ERC20(_asset).forceApprove(_controller, type(uint256).max);
        ERC20(_borrowToken).forceApprove(_controller, type(uint256).max);

        AMM = _amm;
        CRVUSD_INDEX = IAMM(AMM).coins(0) == address(asset) ? 1 : 0;
        ASSET_INDEX = CRVUSD_INDEX == 1 ? 0 : 1;
        ERC20(_borrowToken).forceApprove(_amm, type(uint256).max);
    }

    // ----------------- WRITE FUNCTIONS ----------------- \\

    /**
     * @notice Supplies a specified amount of `asset` as collateral.
     * @param amount The amount of the asset to supply.
     */
    function _supplyCollateral(uint256 amount) internal virtual override {
        // Must create a loan if one doesn't exist
        if (!IController(CONTROLLER).loan_exists(address(this))) {
            IController(CONTROLLER).create_loan(amount, 1, 10);
        } else {
            IController(CONTROLLER).add_collateral(amount);
        }
    }

    /**
     * @notice Withdraws a specified amount of collateral.
     * @param amount The amount of the collateral to withdraw.
     */
    function _withdrawCollateral(uint256 amount) internal virtual override {
        IController(CONTROLLER).remove_collateral(amount, false);
    }

    /**
     * @notice Borrows a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to borrow.
     */
    function _borrow(uint256 amount) internal virtual override {
        IController(CONTROLLER).borrow_more(0, amount);
    }

    /**
     * @notice Repays a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to repay.
     */
    function _repay(uint256 amount) internal virtual override {
        IController(CONTROLLER).repay(
            amount,
            address(this),
            2 ** 255 - 1,
            false
        );
    }

    // ----------------- INTERNAL VIEW FUNCTIONS ----------------- \\

    /**
     * @notice Gets asset price returned 1e8
     * @param _asset The asset address
     * @return price asset price
     */
    function _getPrice(
        address _asset
    ) internal view virtual override returns (uint256 price) {
        if (_asset == address(asset)) {
            price = IController(CONTROLLER).amm_price() / 1e10;
        } else {
            // Assumes crvUSD is 1
            price = 1e8;
        }
    }

    /**
     * @notice Checks if lending or borrowing is paused
     * @return True if paused, false otherwise
     */
    function _isSupplyPaused() internal view virtual override returns (bool) {
        return false;
    }

    /**
     * @notice Checks if borrowing is paused
     * @return True if paused, false otherwise
     */
    function _isBorrowPaused() internal view virtual override returns (bool) {
        return false;
    }

    /**
     * @notice Checks if the strategy is liquidatable
     * @return True if liquidatable, false otherwise
     */
    function _isLiquidatable() internal view virtual override returns (bool) {
        return IController(CONTROLLER).health(address(this), true) < 0;
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
        return type(uint256).max;
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
        return ERC20(borrowToken).balanceOf(address(CONTROLLER));
    }

    /**
     * @notice Gets net borrow APR from depositor
     * @param newAmount Simulated supply amount
     * @return Net borrow APR
     */
    function getNetBorrowApr(
        uint256 newAmount
    ) public view virtual override returns (uint256) {
        return 1;
    }

    /**
     * @notice Gets net reward APR from depositor
     * @param newAmount Simulated supply amount
     * @return Net reward APR
     */
    function getNetRewardApr(
        uint256 newAmount
    ) public view virtual override returns (uint256) {
        return 10;
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
        return IController(CONTROLLER).loan_discount() * 10;
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
        return IController(CONTROLLER).user_state(address(this))[0];
    }

    /**
     * @notice Gets current borrow balance
     * @return Borrow balance
     */
    function balanceOfDebt() public view virtual override returns (uint256) {
        return IController(CONTROLLER).debt(address(this));
    }

    /// ----------------- HARVEST / TOKEN CONVERSIONS ----------------- \\

    /**
     * @notice Claims reward tokens
     */
    function _claimRewards() internal virtual override {}

    /**
     * @notice Claims and sells available reward tokens
     * @dev Handles claiming, selling rewards for base tokens if needed, and selling remaining rewards for asset
     */
    function _claimAndSellRewards() internal virtual override {
        uint256 loose = balanceOfBorrowToken();
        uint256 have = balanceOfLentAssets() + loose;
        uint256 owe = balanceOfDebt();

        if (owe >= have) return;

        uint256 toSell = have - owe;
        if (toSell > loose) {
            _withdrawBorrowToken(toSell - loose);
        }

        loose = balanceOfBorrowToken();

        _sellBorrowToken(toSell > loose ? loose : toSell);
    }

    /**
     * @dev Buys the borrow token using the strategy's assets.
     * This function should only ever be called when withdrawing all funds from the strategy if there is debt left over.
     * Initially, it tries to sell rewards for the needed amount of base token, then it will swap assets.
     * Using this function in a standard withdrawal can cause it to be sandwiched, which is why rewards are used first.
     */
    function _buyBorrowToken() internal virtual override {
        uint256 amount = borrowTokenOwedBalance();
        IAMM(AMM).exchange(ASSET_INDEX, CRVUSD_INDEX, amount, 0);
    }

    /**
     * @dev Will swap from the base token => underlying asset.
     */
    function _sellBorrowToken(uint256 _amount) internal virtual override {
        IAMM(AMM).exchange(CRVUSD_INDEX, ASSET_INDEX, _amount, 0);
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external {
        require(msg.sender == GOV, "!gov");
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }
}
