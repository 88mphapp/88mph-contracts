// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {SafeERC20} from "../../libs/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {MoneyMarket} from "../MoneyMarket.sol";
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";
import {HarvestVault} from "./imports/HarvestVault.sol";
import {HarvestStaking} from "./imports/HarvestStaking.sol";

contract HarvestMarket is MoneyMarket {
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for ERC20;
    using AddressUpgradeable for address;

    HarvestVault public vault;
    address public rewards;
    HarvestStaking public stakingPool;
    ERC20 public override stablecoin;

    function initialize(
        address _vault,
        address _rewards,
        address _stakingPool,
        address _rescuer,
        address _stablecoin
    ) external initializer {
        __MoneyMarket_init(_rescuer);

        // Verify input addresses
        require(
            _vault.isContract() &&
                _rewards != address(0) &&
                _stakingPool.isContract() &&
                _stablecoin.isContract(),
            "HarvestMarket: Invalid input address"
        );

        vault = HarvestVault(_vault);
        rewards = _rewards;
        stakingPool = HarvestStaking(_stakingPool);
        stablecoin = ERC20(_stablecoin);
    }

    function deposit(uint256 amount) external override onlyOwner {
        require(amount > 0, "HarvestMarket: amount is 0");

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Approve `amount` stablecoin to vault
        stablecoin.safeIncreaseAllowance(address(vault), amount);

        // Deposit `amount` stablecoin to vault
        vault.deposit(amount);

        // Stake vault token balance into staking pool
        uint256 vaultShareBalance = vault.balanceOf(address(this));
        vault.approve(address(stakingPool), vaultShareBalance);
        stakingPool.stake(vaultShareBalance);
    }

    function withdraw(uint256 amountInUnderlying)
        external
        override
        onlyOwner
        returns (uint256 actualAmountWithdrawn)
    {
        require(
            amountInUnderlying > 0,
            "HarvestMarket: amountInUnderlying is 0"
        );

        // Withdraw `amountInShares` shares from vault
        uint256 sharePrice = vault.getPricePerFullShare();
        uint256 amountInShares = amountInUnderlying.div(sharePrice);
        if (amountInShares > 0) {
            stakingPool.withdraw(amountInShares);
            vault.withdraw(amountInShares);
        }

        // Transfer stablecoin to `msg.sender`
        actualAmountWithdrawn = stablecoin.balanceOf(address(this));
        if (actualAmountWithdrawn > 0) {
            stablecoin.safeTransfer(msg.sender, actualAmountWithdrawn);
        }
    }

    function claimRewards() external override {
        stakingPool.getReward();
        ERC20 rewardToken = ERC20(stakingPool.rewardToken());
        rewardToken.safeTransfer(rewards, rewardToken.balanceOf(address(this)));
    }

    /**
        Param setters
     */
    function setRewards(address newValue) external override onlyOwner {
        require(newValue != address(0), "HarvestMarket: 0 address");
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
        require(token != address(stakingPool), "HarvestMarket: no steal");
    }

    function _totalValue(uint256 currentIncomeIndex)
        internal
        view
        override
        returns (uint256)
    {
        // not including vault token balance
        // because it should be 0 during normal operation
        // if tokens are sent to contract by mistake
        // they will be rescued
        uint256 shareBalance = stakingPool.balanceOf(address(this));
        return shareBalance.mul(currentIncomeIndex);
    }

    function _incomeIndex() internal view override returns (uint256 index) {
        index = vault.getPricePerFullShare();
        require(index > 0, "HarvestMarket: BAD_INDEX");
    }

    uint256[46] private __gap;
}
