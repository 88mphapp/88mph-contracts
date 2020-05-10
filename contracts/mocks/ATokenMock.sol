pragma solidity 0.6.5;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libs/DecMath.sol";

contract ATokenMock is ERC20 {
    using SafeMath for uint256;
    using DecMath for uint256;

    uint256 internal constant YEAR = 31556952; // Number of seconds in one Gregorian calendar year (365.2425 days)

    ERC20 public dai;
    uint256 public liquidityRate;
    uint256 public normalizedIncome;
    address[] public users;

    constructor(address _dai)
        public
        ERC20("aDAI", "aDAI")
    {
        dai = ERC20(_dai);

        liquidityRate = 10 ** 26; // 10% APY
        normalizedIncome = 10 ** 27;
    }

    function redeem(uint256 _amount) external {
        _burn(msg.sender, _amount);
        dai.transfer(msg.sender, _amount);
    }

    function principalBalanceOf(address _user) external view returns (uint256) {
        return balanceOf(_user); // TODO
    }

    function mint(address _user, uint256 _amount) external {
        _mint(_user, _amount);
        users.push(_user);
    }

    function mintInterest(uint256 _seconds) external {
        uint256 interest;
        address user;
        for (uint256 i = 0; i < users.length; i++) {
            user = users[i];
            interest = balanceOf(user).mul(_seconds).decmul(liquidityRate.div(YEAR.mul(10**9)));
            _mint(user, interest);
        }
        normalizedIncome = normalizedIncome.mul(_seconds).mul(liquidityRate.div(YEAR.mul(10**9))).div(10**27);
    }

    function setLiquidityRate(uint256 _liquidityRate) external {
        liquidityRate = _liquidityRate;
    }
}