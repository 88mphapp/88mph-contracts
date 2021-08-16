// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {SafeERC20} from "../../libs/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    AddressUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {MoneyMarket} from "../MoneyMarket.sol";
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";
import {IBToken} from "./imports/IBToken.sol";
import {IBComptroller} from "./imports/IBComptroller.sol";

contract BProtocolMarket is MoneyMarket {
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for ERC20;
    using AddressUpgradeable for address;

    uint256 internal constant ERRCODE_OK = 0;

    IBToken public bToken;
    IBComptroller public bComptroller;
    address public rewards;
    ERC20 public override stablecoin;

    function initialize(
        address _bToken,
        address _bComptroller,
        address _rewards,
        address _rescuer,
        address _stablecoin
    ) external initializer {
        __MoneyMarket_init(_rescuer);

        // Verify input addresses
        require(
            _bToken.isContract() &&
                _bComptroller.isContract() &&
                _rewards != address(0) &&
                _stablecoin.isContract(),
            "BProtocolMarket: Invalid input address"
        );

        bToken = IBToken(_bToken);
        bComptroller = IBComptroller(_bComptroller);
        rewards = _rewards;
        stablecoin = ERC20(_stablecoin);
    }

    function deposit(uint256 amount) external override onlyOwner {
        require(amount > 0, "BProtocolMarket: amount is 0");

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit `amount` stablecoin into bToken
        stablecoin.safeIncreaseAllowance(address(bToken), amount);
        require(
            bToken.mint(amount) == ERRCODE_OK,
            "BProtocolMarket: Failed to mint bTokens"
        );
    }

    function withdraw(uint256 amountInUnderlying)
        external
        override
        onlyOwner
        returns (uint256 actualAmountWithdrawn)
    {
        require(
            amountInUnderlying > 0,
            "BProtocolMarket: amountInUnderlying is 0"
        );

        // Withdraw `amountInUnderlying` stablecoin from bToken
        require(
            bToken.redeemUnderlying(amountInUnderlying) == ERRCODE_OK,
            "BProtocolMarket: Failed to redeem"
        );

        // Transfer `amountInUnderlying` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, amountInUnderlying);

        return amountInUnderlying;
    }

    function claimRewards() external override {
        ERC20 comp = ERC20(bComptroller.registry().comp());
        uint256 beforeBalance = comp.balanceOf(address(this));
        bComptroller.claimComp(address(this));
        comp.safeTransfer(
            rewards,
            comp.balanceOf(address(this)) - beforeBalance
        );
    }

    /**
        Param setters
     */
    function setRewards(address newValue) external override onlyOwner {
        require(newValue != address(0), "BProtocolMarket: 0 address");
        rewards = newValue;
        emit ESetParamAddress(msg.sender, "rewards", newValue);
    }

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
    function _authorizeRescue(address token, address target)
        internal
        view
        override
    {
        super._authorizeRescue(token, target);
        require(token != address(bToken), "BProtocolMarket: no steal");
    }

    function _totalValue(uint256 currentIncomeIndex)
        internal
        view
        override
        returns (uint256)
    {
        uint256 bTokenBalance = bToken.balanceOf(address(this));
        return bTokenBalance.mul(currentIncomeIndex);
    }

    function _incomeIndex() internal override returns (uint256 index) {
        index = bToken.exchangeRateCurrent();
        require(index > 0, "BProtocolMarket: BAD_INDEX");
    }

    uint256[46] private __gap;
}
