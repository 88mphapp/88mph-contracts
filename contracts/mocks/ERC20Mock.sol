pragma solidity 0.6.5;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20("", "") {
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}