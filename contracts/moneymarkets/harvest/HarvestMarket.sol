pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../IMoneyMarket.sol";
import "../../libs/DecMath.sol";
import "./imports/HarvestVault.sol";
import "./imports/HarvestStaking.sol";

contract HarvestMarket is IMoneyMarket, Ownable {
    using SafeMath for uint256;
    using DecMath for uint256;
    using SafeERC20 for ERC20;
    using Address for address;

    HarvestVault public vault;
    address public rewards;
    HarvestStaking public stakingPool;
    ERC20 public stablecoin;

    constructor(
        address _vault,
        address _rewards,
        address _stakingPool,
        address _stablecoin
    ) public {
        // Verify input addresses
        require(
            _vault.isContract() &&
                _rewards.isContract() &&
                _stakingPool.isContract() &&
                _stablecoin.isContract(),
            "HarvestMarket: An input address is not a contract"
        );

        vault = HarvestVault(_vault);
        rewards = _rewards;
        stakingPool = HarvestStaking(_stakingPool);
        stablecoin = ERC20(_stablecoin);
    }

    function deposit(uint256 amount) external onlyOwner {
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
        onlyOwner
        returns (uint256 actualAmountWithdrawn)
    {
        require(
            amountInUnderlying > 0,
            "HarvestMarket: amountInUnderlying is 0"
        );

        // Withdraw `amountInShares` shares from vault
        uint256 sharePrice = vault.getPricePerFullShare();
        uint256 amountInShares = amountInUnderlying.decdiv(sharePrice);
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

    function claimRewards() external {
        stakingPool.getReward();
        ERC20 rewardToken = ERC20(stakingPool.rewardToken());
        rewardToken.safeTransfer(rewards, rewardToken.balanceOf(address(this)));
    }

    function totalValue() external returns (uint256) {
        uint256 sharePrice = vault.getPricePerFullShare();
        uint256 shareBalance = vault.balanceOf(address(this)).add(stakingPool.balanceOf(address(this)));
        return shareBalance.decmul(sharePrice);
    }

    function incomeIndex() external returns (uint256) {
        return vault.getPricePerFullShare();
    }

    /**
        Param setters
     */
    function setRewards(address newValue) external onlyOwner {
        require(newValue.isContract(), "HarvestMarket: not contract");
        rewards = newValue;
        emit ESetParamAddress(msg.sender, "rewards", newValue);
    }
}
