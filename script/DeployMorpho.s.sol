// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {MorphoBlueLenderBorrowerFactory} from "../src/MorphoBlueLenderBorrowerFactory.sol";
import {Id} from "../src/interfaces/morpho/IMorpho.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";
import {AprOracle} from "@periphery/AprOracle/AprOracle.sol";

/// @notice Deploy factory first, then deploy multiple strategies from a hardcoded list.
///         Required env for factory:
///         GOV, MORPHO, ROUTER (optional: MANAGEMENT, PERFORMANCE_FEE_RECIPIENT, KEEPER, EMERGENCY_ADMIN).
contract DeployMorpho is Script {
    AprOracle public constant APR_ORACLE = AprOracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92);
    // Factory deploy params (hardcoded, no env).
    address public deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;
    address public morpho =
        0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public router =
        0xE592427A0AEce92De3Edee1F18E0157C05861564; // Uniswap V3 Router
    address public gov = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public management = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address public performanceFeeRecipient =
        0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69;
    address public keeper = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address public emergencyAdmin =
        0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    struct StrategyConfig {
        address asset;
        string name;
        address borrowToken;
        address lenderVault;
        bytes32 marketId;
        address borrowUsdOracle;
    }

    StrategyConfig[] public configs;

    function run() external {
        setupDeployments();

        uint256 count = configs.length;
        require(count > 0, "no strategies");

        vm.startBroadcast();

        MorphoBlueLenderBorrowerFactory factory = new MorphoBlueLenderBorrowerFactory(
            deployer,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin,
            gov,
            morpho,
            router
        );

        console2.log("MorphoBlueLenderBorrowerFactory deployed at", address(factory));

        StrategyAprOracle aprOracle = StrategyAprOracle(0x8C1dB64512A62A2E9528f4B54d8FbC924b99251c);

        console2.log("StrategyAprOracle deployed at", address(aprOracle));

        for (uint256 i = 0; i < count; i++) {
            StrategyConfig storage cfg = configs[i];
            address strategy = factory.newStrategy(
                cfg.asset,
                cfg.name,
                cfg.borrowToken,
                cfg.lenderVault,
                Id.wrap(cfg.marketId),
                cfg.borrowUsdOracle
            );
            console2.log("Strategy deployed", i, strategy);

            IStrategyInterface(strategy).acceptManagement();
            IStrategyInterface(strategy).setPerformanceFee(500);
            IStrategyInterface(strategy).setLossLimitRatio(10);

            if (cfg.asset != 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3) {
                IStrategyInterface(strategy).setUniFees(cfg.asset, cfg.borrowToken, 3000);
                IStrategyInterface(strategy).setUniBase(cfg.borrowToken);
            } else {
                IStrategyInterface(strategy).setUniFees(cfg.asset, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 500);
                IStrategyInterface(strategy).setUniFees(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, cfg.borrowToken, 500);
            }

            APR_ORACLE.setOracle(strategy, address(aprOracle));

            IStrategyInterface(strategy).setPendingManagement(management);
        }

        factory.setAddresses(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );

        vm.stopBroadcast();
    }

    function setupDeployments() internal {
        delete configs;

        // First entry: existing WBTC/USDC setup on mainnet.
        configs.push(
            StrategyConfig({
                asset: address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599), // WBTC
                name: "Morpho WBTC/yvUSDC-1 Lender Borrower",
                borrowToken: address(
                    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
                ), // USDC
                lenderVault: address(
                    0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204
                ), // USDC ERC4626 vault
                marketId: bytes32(
                    0x3a85e619751152991742810df6ec69ce473daef99e28a64ab2340d7b7ccfee49
                ),
                borrowUsdOracle: address(
                    0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6
                ) // USDC/USD
            })
        );

        configs.push(
            StrategyConfig({
                asset: address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599), // WBTC
                name: "Morpho WBTC/yvUSDT-1 Lender Borrower",
                borrowToken: address(
                    0xdAC17F958D2ee523a2206206994597C13D831ec7
                ), // USDT
                lenderVault: address(
                    0x310B7Ea7475A0B449Cfd73bE81522F1B88eFAFaa
                ), // yvUSDT ERC4626 vault
                marketId: bytes32(
                    0xa921ef34e2fc7a27ccc50ae7e4b154e16c9799d3387076c421423ef52ac4df99
                ),
                borrowUsdOracle: address(
                    0x3E7d1eAB13ad0104d2750B8863b489D65364e32D
                ) // USDT/USD
            })
        );

        configs.push(
            StrategyConfig({
                asset: address(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3), // OETH
                name: "Morpho OETH/yvUSDC-1 Lender Borrower",
                borrowToken: address(
                    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
                ), // USDC
                lenderVault: address(
                    0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204
                ), // USDC ERC4626 vault
                marketId: bytes32(
                    0xb8fef900b383db2dbbf4458c7f46acf5b140f26d603a6d1829963f241b82510e
                ),
                borrowUsdOracle: address(
                    0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6
                ) // USDC/USD
            })
        );
    }

}
