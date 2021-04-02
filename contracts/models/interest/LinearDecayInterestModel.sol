pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../../libs/DecMath.sol";

contract LinearDecayInterestModel {
    using SafeMath for uint256;
    using DecMath for uint256;

    uint256 public constant PRECISION = 10**18;
    uint256 public multiplierIntercept;
    uint256 public multiplierSlope;

    constructor(uint256 _multiplierIntercept, uint256 _multiplierSlope) public {
        multiplierIntercept = _multiplierIntercept;
        multiplierSlope = _multiplierSlope;
    }

    function getIRMultiplier(uint256 depositPeriodInSeconds) public view returns (uint256) {
        uint256 multiplierDecrease = depositPeriodInSeconds.mul(multiplierSlope);
        if (multiplierDecrease >= multiplierIntercept) {
            return 0;
        } else {
            return multiplierIntercept.sub(multiplierDecrease);
        }
    }

    function calculateInterestAmount(
        uint256 depositAmount,
        uint256 depositPeriodInSeconds,
        uint256 moneyMarketInterestRatePerSecond,
        bool, /*surplusIsNegative*/
        uint256 /*surplusAmount*/
    ) external view returns (uint256 interestAmount) {
        // interestAmount = depositAmount * moneyMarketInterestRatePerSecond * IRMultiplier * depositPeriodInSeconds
        interestAmount = depositAmount
            .mul(PRECISION)
            .decmul(moneyMarketInterestRatePerSecond)
            .decmul(getIRMultiplier(depositPeriodInSeconds))
            .mul(depositPeriodInSeconds)
            .div(PRECISION);
    }
}
