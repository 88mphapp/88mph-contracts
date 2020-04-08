pragma solidity 0.5.15;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";

contract FeeModel is Ownable {
    using SafeMath for uint256;

    uint256 internal constant PRECISION = 10**18;

    address payable public beneficiary = 0x332D87209f7c8296389C307eAe170c2440830A47;

    function getFee(uint256 _txAmount)
        public
        pure
        returns (uint256 _feeAmount)
    {
        _feeAmount = _txAmount.div(10);
    }

    function setBeneficiary(address payable _addr) public onlyOwner {
        require(_addr != address(0), "0 address");
        beneficiary = _addr;
    }
}
