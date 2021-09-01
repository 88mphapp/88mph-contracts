// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
    @notice Inherit this to allow for rescuing ERC20 tokens sent to the contract in error.
 */
abstract contract Rescuable {
    using SafeERC20 for IERC20;

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
        IERC20 tokenContract = IERC20(token);
        tokenContract.safeTransfer(
            target,
            tokenContract.balanceOf(address(this))
        );
    }

    /**
        @dev IMPORTANT MUST READ
        IF YOU DON'T GET IT RIGHT YOU WILL LOSE PEOPLE'S MONEY
        MAKE SURE YOU DO ALL OF THE FOLLOWING
        1) You MUST revert during a call to this function if the token rescue should be stopped.
        2) You MUST implement proper access control to prevent stealing funds.
        3) You MUST revert if `token` is a token your contract holds as user funds.
        @param token The ERC20 token to rescue
        @param target The address to send the tokens to
     */
    function _authorizeRescue(address token, address target) internal virtual;

    uint256[50] private __gap;
}
