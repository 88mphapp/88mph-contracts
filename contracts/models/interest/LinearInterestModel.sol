// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {DecMath} from "../../libs/DecMath.sol";
import {IInterestModel} from "./IInterestModel.sol";

contract LinearInterestModel is IInterestModel {
    using DecMath for uint256;

    uint256 public constant PRECISION = 10**18;
    uint256 public IRMultiplier;

    constructor(uint256 _IRMultiplier) {
        IRMultiplier = _IRMultiplier;
    }

    function calculateInterestAmount(
        uint256 depositAmount,
        uint256 depositPeriodInSeconds,
        uint256 moneyMarketInterestRatePerSecond,
        bool, /*surplusIsNegative*/
        uint256 /*surplusAmount*/
    ) external view override returns (uint256 interestAmount) {
        // interestAmount = depositAmount * moneyMarketInterestRatePerSecond * IRMultiplier * depositPeriodInSeconds
        interestAmount =
            ((depositAmount * PRECISION)
                .decmul(moneyMarketInterestRatePerSecond)
                .decmul(IRMultiplier) * depositPeriodInSeconds) /
            PRECISION;
    }
}
