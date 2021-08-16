// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import "./IRegistry.sol";

// B.Protocol BComptroller interface
interface IBComptroller {
    function claimComp(address holder) external;

    function registry() external returns (IRegistry);
}
