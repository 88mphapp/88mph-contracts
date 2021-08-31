// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract AdminControlled is AccessControlUpgradeable {
    function __AdminControlled_init() internal initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyAdmin {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "AdminControlled: not admin"
        );
        _;
    }
}
