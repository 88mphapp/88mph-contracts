// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DecMath} from "../libs/DecMath.sol";

contract VaultWithDepositFeeMock is ERC20 {
    using DecMath for uint256;

    uint256 PRECISION = 10**18;

    ERC20 public underlying;
    uint256 public depositFee;
    uint256 public feeCollected;

    constructor(address _underlying, uint256 _depositFee)
        ERC20("yUSD", "yUSD")
    {
        underlying = ERC20(_underlying);
        depositFee = _depositFee;
    }

    function deposit(uint256 tokenAmount) public {
        uint256 sharePrice = getPricePerFullShare();
        uint256 shareAmountAfterFee =
            tokenAmount.decdiv(sharePrice).decmul(PRECISION - depositFee);
        uint256 tokenFee = tokenAmount.decmul(depositFee);
        _mint(msg.sender, shareAmountAfterFee);

        underlying.transferFrom(msg.sender, address(this), tokenAmount);

        feeCollected = feeCollected + tokenFee;
    }

    function withdraw(uint256 sharesAmount) public {
        uint256 sharePrice = getPricePerFullShare();
        uint256 underlyingAmount = sharesAmount.decmul(sharePrice);
        _burn(msg.sender, sharesAmount);

        underlying.transfer(msg.sender, underlyingAmount);
    }

    function getPricePerFullShare() public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 10**18;
        }
        return
            (underlying.balanceOf(address(this)) - feeCollected).decdiv(
                _totalSupply
            );
    }

    function pricePerShare() external view returns (uint256) {
        return getPricePerFullShare();
    }
}
