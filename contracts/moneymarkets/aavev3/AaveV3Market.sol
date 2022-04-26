// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {SafeERC20} from "../../libs/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    AddressUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {MoneyMarket} from "../MoneyMarket.sol";
import {IPool} from "./imports/IPool.sol";
import {IPoolAddressesProvider} from "./imports/IPoolAddressesProvider.sol";
import {IRewardsController} from "./imports/IRewardsController.sol";

contract AaveV3Market is MoneyMarket {
    using SafeERC20 for ERC20;
    using AddressUpgradeable for address;

    uint16 internal constant REFERRALCODE = 0; // Aave referral program code

    IPoolAddressesProvider public provider; // Used for fetching the current address of LendingPool
    ERC20 public override stablecoin;
    ERC20 public aToken;
    IRewardsController public aaveRewards;
    address public rewards;
    address public rewardToken;

    function initialize(
        address _provider,
        address _aToken,
        address _aaveReward,
        address _rewards,
        address _rewardToken,
        address _rescuer,
        address _stablecoin
    ) external initializer {
        __MoneyMarket_init(_rescuer);

        // Verify input addresses
        require(
            _provider.isContract() &&
                _aToken.isContract() &&
                _aaveReward.isContract() &&
                _rewards != address(0) &&
                _stablecoin.isContract(),
            "AaveV3Market: An input address is not a contract"
        );

        provider = IPoolAddressesProvider(_provider);
        stablecoin = ERC20(_stablecoin);
        aaveRewards = IRewardsController(_aaveReward);
        aToken = ERC20(_aToken);
        rewards = _rewards;
        rewardToken = _rewardToken;
    }

    function deposit(uint256 amount) external override onlyOwner {
        require(amount > 0, "AaveV3Market: amount is 0");

        IPool pool = IPool(provider.getPool());

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Approve `amount` stablecoin to lendingPool
        stablecoin.safeIncreaseAllowance(address(pool), amount);

        // Deposit `amount` stablecoin to lendingPool
        pool.supply(address(stablecoin), amount, address(this), REFERRALCODE);
    }

    function withdraw(uint256 amountInUnderlying)
        external
        override
        onlyOwner
        returns (uint256 actualAmountWithdrawn)
    {
        require(
            amountInUnderlying > 0,
            "AaveV3Market: amountInUnderlying is 0"
        );

        IPool pool = IPool(provider.getPool());

        // Redeem `amountInUnderlying` aToken, since 1 aToken = 1 stablecoin
        // Transfer `amountInUnderlying` stablecoin to `msg.sender`
        pool.withdraw(address(stablecoin), amountInUnderlying, msg.sender);

        return amountInUnderlying;
    }

    function claimRewards() external override {
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        aaveRewards.claimRewards(
            assets,
            type(uint256).max,
            rewards,
            rewardToken
        );
    }

    /**
        Param setters
     */
    function setRewards(address newValue) external override onlyOwner {
        require(newValue != address(0), "AaveV3Market: 0 address");
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
        require(token != address(aToken), "AaveV3Market: no steal");
    }

    function _totalValue(
        uint256 /*currentIncomeIndex*/
    ) internal view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function _incomeIndex() internal view override returns (uint256 index) {
        IPool pool = IPool(provider.getPool());
        index = pool.getReserveNormalizedIncome(address(stablecoin));
        require(index > 0, "AaveV3Market: BAD_INDEX");
    }

    uint256[45] private __gap;
}
