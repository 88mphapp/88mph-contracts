// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.3;

import {MPHToken} from "../rewards/MPHToken.sol";
import {xMPH} from "../rewards/xMPH.sol";
import {DecMath} from "../libs/DecMath.sol";
import {Asserts} from "./Asserts.sol";

contract xMPHEchidnaTest is Asserts {
    using DecMath for uint256;

    uint256 private constant REWARD_UNLOCK_PERIOD = 14 days;

    MPHToken private mphToken;
    xMPH private xMPHToken;

    constructor() {
        // initialize
        mphToken = new MPHToken();
        mphToken.initialize();

        // mint this contract some MPH
        mphToken.ownerMint(address(this), 100 * PRECISION);

        // deploy xMPH
        xMPHToken = new xMPH();
        uint256 mphAmount = xMPHToken.MIN_AMOUNT();
        mphToken.increaseAllowance(address(xMPHToken), mphAmount);
        xMPHToken.initialize(
            address(mphToken),
            REWARD_UNLOCK_PERIOD,
            address(this)
        );
    }

    /**
        Checks
     */

    function sanityChecks_deposit(uint256 _mphAmount) external {
        uint256 beforeMPHBalance = mphToken.balanceOf(address(this));
        uint256 beforePricePerFullShare = xMPHToken.getPricePerFullShare();
        uint256 beforeShareBalance = xMPHToken.balanceOf(address(this));

        mphToken.increaseAllowance(address(xMPHToken), _mphAmount);
        uint256 shareAmount = xMPHToken.deposit(_mphAmount);

        uint256 afterMPHBalance = mphToken.balanceOf(address(this));
        uint256 afterPricePerFullShare = xMPHToken.getPricePerFullShare();
        uint256 afterShareBalance = xMPHToken.balanceOf(address(this));

        Assert(beforeMPHBalance - afterMPHBalance == _mphAmount);
        AssertEpsilonEqual(beforePricePerFullShare, afterPricePerFullShare);
        Assert(
            afterShareBalance - beforeShareBalance ==
                _mphAmount.decdiv(beforePricePerFullShare)
        );
        Assert(afterShareBalance - beforeShareBalance == shareAmount);
    }

    function sanityChecks_withdraw(uint256 _shareAmount) external {
        uint256 beforeMPHBalance = mphToken.balanceOf(address(this));
        uint256 beforePricePerFullShare = xMPHToken.getPricePerFullShare();
        uint256 beforeShareBalance = xMPHToken.balanceOf(address(this));

        uint256 mphAmount = xMPHToken.withdraw(_shareAmount);

        uint256 afterMPHBalance = mphToken.balanceOf(address(this));
        uint256 afterPricePerFullShare = xMPHToken.getPricePerFullShare();
        uint256 afterShareBalance = xMPHToken.balanceOf(address(this));

        Assert(
            afterMPHBalance - beforeMPHBalance ==
                _shareAmount.decmul(beforePricePerFullShare)
        );
        Assert(afterMPHBalance - beforeMPHBalance == mphAmount);
        AssertEpsilonEqual(beforePricePerFullShare, afterPricePerFullShare);
        Assert(beforeShareBalance - afterShareBalance == _shareAmount);
    }

    function sanityChecks_distributeReward(uint256 rewardAmount) external {
        uint256 beforeMPHBalance = mphToken.balanceOf(address(this));
        uint256 beforePricePerFullShare = xMPHToken.getPricePerFullShare();

        mphToken.increaseAllowance(address(xMPHToken), rewardAmount);
        xMPHToken.distributeReward(rewardAmount);

        uint256 afterMPHBalance = mphToken.balanceOf(address(this));
        uint256 afterPricePerFullShare = xMPHToken.getPricePerFullShare();

        Assert(xMPHToken.hasRole(xMPHToken.DISTRIBUTOR_ROLE(), address(this)));
        Assert(beforeMPHBalance - afterMPHBalance == rewardAmount);
        AssertEpsilonEqual(beforePricePerFullShare, afterPricePerFullShare);
    }

    /**
        Actions
     */
    function action_sendMPHToContract(uint256 mphAmount) external {
        mphToken.transfer(address(xMPHToken), mphAmount);
    }
}
