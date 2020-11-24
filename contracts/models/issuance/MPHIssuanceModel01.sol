pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../../libs/DecMath.sol";
import "./IMPHIssuanceModel.sol";

contract MPHIssuanceModel01 is Ownable, IMPHIssuanceModel {
    using Address for address;
    using DecMath for uint256;
    using SafeMath for uint256;

    uint256 internal constant PRECISION = 10**18;

    /**
        @notice The multiplier applied when minting MPH for a pool's depositor reward.
                Unit is MPH-wei per depositToken-wei per second. (wei here is the smallest decimal place)
                Scaled by 10^18.
                NOTE: The depositToken's decimals matter! 
     */
    mapping(address => uint256) public poolDepositorRewardMintMultiplier;
    /**
        @notice The multiplier applied when taking back MPH from depositors upon withdrawal.
                No unit, is a proportion between 0 and 1.
                Scaled by 10^18.
     */
    mapping(address => uint256) public poolDepositorRewardTakeBackMultiplier;
    /**
        @notice The multiplier applied when minting MPH for a pool's funder reward.
                Unit is MPH-wei per depositToken-wei per second. (wei here is the smallest decimal place)
                Scaled by 10^18.
                NOTE: The depositToken's decimals matter! 
     */
    mapping(address => uint256) public poolFunderRewardMultiplier;
    /**
        @notice The period over which the depositor reward will be vested, in seconds.
     */
    mapping(address => uint256) public poolDepositorRewardVestPeriod;
    /**
        @notice The period over which the funder reward will be vested, in seconds.
     */
    mapping(address => uint256) public poolFunderRewardVestPeriod;

    /**
        @notice Multiplier used for calculating dev reward
     */
    uint256 public devRewardMultiplier;

    event ESetParamAddress(
        address indexed sender,
        string indexed paramName,
        address newValue
    );
    event ESetParamUint(
        address indexed sender,
        string indexed paramName,
        address indexed pool,
        uint256 newValue
    );

    constructor(uint256 _devRewardMultiplier) public {
        devRewardMultiplier = _devRewardMultiplier;
    }

    /**
        @notice Computes the MPH amount to reward to a depositor upon deposit.
        @param  pool The DInterest pool trying to mint reward
        @param  depositAmount The deposit amount in the pool's stablecoins
        @param  depositPeriodInSeconds The deposit's lock period in seconds
        @param  interestAmount The deposit's fixed-rate interest amount in the pool's stablecoins
        @return depositorReward The MPH amount to mint to the depositor
                devReward The MPH amount to mint to the dev wallet
                govReward The MPH amount to mint to the gov treasury
     */
    function computeDepositorReward(
        address pool,
        uint256 depositAmount,
        uint256 depositPeriodInSeconds,
        uint256 interestAmount
    )
        external
        view
        returns (
            uint256 depositorReward,
            uint256 devReward,
            uint256 govReward
        )
    {
        uint256 mintAmount = depositAmount.mul(depositPeriodInSeconds).decmul(
            poolDepositorRewardMintMultiplier[pool]
        );
        depositorReward = mintAmount;
        devReward = mintAmount.decmul(devRewardMultiplier);
        govReward = 0;
    }

    /**
        @notice Computes the MPH amount to take back from a depositor upon withdrawal.
                If takeBackAmount > devReward + govReward, the extra MPH should be burnt.
        @param  pool The DInterest pool trying to mint reward
        @param  mintMPHAmount The MPH amount originally minted to the depositor as reward
        @param  early True if the deposit is withdrawn early, false if the deposit is mature
        @return takeBackAmount The MPH amount to take back from the depositor
                devReward The MPH amount from takeBackAmount to send to the dev wallet
                govReward The MPH amount from takeBackAmount to send to the gov treasury
     */
    function computeTakeBackDepositorRewardAmount(
        address pool,
        uint256 mintMPHAmount,
        bool early
    )
        external
        view
        returns (
            uint256 takeBackAmount,
            uint256 devReward,
            uint256 govReward
        )
    {
        takeBackAmount = early
            ? mintMPHAmount
            : mintMPHAmount.decmul(poolDepositorRewardTakeBackMultiplier[pool]);
        devReward = 0;
        govReward = early ? 0 : takeBackAmount;
    }

    /**
        @notice Computes the MPH amount to reward to a deficit funder upon withdrawal of an underlying deposit.
        @param  pool The DInterest pool trying to mint reward
        @param  depositAmount The deposit amount in the pool's stablecoins
        @param  fundingCreationTimestamp The timestamp of the funding's creation, in seconds
        @param  maturationTimestamp The maturation timestamp of the deposit, in seconds
        @param  interestPayoutAmount The interest payout amount to the funder, in the pool's stablecoins.
                                     Includes the interest from other funded deposits.
        @param  early True if the deposit is withdrawn early, false if the deposit is mature
        @return funderReward The MPH amount to mint to the funder
                devReward The MPH amount to mint to the dev wallet
                govReward The MPH amount to mint to the gov treasury
     */
    function computeFunderReward(
        address pool,
        uint256 depositAmount,
        uint256 fundingCreationTimestamp,
        uint256 maturationTimestamp,
        uint256 interestPayoutAmount,
        bool early
    )
        external
        view
        returns (
            uint256 funderReward,
            uint256 devReward,
            uint256 govReward
        )
    {
        if (early) {
            return (0, 0, 0);
        }
        funderReward = maturationTimestamp > fundingCreationTimestamp
            ? depositAmount
                .mul(maturationTimestamp.sub(fundingCreationTimestamp))
                .decmul(poolFunderRewardMultiplier[pool])
            : 0;
        devReward = funderReward.decmul(devRewardMultiplier);
        govReward = 0;
    }

    /**
        Param setters
     */

    function setPoolDepositorRewardMintMultiplier(
        address pool,
        uint256 newMultiplier
    ) external onlyOwner {
        require(pool.isContract(), "MPHIssuanceModel: pool not contract");
        poolDepositorRewardMintMultiplier[pool] = newMultiplier;
        emit ESetParamUint(
            msg.sender,
            "poolDepositorRewardMintMultiplier",
            pool,
            newMultiplier
        );
    }

    function setPoolDepositorRewardTakeBackMultiplier(
        address pool,
        uint256 newMultiplier
    ) external onlyOwner {
        require(pool.isContract(), "MPHIssuanceModel: pool not contract");
        require(
            newMultiplier <= PRECISION,
            "MPHIssuanceModel: invalid multiplier"
        );
        poolDepositorRewardTakeBackMultiplier[pool] = newMultiplier;
        emit ESetParamUint(
            msg.sender,
            "poolDepositorRewardTakeBackMultiplier",
            pool,
            newMultiplier
        );
    }

    function setPoolFunderRewardMultiplier(address pool, uint256 newMultiplier)
        external
        onlyOwner
    {
        require(pool.isContract(), "MPHIssuanceModel: pool not contract");
        poolFunderRewardMultiplier[pool] = newMultiplier;
        emit ESetParamUint(
            msg.sender,
            "poolFunderRewardMultiplier",
            pool,
            newMultiplier
        );
    }

    function setPoolDepositorRewardVestPeriod(
        address pool,
        uint256 newVestPeriodInSeconds
    ) external onlyOwner {
        require(pool.isContract(), "MPHIssuanceModel: pool not contract");
        poolDepositorRewardVestPeriod[pool] = newVestPeriodInSeconds;
        emit ESetParamUint(
            msg.sender,
            "poolDepositorRewardVestPeriod",
            pool,
            newVestPeriodInSeconds
        );
    }

    function setPoolFunderRewardVestPeriod(
        address pool,
        uint256 newVestPeriodInSeconds
    ) external onlyOwner {
        require(pool.isContract(), "MPHIssuanceModel: pool not contract");
        poolFunderRewardVestPeriod[pool] = newVestPeriodInSeconds;
        emit ESetParamUint(
            msg.sender,
            "poolFunderRewardVestPeriod",
            pool,
            newVestPeriodInSeconds
        );
    }

    function setDevRewardMultiplier(uint256 newMultiplier) external onlyOwner {
        require(
            newMultiplier <= PRECISION,
            "MPHIssuanceModel: invalid multiplier"
        );
        devRewardMultiplier = newMultiplier;
        emit ESetParamUint(
            msg.sender,
            "devRewardMultiplier",
            address(0),
            newMultiplier
        );
    }
}
