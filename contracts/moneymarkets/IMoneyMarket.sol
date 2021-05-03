// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

// Interface for money market protocols (Compound, Aave, bZx, etc.)
interface IMoneyMarket {
    function deposit(uint256 amount) external;

    function withdraw(uint256 amountInUnderlying)
        external
        returns (uint256 actualAmountWithdrawn);

    function totalValue() external returns (uint256); // The total value locked in the money market, in terms of the underlying stablecoin

    function incomeIndex() external returns (uint256); // Used for calculating the interest generated (e.g. cDai's price for the Compound market)

    function stablecoin() external view returns (ERC20Upgradeable);

    function claimRewards() external; // Claims farmed tokens (e.g. COMP, CRV) and sends it to the rewards pool

    function setRewards(address newValue) external;

    event ESetParamAddress(
        address indexed sender,
        string indexed paramName,
        address newValue
    );
}
