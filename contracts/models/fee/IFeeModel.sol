// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

interface IFeeModel {
    function beneficiary() external view returns (address payable);

    function getFee(uint256 _txAmount)
        external
        pure
        returns (uint256 _feeAmount);
}
