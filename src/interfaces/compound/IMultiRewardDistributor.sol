// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.18;

// The commonly structures and events for the MultiRewardDistributor
interface IMultiRewardDistributor {
    function getAllMarketConfigs(
        address _mToken
    ) external view returns (MarketConfig[] memory);

    struct MarketConfig {
        // The owner/admin of the emission config
        address owner;
        // The emission token
        address emissionToken;
        // Scheduled to end at this time
        uint endTime;
        // Supplier global state
        uint224 supplyGlobalIndex;
        uint32 supplyGlobalTimestamp;
        // Borrower global state
        uint224 borrowGlobalIndex;
        uint32 borrowGlobalTimestamp;
        uint supplyEmissionsPerSec;
        uint borrowEmissionsPerSec;
    }

    struct MarketEmissionConfig {
        MarketConfig config;
        mapping(address => uint) supplierIndices;
        mapping(address => uint) supplierRewardsAccrued;
        mapping(address => uint) borrowerIndices;
        mapping(address => uint) borrowerRewardsAccrued;
    }

    struct RewardInfo {
        address emissionToken;
        uint totalAmount;
        uint supplySide;
        uint borrowSide;
    }

    struct IndexUpdate {
        uint224 newIndex;
        uint32 newTimestamp;
    }

    struct MTokenData {
        uint mTokenBalance;
        uint borrowBalanceStored;
    }

    struct RewardWithMToken {
        address mToken;
        RewardInfo[] rewards;
    }
}
