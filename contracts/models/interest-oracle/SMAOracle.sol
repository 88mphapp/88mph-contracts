pragma solidity 0.5.17;

import "./IInterestOracle.sol";

contract SMAOracle is IInterestOracle {
    function updateAndQuery() external returns (bool updated, uint256 value) {
        return (false, 0);
    }

    function query() external view returns (uint256 value) {
        return 0;
    }
}
