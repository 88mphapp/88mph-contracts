pragma solidity 0.5.17;

import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

contract MPHToken is ERC20Mintable, ERC20Detailed {
    constructor() public ERC20Detailed("88mph.app", "MPH", 18) {}
}
