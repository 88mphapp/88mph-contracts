// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

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

    /**
        @notice The total value locked in the money market, in terms of the underlying stablecoin
     */
    function totalValue() external returns (uint256) {
        return _totalValue(_incomeIndex());
    }

    /**
        @notice The total value locked in the money market, in terms of the underlying stablecoin
     */
    function totalValue(uint256 currentIncomeIndex)
        external
        view
        returns (uint256)
    {
        return _totalValue(currentIncomeIndex);
    }

    /**
        @notice Used for calculating the interest generated (e.g. cDai's price for the Compound market)
     */
    function incomeIndex() external returns (uint256 index) {
        return _incomeIndex();
    }

    function stablecoin() external view virtual returns (ERC20);

    function claimRewards() external virtual; // Claims farmed tokens (e.g. COMP, CRV) and sends it to the rewards pool

    function setRewards(address newValue) external virtual;

    /**
        @dev See {Rescuable._authorizeRescue}
     */
    function _authorizeRescue(
        address, /*token*/
        address /*target*/
    ) internal view virtual override {
        require(hasRole(RESCUER_ROLE, msg.sender), "MoneyMarket: not rescuer");
    }

    function _totalValue(uint256 currentIncomeIndex)
        internal
        view
        virtual
        returns (uint256);

    function _incomeIndex() internal virtual returns (uint256 index);

    event ESetParamAddress(
        address indexed sender,
        string indexed paramName,
        address newValue
    );
}
