// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

interface ILenderBorrower {
    // Public Variables
    function GOV() external view returns (address);

    function borrowToken() external view returns (address);

    function leaveDebtBehind() external view returns (bool);

    function depositLimit() external view returns (uint256);

    function targetLTVMultiplier() external view returns (uint16);

    function warningLTVMultiplier() external view returns (uint16);

    function maxGasPriceToTend() external view returns (uint256);

    function slippage() external view returns (uint256);

    // External Functions
    function setStrategyParams(
        uint256 _depositLimit,
        uint16 _targetLTVMultiplier,
        uint16 _warningLTVMultiplier,
        bool _leaveDebtBehind,
        uint256 _maxGasPriceToTend,
        uint256 _slippage
    ) external;

    // Public View Functions
    function getCurrentLTV() external view returns (uint256);

    function getNetBorrowApr(uint256 newAmount) external view returns (uint256);

    function getNetRewardApr(uint256 newAmount) external view returns (uint256);

    function getLiquidateCollateralFactor() external view returns (uint256);

    function balanceOfCollateral() external view returns (uint256);

    function balanceOfDebt() external view returns (uint256);

    function balanceOfLentAssets() external view returns (uint256);

    function balanceOfAsset() external view returns (uint256);

    function balanceOfBorrowToken() external view returns (uint256);

    function borrowTokenOwedBalance() external view returns (uint256);

    // Emergency Functions
    function claimAndSellRewards() external;

    function sellBorrowToken(uint256 _amount) external;

    function manualWithdraw(address _token, uint256 _amount) external;

    function manualRepayDebt() external;

    function sweep(address _token) external;
}
