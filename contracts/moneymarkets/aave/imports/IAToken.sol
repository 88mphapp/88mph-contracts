pragma solidity 0.5.15;

// Aave aToken interface
interface IAToken {
    function redeem(uint256 _amount) external;
}