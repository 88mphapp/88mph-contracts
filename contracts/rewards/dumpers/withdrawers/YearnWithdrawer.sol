// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {AdminControlled} from "../../../libs/AdminControlled.sol";
import {yERC20} from "../imports/yERC20.sol";

contract YearnWithdrawer is AdminControlled {
    function yearnWithdraw(address yTokenAddress) external onlyAdmin {
        yERC20 yToken = yERC20(yTokenAddress);
        uint256 balance = yToken.balanceOf(address(this));
        yToken.withdraw(balance);
    }
}
