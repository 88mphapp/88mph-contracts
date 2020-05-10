pragma solidity 0.6.5;

// Aave lending pool core interface
interface ILendingPoolCore {
    // The equivalent of exchangeRateStored() for Compound cTokens
    function getReserveNormalizedIncome(address _reserve) external view returns (uint256);
}
