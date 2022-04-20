// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";

import {Bytes32AddressLib} from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

import {Forwarder} from "./Forwarder.sol";
import {Vesting02} from "./Vesting02.sol";
import {DInterest} from "../DInterest.sol";
import {FullMath} from "../libs/FullMath.sol";

/// @title Vesting03
/// @author zefram.eth
/// @notice Distributes MPH rewards to depositors over time based on a staking-pool like logic
contract Vesting03 is Vesting02 {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using Clones for address;
    using PRBMathUD60x18 for uint256;
    using Bytes32AddressLib for address;
    using Bytes32AddressLib for bytes32;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error Error_Overflow();
    error Error_NotMinter();
    error Error_NotVestOwner();
    error Error_AmountTooLarge();
    error Error_ForwarderNotDeployed();
    error Error_NotRewardDistributor();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event RewardAdded(address indexed pool, uint256 reward);
    event Staked(uint64 indexed vestID, uint256 amount);
    event Withdrawn(uint64 indexed vestID, uint256 amount);
    event RewardPaid(uint64 indexed vestID, uint256 reward);
    event UpdateDuration(uint64 newDuration);
    event SetRewardDistributor(address indexed account, bool isDistributor);

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice The Forwarder template for cloning Forwarders
    Forwarder public immutable forwarderTemplate;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    struct PeriodInfo {
        /// @notice The last Unix timestamp (in seconds) when rewardPerTokenStored was updated
        uint64 lastUpdateTime;
        /// @notice The Unix timestamp (in seconds) at which the current reward period ends
        uint64 periodFinish;
    }
    /// @notice Info about the reward period of each pool
    /// @dev pool => value
    mapping(address => PeriodInfo) public periodInfo;

    /// @notice The per-second rate at which rewardPerToken increases
    /// @dev pool => value
    mapping(address => uint256) public rewardRate;

    /// @notice The last stored rewardPerToken value
    /// @dev pool => value
    mapping(address => uint256) public rewardPerTokenStored;

    /// @notice The rewardPerToken value when a vest last staked/withdrew/withdrew rewards
    /// @dev vestId => value
    mapping(uint64 => uint256) public vestRewardPerTokenPaid;

    /// @notice The earned() value when a vest last staked/withdrew/withdrew rewards
    /// @dev vestId => value
    mapping(uint64 => uint256) public rewards;

    /// @notice The total virtual tokens staked in each pool
    /// @dev pool => value
    mapping(address => uint256) public totalSupply;

    /// @notice The total deposit of each pool when a vest related to the pool was last updated
    /// @dev pool => value
    mapping(address => uint256) public totalDepositStored;

    /// @notice Tracks if an address can call notifyReward()
    /// @dev account => value
    mapping(address => bool) public isRewardDistributor;

    /// @notice The duration of each reward period, in seconds
    uint64 public DURATION;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor() {
        forwarderTemplate = new Forwarder(address(this));
    }

    /// -----------------------------------------------------------------------
    /// Vesting02 compatibility
    /// -----------------------------------------------------------------------

    function createVestForDeposit(
        address to,
        address pool,
        uint64 depositID,
        uint256 /*vestAmountPerStablecoinPerSecond*/
    ) external virtual override returns (uint64 vestID) {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        if (address(msg.sender) != address(mphMinter)) {
            revert Error_NotMinter();
        }

        /// -----------------------------------------------------------------------
        /// Storage loads
        /// -----------------------------------------------------------------------

        uint256 totalSupply_ = totalSupply[pool];
        uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable(pool);
        uint256 rewardPerToken_ = _rewardPerToken(
            pool,
            totalSupply_,
            lastTimeRewardApplicable_,
            rewardRate[pool]
        );
        DInterest.Deposit memory deposit = DInterest(pool).getDeposit(
            depositID
        );
        uint256 depositAmount = FullMath.mulDiv(
            deposit.virtualTokenTotalSupply,
            PRECISION,
            PRECISION + deposit.interestRate
        );
        uint256 totalDeposit = DInterest(pool).totalDeposit();

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        // create vest object
        if (block.timestamp > type(uint64).max) {
            revert Error_Overflow();
        }
        vestList.push(
            Vest({
                pool: pool,
                depositID: depositID,
                lastUpdateTimestamp: 0,
                accumulatedAmount: 0,
                withdrawnAmount: 0,
                vestAmountPerStablecoinPerSecond: 0
            })
        );
        uint256 vestListLength = vestList.length;
        if (vestListLength > type(uint64).max) {
            revert Error_Overflow();
        }
        vestID = uint64(vestListLength); // 1-indexed
        depositIDToVestID[pool][depositID] = vestID;

        // mint NFT
        _safeMint(to, vestID);

        // accrue rewards
        rewardPerTokenStored[pool] = rewardPerToken_;
        periodInfo[pool].lastUpdateTime = lastTimeRewardApplicable_;

        // update stored totalDeposit
        totalDepositStored[pool] = totalDeposit;

        // update total supply
        totalSupply[pool] = totalSupply_ + depositAmount;

        emit Staked(vestID, depositAmount);
    }

    function updateVestForDeposit(
        address pool,
        uint64 depositID,
        uint256 currentDepositAmount,
        uint256 depositAmount,
        uint256 vestAmountPerStablecoinPerSecond
    ) external virtual override {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        if (address(msg.sender) != address(mphMinter)) {
            revert Error_NotMinter();
        }

        uint64 vestID = depositIDToVestID[pool][depositID];
        if (vestID == 0) {
            // deposit was created before vesting contract, return
            return;
        }
        Vest storage vestEntry = _getVest(vestID);

        if (vestEntry.lastUpdateTimestamp == 0) {
            // created by Vesting03

            /// -----------------------------------------------------------------------
            /// Storage loads
            /// -----------------------------------------------------------------------

            uint256 totalSupply_ = totalSupply[pool];
            uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable(pool);
            uint256 rewardPerToken_ = _rewardPerToken(
                pool,
                totalSupply_,
                lastTimeRewardApplicable_,
                rewardRate[pool]
            );
            uint256 totalDeposit = DInterest(pool).totalDeposit();
            uint256 totalDepositStored_ = totalDepositStored[pool];

            /// -----------------------------------------------------------------------
            /// State updates
            /// -----------------------------------------------------------------------

            // accrue rewards
            rewardPerTokenStored[pool] = rewardPerToken_;
            periodInfo[pool].lastUpdateTime = lastTimeRewardApplicable_;
            rewards[vestID] = _earned(
                vestID,
                currentDepositAmount,
                rewardPerToken_,
                rewards[vestID]
            );
            vestRewardPerTokenPaid[vestID] = rewardPerToken_;

            // update stored totalDeposit
            totalDepositStored[pool] = totalDeposit;

            // update total supply
            if (depositAmount > 0) {
                // deposit
                totalSupply[pool] = totalSupply_ + depositAmount;

                emit Staked(vestID, depositAmount);
            } else {
                // withdrawal
                // this is the only way for the vesting contract to learn
                // of the amount that was withdrawn, since it's not passed in
                // as an argument
                uint256 withdrawAmount = totalDepositStored_ - totalDeposit;
                totalSupply[pool] = totalSupply_ - withdrawAmount;

                emit Withdrawn(vestID, withdrawAmount);
            }
        } else {
            // created by Vesting02
            // use the same code
            DInterest poolContract = DInterest(pool);
            DInterest.Deposit memory depositEntry = poolContract.getDeposit(
                vestEntry.depositID
            );
            uint256 currentTimestamp = block.timestamp <
                depositEntry.maturationTimestamp
                ? block.timestamp
                : depositEntry.maturationTimestamp;
            if (currentTimestamp > vestEntry.lastUpdateTimestamp) {
                vestEntry.accumulatedAmount += (currentDepositAmount *
                    (currentTimestamp - vestEntry.lastUpdateTimestamp)).mul(
                        vestEntry.vestAmountPerStablecoinPerSecond
                    );
                require(
                    block.timestamp <= type(uint64).max,
                    "Vesting02: OVERFLOW"
                );
                vestEntry.lastUpdateTimestamp = uint64(block.timestamp);
            }
            vestEntry.vestAmountPerStablecoinPerSecond =
                (vestEntry.vestAmountPerStablecoinPerSecond *
                    currentDepositAmount +
                    vestAmountPerStablecoinPerSecond *
                    depositAmount) /
                (currentDepositAmount + depositAmount);

            emit EUpdateVest(
                vestID,
                pool,
                depositID,
                currentDepositAmount,
                depositAmount,
                vestAmountPerStablecoinPerSecond
            );
        }
    }

    function _withdraw(uint64 vestID)
        internal
        virtual
        override
        returns (uint256 withdrawnAmount)
    {
        Vest storage vestEntry = _getVest(vestID);

        if (vestEntry.lastUpdateTimestamp == 0) {
            // created by Vesting03
            /// -----------------------------------------------------------------------
            /// Validation
            /// -----------------------------------------------------------------------

            if (ownerOf(vestID) != msg.sender) {
                revert Error_NotVestOwner();
            }

            /// -----------------------------------------------------------------------
            /// Storage loads
            /// -----------------------------------------------------------------------

            address pool = vestEntry.pool;
            uint64 depositID = vestEntry.depositID;
            uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable(pool);
            uint256 rewardPerToken_ = _rewardPerToken(
                pool,
                totalSupply[pool],
                lastTimeRewardApplicable_,
                rewardRate[pool]
            );
            DInterest.Deposit memory deposit = DInterest(pool).getDeposit(
                depositID
            );
            uint256 depositAmount = FullMath.mulDiv(
                deposit.virtualTokenTotalSupply,
                PRECISION,
                PRECISION + deposit.interestRate
            );

            /// -----------------------------------------------------------------------
            /// State updates
            /// -----------------------------------------------------------------------

            withdrawnAmount = _earned(
                vestID,
                depositAmount,
                rewardPerToken_,
                rewards[vestID]
            );

            // accrue rewards
            rewardPerTokenStored[pool] = rewardPerToken_;
            periodInfo[pool].lastUpdateTime = lastTimeRewardApplicable_;
            vestRewardPerTokenPaid[vestID] = rewardPerToken_;

            // withdraw rewards
            if (withdrawnAmount > 0) {
                rewards[vestID] = 0;

                /// -----------------------------------------------------------------------
                /// Effects
                /// -----------------------------------------------------------------------

                mphMinter.mph().transfer(msg.sender, withdrawnAmount);
                emit RewardPaid(vestID, withdrawnAmount);
            }
        } else {
            // created by Vesting02
            return super._withdraw(vestID);
        }
    }

    function _getVestWithdrawableAmount(uint64 vestID)
        internal
        view
        virtual
        override
        returns (uint256 withdrawableAmount)
    {
        Vest storage vestEntry = _getVest(vestID);
        address pool = vestEntry.pool;
        uint64 depositID = vestEntry.depositID;

        if (vestEntry.lastUpdateTimestamp == 0) {
            // created by Vesting03
            uint64 lastTimeRewardApplicable_ = lastTimeRewardApplicable(pool);
            uint256 rewardPerToken_ = _rewardPerToken(
                pool,
                totalSupply[pool],
                lastTimeRewardApplicable_,
                rewardRate[pool]
            );
            DInterest.Deposit memory deposit = DInterest(pool).getDeposit(
                depositID
            );
            uint256 depositAmount = FullMath.mulDiv(
                deposit.virtualTokenTotalSupply,
                PRECISION,
                PRECISION + deposit.interestRate
            );

            return
                _earned(
                    vestID,
                    depositAmount,
                    rewardPerToken_,
                    rewards[vestID]
                );
        } else {
            // created by Vesting02
            return super._getVestWithdrawableAmount(vestID);
        }
    }

    /// -----------------------------------------------------------------------
    /// Getters
    /// -----------------------------------------------------------------------

    /// @notice The latest time at which stakers are earning rewards.
    function lastTimeRewardApplicable(address pool)
        public
        view
        returns (uint64)
    {
        uint64 periodFinish = periodInfo[pool].periodFinish;
        return
            block.timestamp < periodFinish
                ? uint64(block.timestamp)
                : periodFinish;
    }

    /// @notice The amount of reward tokens each staked token has earned so far
    function rewardPerToken(address pool) external view returns (uint256) {
        return
            _rewardPerToken(
                pool,
                DInterest(pool).totalDeposit(),
                lastTimeRewardApplicable(pool),
                rewardRate[pool]
            );
    }

    /// -----------------------------------------------------------------------
    /// Forwarder
    /// -----------------------------------------------------------------------

    function forwarderOfPool(address pool) public view returns (Forwarder) {
        return
            Forwarder(
                Clones.predictDeterministicAddress(
                    address(forwarderTemplate),
                    pool.fillLast12Bytes()
                )
            );
    }

    function deployForwarderOfPool(address pool) external {
        address(forwarderTemplate).cloneDeterministic(pool.fillLast12Bytes());
    }

    /// -----------------------------------------------------------------------
    /// Staking pool logic
    /// -----------------------------------------------------------------------

    /// @notice Lets a reward distributor start a new reward period. The reward tokens must have already
    /// been transferred to this contract before calling this function. If it is called
    /// when a reward period is still active, a new reward period will begin from the time
    /// of calling this function, using the leftover rewards from the old reward period plus
    /// the newly sent rewards as the reward.
    /// @dev If the reward amount will cause an overflow when computing rewardPerToken, then
    /// this function will revert.
    /// @param pool The pool to distribute reward tokens to
    /// @param reward The amount of reward tokens to use in the new reward period.
    function notifyRewardAmount(address pool, uint256 reward) external {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        if (reward == 0) {
            return;
        }
        if (!isRewardDistributor[msg.sender]) {
            revert Error_NotRewardDistributor();
        }

        /// -----------------------------------------------------------------------
        /// Storage loads
        /// -----------------------------------------------------------------------

        uint256 rewardRate_ = rewardRate[pool];
        uint64 periodFinish_ = periodInfo[pool].periodFinish;
        uint64 lastTimeRewardApplicable_ = block.timestamp < periodFinish_
            ? uint64(block.timestamp)
            : periodFinish_;
        uint64 duration = DURATION;

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        // accrue rewards
        rewardPerTokenStored[pool] = _rewardPerToken(
            pool,
            totalSupply[pool],
            lastTimeRewardApplicable_,
            rewardRate_
        );

        // record new reward
        uint256 newRewardRate;
        if (block.timestamp >= periodFinish_) {
            newRewardRate = reward / duration;
        } else {
            uint256 remaining = periodFinish_ - block.timestamp;
            uint256 leftover = remaining * rewardRate_;
            newRewardRate = (reward + leftover) / duration;
        }
        // prevent overflow when computing rewardPerToken
        if (newRewardRate >= ((type(uint256).max / PRECISION) / duration)) {
            revert Error_AmountTooLarge();
        }
        rewardRate[pool] = newRewardRate;
        periodInfo[pool] = PeriodInfo({
            lastUpdateTime: uint64(block.timestamp),
            periodFinish: uint64(block.timestamp + duration)
        });

        /// -----------------------------------------------------------------------
        /// Effects
        /// -----------------------------------------------------------------------

        // pull rewards from the forwarder contract
        Forwarder forwarder = forwarderOfPool(pool);
        if (address(forwarder).code.length == 0)
            revert Error_ForwarderNotDeployed();
        forwarder.pullTokens(address(mphMinter.mph()), reward);

        emit RewardAdded(pool, reward);
    }

    /// -----------------------------------------------------------------------
    /// Owner functions
    /// -----------------------------------------------------------------------

    function updateDuration(uint64 duration_) external onlyOwner {
        DURATION = duration_;
        emit UpdateDuration(duration_);
    }

    /// @notice Lets the owner add/remove accounts from the list of reward distributors.
    /// Reward distributors can call notifyRewardAmount()
    /// @param rewardDistributor The account to add/remove
    /// @param isRewardDistributor_ True to add the account, false to remove the account
    function setRewardDistributor(
        address rewardDistributor,
        bool isRewardDistributor_
    ) external onlyOwner {
        isRewardDistributor[rewardDistributor] = isRewardDistributor_;
        emit SetRewardDistributor(rewardDistributor, isRewardDistributor_);
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _earned(
        uint64 vestID,
        uint256 accountBalance,
        uint256 rewardPerToken_,
        uint256 accountRewards
    ) internal view returns (uint256) {
        return
            FullMath.mulDiv(
                accountBalance,
                rewardPerToken_ - vestRewardPerTokenPaid[vestID],
                PRECISION
            ) + accountRewards;
    }

    function _rewardPerToken(
        address pool,
        uint256 totalSupply_,
        uint256 lastTimeRewardApplicable_,
        uint256 rewardRate_
    ) internal view returns (uint256) {
        if (totalSupply_ == 0) {
            return rewardPerTokenStored[pool];
        }
        return
            rewardPerTokenStored[pool] +
            FullMath.mulDiv(
                (lastTimeRewardApplicable_ - periodInfo[pool].lastUpdateTime) *
                    PRECISION,
                rewardRate_,
                totalSupply_
            );
    }
}
