pragma solidity 0.5.15;

import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "./ATokenMock.sol";

contract LendingPoolMock {
    mapping(address => address) internal reserveAToken;

    function setReserveAToken(address _reserve, address _aTokenAddress) external {
        reserveAToken[_reserve] = _aTokenAddress;
    }

    function deposit(address _reserve, uint256 _amount, uint16 _referralCode)
        external
    {
        ERC20Detailed token = ERC20Detailed(_reserve);
        token.transferFrom(msg.sender, address(this), _amount);

        // Mint aTokens
        address aTokenAddress = reserveAToken[_reserve];
        ATokenMock aToken = ATokenMock(aTokenAddress);
        aToken.mint(msg.sender, _amount);
        token.transfer(aTokenAddress, _amount);
    }

    function getReserveData(address _reserve)
        external
        view
        returns (
            uint256 totalLiquidity,
            uint256 availableLiquidity,
            uint256 totalBorrowsStable,
            uint256 totalBorrowsVariable,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 stableBorrowRate,
            uint256 averageStableBorrowRate,
            uint256 utilizationRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            address aTokenAddress,
            uint40 lastUpdateTimestamp
        )
    {
        aTokenAddress = reserveAToken[_reserve];
        ATokenMock aToken = ATokenMock(aTokenAddress);
        liquidityRate = aToken.liquidityRate();
    }
}
