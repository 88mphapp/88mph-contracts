// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";

contract VaultMock is ERC20 {
    using PRBMathUD60x18 for uint256;

    ERC20 public underlying;

    constructor(address _underlying) ERC20("yUSD", "yUSD") {
        underlying = ERC20(_underlying);
    }

    function deposit(uint256 tokenAmount) public {
        uint256 sharePrice = getPricePerFullShare();
        _mint(msg.sender, tokenAmount.div(sharePrice));

        underlying.transferFrom(msg.sender, address(this), tokenAmount);
    }

    function withdraw(uint256 sharesAmount)
        public
        returns (uint256 underlyingAmount)
    {
        uint256 sharePrice = getPricePerFullShare();
        underlyingAmount = sharesAmount.mul(sharePrice);
        _burn(msg.sender, sharesAmount);

        underlying.transfer(msg.sender, underlyingAmount);
    }

    function withdraw(
        uint256 sharesAmount,
        address recipient,
        uint256 maxLoss
    ) public returns (uint256 underlyingAmount) {
        uint256 sharePrice = getPricePerFullShare();
        underlyingAmount = sharesAmount.mul(sharePrice);
        _burn(msg.sender, sharesAmount);

        underlying.transfer(recipient, underlyingAmount);
    }

    function getPricePerFullShare() public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 10**18;
        }
        return underlying.balanceOf(address(this)).div(_totalSupply);
    }

    function pricePerShare() external view returns (uint256) {
        return getPricePerFullShare();
    }
}
