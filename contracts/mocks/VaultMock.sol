// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DecMath} from "../libs/DecMath.sol";

contract VaultMock is ERC20 {
    using DecMath for uint256;

    ERC20 public underlying;

    constructor(address _underlying) ERC20("yUSD", "yUSD") {
        underlying = ERC20(_underlying);
    }

    function deposit(uint256 tokenAmount) public {
        uint256 sharePrice = getPricePerFullShare();
        _mint(msg.sender, tokenAmount.decdiv(sharePrice));

        underlying.transferFrom(msg.sender, address(this), tokenAmount);
    }

    function withdraw(uint256 sharesAmount)
        public
        returns (uint256 underlyingAmount)
    {
        uint256 sharePrice = getPricePerFullShare();
        underlyingAmount = sharesAmount.decmul(sharePrice);
        _burn(msg.sender, sharesAmount);

        underlying.transfer(msg.sender, underlyingAmount);
    }

    function withdraw(uint256 sharesAmount, address recipient)
        public
        returns (uint256 underlyingAmount)
    {
        uint256 sharePrice = getPricePerFullShare();
        underlyingAmount = sharesAmount.decmul(sharePrice);
        _burn(msg.sender, sharesAmount);

        underlying.transfer(recipient, underlyingAmount);
    }

    function getPricePerFullShare() public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 10**18;
        }
        return underlying.balanceOf(address(this)).decdiv(_totalSupply);
    }

    function pricePerShare() external view returns (uint256) {
        return getPricePerFullShare();
    }
}
