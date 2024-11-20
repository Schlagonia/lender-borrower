// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {Depositor} from "./Depositor.sol";
import {BaseLenderBorrower, ERC20, SafeERC20, Math} from "./BaseLenderBorrower.sol";
import {CometStructs} from "./interfaces/Compound/V3/CompoundV3.sol";
import {Comet} from "./interfaces/Compound/V3/CompoundV3.sol";
import {CometRewards} from "./interfaces/Compound/V3/CompoundV3.sol";

abstract contract CompoundV3LenderBorrower is BaseLenderBorrower {
    using SafeERC20 for ERC20;

    struct TokenInfo {
        address priceFeed;
        uint96 decimals;
    }

    // The address of the main V3 pool.
    Comet public immutable comet;

    /// The contract to get Comp rewards from.
    CometRewards public constant rewardsContract =
        CometRewards(0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1);

    address public immutable GOV;

    address internal immutable WETH;

    /// The Contract that will deposit the borrowToken back into Compound
    Depositor public immutable depositor;

    /// The reward Token (COMP).
    address public immutable rewardToken;

    /// Mapping from token => struct containing its reused info
    mapping(address => TokenInfo) public tokenInfo;

    constructor(
        address _asset,
        string memory _name,
        address _borrowToken,
        address _gov,
        address _weth,
        address _comet,
        address _depositor
    ) BaseLenderBorrower(_asset, _name, _borrowToken) {
        GOV = _gov;
        WETH = _weth;

        comet = Comet(_comet);
        minThreshold = comet.baseBorrowMin();

        depositor = Depositor(_depositor);
        require(borrowToken == address(depositor.borrowToken()), "!base");

        /// Set the rewardToken token we will get.
        rewardToken = rewardsContract.rewardConfig(_comet).token;

        /// To supply asset as collateral
        asset.safeApprove(_comet, type(uint256).max);
        /// To repay debt
        ERC20(borrowToken).safeApprove(_comet, type(uint256).max);
        /// For depositor to pull funds to deposit
        ERC20(borrowToken).safeApprove(_depositor, type(uint256).max);

        tokenInfo[_borrowToken] = TokenInfo({
            priceFeed: comet.baseTokenPriceFeed(),
            decimals: uint96(10 ** ERC20(_borrowToken).decimals())
        });

        tokenInfo[address(asset)] = TokenInfo({
            priceFeed: comet.getAssetInfoByAddress(address(asset)).priceFeed,
            decimals: uint96(10 ** ERC20(address(asset)).decimals())
        });

        tokenInfo[rewardToken] = TokenInfo({
            priceFeed: 0x9DDa783DE64A9d1A60c49ca761EbE528C35BA428,
            decimals: uint96(10 ** ERC20(rewardToken).decimals())
        });
    }

    /**
     * @notice Set the price feed for a given token
     * @dev Updates the price feed for the specified token after a revert check
     * Can only be called by management
     * @param _token Address of the token for which to set the price feed
     * @param _priceFeed Address of the price feed contract
     */
    function setPriceFeed(
        address _token,
        address _priceFeed
    ) external onlyManagement {
        // just check it doesn't revert
        comet.getPrice(_priceFeed);
        tokenInfo[_token].priceFeed = _priceFeed;
    }

    // ----------------- WRITE FUNCTIONS ----------------- \\

    /**
     * @notice Supplies a specified amount of `asset` as collateral.
     * @param amount The amount of the asset to supply.
     */
    function _supplyCollateral(uint256 amount) internal virtual override {
        comet.supply(address(asset), amount);
    }

    /**
     * @notice Withdraws a specified amount of collateral.
     * @param amount The amount of the collateral to withdraw.
     */
    function _withdrawCollateral(uint256 amount) internal virtual override {
        comet.withdraw(address(asset), amount);
    }

    /**
     * @notice Borrows a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to borrow.
     */
    function _borrow(uint256 amount) internal virtual override {
        comet.withdraw(borrowToken, amount);
    }

    /**
     * @notice Repays a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to repay.
     */
    function _repay(uint256 amount) internal virtual override {
        comet.supply(borrowToken, amount);
    }

    /**
     * @notice Lends a specified amount of `borrowToken`.
     */
    function _lendBorrowToken(uint256 /*amount*/) internal virtual override {
        depositor.deposit();
    }

    /**
     * @notice Withdraws a specified amount of `borrowToken`.
     * @param amount The amount of the borrowToken to withdraw.
     */
    function _withdrawBorrowToken(uint256 amount) internal virtual override {
        depositor.withdraw(amount);
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
     * @param _asset The asset address
     * @return price asset price
     */
    function _getPrice(
        address _asset
    ) internal view virtual override returns (uint256 price) {
        price = comet.getPrice(_getPriceFeedAddress(_asset));
        /// If weth is base token we need to scale response to e18
        if (price == 1e8 && _asset == WETH) price = 1e18;
    }

    /**
     * @notice Gets price feed address for an asset
     * @param _asset The asset address
     * @return priceFeed price feed address
     */
    function _getPriceFeedAddress(
        address _asset
    ) internal view returns (address priceFeed) {
        priceFeed = tokenInfo[_asset].priceFeed;
        if (priceFeed == address(0)) {
            priceFeed = comet.getAssetInfoByAddress(_asset).priceFeed;
        }
    }

    /**
     * @notice Checks if lending or borrowing is paused
     * @return True if paused, false otherwise
     */
    function _isPaused() internal view virtual override returns (bool) {
        return comet.isSupplyPaused() || comet.isWithdrawPaused();
    }

    /**
     * @notice Checks if the strategy is liquidatable
     * @return True if liquidatable, false otherwise
     */
    function _isLiquidatable() internal view virtual override returns (bool) {
        return comet.isLiquidatable(address(this));
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
        return
            uint256(
                comet.getAssetInfoByAddress(address(asset)).supplyCap -
                    comet.totalsCollateral(address(asset)).totalSupplyAsset
            );
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
        return ERC20(borrowToken).balanceOf(address(comet));
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
        return type(uint256).max;
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
            Math.min(
                ERC20(borrowToken).balanceOf(address(comet)),
                depositor.cometBalance()
            );
    }

    /**
     * @notice Gets net borrow APR from depositor
     * @param newAmount Simulated supply amount
     * @return Net borrow APR
     */
    function getNetBorrowApr(
        uint256 newAmount
    ) public view virtual override returns (uint256) {
        return depositor.getNetBorrowApr(newAmount);
    }

    /**
     * @notice Gets net reward APR from depositor
     * @param newAmount Simulated supply amount
     * @return Net reward APR
     */
    function getNetRewardApr(
        uint256 newAmount
    ) public view virtual override returns (uint256) {
        return depositor.getNetRewardApr(newAmount);
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
        return
            uint256(
                comet
                    .getAssetInfoByAddress(address(asset))
                    .liquidateCollateralFactor
            );
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
            uint256(
                comet.userCollateral(address(this), address(asset)).balance
            );
    }

    /**
     * @notice Gets current borrow balance
     * @return Borrow balance
     */
    function balanceOfDebt() public view virtual override returns (uint256) {
        return comet.borrowBalanceOf(address(this));
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
        return depositor.cometBalance();
    }

    /// ----------------- HARVEST / TOKEN CONVERSIONS ----------------- \\

    /**
     * @notice Claims reward tokens from Comet and depositor
     */
    function _claimRewards() internal virtual override {
        rewardsContract.claim(address(comet), address(this), true);
        /// Pull rewards from depositor even if not incentivized to accrue the account
        depositor.claimRewards(true);
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external {
        require(msg.sender == GOV, "!gov");
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }
}
