// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.3;

import "@openzeppelin/contracts/utils/math/Math.sol";

/**
    @notice Lets Echidna work with solidity 0.8 asserts
 */
contract Asserts {
    uint256 internal constant EPSILON = 10**9;
    uint256 internal constant PRECISION = 10**18;

    event AssertionFailed();

    function Assert(bool condition) internal {
        if (!condition) {
            emit AssertionFailed();
        }
    }

    function AssertEpsilonEqual(uint256 a, uint256 b) internal {
        if (a == 0 || b == 0) {
            if (Math.max(a, b) > EPSILON) {
                emit AssertionFailed();
            }
        } else {
            uint256 hi = Math.max(a, b);
            uint256 lo = Math.min(a, b);
            uint256 delta = ((hi - lo) * PRECISION) / lo;
            if (delta > EPSILON) {
                emit AssertionFailed();
            }
        }
    }
}
