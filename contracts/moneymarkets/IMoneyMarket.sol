pragma solidity 0.5.17;

// Interface for money market protocols (Compound, Aave, bZx, etc.)
interface IMoneyMarket {
    function deposit(uint256 amount) external;

    function withdraw(uint256 amountInUnderlying) external;

    function claimRewards() external; // Claims farmed tokens (e.g. CRV) and sends it to the rewards pool

    function supplyRatePerSecond(uint256 blocktime)
        external
        view
        returns (uint256); // The supply interest rate per second, scaled by 10^18

    function totalValue() external returns (uint256); // The total value locked in the money market, in terms of the underlying stablecoin

    function incomeIndex() external returns (uint256); // Used for calculating the interest generated (e.g. cDai's price for the Compound market)

    function stablecoin() external view returns (address);
}
