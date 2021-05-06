// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {
    SafeERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/**
    @notice Inherit this to allow for rescuing ERC20 tokens sent to the contract in error.
 */
abstract contract Rescuable {
    using SafeERC20Upgradeable for ERC20Upgradeable;

    /**
        @notice Rescues ERC20 tokens sent to the contract in error.
        @dev Need to implement {_authorizeRescue} to do access-control for this function.
        @param token The ERC20 token to rescue
        @param target The address to send the tokens to
     */
    function rescue(address token, address target) external virtual {
        // make sure we're not stealing funds or something
        _authorizeRescue(token, target);

        // transfer token to target
        ERC20Upgradeable tokenContract = ERC20Upgradeable(token);
        tokenContract.safeTransfer(
            target,
            tokenContract.balanceOf(address(this))
        );
    }

    /**
        @dev Should revert if the rescue call should be stopped.
        @param token The ERC20 token to rescue
        @param target The address to send the tokens to
     */
    function _authorizeRescue(address token, address target) internal virtual;

    uint256[50] private __gap;
}
