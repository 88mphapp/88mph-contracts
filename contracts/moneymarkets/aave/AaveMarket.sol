pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../IMoneyMarket.sol";
import "../../libs/DecMath.sol";
import "./imports/IAToken.sol";
import "./imports/ILendingPool.sol";
import "./imports/ILendingPoolAddressesProvider.sol";
import "./imports/ILendingPoolCore.sol";

contract AaveMarket is IMoneyMarket, Ownable {
    using SafeMath for uint256;
    using DecMath for uint256;
    using SafeERC20 for ERC20;
    using Address for address;

    uint256 internal constant YEAR = 31556952; // Number of seconds in one Gregorian calendar year (365.2425 days)
    uint16 internal constant REFERRALCODE = 20; // Aave referral program code

    ILendingPoolAddressesProvider public provider; // Used for fetching the current address of LendingPool
    ERC20 public stablecoin;

    constructor(address _provider, address _stablecoin) public {
        // Verify input addresses
        require(
            _provider != address(0) && _stablecoin != address(0),
            "AaveMarket: An input address is 0"
        );
        require(
            _provider.isContract() && _stablecoin.isContract(),
            "AaveMarket: An input address is not a contract"
        );

        provider = ILendingPoolAddressesProvider(_provider);
        stablecoin = ERC20(_stablecoin);
    }

    function deposit(uint256 amount) external onlyOwner {
        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());
        address lendingPoolCore = provider.getLendingPoolCore();

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Approve `amount` stablecoin to lendingPool
        stablecoin.safeIncreaseAllowance(lendingPoolCore, amount);

        // Deposit `amount` stablecoin to lendingPool
        lendingPool.deposit(address(stablecoin), amount, REFERRALCODE);
    }

    function withdraw(uint256 amountInUnderlying) external onlyOwner {
        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());

        // Initialize aToken
        (, , , , , , , , , , , address aTokenAddress, ) = lendingPool
            .getReserveData(address(stablecoin));
        IAToken aToken = IAToken(aTokenAddress);

        // Redeem `amountInUnderlying` aToken, since 1 aToken = 1 stablecoin
        aToken.redeem(amountInUnderlying);

        // Transfer `amountInUnderlying` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, amountInUnderlying);
    }

    function supplyRatePerSecond(
        uint256 /*blocktime*/
    ) external view returns (uint256) {
        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());

        // The annual supply interest rate, scaled by 10^27
        (, , , , uint256 liquidityRate, , , , , , , , ) = lendingPool
            .getReserveData(address(stablecoin));

        // supplyRatePerSecond = liquidityRate / 10^9 / YEAR = liquidityRate / (YEAR * 10^9)
        return liquidityRate.div(YEAR.mul(10**9));
    }

    function totalValue() external returns (uint256) {
        ILendingPool lendingPool = ILendingPool(provider.getLendingPool());

        // Initialize aToken
        (, , , , , , , , , , , address aTokenAddress, ) = lendingPool
            .getReserveData(address(stablecoin));
        IAToken aToken = IAToken(aTokenAddress);

        return aToken.balanceOf(address(this));
    }

    function price() external returns (uint256) {
        ILendingPoolCore lendingPoolCore = ILendingPoolCore(
            provider.getLendingPoolCore()
        );
        return lendingPoolCore.getReserveNormalizedIncome(address(stablecoin));
    }
}
