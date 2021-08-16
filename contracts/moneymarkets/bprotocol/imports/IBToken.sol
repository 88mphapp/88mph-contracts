// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

// B.Protocol bToken interface
interface IBToken {
    function mint(uint256 mintAmount) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);
}
