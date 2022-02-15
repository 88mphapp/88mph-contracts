// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

// interfaces
import {ERC20Mock} from "./ERC20Mock.sol";

contract RewardsDistributorMock {
    uint256 public constant CLAIM_AMOUNT = 10**18;
    ERC20Mock public dai;
    address[] public markets;

    constructor(address _dai) {
        dai = ERC20Mock(_dai);
    }

    function claimRewards(address holder, address[] memory fDai) external {
        dai.mint(holder, CLAIM_AMOUNT);
    }

    function rewardToken() external view returns (address) {
        return address(dai);
    }

    function addMarket(address fToken) external {
        markets.push(fToken);
    }

    function getAllMarkets() external view returns (address[] memory) {
        return markets;
    }

    function isRewardsDistributor() external view returns (bool) {
        return true;
    }
}
