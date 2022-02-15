// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

// Fuse RewardsDistributor interface
interface IRewardsDistributor {
    function getAllMarkets() external view returns (address[] memory);

    function isRewardsDistributor() external view returns (bool);

    function claimRewards(address holder, address[] memory fTokens) external;

    function rewardToken() external returns (address);
}
