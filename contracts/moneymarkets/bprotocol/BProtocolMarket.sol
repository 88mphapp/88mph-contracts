// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {SafeERC20} from "../../libs/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    AddressUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {MoneyMarket} from "../MoneyMarket.sol";
import {DecMath} from "../../libs/DecMath.sol";
import {IBToken} from "./imports/IBToken.sol";
import {IBComptroller} from "./imports/IBComptroller.sol";

contract BProtocolMarket is MoneyMarket {
    using DecMath for uint256;
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
        stablecoin.safeApprove(address(bToken), amount);
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
        bComptroller.claimComp(address(this));
        ERC20 comp = ERC20(bComptroller.registry().comp());
        comp.safeTransfer(rewards, comp.balanceOf(address(this)));
    }

    function totalValue() external override returns (uint256) {
        uint256 bTokenBalance = bToken.balanceOf(address(this));
        // Amount of stablecoin units that 1 unit of bToken can be exchanged for, scaled by 10^18
        uint256 bTokenPrice = bToken.exchangeRateCurrent();
        return bTokenBalance.decmul(bTokenPrice);
    }

    function totalValue(uint256 currentIncomeIndex)
        external
        view
        override
        returns (uint256)
    {
        uint256 bTokenBalance = bToken.balanceOf(address(this));
        return bTokenBalance.decmul(currentIncomeIndex);
    }

    function incomeIndex() external override returns (uint256 index) {
        index = bToken.exchangeRateCurrent();
        require(index > 0, "BProtocolMarket: BAD_INDEX");
    }

    /**
        Param setters
     */
    function setRewards(address newValue) external override onlyOwner {
        require(newValue.isContract(), "BProtocolMarket: not contract");
        rewards = newValue;
        emit ESetParamAddress(msg.sender, "rewards", newValue);
    }

    /**
        @dev See {Rescuable._authorizeRescue}
     */
    function _authorizeRescue(address token, address target)
        internal
        view
        override
    {
        super._authorizeRescue(token, target);
        require(token != address(bToken), "BProtocolMarket: no steal");
    }

    uint256[46] private __gap;
}
