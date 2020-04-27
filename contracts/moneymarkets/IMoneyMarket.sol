pragma solidity 0.6.5;

// Interface for money market protocols (Compound, Aave, bZx, etc.)
interface IMoneyMarket {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amountInUnderlying) external;
    function supplyRatePerSecond(uint256 blocktime)
        external
        view
        returns (uint256); // The supply interest rate per second, scaled by 10^18
    function totalValue() external view returns (uint256); // The total value locked in the money market, in terms of the underlying stablecoin
    function price() external view returns (uint256); // Used for calculating interest generated (e.g. cDai's price for Compound)
}