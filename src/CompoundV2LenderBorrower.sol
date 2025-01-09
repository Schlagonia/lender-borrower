// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {IOracle} from "./interfaces/IOracle.sol";
import {CErc20I} from "./interfaces/compound/CErc20I.sol";
import {ComptrollerI} from "./interfaces/compound/ComptrollerI.sol";
import {CompoundOracleI} from "./interfaces/compound/CompoundOracleI.sol";

import {BaseLenderBorrower, ERC20, SafeERC20, Math} from "./BaseLenderBorrower.sol";

abstract contract CompoundV2LenderBorrower is BaseLenderBorrower {
    using SafeERC20 for ERC20;

    struct TokenInfo {
        address priceFeed;
        uint96 decimals;
    }

    modifier accrue() {
        accrueInterest();
        _;
    }

    /// @notice The governance address
    address public immutable GOV;

    CErc20I public immutable cToken;

    CErc20I public immutable cBorrowToken;

    ComptrollerI public immutable comptroller;

    uint256 public minAmountToSell;

    /// Mapping from token => struct containing its reused info
    mapping(address => TokenInfo) public tokenInfo;

    constructor(
        address _asset,
        string memory _name,
        address _borrowToken,
        address _lenderVault,
        address _gov,
        address _cToken,
        address _cBorrowToken
    ) BaseLenderBorrower(_asset, _name, _borrowToken, _lenderVault) {
        GOV = _gov;
        cToken = CErc20I(_cToken);
        require(cToken.underlying() == _asset, "!asset");

        cBorrowToken = CErc20I(_cBorrowToken);
        require(cBorrowToken.underlying() == _borrowToken, "!borrowToken");

        comptroller = ComptrollerI(cToken.comptroller());

        address[] memory cTokens = new address[](1);
        cTokens[0] = _cToken;
        comptroller.enterMarkets(cTokens);

        asset.safeApprove(_cToken, type(uint256).max);

        ERC20(_borrowToken).safeApprove(_cBorrowToken, type(uint256).max);

        minAmountToSell = 1e14;

        CompoundOracleI compoundOracle = CompoundOracleI(comptroller.oracle());

        tokenInfo[_borrowToken].decimals = uint96(
            10 ** ERC20(_borrowToken).decimals()
        );

        tokenInfo[address(asset)].decimals = uint96(
            10 ** ERC20(address(asset)).decimals()
        );
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
        _leveragePosition(_amount);
    }

    function _freeFunds(uint256 _amount) internal virtual override accrue {
        _liquidatePosition(_amount);
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
    ) external virtual onlyManagement {
        // Make sure it works
        IOracle(_priceFeed).latestAnswer();
        tokenInfo[_token].priceFeed = _priceFeed;
    }

    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external virtual onlyManagement {
        minAmountToSell = _minAmountToSell;
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
        if (amount == 0) return;
        require(cBorrowToken.repayBorrow(amount) == 0);
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
        if (priceFeed != address(0)) {
            return uint256(IOracle(priceFeed).latestAnswer());
        }

        uint256 decimalDelta = WAD / tokenInfo[_token].decimals;
        // Compound oracle expects the token to be the cToken
        if (_token == address(asset)) {
            _token = address(cToken);
        } else if (_token == address(borrowToken)) {
            _token = address(cBorrowToken);
        }

        return
            CompoundOracleI(comptroller.oracle()).getUnderlyingPrice(_token) /
            (1e10 * decimalDelta);
    }

    /**
     * @notice Checks if lending or borrowing is paused
     * @return True if paused, false otherwise
     */
    function _isSupplyPaused() internal view virtual override returns (bool) {
        return comptroller.mintGuardianPaused(address(cToken));
    }

    function _isBorrowPaused() internal view virtual override returns (bool) {
        return comptroller.borrowGuardianPaused(address(cBorrowToken));
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
        uint256 supplied = cToken.getCash() +
            cToken.totalBorrows() -
            cToken.totalReserves();
        uint256 supplyCap = comptroller.supplyCaps(address(cToken));

        return supplied > supplyCap ? 0 : supplyCap - supplied;
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
        uint256 borrowCap = comptroller.borrowCaps(address(cBorrowToken));
        uint256 borrows = cBorrowToken.totalBorrows();

        if (borrows >= borrowCap) return 0;

        return Math.min(borrowCap - borrows, cBorrowToken.getCash());
    }

    /**
     * @notice Gets net borrow APR from depositor
     * @param newAmount Simulated supply amount
     * @return Net borrow APR
     */
    function getNetBorrowApr(
        uint256 newAmount
    ) public view virtual override returns (uint256) {
        return WAD;
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
            WAD;
    }

    /**
     * @notice Gets current borrow balance
     * @return Borrow balance
     */
    function balanceOfDebt() public view virtual override returns (uint256) {
        return cBorrowToken.borrowBalanceStored(address(this));
    }

    /// ----------------- HARVEST / TOKEN CONVERSIONS ----------------- \\

    /**
     * @notice Claims reward tokens
     */
    function _claimRewards() internal virtual override {
        address[] memory tokens = new address[](2);
        tokens[0] = address(cToken);
        tokens[1] = address(cBorrowToken);

        comptroller.claimComp(address(this), tokens);
    }

    function _emergencyWithdraw(
        uint256 _amount
    ) internal virtual override accrue {
        super._emergencyWithdraw(_amount);
    }

    function sellBorrowToken(
        uint256 _amount
    ) external virtual override onlyEmergencyAuthorized accrue {
        if (_amount == type(uint256).max) {
            uint256 _balanceOfBorrowToken = balanceOfBorrowToken();
            _amount = Math.min(
                balanceOfLentAssets() + _balanceOfBorrowToken - balanceOfDebt(),
                _balanceOfBorrowToken
            );
        }
        _sellBorrowToken(_amount);
    }

    function manualRepayDebt()
        external
        virtual
        override
        onlyEmergencyAuthorized
        accrue
    {
        _repayTokenDebt();
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external {
        require(msg.sender == GOV, "!gov");
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }
}
