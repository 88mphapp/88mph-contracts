// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

// Compound finance Comptroller interface
// Documentation: https://compound.finance/docs/comptroller
interface IComptroller {
    function claimReward(uint8 rewardType, address payable holder) external;

    function qiAddress() external view returns (address);
}
