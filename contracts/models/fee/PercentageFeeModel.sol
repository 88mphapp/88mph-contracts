pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./IFeeModel.sol";

contract PercentageFeeModel is IFeeModel, Ownable {
    using SafeMath for uint256;

    address payable public beneficiary;

    event SetBeneficiary(address newBeneficiary);

    constructor(address payable _beneficiary) public {
        beneficiary = _beneficiary;
    }

    function getFee(uint256 _txAmount)
        external
        pure
        returns (uint256 _feeAmount)
    {
        _feeAmount = _txAmount.div(5); // Precision is decreased by 1 decimal place
    }

    function setBeneficiary(address payable newValue) external onlyOwner {
        require(newValue != address(0), "PercentageFeeModel: 0 address");
        beneficiary = newValue;
        emit SetBeneficiary(newValue);
    }
}
