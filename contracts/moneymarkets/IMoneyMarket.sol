pragma solidity 0.5.15;

// Interface for money market protocols (Compound, Aave, bZx, etc.)
interface IMoneyMarket {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amountInUnderlying) external;
    function supplyRatePerBlock() external view returns (uint256);
}