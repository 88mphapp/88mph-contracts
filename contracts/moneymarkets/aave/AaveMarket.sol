pragma solidity 0.5.15;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "../IMoneyMarket.sol";
import "../../libs/DecMath.sol";

contract AaveMarket is IMoneyMarket {
    using SafeMath for uint256;
    using DecMath for uint256;
    using SafeERC20 for ERC20Detailed;

    address public lendingPool;
    ERC20Detailed public stablecoin;

    constructor (address _lendingPool, address _stablecoin) public {
        lendingPool = _lendingPool;
        stablecoin = ERC20Detailed(_stablecoin);
    }

    function deposit(uint256 amount) external {

    }

    function withdraw(uint256 amountInUnderlying) external {

    }

    function supplyRatePerBlock() external view returns (uint256) {

    }
}