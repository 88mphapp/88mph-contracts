// SPDX-License-Identifier: MIT

pragma solidity 0.5.17;

interface HarvestStaking {
    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    function rewardToken() external returns (address);

    function balanceOf(address account) external view returns (uint256);
}
