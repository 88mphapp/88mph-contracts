// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.4;

interface IGeistMining {
    function setClaimReceiver(address _user, address _receiver) external;

    function claim(address _user, address[] calldata _tokens) external;
}
