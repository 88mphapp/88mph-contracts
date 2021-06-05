// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.3;

import {MPHToken} from "../rewards/MPHToken.sol";
import {xMPH} from "../rewards/xMPH.sol";
import {DecMath} from "../libs/DecMath.sol";

contract xMPHEchidnaTest is xMPH {
    using DecMath for uint256;

    address private constant ECHIDNA_CALLER =
        0x00a329C0648769a73afAC7F9381e08fb43DBEA70;
    uint256 private constant REWARD_UNLOCK_PERIOD = 14 days;

    constructor() {
        // initialize
        MPHToken _mph = new MPHToken();
        _mph.initialize();
        __xMPH_init(address(_mph), REWARD_UNLOCK_PERIOD, ECHIDNA_CALLER);

        // mint caller some MPH
        _mph.ownerMint(ECHIDNA_CALLER, 100 * PRECISION);
    }

    function deposit(uint256 _mphAmount)
        external
        override
        returns (uint256 shareAmount)
    {
        uint256 beforeMPHBalance = mph.balanceOf(msg.sender);
        uint256 beforePricePerFullShare = getPricePerFullShare();
        uint256 beforeShareBalance = balanceOf(msg.sender);

        shareAmount = _deposit(_mphAmount);

        uint256 afterMPHBalance = mph.balanceOf(msg.sender);
        uint256 afterPricePerFullShare = getPricePerFullShare();
        uint256 afterShareBalance = balanceOf(msg.sender);

        assert(beforeMPHBalance - afterMPHBalance == _mphAmount);
        assert(beforePricePerFullShare == afterPricePerFullShare);
        assert(
            afterShareBalance - beforeShareBalance ==
                _mphAmount.decdiv(beforePricePerFullShare)
        );
    }

    function withdraw(uint256 _shareAmount)
        external
        override
        returns (uint256 mphAmount)
    {
        uint256 beforeMPHBalance = mph.balanceOf(msg.sender);
        uint256 beforePricePerFullShare = getPricePerFullShare();
        uint256 beforeShareBalance = balanceOf(msg.sender);

        mphAmount = _withdraw(_shareAmount);

        uint256 afterMPHBalance = mph.balanceOf(msg.sender);
        uint256 afterPricePerFullShare = getPricePerFullShare();
        uint256 afterShareBalance = balanceOf(msg.sender);

        assert(
            afterMPHBalance - beforeMPHBalance ==
                _shareAmount.decmul(beforePricePerFullShare)
        );
        assert(beforePricePerFullShare == afterPricePerFullShare);
        assert(beforeShareBalance - afterShareBalance == _shareAmount);
    }

    function distributeReward(uint256 rewardAmount) external override {
        uint256 beforeMPHBalance = mph.balanceOf(msg.sender);
        uint256 beforePricePerFullShare = getPricePerFullShare();

        _distributeReward(rewardAmount);

        uint256 afterMPHBalance = mph.balanceOf(msg.sender);
        uint256 afterPricePerFullShare = getPricePerFullShare();

        assert(hasRole(DISTRIBUTOR_ROLE, msg.sender));
        assert(beforeMPHBalance - afterMPHBalance == rewardAmount);
        assert(beforePricePerFullShare == afterPricePerFullShare);
    }
}
