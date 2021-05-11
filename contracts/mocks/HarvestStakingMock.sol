// SPDX-License-Identifier: MIT

/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/
* Synthetix: Rewards.sol
*
* Docs: https://docs.synthetix.io/
*
*
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

pragma solidity 0.8.3;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "../libs/SafeERC20.sol";

abstract contract IRewardDistributionRecipient is Ownable {
    mapping(address => bool) public isRewardDistribution;

    function notifyRewardAmount(uint256 reward) external virtual;

    modifier onlyRewardDistribution() {
        require(
            isRewardDistribution[_msgSender()],
            "Caller is not reward distribution"
        );
        _;
    }

    function setRewardDistribution(
        address _rewardDistribution,
        bool _isRewardDistribution
    ) external onlyOwner {
        isRewardDistribution[_rewardDistribution] = _isRewardDistribution;
    }
}

abstract contract LPTokenWrapper {
    using SafeERC20 for IERC20;

    IERC20 public stakeToken;

    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;

    constructor(address _stakeToken) {
        stakeToken = IERC20(_stakeToken);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        stakeToken.safeTransfer(msg.sender, amount);
    }
}

contract HarvestStakingMock is LPTokenWrapper, IRewardDistributionRecipient {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    uint256 public constant DURATION = 7 days;

    uint256 public starttime;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier checkStart {
        require(block.timestamp >= starttime, "Rewards: not start");
        _;
    }

    constructor(
        address _stakeToken,
        address _rewardToken,
        uint256 _starttime
    ) LPTokenWrapper(_stakeToken) {
        rewardToken = IERC20(_rewardToken);
        starttime = _starttime;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) *
                rewardRate *
                1e18) / totalSupply());
    }

    function earned(address account) public view returns (uint256) {
        return
            (balanceOf(account) *
                (rewardPerToken() - userRewardPerTokenPaid[account])) /
            1e18 +
            rewards[account];
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount)
        public
        override
        updateReward(msg.sender)
        checkStart
    {
        require(amount > 0, "Rewards: cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        override
        updateReward(msg.sender)
        checkStart
    {
        require(amount > 0, "Rewards: cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) checkStart {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function notifyRewardAmount(uint256 reward)
        external
        override
        onlyRewardDistribution
        updateReward(address(0))
    {
        // https://sips.synthetix.io/sips/sip-77
        require(reward > 0, "Rewards: reward == 0");
        require(
            reward < type(uint256).max / 10**18,
            "Rewards: rewards too large, would lock"
        );
        if (block.timestamp > starttime) {
            if (block.timestamp >= periodFinish) {
                rewardRate = reward / DURATION;
            } else {
                uint256 remaining = periodFinish - block.timestamp;
                uint256 leftover = remaining * rewardRate;
                rewardRate = (reward + leftover) / DURATION;
            }
            lastUpdateTime = block.timestamp;
            periodFinish = block.timestamp + DURATION;
            emit RewardAdded(reward);
        } else {
            rewardRate = reward / DURATION;
            lastUpdateTime = starttime;
            periodFinish = starttime + DURATION;
            emit RewardAdded(reward);
        }
    }
}
