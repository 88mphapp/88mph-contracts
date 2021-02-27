pragma solidity 0.5.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

contract ERC20Mock is ERC20, ERC20Detailed("", "", 6) {
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        require(amount > 0, "ERC20Mock: amount 0");
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
}