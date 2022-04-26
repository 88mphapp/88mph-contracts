// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

// interfaces
import {ERC20Mock} from "./ERC20Mock.sol";

contract AaveV3RewardsMock {
    uint256 public constant CLAIM_AMOUNT = 10**18;
    ERC20Mock public aave;

    function claimRewards(
        address[] calldata, /*assets*/
        uint256, /*amount*/
        address to,
        address rewAave
    ) external returns (uint256) {
        aave = ERC20Mock(rewAave);
        aave.mint(to, CLAIM_AMOUNT);
        return CLAIM_AMOUNT;
    }
}
