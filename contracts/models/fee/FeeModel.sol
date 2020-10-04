pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./IFeeModel.sol";

contract FeeModel is Ownable, IFeeModel {
    using SafeMath for uint256;

    address payable public beneficiary = 0x332D87209f7c8296389C307eAe170c2440830A47;

    function getFee(uint256 _txAmount)
        external
        pure
        returns (uint256 _feeAmount)
    {
        _feeAmount = _txAmount.div(10); // Precision is decreased by 1 decimal place
    }

    function setBeneficiary(address payable _addr) external onlyOwner {
        require(_addr != address(0), "FeeModel: 0 address");
        beneficiary = _addr;
    }
}
