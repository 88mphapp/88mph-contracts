// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

interface IFeeModel {
    function beneficiary() external view returns (address payable);

    function getInterestFeeAmount(address pool, uint256 interestAmount)
        external
        view
        returns (uint256 feeAmount);

    function getEarlyWithdrawFeeAmount(
        address pool,
        uint64 depositID,
        uint256 withdrawnDepositAmount
    ) external view returns (uint256 feeAmount);
}
