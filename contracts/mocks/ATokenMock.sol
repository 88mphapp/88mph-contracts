// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DecMath} from "../libs/DecMath.sol";

contract ATokenMock is ERC20 {
    using DecMath for uint256;

    uint256 internal constant YEAR = 31556952; // Number of seconds in one Gregorian calendar year (365.2425 days)

    ERC20 public dai;
    uint256 public liquidityRate;
    uint256 public normalizedIncome;
    address[] public users;
    mapping(address => bool) public isUser;

    constructor(address _dai) ERC20("aDAI", "aDAI") {
        dai = ERC20(_dai);

        liquidityRate = 10**26; // 10% APY
        normalizedIncome = 10**27;
    }

    function mint(address _user, uint256 _amount) external {
        _mint(_user, _amount);
        if (!isUser[_user]) {
            users.push(_user);
            isUser[_user] = true;
        }
    }

    function burn(address _user, uint256 _amount) external {
        _burn(_user, _amount);
    }

    function mintInterest(uint256 _seconds) external {
        uint256 interest;
        address user;
        for (uint256 i = 0; i < users.length; i++) {
            user = users[i];
            interest =
                (balanceOf(user) * _seconds * liquidityRate) /
                (YEAR * 10**27);
            _mint(user, interest);
        }
        normalizedIncome +=
            (normalizedIncome * _seconds * liquidityRate) /
            (YEAR * 10**27);
    }

    function setLiquidityRate(uint256 _liquidityRate) external {
        liquidityRate = _liquidityRate;
    }
}
