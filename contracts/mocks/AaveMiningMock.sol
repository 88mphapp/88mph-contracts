// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

// interfaces
import {ERC20Mock} from "./ERC20Mock.sol";

contract AaveMiningMock {
    uint256 public constant CLAIM_AMOUNT = 10**18;
    ERC20Mock public aave;

    constructor(address _aave) {
        aave = ERC20Mock(_aave);
    }

    function claimRewards(
        address[] calldata, /*assets*/
        uint256, /*amount*/
        address to
    ) external returns (uint256) {
        aave.mint(to, CLAIM_AMOUNT);
        return CLAIM_AMOUNT;
    }
}
