// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.3;

interface IAaveMining {
    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to
    ) external returns (uint256);
}
