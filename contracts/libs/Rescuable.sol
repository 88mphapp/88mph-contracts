// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {
    SafeERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

abstract contract Rescuable {
    using SafeERC20Upgradeable for ERC20Upgradeable;

    function rescue(address token, address target) external {
        // make sure we're not stealing funds or something
        _authorizeRescue(token, target);

        // transfer token to target
        ERC20Upgradeable tokenContract = ERC20Upgradeable(token);
        tokenContract.safeTransfer(
            target,
            tokenContract.balanceOf(address(this))
        );
    }

    function _authorizeRescue(address token, address target) internal virtual;
}
