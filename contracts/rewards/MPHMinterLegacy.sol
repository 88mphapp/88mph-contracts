// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {MPHToken} from "./MPHToken.sol";
import {MPHMinter} from "./MPHMinter.sol";

/**
    @title Dummy MPHMinter that doesn't mint anything. For legacy support.
*/
contract MPHMinterLegacy {
    bytes32 public constant WHITELISTED_POOL_ROLE =
        keccak256("WHITELISTED_POOL_ROLE");

    MPHMinter public mphMinter;

    constructor(MPHMinter _mphMinter) {
        mphMinter = _mphMinter;
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
        address from,
        uint256 mintMPHAmount,
        bool early
    ) external returns (uint256) {
        require(
            mphMinter.hasRole(WHITELISTED_POOL_ROLE, msg.sender),
            "NOT_POOL"
        );
        if (!early) {
            return 0;
        }
        mphMinter.mph().transferFrom(
            from,
            mphMinter.govTreasury(),
            mintMPHAmount
        );
        return mintMPHAmount;
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
