// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IFeeModel.sol";

contract PercentageFeeModel is IFeeModel, Ownable {
    address payable public override beneficiary;

    event SetBeneficiary(address newBeneficiary);

    constructor(address payable _beneficiary) {
        beneficiary = _beneficiary;
    }

    function getFee(uint256 _txAmount)
        external
        pure
        override
        returns (uint256 _feeAmount)
    {
        _feeAmount = _txAmount / 5; // Precision is decreased by 1 decimal place
    }

    function setBeneficiary(address payable newValue) external onlyOwner {
        require(newValue != address(0), "PercentageFeeModel: 0 address");
        beneficiary = newValue;
        emit SetBeneficiary(newValue);
    }
}
