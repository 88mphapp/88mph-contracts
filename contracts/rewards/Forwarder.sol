// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "../libs/SafeERC20.sol";

/// @title Forwarder
/// @author zefram.eth
/// @notice Allows its controller to pull any ERC20 token from it
contract Forwarder {
    using SafeERC20 for IERC20;

    error Forwarder__NotController();

    address public immutable controller;

    constructor(address controller_) {
        controller = controller_;
    }

    function pullTokens(address token, uint256 amount) external {
        if (msg.sender != controller) revert Forwarder__NotController();

        IERC20(token).safeTransfer(controller, amount);
    }
}
