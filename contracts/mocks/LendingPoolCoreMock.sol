pragma solidity 0.6.5;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./ATokenMock.sol";

contract LendingPoolCoreMock {
    function bounceTransfer(address _reserve, address _sender, uint256 _amount)
        external
    {
        ERC20 token = ERC20(_reserve);
        token.transferFrom(_sender, address(this), _amount);

        token.transfer(msg.sender, _amount);
    }
}
