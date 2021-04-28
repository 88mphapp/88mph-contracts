// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

interface IMPHIssuanceModel {
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
        returns (
            uint256 depositorReward,
            uint256 devReward,
            uint256 govReward
        );

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
        view
        returns (
            uint256 takeBackAmount,
            uint256 devReward,
            uint256 govReward
        );

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
        returns (
            uint256 funderReward,
            uint256 devReward,
            uint256 govReward
        );

    /**
        @notice The period over which the funder reward will be vested, in seconds.
     */
    function poolFunderRewardVestPeriod(address pool)
        external
        view
        returns (uint256 vestPeriodInSeconds);

    /**
        v3 functions
     */
    /**
        @notice The multiplier applied when minting MPH for a pool's depositor reward.
                Unit is MPH-wei per depositToken-wei per second. (wei here is the smallest decimal place)
                Scaled by 10^18.
                NOTE: The depositToken's decimals matter! 
     */
    function poolDepositorRewardMintMultiplier(address pool)
        external
        view
        returns (uint256);

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
    function poolFunderRewardMultiplier(address pool)
        external
        view
        returns (uint256);
}
