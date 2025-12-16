// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";

import {MorphoBlueLenderBorrower} from "../src/MorphoBlueLenderBorrower.sol";
import {Id} from "../src/interfaces/morpho/IMorpho.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Basic deployment script for MorphoBlueLenderBorrower without using the factory.
///         Provide constructor params via environment variables.
///         Required env:
///         ASSET, BORROW_TOKEN, LENDER_VAULT, GOV, MORPHO, MARKET_ID (bytes32), BORROW_USD_ORACLE, STRAT_NAME.
contract DeployMorpho is Script {

    address public deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    function run() external {
        // Defaults from test setup (WBTC/USDC market on mainnet):
        address asset = vm.envOr(
            "ASSET",
            address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) // WBTC
        );
        address borrowToken = vm.envOr(
            "BORROW_TOKEN",
            address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) // USDC
        );
        address lenderVault = vm.envOr(
            "LENDER_VAULT",
            address(0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204) // USDC ERC4626 vault
        );
        address gov = vm.envOr("GOV", deployer);
        address morpho = vm.envOr(
            "MORPHO",
            address(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb)
        );
        address borrowUsdOracle = vm.envOr(
            "BORROW_USD_ORACLE",
            address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6) // USDC/USD
        );
        bytes32 marketIdBytes = vm.envOr(
            "MARKET_ID",
            bytes32(
                0x3a85e619751152991742810df6ec69ce473daef99e28a64ab2340d7b7ccfee49
            )
        );
        address router = vm.envOr(
            "ROUTER",
            address(0xE592427A0AEce92De3Edee1F18E0157C05861564) // Uniswap V3 Router
        );
        string memory name = vm.envOr(
            "STRAT_NAME",
            string("Morpho WBTC/USDC Lender Borrower")
        );

        vm.startBroadcast();

        MorphoBlueLenderBorrower deployed = new MorphoBlueLenderBorrower(
            asset,
            name,
            borrowToken,
            lenderVault,
            gov,
            morpho,
            Id.wrap(marketIdBytes),
            borrowUsdOracle,
            router
        );

        console2.log("MorphoBlueLenderBorrower deployed at", address(deployed));

        vm.stopBroadcast();
    }
}
