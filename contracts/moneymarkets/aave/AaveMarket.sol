// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../IMoneyMarket.sol";
import "./imports/ILendingPool.sol";
import "./imports/ILendingPoolAddressesProvider.sol";

contract AaveMarket is IMoneyMarket, Ownable {
    using SafeERC20 for ERC20;
    using Address for address;

    uint16 internal constant REFERRALCODE = 20; // Aave referral program code

    ILendingPoolAddressesProvider public provider; // Used for fetching the current address of LendingPool
    ERC20 public override stablecoin;
    ERC20 public aToken;

    constructor(
        address _provider,
        address _aToken,
        address _stablecoin
    ) {
        // Verify input addresses
        require(
            _provider.isContract() &&
                _aToken.isContract() &&
                _stablecoin.isContract(),
            "AaveMarket: An input address is not a contract"
        );

        provider = ILendingPoolAddressesProvider(_provider);
        stablecoin = ERC20(_stablecoin);
        aToken = ERC20(_aToken);
    }

    function deposit(uint256 amount) external override onlyOwner {
        require(amount > 0, "AaveMarket: amount is 0");

        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Approve `amount` stablecoin to lendingPool
        stablecoin.safeIncreaseAllowance(address(lendingPool), amount);

        // Deposit `amount` stablecoin to lendingPool
        lendingPool.deposit(
            address(stablecoin),
            amount,
            address(this),
            REFERRALCODE
        );
    }

    function withdraw(uint256 amountInUnderlying)
        external
        override
        onlyOwner
        returns (uint256 actualAmountWithdrawn)
    {
        require(amountInUnderlying > 0, "AaveMarket: amountInUnderlying is 0");

        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());

        // Redeem `amountInUnderlying` aToken, since 1 aToken = 1 stablecoin
        // Transfer `amountInUnderlying` stablecoin to `msg.sender`
        lendingPool.withdraw(
            address(stablecoin),
            amountInUnderlying,
            msg.sender
        );

        return amountInUnderlying;
    }

    function claimRewards() external override {}

    function totalValue() external view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function incomeIndex() external view override returns (uint256) {
        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
        return lendingPool.getReserveNormalizedIncome(address(stablecoin));
    }

    function setRewards(address newValue) external override {}
}
