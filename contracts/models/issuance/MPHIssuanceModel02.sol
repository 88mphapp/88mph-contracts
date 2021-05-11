// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    AddressUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {DecMath} from "../../libs/DecMath.sol";
import {IMPHIssuanceModel} from "./IMPHIssuanceModel.sol";

contract MPHIssuanceModel02 is OwnableUpgradeable, IMPHIssuanceModel {
    using AddressUpgradeable for address;
    using DecMath for uint256;

    uint256 internal constant PRECISION = 10**18;

    /**
        @notice The multiplier applied when minting MPH for a pool's depositor reward.
                Unit is MPH-wei per depositToken-wei per second. (wei here is the smallest decimal place)
                Scaled by 10^18.
                NOTE: The depositToken's decimals matter! 
     */
    mapping(address => uint256)
        public
        override poolDepositorRewardMintMultiplier;
    /**
        @notice The multiplier applied when minting MPH for a pool's funder reward.
                v2 usage:
                Unit is MPH-wei per depositToken-wei per second. (wei here is the smallest decimal place)
                Scaled by 10^18.
                NOTE: The depositToken's decimals matter!
                v3 usage:
                Unit is MPH-wei per depositToken-wei. (wei here is the smallest decimal place)
                Scaled by 10^18.
                NOTE: The depositToken's decimals matter!
     */
    mapping(address => uint256) public override poolFunderRewardMultiplier;
    /**
        @notice v2 usage:
                The period over which the funder reward will be vested, in seconds.
     */
    mapping(address => uint256) public override poolFunderRewardVestPeriod;

    /**
        @notice Multiplier used for calculating dev reward
     */
    uint256 public devRewardMultiplier;
    /**
        @notice Multiplier used for calculating gov reward
     */
    uint256 public govRewardMultiplier;

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

    function __MPHIssuanceModel02_init(
        uint256 _devRewardMultiplier,
        uint256 _govRewardMultiplier
    ) internal initializer {
        __Ownable_init();
        __MPHIssuanceModel02_init_unchained(
            _devRewardMultiplier,
            _govRewardMultiplier
        );
    }

    function __MPHIssuanceModel02_init_unchained(
        uint256 _devRewardMultiplier,
        uint256 _govRewardMultiplier
    ) internal initializer {
        devRewardMultiplier = _devRewardMultiplier;
        govRewardMultiplier = _govRewardMultiplier;
    }

    function initialize(
        uint256 _devRewardMultiplier,
        uint256 _govRewardMultiplier
    ) external initializer {
        __MPHIssuanceModel02_init(_devRewardMultiplier, _govRewardMultiplier);
    }

    /**
        v2 legacy functions
     */
    /**
        @notice Computes the MPH amount to reward to a depositor upon deposit.
        @param  pool The DInterest pool trying to mint reward
        @param  depositAmount The deposit amount in the pool's stablecoins
        @param  depositPeriodInSeconds The deposit's lock period in seconds
        @return depositorReward The MPH amount to mint to the depositor
                devReward The MPH amount to mint to the dev wallet
                govReward The MPH amount to mint to the gov treasury
     */
    function computeDepositorReward(
        address pool,
        uint256 depositAmount,
        uint256 depositPeriodInSeconds
    )
        external
        view
        override
        returns (
            uint256 depositorReward,
            uint256 devReward,
            uint256 govReward
        )
    {
        uint256 mintAmount =
            (depositAmount * depositPeriodInSeconds).decmul(
                poolDepositorRewardMintMultiplier[pool]
            );
        depositorReward = mintAmount;
        devReward = mintAmount.decmul(devRewardMultiplier);
        govReward = mintAmount.decmul(govRewardMultiplier);
    }

    /**
        @notice Computes the MPH amount to take back from a depositor upon withdrawal.
                If takeBackAmount > devReward + govReward, the extra MPH should be burnt.
        @param  mintMPHAmount The MPH amount originally minted to the depositor as reward
        @param  early True if the deposit is withdrawn early, false if the deposit is mature
        @return takeBackAmount The MPH amount to take back from the depositor
                devReward The MPH amount from takeBackAmount to send to the dev wallet
                govReward The MPH amount from takeBackAmount to send to the gov treasury
     */
    function computeTakeBackDepositorRewardAmount(
        uint256 mintMPHAmount,
        bool early
    )
        external
        pure
        override
        returns (
            uint256 takeBackAmount,
            uint256 devReward,
            uint256 govReward
        )
    {
        takeBackAmount = early ? mintMPHAmount : 0;
        devReward = 0;
        govReward = 0;
    }

    /**
        @notice Computes the MPH amount to reward to a deficit funder upon withdrawal of an underlying deposit.
        @param  pool The DInterest pool trying to mint reward
        @param  depositAmount The deposit amount in the pool's stablecoins
        @param  fundingCreationTimestamp The timestamp of the funding's creation, in seconds
        @param  maturationTimestamp The maturation timestamp of the deposit, in seconds
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
        bool early
    )
        external
        view
        override
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
            ? (depositAmount * (maturationTimestamp - fundingCreationTimestamp))
                .decmul(poolFunderRewardMultiplier[pool])
            : 0;
        devReward = funderReward.decmul(devRewardMultiplier);
        govReward = funderReward.decmul(govRewardMultiplier);
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

    function setGovRewardMultiplier(uint256 newMultiplier) external onlyOwner {
        require(
            newMultiplier <= PRECISION,
            "MPHIssuanceModel: invalid multiplier"
        );
        govRewardMultiplier = newMultiplier;
        emit ESetParamUint(
            msg.sender,
            "govRewardMultiplier",
            address(0),
            newMultiplier
        );
    }

    uint256[45] private __gap;
}
