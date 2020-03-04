pragma solidity 0.5.15;

import "@openzeppelin/contracts/math/SafeMath.sol";

// Decimal math library
library DecMath {
    uint256 internal constant PRECISION = 10**18;

    function decmul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        c = c / PRECISION;

        return c;
    }

    function decdiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a * PRECISION;
        require(c / a == PRECISION, "SafeMath: multiplication overflow");
        c = c / b;

        return c;
    }
}
