// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {AdminControlled} from "../../../libs/AdminControlled.sol";
import {StakedAave} from "../imports/StakedAave.sol";

contract StakedAaveWithdrawer is AdminControlled {
    StakedAave public constant STAKED_AAVE =
        StakedAave(0x4da27a545c0c5B758a6BA100e3a049001de870f5);

    function stakedAaveCooldown() external onlyAdmin {
        STAKED_AAVE.cooldown();
    }

    function stakedAaveRedeem() external onlyAdmin {
        STAKED_AAVE.redeem(address(this), type(uint256).max);
    }
}
