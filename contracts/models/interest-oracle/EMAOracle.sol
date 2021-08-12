// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {DecMath} from "../../libs/DecMath.sol";
import {IInterestOracle} from "./IInterestOracle.sol";
import {MoneyMarket} from "../../moneymarkets/MoneyMarket.sol";

contract EMAOracle is IInterestOracle, Initializable {
    using DecMath for uint256;

    uint256 internal constant PRECISION = 10**18;

    /**
        Immutable parameters
     */
    uint256 public UPDATE_INTERVAL;
    uint256 public UPDATE_MULTIPLIER;
    uint256 public ONE_MINUS_UPDATE_MULTIPLIER;

    /**
        Public variables
     */
    uint256 public emaStored;
    uint256 public lastIncomeIndex;
    uint256 public lastUpdateTimestamp;

    /**
        External contracts
     */
    MoneyMarket public override moneyMarket;

    function initialize(
        uint256 _emaInitial,
        uint256 _updateInterval,
        uint256 _smoothingFactor,
        uint256 _averageWindowInIntervals,
        address _moneyMarket
    ) external initializer {
        emaStored = _emaInitial;
        UPDATE_INTERVAL = _updateInterval;
        lastUpdateTimestamp = block.timestamp;

        uint256 updateMultiplier =
            _smoothingFactor / (_averageWindowInIntervals + 1);
        UPDATE_MULTIPLIER = updateMultiplier;
        ONE_MINUS_UPDATE_MULTIPLIER = PRECISION - updateMultiplier;

        moneyMarket = MoneyMarket(_moneyMarket);
        lastIncomeIndex = moneyMarket.incomeIndex();
    }

    function updateAndQuery()
        external
        override
        returns (bool updated, uint256 value)
    {
        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp;
        if (timeElapsed < UPDATE_INTERVAL) {
            return (false, emaStored);
        }

        // save gas by loading storage variables to memory
        uint256 _lastIncomeIndex = lastIncomeIndex;
        uint256 _emaStored = emaStored;

        uint256 newIncomeIndex = moneyMarket.incomeIndex();
        if (newIncomeIndex < _lastIncomeIndex) {
            // Shouldn't revert (which would block execution)
            // Assume no interest was accrued and use the last index as the new one
            // which would push the EMA towards zero if there's e.g. an exploit
            // in the underlying yield protocol
            newIncomeIndex = _lastIncomeIndex;
        }
        uint256 incomingValue =
            (newIncomeIndex - _lastIncomeIndex).decdiv(_lastIncomeIndex) /
                timeElapsed;

        updated = true;
        value =
            (incomingValue *
                UPDATE_MULTIPLIER +
                _emaStored *
                ONE_MINUS_UPDATE_MULTIPLIER) /
            PRECISION;
        emaStored = value;
        lastIncomeIndex = newIncomeIndex;
        lastUpdateTimestamp = block.timestamp;
    }

    function query() external view override returns (uint256 value) {
        return emaStored;
    }

    uint256[43] private __gap;
}
