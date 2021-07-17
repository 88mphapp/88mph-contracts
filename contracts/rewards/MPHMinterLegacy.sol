// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {MPHMinter} from "./MPHMinter.sol";

/**
    @title Dummy MPHMinter that doesn't mint anything. For legacy support.
*/
contract MPHMinterLegacy {
    MPHMinter public mphMinter;

    constructor(address _mphMinter) {
        mphMinter = MPHMinter(_mphMinter);
    }

    function mintDepositorReward(
        address, /*to*/
        uint256, /*depositAmount*/
        uint256, /*depositPeriodInSeconds*/
        uint256 /*interestAmount*/
    ) external pure returns (uint256) {
        return 0;
    }

    function takeBackDepositorReward(
        address, /*from*/
        uint256, /*mintMPHAmount*/
        bool /*early*/
    ) external pure returns (uint256) {
        return 0;
    }

    function mintFunderReward(
        address to,
        uint256 depositAmount,
        uint256 fundingCreationTimestamp,
        uint256 maturationTimestamp,
        uint256 interestPayoutAmount,
        bool early
    ) external returns (uint256) {
        return
            mphMinter.legacyMintFunderReward(
                msg.sender,
                to,
                depositAmount,
                fundingCreationTimestamp,
                maturationTimestamp,
                interestPayoutAmount,
                early
            );
    }
}
