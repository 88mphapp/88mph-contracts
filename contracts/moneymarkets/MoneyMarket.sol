// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Rescuable} from "../libs/Rescuable.sol";

// Interface for money market protocols (Compound, Aave, etc.)
abstract contract MoneyMarket is
    Rescuable,
    OwnableUpgradeable,
    AccessControlUpgradeable
{
    bytes32 internal constant RESCUER_ROLE = keccak256("RESCUER_ROLE");

    function __MoneyMarket_init(address rescuer) internal initializer {
        __Ownable_init();
        __AccessControl_init();

        // RESCUER_ROLE is managed by itself
        _setupRole(RESCUER_ROLE, rescuer);
        _setRoleAdmin(RESCUER_ROLE, RESCUER_ROLE);
    }

    function deposit(uint256 amount) external virtual;

    function withdraw(uint256 amountInUnderlying)
        external
        virtual
        returns (uint256 actualAmountWithdrawn);

    function totalValue() external virtual returns (uint256); // The total value locked in the money market, in terms of the underlying stablecoin

    function totalValue(uint256 currentIncomeIndex)
        external
        view
        virtual
        returns (uint256); // The total value locked in the money market, in terms of the underlying stablecoin

    function incomeIndex() external virtual returns (uint256); // Used for calculating the interest generated (e.g. cDai's price for the Compound market)

    function stablecoin() external view virtual returns (ERC20);

    function claimRewards() external virtual; // Claims farmed tokens (e.g. COMP, CRV) and sends it to the rewards pool

    function setRewards(address newValue) external virtual;

    /**
        @dev IMPORTANT MUST READ
        This function is for restricting unauthorized accounts from taking funds
        and ensuring only tokens not used by the MoneyMarket can be rescued.
        IF YOU DON'T GET IT RIGHT YOU WILL LOSE PEOPLE'S MONEY
        MAKE SURE YOU DO ALL OF THE FOLLOWING
        1) You MUST override it in a MoneyMarket implementation.
        2) You MUST make `super._authorizeRescue(token, target);` the first line of your overriding function.
        3) You MUST revert during a call to this function if a token used by the MoneyMarket is being rescued.
        4) You SHOULD look at how existing MoneyMarkets do it as an example.
     */
    function _authorizeRescue(
        address, /*token*/
        address /*target*/
    ) internal view virtual override {
        require(hasRole(RESCUER_ROLE, msg.sender), "MoneyMarket: not rescuer");
    }

    event ESetParamAddress(
        address indexed sender,
        string indexed paramName,
        address newValue
    );
}
