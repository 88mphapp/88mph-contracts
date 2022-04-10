// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MPHToken is
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable
{
    function initialize() external initializer {
        __Ownable_init();
        __ERC20Burnable_init();
        __ERC20_init("88mph.app", "MPH");
    }

    function ownerMint(address account, uint256 amount)
        external
        onlyOwner
        returns (bool)
    {
        _mint(account, amount);
        return true;
    }
}
