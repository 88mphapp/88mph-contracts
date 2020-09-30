pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../IMoneyMarket.sol";
import "../../libs/DecMath.sol";
import "./imports/Vault.sol";

contract YVaultMarket is IMoneyMarket, Ownable {
    using SafeMath for uint256;
    using DecMath for uint256;
    using SafeERC20 for ERC20;
    using Address for address;

    uint256 internal constant SUPPLY_RATE_UPDATE_INTERVAL = 12 hours;

    uint256 public lastSupplyRateUpdateTimestamp;
    uint256 public lastSupplyRate;

    Vault public vault;
    ERC20 public stablecoin;

    constructor(address _vault, address _stablecoin) public {
        // Verify input addresses
        require(
            _vault != address(0) && _stablecoin != address(0),
            "YVaultMarket: An input address is 0"
        );
        require(
            _vault.isContract() && _stablecoin.isContract(),
            "YVaultMarket: An input address is not a contract"
        );

        vault = Vault(_vault);
        stablecoin = ERC20(_stablecoin);

        _updateSupplyRate();
    }

    function deposit(uint256 amount) external onlyOwner {
        require(amount > 0, "YVaultMarket: amount is 0");

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Approve `amount` stablecoin to vault
        stablecoin.safeIncreaseAllowance(address(vault), amount);

        // Deposit `amount` stablecoin to vault
        vault.deposit(amount);
    }

    function withdraw(uint256 amountInUnderlying) external onlyOwner {
        require(
            amountInUnderlying > 0,
            "YVaultMarket: amountInUnderlying is 0"
        );

        // Withdraw `amountInShares` shares from vault
        uint256 sharePrice = vault.getPricePerFullShare();
        uint256 amountInShares = amountInUnderlying.decdiv(sharePrice);
        vault.withdraw(amountInShares);

        // Transfer `amountInUnderlying` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, amountInUnderlying);
    }

    function updateSupplyRate() external {
        _updateSupplyRate();
    }

    function supplyRatePerSecond(
        uint256 /*blocktime*/
    ) external view returns (uint256) {
        return lastSupplyRate;
    }

    function supplyRatePerSecondAfterUpdate(
        uint256 /*blocktime*/
    ) external returns (uint256) {
        _updateSupplyRate();
        return lastSupplyRate;
    }

    function totalValue() external returns (uint256) {
        uint256 sharePrice = vault.getPricePerFullShare();
        uint256 shareBalance = vault.balanceOf(address(this));
        return shareBalance.decmul(sharePrice);
    }

    function incomeIndex() external returns (uint256) {
        return _incomeIndex();
    }

    function _updateSupplyRate() internal {
        uint256 secondsSinceLastUpdate = now.sub(lastSupplyRateUpdateTimestamp);
        if (secondsSinceLastUpdate < SUPPLY_RATE_UPDATE_INTERVAL) {
            return;
        }
        uint256 _lastSupplyRate = lastSupplyRate;
        uint256 incomeIndexIncreasePercentage = _incomeIndex()
            .sub(_lastSupplyRate)
            .decdiv(_lastSupplyRate);

        lastSupplyRate = incomeIndexIncreasePercentage.div(
            secondsSinceLastUpdate
        );
        lastSupplyRateUpdateTimestamp = now;
    }

    function _incomeIndex() internal view returns (uint256) {
        return vault.getPricePerFullShare();
    }
}
