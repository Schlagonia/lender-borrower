// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {Id} from "../src/interfaces/morpho/IMorpho.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";
import {AprOracle} from "@periphery/AprOracle/AprOracle.sol";
import {MorphoBlueLenderBorrower} from "../src/MorphoBlueLenderBorrower.sol";
import {ManualBorrowRewardAprOracle} from "../src/periphery/ManualBorrowRewardAprOracle.sol";

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
    address public aprOracle;
    address public constant EXCHANGE = 0xf46cbBCBE2b8D4dfB19c44652C1d015De1333C02; // curve swapper
    
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

        ManualBorrowRewardAprOracle manualBorrowRewardAprOracle = new ManualBorrowRewardAprOracle(deployer);
        console2.log("ManualBorrowRewardAprOracle deployed at", address(manualBorrowRewardAprOracle));
        return;

        if (aprOracle == address(0)) {
            aprOracle = address(new StrategyAprOracle(deployer));
        }

        console2.log("StrategyAprOracle deployed at", address(aprOracle));

        for (uint256 i = 0; i < count; i++) {
            StrategyConfig storage cfg = configs[i];
            address strategy = address(new MorphoBlueLenderBorrower(
                cfg.asset,
                cfg.name,
                cfg.borrowToken,
                cfg.lenderVault,
                gov,
                morpho,
                Id.wrap(cfg.marketId),
                cfg.borrowUsdOracle,
                router,
                address(EXCHANGE)
            ));
            console2.log("Strategy deployed", i, strategy);

            IStrategyInterface(strategy).setPerformanceFeeRecipient(performanceFeeRecipient);
            IStrategyInterface(strategy).setKeeper(keeper);
            IStrategyInterface(strategy).setEmergencyAdmin(emergencyAdmin);
            IStrategyInterface(strategy).setPerformanceFee(500);
            IStrategyInterface(strategy).setLossLimitRatio(10);

            if (cfg.asset != 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3) {
                IStrategyInterface(strategy).setUniFees(cfg.asset, cfg.borrowToken, 3000);
                IStrategyInterface(strategy).setUniBase(cfg.borrowToken);
            } else {
                address weth = IStrategyInterface(strategy).base();
                IStrategyInterface(strategy).setUniFees(cfg.asset, weth, 500);
                IStrategyInterface(strategy).setUniFees(weth, cfg.borrowToken, 500);
            }

            APR_ORACLE.setOracle(strategy, address(aprOracle));

            IStrategyInterface(strategy).setPendingManagement(management);
        }

        vm.stopBroadcast();
    }

    function setupDeployments() internal {
        delete configs;
        if (block.chainid == 1) {
            setupMainnetDeployments();
        } else if (block.chainid == 747474) {
            setupKatanaDeployments();
        } else {
            revert("Unsupported chain");
        }
    }

    function setupMainnetDeployments() internal {
        aprOracle = 0x8C1dB64512A62A2E9528f4B54d8FbC924b99251c;

        /**
        // First entry: existing WBTC/USDC setup on mainnet.
        configs.push(
            StrategyConfig({
                asset: address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599), // WBTC
                name: "Morpho WBTC/yvUSD Lender Borrower",
                borrowToken: address(
                    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
                ), // USDC
                lenderVault: address(
                    0x696d02Db93291651ED510704c9b286841d506987
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
        */


        configs.push(
            StrategyConfig({
                asset: address(0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b), // syrupUSDC
                name: "Morpho syrupUSDC/Euler Ondo PYUSD Lender Borrower",
                borrowToken: address(
                    0x6c3ea9036406852006290770BEdFcAbA0e23A0e8
                ), // PYUSD
                lenderVault: address(
                    0x69ebF644533655B5D3b6455e8E47ddE21b5993f1
                ), // EVK PYUSD ERC4626 vault
                marketId: bytes32(
                    0xc9629945524f3fde56c7e8854a6c3d48e76b9d97236abbe73c750fcc7aeb8501
                ),
                borrowUsdOracle: address(
                    0x39E31761911b9aaBAEF5fb81B18Fd1C24a60E884
                ) // PYUSD/USD
            })
        );
    }

    function setupKatanaDeployments() internal {
        // Override global variables for Katana.
        morpho = 0xD50F2DffFd62f94Ee4AEd9ca05C61d0753268aBc;
        router = 0x4e1d81A3E627b9294532e990109e4c21d217376C;
        gov = 0xe6ad5A88f5da0F276C903d9Ac2647A937c917162;
        management = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;
        performanceFeeRecipient = 0x1f399808fE52d0E960CAB84b6b54d5707ab27c8a;
        keeper = 0xC29cbdcf5843f8550530cc5d627e1dd3007EF231;
        emergencyAdmin = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;

        // vbWBTC/yvUSDC
        configs.push(
            StrategyConfig({
                asset: address(0x0913DA6Da4b42f538B445599b46Bb4622342Cf52), // vbWBTC
                name: "Morpho vbWBTC/yvUSDC Lender Borrower",
                borrowToken: address(0x203A662b0BD271A6ed5a60EdFbd04bFce608FD36),
                lenderVault: address(0x80c34BD3A3569E126e7055831036aa7b212cB159), // USDC ERC4626 vault
                marketId: bytes32(0xcd2dc555dced7422a3144a4126286675449019366f83e9717be7c2deb3daae3e),
                borrowUsdOracle: address(0xbe5CE90e16B9d9d988D64b0E1f6ed46EbAfb9606) // USDC/USD
            })
        );

        // vbWBTC/yvUSDT
        configs.push(
            StrategyConfig({
                asset: address(0x0913DA6Da4b42f538B445599b46Bb4622342Cf52), // vbWBTC
                name: "Morpho vbWBTC/yvUSDT Lender Borrower",
                borrowToken: address(0x2DCa96907fde857dd3D816880A0df407eeB2D2F2),
                lenderVault: address(0x9A6bd7B6Fd5C4F87eb66356441502fc7dCdd185B), // USDT ERC4626 vault
                marketId: bytes32(0xd4ab732112fa9087c9c3c3566cd25bc78ee7be4f1b8bdfe20d6328debb818656),
                borrowUsdOracle: address(0xF03E1566Fc6B0eBFA3dD3aA197759C4c6617ec78) // USDT/USD
            })
        );

        // vbWETH/yvUSDC
        configs.push(
            StrategyConfig({
                asset: address(0xEE7D8BCFb72bC1880D0Cf19822eB0A2e6577aB62), // vbWETH
                name: "Morpho vbWETH/yvUSDC Lender Borrower",
                borrowToken: address(0x203A662b0BD271A6ed5a60EdFbd04bFce608FD36),
                lenderVault: address(0x80c34BD3A3569E126e7055831036aa7b212cB159), // USDC ERC4626 vault
                marketId: bytes32(0x2fb14719030835b8e0a39a1461b384ad6a9c8392550197a7c857cf9fcbd6c534),
                borrowUsdOracle: address(0xbe5CE90e16B9d9d988D64b0E1f6ed46EbAfb9606) // USDC/USD
            })
        );
    }

}
