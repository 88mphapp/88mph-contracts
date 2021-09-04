// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";
import {IInterestModel} from "./IInterestModel.sol";

contract LinearDecayInterestModel is IInterestModel {
    using PRBMathUD60x18 for uint256;

    uint256 public constant PRECISION = 10**18;
    uint256 public immutable multiplierIntercept;
    uint256 public immutable multiplierSlope;

    constructor(uint256 _multiplierIntercept, uint256 _multiplierSlope) {
        multiplierIntercept = _multiplierIntercept;
        multiplierSlope = _multiplierSlope;
    }

    function getIRMultiplier(uint256 depositPeriodInSeconds)
        public
        view
        returns (uint256)
    {
        uint256 multiplierDecrease = depositPeriodInSeconds * multiplierSlope;
        if (multiplierDecrease >= multiplierIntercept) {
            return 0;
        } else {
            return multiplierIntercept - multiplierDecrease;
        }
    }

    function calculateInterestAmount(
        uint256 depositAmount,
        uint256 depositPeriodInSeconds,
        uint256 moneyMarketInterestRatePerSecond,
        bool, /*surplusIsNegative*/
        uint256 /*surplusAmount*/
    ) external view override returns (uint256 interestAmount) {
        // interestAmount = depositAmount * (2 ** (moneyMarketInterestRatePerSecond * depositPeriodInSeconds) - 1) * IRMultiplier
        interestAmount = depositAmount
            .mul(
            (moneyMarketInterestRatePerSecond * depositPeriodInSeconds).exp2() -
                PRECISION
        )
            .mul(getIRMultiplier(depositPeriodInSeconds));
    }
}
