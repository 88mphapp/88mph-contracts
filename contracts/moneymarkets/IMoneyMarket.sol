pragma solidity 0.5.15;

// Interface for money market protocols (Compound, Aave, bZx, etc.)
interface IMoneyMarket {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amountInUnderlying) external;
    function supplyRatePerSecond(uint256 blocktime)
        external
        view
        returns (uint256); // The supply interest rate per second, scaled by 10^18
}
