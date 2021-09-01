// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

// Compound finance Comptroller interface
// Documentation: https://compound.finance/docs/comptroller
interface IComptroller {
    function claimComp(address holder) external;

    function getCompAddress() external view returns (address);
}
