// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

interface IController {
    function create_loan(uint256 collateral, uint256 debt, uint256 _n) external;
    function repay(
        uint256 debt_amount,
        address user,
        int256 _n,
        bool use_eth
    ) external;
    function remove_collateral(
        uint256 collateral_amount,
        bool use_eth
    ) external;
    function add_collateral(uint256 collateral_amount) external;
    function borrow_more(uint256 collateral, uint256 debt) external;
    function debt(address user) external view returns (uint256);
    function health(address user, bool full) external view returns (int256);
    function user_state(address user) external view returns (uint256[4] memory);
    function amm_price() external view returns (uint256);
    function max_borrowable(
        uint256 collateral,
        uint256 _n
    ) external view returns (uint256);
    function loan_exists(address user) external view returns (bool);
    function loan_discount() external view returns (uint256);
}
