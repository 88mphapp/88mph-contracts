// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {DecMath} from "../libs/DecMath.sol";

/**
    @title Staked MPH
    @author Zefram Lou
    @notice The MPH staking contract
 */
contract xMPH is ERC20Upgradeable, AccessControlUpgradeable {
    using DecMath for uint256;

    uint256 internal constant PRECISION = 10**18;
    uint256 internal constant MAX_REWARD_UNLOCK_PERIOD = 365 days;
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    ERC20Upgradeable public mph;
    uint256 public rewardUnlockPeriod;
    uint256 public currentUnlockEndTimestamp;
    uint256 public lastRewardTimestamp;
    uint256 public lastRewardAmount;

    /**
        @param _mph The MPH token
        @param _rewardUnlockPeriod The length of each reward distribution period, in seconds
        @param _distributor The account that will call distributeReward()
     */
    function initialize(
        ERC20Upgradeable _mph,
        uint256 _rewardUnlockPeriod,
        address _distributor
    ) external initializer {
        __ERC20_init("Staked MPH", "xMPH");
        __AccessControl_init();

        // Validate input
        require(
            address(_mph) != address(0) && _distributor != address(0),
            "xMPH: 0 address"
        );
        require(
            _rewardUnlockPeriod > 0 &&
                _rewardUnlockPeriod <= MAX_REWARD_UNLOCK_PERIOD,
            "xMPH: invalid _rewardUnlockPeriod"
        );

        // _distributor and msg.sender are given DISTRIBUTOR_ROLE
        // DISTRIBUTOR_ROLE is managed by itself
        // msg.sender is given DEFAULT_ADMIN_ROLE which enables
        // calling setRewardUnlockPeriod()
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(DISTRIBUTOR_ROLE, msg.sender);
        _setupRole(DISTRIBUTOR_ROLE, _distributor);
        _setRoleAdmin(DISTRIBUTOR_ROLE, DISTRIBUTOR_ROLE);
        mph = _mph;
        rewardUnlockPeriod = _rewardUnlockPeriod;
    }

    /**
        @notice Deposit MPH to get xMPH
        @dev The amount can't be 0
        @param _mphAmount The amount of MPH to deposit
        @return shareAmount The amount of xMPH minted
     */
    function deposit(uint256 _mphAmount)
        external
        returns (uint256 shareAmount)
    {
        require(_mphAmount > 0, "xMPH: 0 amount");
        shareAmount = _mphAmount.decdiv(getPricePerFullShare());
        _mint(msg.sender, shareAmount);
        mph.transferFrom(msg.sender, address(this), _mphAmount);
    }

    /**
        @notice Withdraw MPH using xMPH
        @dev The amount can't be 0
        @param _shareAmount The amount of xMPH to burn
        @return mphAmount The amount of MPH withdrawn
     */
    function withdraw(uint256 _shareAmount)
        external
        returns (uint256 mphAmount)
    {
        require(_shareAmount > 0, "xMPH: 0 amount");
        mphAmount = _shareAmount.decmul(getPricePerFullShare());
        _burn(msg.sender, _shareAmount);
        mph.transfer(msg.sender, mphAmount);
    }

    /**
        @notice Compute the amount of MPH that can be withdrawn by burning
                1 xMPH. Increases linearly during a reward distribution period.
        @dev Initialized to be PRECISION (representing 1 MPH = 1 xMPH)
        @return The amount of MPH that can be withdrawn by burning
                1 xMPH
     */
    function getPricePerFullShare() public view returns (uint256) {
        uint256 totalShares = totalSupply();
        uint256 mphBalance = mph.balanceOf(address(this));
        if (totalShares == 0 || mphBalance == 0) {
            return PRECISION;
        }
        uint256 _lastRewardAmount = lastRewardAmount;
        uint256 _currentUnlockEndTimestamp = currentUnlockEndTimestamp;
        if (
            _lastRewardAmount == 0 ||
            block.timestamp >= _currentUnlockEndTimestamp
        ) {
            // no rewards or rewards fully unlocked
            // entire balance is withdrawable
            return mphBalance.decdiv(totalShares);
        } else {
            // rewards not fully unlocked
            // deduct locked rewards from balance
            uint256 _lastRewardTimestamp = lastRewardTimestamp;
            uint256 lockedRewardAmount =
                (_lastRewardAmount *
                    (_currentUnlockEndTimestamp - block.timestamp)) /
                    (_currentUnlockEndTimestamp - _lastRewardTimestamp);
            return (mphBalance - lockedRewardAmount).decdiv(totalShares);
        }
    }

    /**
        @notice Distributes MPH rewards to xMPH holders
        @dev When not in a distribution period, start a new one with rewardUnlockPeriod seconds.
             When in a distribution period, add rewards to current period
     */
    function distributeReward(uint256 rewardAmount) external {
        require(rewardAmount > 0, "xMPH: reward == 0");
        require(
            rewardAmount < type(uint256).max / PRECISION,
            "xMPH: rewards too large, would lock"
        );
        require(hasRole(DISTRIBUTOR_ROLE, msg.sender), "xMPH: not distributor");

        // transfer rewards from sender
        mph.transferFrom(msg.sender, address(this), rewardAmount);

        if (block.timestamp >= currentUnlockEndTimestamp) {
            // start new reward period
            currentUnlockEndTimestamp = block.timestamp + rewardUnlockPeriod;
            lastRewardTimestamp = block.timestamp;
            lastRewardAmount = rewardAmount;
        } else {
            // add rewards to current reward period
            uint256 lockedRewardAmount =
                (lastRewardAmount *
                    (currentUnlockEndTimestamp - block.timestamp)) /
                    (currentUnlockEndTimestamp - lastRewardTimestamp);
            lastRewardTimestamp = block.timestamp;
            lastRewardAmount = rewardAmount + lockedRewardAmount;
        }
    }

    function setRewardUnlockPeriod(uint256 newValue) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "xMPH: not admin");
        require(
            newValue > 0 && newValue <= MAX_REWARD_UNLOCK_PERIOD,
            "xMPH: invalid value"
        );
        rewardUnlockPeriod = newValue;
    }

    uint256[45] private __gap;
}
