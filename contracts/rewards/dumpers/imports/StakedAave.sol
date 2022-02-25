// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface StakedAave {
    function cooldown() external;

    function redeem(address to, uint256 amount) external;
}
