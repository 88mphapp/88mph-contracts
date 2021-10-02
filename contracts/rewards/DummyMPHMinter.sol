// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

/// @dev Used on non-mainnet chains where MPH minting is not available
contract DummyMPHMinter {
    function createVestForDeposit(address account, uint64 depositID) external {}

    function updateVestForDeposit(
        uint64 depositID,
        uint256 currentDepositAmount,
        uint256 depositAmount
    ) external {}

    function mintVested(address account, uint256 amount)
        external
        returns (uint256 mintedAmount)
    {
        return 0;
    }

    function distributeFundingRewards(uint64 fundingID, uint256 interestAmount)
        external
    {}

    uint256[50] private __gap;
}
