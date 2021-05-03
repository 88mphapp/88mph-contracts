// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

// interfaces
import {ERC20Mock} from "./ERC20Mock.sol";

contract ComptrollerMock {
    uint256 public constant CLAIM_AMOUNT = 10**18;
    ERC20Mock public comp;

    constructor(address _comp) {
        comp = ERC20Mock(_comp);
    }

    function claimComp(address holder) external {
        comp.mint(holder, CLAIM_AMOUNT);
    }

    function getCompAddress() external view returns (address) {
        return address(comp);
    }
}
